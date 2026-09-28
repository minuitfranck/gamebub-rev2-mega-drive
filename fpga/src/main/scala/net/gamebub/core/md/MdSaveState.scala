package net.gamebub.core.md

import chisel3._
import chisel3.util._
import lib.mem.PipelineMemoryInterface

/**
 * Save-state storage for the Mega Drive port (docs/md-port-design.md section 12).
 *
 * The engine is keFEAR89's Genesis_MiSTer_Savestates R58 (`rtl/savestate`, wired in
 * `md_gamebub_core.sv`). On a MiSTer it keeps four slots in DDR3 at 0x3E100000 with a 256 KiB
 * stride, and MiSTer's Main writes a slot to the `.ss` file when the slot's first word (a change
 * counter) moves. Here the same four slots live in the SDRAM, and the firmware's States file (id 2,
 * host window 0x5xxx_xxxx) is that memory as it is: byte for byte a MiSTer `.ss` file.
 */
object MdSaveState {
  val Slots = 4
  /** One slot as the engine lays it out (ss_slot_engine.sv `control_word`: a 0x8000 64-bit-word stride). */
  val SlotSize = 0x4_0000
  /** SDRAM byte address of slot 0: bit 24, above the 10 MiB cartridge. */
  val SlotsBase = 0x100_0000
  val FullSize = Slots * SlotSize
  /**
   * A slot's first 64-bit word is {BODY_WORDS, counter} (bytes 4..7 hold BODY_WORDS =
   * (PAYLOAD_BYTES + 32) / 4); a slot without a state has 0 or 0xFFFFFFFF there.
   */
  val BodyWords = (0x22800 + 32) / 4
  /** Bytes 8..15: {32'h52353853 "R58S", 16'h0001, 16'h0001}; the high half, at +12, is the magic. */
  val HeaderHigh = 0x52353853L
  /** The engine's 64-bit word address of slot 0 (words from MiSTer's 0x3E000000). */
  val EngineWordBase = 0x20000
}

/**
 * The engine's slot memory channel (`ss_mem_*` on `md_gamebub_core`, the fork's private DDR3
 * channel in its `ddram.sv`) on the SDRAM. A request is outstanding while `req =/= ack`; the
 * engine holds `address`, `rnw` and `dataWrite` until `ack` follows, and reads `dataRead` then
 * (it synchronises `ack` through two registers first). Each 64-bit word is two 32-bit accesses,
 * little-endian: the low half at byte `SlotsBase + (address - 0x20000) * 8`, the high half four
 * bytes on. That is the order MiSTer's Main sees the words in too (an ARM reading DDR3), so the
 * slot in the SDRAM matches a MiSTer's slot byte for byte.
 */
class MdSaveStatePort extends Module {
  import MdSaveState._
  val io = IO(new Bundle {
    val req = Input(Bool())
    val rnw = Input(Bool())
    val address = Input(UInt(22.W))
    val dataWrite = Input(UInt(64.W))
    val dataRead = Output(UInt(64.W))
    val ack = Output(Bool())
    val busy = Output(Bool())
    /** Do not start a new access (the slot scanner has the SDRAM side port). */
    val hold = Input(Bool())
    val mem = Flipped(new PipelineMemoryInterface(addressWidth = 25, dataWidth = 32))
  })

  object State extends ChiselEnum {
    val idle, issue, data = Value
  }
  val state = RegInit(State.idle)
  val ack = RegInit(false.B)
  val high = RegInit(false.B)
  val write = Reg(Bool())
  /** The word within the slot area: the engine's address less 0x20000 (its bit 17 is the area). */
  val word = Reg(UInt(17.W))
  val dataWrite = Reg(UInt(64.W))
  val dataRead = RegInit(0.U(64.W))

  io.ack := ack
  io.dataRead := dataRead
  io.busy := state =/= State.idle

  // 0x1000000 + word * 8 (+ 4 for the high half).
  io.mem.enable := state === State.issue
  io.mem.address := Cat(1.U(1.W), 0.U(4.W), word, high, 0.U(2.W))
  io.mem.isWrite := write
  io.mem.writeStrobe := "b1111".U
  io.mem.dataWrite := Mux(high, dataWrite(63, 32), dataWrite(31, 0))

