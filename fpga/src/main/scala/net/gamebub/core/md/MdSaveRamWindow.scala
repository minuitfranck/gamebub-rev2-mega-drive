package net.gamebub.core.md

import chisel3._
import chisel3.util._
import lib.mem.MemoryInterface

/**
 * The host's `.sav` window on the cartridge save RAM's B port
 * (docs/md-port-design.md section 9).
 *
 * The save RAM's B port is 16-bit and the host window is 32-bit, so each host
 * word is two block RAM accesses. `system.sv`'s memory is built from an even
 * and an odd byte bank (`rtl/xilinx/bram.vhd`), with B-port word `n` holding
 * save bytes `2n` in bits 7:0 and `2n+1` in bits 15:8; a 32-bit host word at
 * byte address `A` therefore holds B word `A/2` in its low half and `A/2 + 1`
 * in its high half, and the file on the card is the save RAM's byte array in
 * address order -- byte for byte a MiSTer `.sav`.
 *
 * Reads take one extra cycle each way because the B port's output is
 * registered. The window stalls while `ramInit` is running, which is the only
 * other owner of that port.
 */
class MdSaveRamWindow extends Module {
  val io = IO(new Bundle {
    /** The host window (byte addresses within the file). */
    val host = new MemoryInterface(addressWidth = 17, dataWidth = 32)
    /** The save RAM's clear is using the port. */
    val ramInit = Input(Bool())

    val bramAddr = Output(UInt(15.W))
    val bramDataWrite = Output(UInt(16.W))
    val bramWrite = Output(Bool())
    val bramDataRead = Input(UInt(16.W))
  })

  object State extends ChiselEnum {
    val idle, writeLow, writeHigh, readLow, readHigh, capture, done = Value
  }
  val state = RegInit(State.idle)

  val addr = Reg(UInt(15.W))
  val low = Reg(UInt(16.W))
  val high = Reg(UInt(16.W))

  io.bramAddr := addr
  io.bramDataWrite := Mux(state === State.writeHigh, high, low)
  io.bramWrite := state === State.writeLow || state === State.writeHigh
  io.host.dataRead := Cat(high, low)
  io.host.done := state === State.done

  switch (state) {
    is (State.idle) {
      when (io.host.enable && !io.ramInit) {
        addr := io.host.address(15, 1)
        low := io.host.dataWrite(15, 0)
        high := io.host.dataWrite(31, 16)
        state := Mux(io.host.write, State.writeLow, State.readLow)
      }
    }
    is (State.writeLow) {
      addr := addr + 1.U
      state := State.writeHigh
    }
    is (State.writeHigh) {
      state := State.done
    }
    // The B port's address is applied in this cycle and its data arrives in
    // the next, so each half needs its own cycle before it can be taken.
    is (State.readLow) {
      addr := addr + 1.U
      state := State.readHigh
    }
    is (State.readHigh) {
      low := io.bramDataRead
      state := State.capture
    }
    is (State.capture) {
      high := io.bramDataRead
      state := State.done
    }
    is (State.done) {
      state := State.idle
    }
  }
}
