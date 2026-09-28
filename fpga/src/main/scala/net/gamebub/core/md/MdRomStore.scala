package net.gamebub.core.md

import chisel3._
import chisel3.util._
import lib.mem.PipelineMemoryInterface

/**
 * The cartridge ROM backing store: `system.sv`'s ROM port on the SDRAM
 * (docs/md-port-design.md section 4).
 *
 * The contract is upstream's toggle handshake. A transaction is outstanding
 * while `req =/= ack`; the machine holds the address, the byte enables and the
 * write data stable for its whole length, and `MBUS_ROM_READ` latches `rdata`
 * in the cycle it first sees `req === ack`. So `ack` and `rdata` are updated by
 * the same clock edge, and a slow answer costs 68000 wait states and nothing
 * else. Both sides reset their half of the handshake to 0, so they are always
 * consistent after a machine reset.
 *
 * **Byte order.** The SDRAM holds the file as the host wrote it: 32-bit
 * little-endian words at 4-aligned byte addresses (the controller maps a 32-bit
 * access onto two chip words in its own order, so an access at another
 * alignment would read a scrambled word). A Mega Drive ROM is big-endian, so
 * the 16-bit word at byte address `W` is `{sdram(7,0), sdram(15,8)}` and the
 * one at `W+2` is `{sdram(23,16), sdram(31,24)}`. The swap is here, not in the
 * loader: the image in the SDRAM stays identical to the file on the card, which
 * is what lets the glue read the cartridge header out of the host stream.
 *
 * **Why a cache.** A 68000 read is four CPU clocks = 28 master clocks, and
 * DTACK has to be low about 14 clocks after AS falls; two of those go to the
 * MBUS state machine, so the store has roughly eleven clocks to answer without
 * costing a wait state, and a random SDRAM read does not always fit in eleven.
 * So:
 *
 *  - `lines` 4-byte windows, fully associative, round-robin replacement. The
 *    68000 fetches two bytes at a time, so every second fetch of a sequential
 *    run hits the window the one before it filled.
 *  - **Sequential prefetch**: every request arms the window after the one it
 *    used, and the store reads it while the bus is idle -- which is the whole
 *    rest of the 68000's bus cycle, about 26 clocks. A sequential run then
 *    costs one SDRAM access per four bytes and the access is issued a bus cycle
 *    before it is needed. The anchor is the machine's own last address, so the
 *    prefetcher stays exactly one window ahead and cannot run away.
 *  - Four lines rather than one because the VDP's DMA reads ROM through the
 *    same port, sequentially, interleaved with instruction fetch; with one line
 *    the two streams would evict each other.
 *
 * The ROM is read-only at run time except through `SCHAN_QUIRK`, so the lines
 * cannot go stale on their own; a write updates the line it modifies, and
 * `invalidate` covers the host rewriting the image during setup. Line tags are
 * unique by construction: a line is only ever installed on a miss.
 */
class MdRomStore(lines: Int = 4) extends Module {
  import MdRomStore._

  require(isPow2(lines) && lines >= 2)

  val io = IO(new Bundle {
    /** Toggles to start a transaction (upstream ROM_REQ). */
    val req = Input(Bool())
    /** Follows `req` when the transaction is done (upstream ROM_ACK). */
    val ack = Output(Bool())
    /** Word address, upstream ROM_ADDR[24:1]. */
    val addr = Input(UInt(24.W))
    val we = Input(Bool())
    /** {UDS, LDS}: bit 1 is the byte at the even address. */
    val be = Input(UInt(2.W))
    val wdata = Input(UInt(16.W))
    val rdata = Output(UInt(16.W))

    /** Forget every line: the image changed under them (setup only). */
    val invalidate = Input(Bool())

    val sdram = Flipped(new PipelineMemoryInterface(addressWidth = 25, dataWidth = 32))

    /** Statistics, one-cycle pulses. */
    val statTransaction = Output(Bool())
    val statHit = Output(Bool())
    val statPrefetchRead = Output(Bool())
    val statSdramRead = Output(Bool())
    val statSdramWrite = Output(Bool())
    /** Clocks from the request to the answer, valid with `statTransaction`. */
    val latency = Output(UInt(8.W))
  })

  // ---- the line store -------------------------------------------------
  val lineValid = RegInit(VecInit(Seq.fill(lines)(false.B)))
  val lineTag = Reg(Vec(lines, UInt(WindowBits.W)))
  val lineData = Reg(Vec(lines, UInt(32.W)))
  val lineNext = RegInit(0.U(log2Ceil(lines).W))

  def lookup(tag: UInt): (Bool, UInt) = {
    val hits = VecInit((0 until lines).map(i => lineValid(i) && lineTag(i) === tag)).asUInt
    (hits.orR, OHToUInt(hits))
  }

  // ---- the handshake --------------------------------------------------
  val ack = RegInit(false.B)
  val rdata = RegInit(0.U(16.W))
  io.ack := ack
  io.rdata := rdata

  val byteAddr = Cat(io.addr, 0.U(1.W))
  val reqTag = byteAddr(24, 2)
  val reqHigh = byteAddr(1)
  val pending = io.req =/= ack