  switch (state) {
    is (State.idle) {
      when (io.req =/= ack && !io.hold) {
        word := io.address(16, 0)
        write := !io.rnw
        dataWrite := io.dataWrite
        high := false.B
        state := State.issue
      }
    }
    is (State.issue) {
      when (io.mem.ready) {
        state := State.data
      }
    }
    is (State.data) {
      when (io.mem.ready) {
        when (!write) {
          when (high) {
            dataRead := Cat(io.mem.dataRead, dataRead(31, 0))
          } .otherwise {
            dataRead := Cat(dataRead(63, 32), io.mem.dataRead)
          }
        }
        when (high) {
          ack := io.req
          state := State.idle
        } .otherwise {
          high := true.B
          state := State.issue
        }
      }
    }
  }
}

/**
 * Which slots hold a state (bytes 4..7 == BodyWords and 12..15 == HeaderHigh, the engine's own
 * marks), as the NES and PC Engine ports' scanners. `start` scans every slot; those beyond
 * `loadedSize` (the bytes of the States file the host transferred; `FullSize` after a save) get
 * bytes 4..7 cleared instead, so a slot left over from another game cannot look valid (the
 * engine would refuse it anyway, by its cartridge identity). `valid` and `usedSlots` (the last
 * valid slot plus one) hold afterwards; `invalidate` forgets every slot (a new cartridge).
 */
class MdSaveSlotScanner extends Module {
  import MdSaveState._
  val io = IO(new Bundle {
    val start = Input(Bool())
    val loadedSize = Input(UInt((log2Ceil(FullSize) + 1).W))
    val invalidate = Input(Bool())
    val busy = Output(Bool())
    val valid = Output(UInt(Slots.W))
    val usedSlots = Output(UInt(log2Ceil(Slots + 1).W))
    val mem = Flipped(new PipelineMemoryInterface(addressWidth = 25, dataWidth = 32))
  })

  object State extends ChiselEnum {
    val idle, decide, clear, readBody, readHeader, next = Value
  }
  val state = RegInit(State.idle)
  val slot = Reg(UInt(log2Ceil(Slots).W))
  val loadedSize = Reg(UInt(io.loadedSize.getWidth.W))
  val valid = RegInit(0.U(Slots.W))
  val dataPhase = RegInit(false.B)

  io.busy := state =/= State.idle
  io.valid := valid
  io.usedSlots := (0 until Slots).map(i => Mux(valid(i), (i + 1).U(io.usedSlots.getWidth.W), 0.U)).reduce((a, b) => Mux(a > b, a, b))

  val access = state === State.clear || state === State.readBody || state === State.readHeader
  io.mem.enable := access && !dataPhase
  io.mem.address := SlotsBase.U(25.W) + (slot << log2Ceil(SlotSize)) + Mux(state === State.readHeader, 12.U, 4.U)
  io.mem.isWrite := state === State.clear
  io.mem.writeStrobe := "b1111".U
  io.mem.dataWrite := 0.U
  val done = access && dataPhase && io.mem.ready
  when (access && io.mem.ready) {
    dataPhase := !dataPhase
  }

  def mark(ok: Bool): Unit = {
    valid := Mux(ok, valid | UIntToOH(slot, Slots), valid & ~UIntToOH(slot, Slots))
  }

  switch (state) {
    is (State.idle) {
      when (io.start) {
        loadedSize := io.loadedSize
        slot := 0.U
        state := State.decide
      }
    }
    is (State.decide) {
      val loaded = ((slot +& 1.U) << log2Ceil(SlotSize)) <= loadedSize
      state := Mux(loaded, State.readBody, State.clear)
    }
    is (State.clear) {
      when (done) {
        mark(false.B)
        state := State.next
      }
    }
    is (State.readBody) {
      when (done) {
        when (io.mem.dataRead === BodyWords.U) {
          state := State.readHeader
        } .otherwise {
          mark(false.B)
          state := State.next
        }
      }
    }
    is (State.readHeader) {
      when (done) {
        mark(io.mem.dataRead === HeaderHigh.U)
        state := State.next
      }
    }
    is (State.next) {
      when (slot === (Slots - 1).U) {
        state := State.idle
      } .otherwise {
        slot := slot + 1.U
        state := State.decide
      }
    }
  }
  when (io.invalidate) {
    valid := 0.U
  }
}
