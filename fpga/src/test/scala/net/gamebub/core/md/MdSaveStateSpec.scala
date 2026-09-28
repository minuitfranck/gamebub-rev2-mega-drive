package net.gamebub.core.md

import chisel3._
import chisel3.util._
import net.gamebub.core.pce.PceTreadle
import org.scalatest.freespec.AnyFreeSpec

/**
 * [[MdSaveStatePort]]: the engine's 64-bit toggle-handshake words land in the SDRAM as two
 * little-endian 32-bit words at `0x1000000 + (address - 0x20000) * 8`, and read back the same.
 * [[MdSaveSlotScanner]]: a slot is valid when bytes 4..7 hold BodyWords and 12..15 the magic;
 * slots beyond the loaded size are cleared.
 */
class MdSaveStateSpec extends AnyFreeSpec {
  import MdSaveStateSpec._

  "the slot port: a 64-bit write is two little-endian SDRAM words, and a read returns them" in {
    val sim = PceTreadle(new PortHarness, "md_ss_port")
    sim.poke("io_rnw", false)
    sim.poke("io_address", BigInt(0x20000 + 5)) // slot 0, word 5
    sim.poke("io_dataWrite", BigInt("1122334455667788", 16))
    sim.poke("io_req", true)
    var n = 0
    while (!sim.peekBool("io_ack") && n < 40) { sim.step(); n += 1 }
    assert(sim.peekBool("io_ack"), "the write was never acknowledged")
    // Peek the memory: index = word (5) * 2 + half.
    sim.poke("io_peekIndex", BigInt(10)); sim.step()
    sim.expect("io_peekData", BigInt("55667788", 16), "low half at +0")
    sim.poke("io_peekIndex", BigInt(11)); sim.step()
    sim.expect("io_peekData", BigInt("11223344", 16), "high half at +4")
    // Read it back through the port.
    sim.poke("io_rnw", true)
    sim.poke("io_req", false)
    n = 0
    while (sim.peekBool("io_ack") && n < 40) { sim.step(); n += 1 }
    assert(!sim.peekBool("io_ack"), "the read was never acknowledged")
    sim.expect("io_dataRead", BigInt("1122334455667788", 16))
    // Slot 3's first word: byte address 0x10C0000 -> index (3 << 15) * 2.
    sim.poke("io_rnw", false)
    sim.poke("io_address", BigInt(0x20000 + 3 * 0x8000))
    sim.poke("io_dataWrite", BigInt("00008A08FFFFFFFF", 16))
    sim.poke("io_req", true)
    n = 0
    while (!sim.peekBool("io_ack") && n < 40) { sim.step(); n += 1 }
    assert(sim.peekBool("io_ack"))
    sim.poke("io_peekIndex", BigInt(3 * 0x8000 * 2)); sim.step()
    sim.expect("io_peekData", BigInt("FFFFFFFF", 16), "slot 3 counter")
    sim.poke("io_peekIndex", BigInt(3 * 0x8000 * 2 + 1)); sim.step()
    sim.expect("io_peekData", BigInt("00008A08", 16), "slot 3 body words")
    sim.expect("io_outside", BigInt(0), "every access inside the 1 MiB slot area")
    sim.finish()
  }

  "the scanner: valid slots by the engine's marks; slots beyond the file cleared" in {
    val sim = PceTreadle(new ScannerHarness, "md_ss_scanner")
    def poke(slot: Int, off: Int, v: BigInt): Unit = {
      sim.poke("io_pokeIndex", BigInt(slot * 8 + off / 4)); sim.poke("io_pokeData", v); sim.poke("io_pokeEn", true); sim.step(); sim.poke("io_pokeEn", false)
    }
    // slot 0: a state; slot 1: right size, wrong magic; slot 2: a state but beyond the file; slot 3: empty (0xFF)
    poke(0, 4, BigInt(MdSaveState.BodyWords)); poke(0, 12, BigInt(MdSaveState.HeaderHigh))
    poke(1, 4, BigInt(MdSaveState.BodyWords)); poke(1, 12, BigInt("DEADBEEF", 16))
    poke(2, 4, BigInt(MdSaveState.BodyWords)); poke(2, 12, BigInt(MdSaveState.HeaderHigh))
    poke(3, 4, BigInt("FFFFFFFF", 16)); poke(3, 12, BigInt("FFFFFFFF", 16))
    sim.poke("io_loadedSize", BigInt(2 * MdSaveState.SlotSize))
    sim.poke("io_start", true); sim.step(); sim.poke("io_start", false)
    var n = 0
    while (sim.peekBool("io_busy") && n < 200) { sim.step(); n += 1 }
    assert(!sim.peekBool("io_busy"), "the scan never finished")
    sim.expect("io_valid", BigInt(1), "only slot 1 holds a state")
    sim.expect("io_usedSlots", BigInt(1))
    sim.poke("io_pokeIndex", BigInt(2 * 8 + 1)); sim.step()
    sim.expect("io_peekData", BigInt(0), "slot 3's size word was cleared")
    sim.poke("io_pokeIndex", BigInt(0 * 8 + 1)); sim.step()
    sim.expect("io_peekData", BigInt(MdSaveState.BodyWords), "slot 1's size word kept")
    // After a save the whole area counts as loaded: slot 2 (index 2) becomes valid too.
    sim.poke("io_loadedSize", BigInt(MdSaveState.FullSize))
    poke(2, 4, BigInt(MdSaveState.BodyWords))
    sim.poke("io_start", true); sim.step(); sim.poke("io_start", false)
    n = 0
    while (sim.peekBool("io_busy") && n < 200) { sim.step(); n += 1 }
    sim.expect("io_valid", BigInt(5), "slots 1 and 3")
    sim.expect("io_usedSlots", BigInt(3))
    sim.finish()
  }
}