  /** The window a sequential run wants next, anchored on the machine's own last access. */
  val prefetchTag = Reg(UInt(WindowBits.W))
  val prefetchArmed = RegInit(false.B)

  object State extends ChiselEnum {
    val idle, fill, fillWait, write, writeWait, prefetch, prefetchWait = Value
  }
  val state = RegInit(State.idle)

  /** The line being filled or written, and the window it will hold. */
  val slot = Reg(UInt(log2Ceil(lines).W))
  val fillTag = Reg(UInt(WindowBits.W))
  val writeValue = Reg(UInt(32.W))

  val latency = RegInit(0.U(8.W))
  val counting = RegInit(false.B)

  io.sdram.enable := false.B
  io.sdram.address := Cat(fillTag, 0.U(2.W))
  io.sdram.isWrite := false.B
  io.sdram.writeStrobe := "b1111".U
  io.sdram.dataWrite := writeValue

  io.statTransaction := false.B
  io.statHit := false.B
  io.statPrefetchRead := false.B
  io.statSdramRead := false.B
  io.statSdramWrite := false.B
  io.latency := latency

  when (pending && !counting) {
    counting := true.B
    latency := 1.U
  } .elsewhen (counting && latency =/= 255.U) {
    latency := latency + 1.U
  }

  /** The big-endian 16-bit half of a window. */
  def halfOf(word: UInt, high: Bool): UInt =
    Mux(high, Cat(word(23, 16), word(31, 24)), Cat(word(7, 0), word(15, 8)))

  /** The window with the written lanes replaced (byte order as above). */
  def modified(old: UInt): UInt = {
    val bytes = Wire(Vec(4, UInt(8.W)))
    bytes := old.asTypeOf(bytes)
    val base = Mux(reqHigh, 2.U, 0.U)
    when (io.be(1)) { bytes(base) := io.wdata(15, 8) }
    when (io.be(0)) { bytes(base + 1.U) := io.wdata(7, 0) }
    bytes.asUInt
  }

  /** Put a freshly read window into its line and move the victim on. */
  def install(data: UInt): Unit = {
    lineValid(slot) := true.B
    lineTag(slot) := fillTag
    lineData(slot) := data
    lineNext := slot + 1.U
  }

  /** Finish the transaction: the answer and the handshake move together. */
  def answer(value: UInt): Unit = {
    rdata := halfOf(value, reqHigh)
    ack := io.req
    counting := false.B
    io.statTransaction := true.B
  }

  val (reqHit, reqSlot) = lookup(reqTag)
  val (prefetchHit, _) = lookup(prefetchTag)

  switch (state) {
    is (State.idle) {
      when (pending) {
        // Anchor the prefetcher on this access, whether it hits or misses.
        prefetchTag := reqTag + 1.U
        prefetchArmed := true.B
        slot := lineNext
        fillTag := reqTag
        when (reqHit) {
          when (io.we) {
            slot := reqSlot
            state := State.write
          } .otherwise {
            io.statHit := true.B
            answer(lineData(reqSlot))
          }
        } .otherwise {
          state := State.fill
        }
      } .elsewhen (prefetchArmed && !prefetchHit) {
        // Only while nothing is pending: a prefetch must never delay the
        // machine's own access.
        slot := lineNext
        fillTag := prefetchTag
        state := State.prefetch
      }
    }

    is (State.fill) {
      io.sdram.enable := true.B
      when (io.sdram.ready) {
        io.statSdramRead := true.B
        state := State.fillWait
      }
    }
    is (State.fillWait) {
      when (io.sdram.ready) {
        install(io.sdram.dataRead)
        when (io.we) {
          state := State.write
        } .otherwise {
          answer(io.sdram.dataRead)
          state := State.idle
        }
      }
    }

    is (State.write) {
      // The window is in `slot` here: a hit, or the fill just put it there.
      val value = modified(lineData(slot))
      writeValue := value
      io.sdram.enable := true.B
      io.sdram.isWrite := true.B
      io.sdram.dataWrite := value
      io.sdram.address := Cat(reqTag, 0.U(2.W))
      when (io.sdram.ready) {
        io.statSdramWrite := true.B
        lineData(slot) := value
        state := State.writeWait
      }
    }
    is (State.writeWait) {
      when (io.sdram.ready) {
        answer(lineData(slot))
        state := State.idle
      }
    }

    is (State.prefetch) {
      io.sdram.enable := true.B
      when (io.sdram.ready) {
        io.statSdramRead := true.B
        io.statPrefetchRead := true.B
        state := State.prefetchWait
      }
    }
    is (State.prefetchWait) {
      when (io.sdram.ready) {
        install(io.sdram.dataRead)
        prefetchArmed := false.B
        state := State.idle
      }
    }
  }

  when (io.invalidate) {
    for (i <- 0 until lines) { lineValid(i) := false.B }
    prefetchArmed := false.B
  }
}

object MdRomStore {
  /** A window is 4 bytes of a 25-bit byte address space. */
  val WindowBits = 23
}