object MdSaveStateSpec {
  /**
   * A PipelineMemoryInterface target: always ready, the access happens in the data phase (the
   * cycle after acceptance), as the arbiter and the SDRAM controller behave for one initiator.
   */
  class MemModel(indexOf: UInt => UInt, entries: Int) {
    val mem = Mem(entries, UInt(32.W))
    val pendingIndex = Reg(UInt(log2Ceil(entries).W))
    val pendingWrite = RegInit(false.B)
    val pending = RegInit(false.B)
    val dataRead = RegInit(0.U(32.W))
    def serve(port: lib.mem.PipelineMemoryInterface): Unit = {
      port.ready := true.B
      port.dataRead := mem(pendingIndex)
      when (pending) {
        when (pendingWrite) { mem(pendingIndex) := port.dataWrite }
        pending := false.B
      }
      when (port.enable) {
        pendingIndex := indexOf(port.address)
        pendingWrite := port.isWrite
        pending := true.B
      }
    }
  }

  class PortHarness extends Module {
    val io = IO(new Bundle {
      val req = Input(Bool())
      val rnw = Input(Bool())
      val address = Input(UInt(22.W))
      val dataWrite = Input(UInt(64.W))
      val dataRead = Output(UInt(64.W))
      val ack = Output(Bool())
      val peekIndex = Input(UInt(18.W))
      val peekData = Output(UInt(32.W))
      val outside = Output(Bool())
    })
    val dut = Module(new MdSaveStatePort)
    dut.io.hold := false.B
    dut.io.req := io.req
    dut.io.rnw := io.rnw
    dut.io.address := io.address
    dut.io.dataWrite := io.dataWrite
    io.dataRead := dut.io.dataRead
    io.ack := dut.io.ack
    // Index: the 32-bit word within the 1 MiB area (addresses must start at 0x1000000).
    val model = new MemModel(a => a(19, 2), 1 << 18)
    model.serve(dut.io.mem)
    // Sticky: an access outside the slot area (the spec checks it stays low).
    val outside = RegInit(false.B)
    when (dut.io.mem.enable && dut.io.mem.address(24, 20) =/= 0x10.U) { outside := true.B }
    io.outside := outside
    io.peekData := model.mem(io.peekIndex)
  }

  class ScannerHarness extends Module {
    val io = IO(new Bundle {
      val start = Input(Bool())
      val loadedSize = Input(UInt(21.W))
      val busy = Output(Bool())
      val valid = Output(UInt(4.W))
      val usedSlots = Output(UInt(3.W))
      val pokeEn = Input(Bool())
      val pokeIndex = Input(UInt(5.W))
      val pokeData = Input(UInt(32.W))
      val peekData = Output(UInt(32.W))
    })
    val dut = Module(new MdSaveSlotScanner)
    dut.io.start := io.start
    dut.io.loadedSize := io.loadedSize
    dut.io.invalidate := false.B
    io.busy := dut.io.busy
    io.valid := dut.io.valid
    io.usedSlots := dut.io.usedSlots
    // Index: slot (address bits 19:18) and the word within the slot's first 32 bytes (bits 4:2).
    val model = new MemModel(a => Cat(a(19, 18), a(4, 2)), 32)
    model.serve(dut.io.mem)
    when (io.pokeEn) { model.mem(io.pokeIndex) := io.pokeData }
    io.peekData := model.mem(io.pokeIndex)
  }
}
