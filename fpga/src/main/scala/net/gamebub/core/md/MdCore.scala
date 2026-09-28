package net.gamebub.core.md

import chisel3._

/**
 * The Mega Drive machine: SystemVerilog module `md_gamebub_core` in
 * `fpga/verilog/md/rtl/gamebub/md_gamebub_core.sv`, around the vendored MiSTer
 * Genesis core (Genesis_MiSTer adc0c42, see `fpga/verilog/md/README.md`).
 *
 * Port names, directions and widths match the SystemVerilog module exactly.
 * Everything runs on `clk_sys` (53.693175 MHz, the Mega Drive master clock);
 * the machine's own clock enables are derived inside `system.sv` (68000 /7,
 * Z80 and PSG /15, FM /7), and `pause` withholds them (focus pause).
 *
 * The cartridge ROM is served through the `rom_*` toggle handshake: see
 * [[MdRomStore]].
 */
class MdCore extends ExtModule {
  override def desiredName: String = "md_gamebub_core"

  val io = FlatIO(new Bundle {
    val clk_sys = Input(Clock())

    /** Held through setup: upstream's cartridge-download reset. */
    val loading = Input(Bool())
    /** Framework reset, CoreHalt, the Reset action, a region strap change. */
    val machine_reset = Input(Bool())
    /** Clears the work RAM, VRAM and save RAM through their B ports. */
    val ram_init = Input(Bool())
    /** Focus pause: withholds every machine clock enable. */
    val pause = Input(Bool())

    val pal = Input(Bool())
    val region_export = Input(Bool())
    val pad_3button = Input(Bool())

    val sram_quirk = Input(Bool())
    val sram00_quirk = Input(Bool())
    val eeprom_quirk = Input(Bool())
    val noram_quirk = Input(Bool())
    val fifo_quirk = Input(Bool())
    val fmbusy_quirk = Input(Bool())
    val schan_quirk = Input(Bool())

    val lpf_mode = Input(UInt(2.W))
    val enable_fm = Input(Bool())
    val enable_psg = Input(Bool())
    val en_hifi_pcm = Input(Bool())
    val ladder = Input(Bool())
    val obj_limit_high = Input(Bool())
    val border = Input(Bool())
    val cram_dots = Input(Bool())

    /** Cartridge size in 16-bit words (upstream ROMSZ[24:1]). */
    val rom_size = Input(UInt(24.W))
    val rom_addr = Output(UInt(24.W))
    val rom_data = Input(UInt(16.W))
    val rom_wdata = Output(UInt(16.W))
    val rom_we = Output(Bool())
    val rom_be = Output(UInt(2.W))
    val rom_req = Output(Bool())
    val rom_ack = Input(Bool())

    /** Cartridge save RAM, host side: word n is save bytes 2n (low) and 2n+1. */
    val bram_a = Input(UInt(15.W))
    val bram_di = Input(UInt(16.W))
    val bram_do = Output(UInt(16.W))
    val bram_we = Input(Bool())
    val bram_change = Output(Bool())

    /** {Z,Y,X,Mode,Start,C,B,A,Up,Down,Left,Right}, active high (`system.sv`'s JOY_1 order). */
    val joy_1 = Input(UInt(12.W))

    val video_ce = Output(Bool())
    val video_r = Output(UInt(4.W))
    val video_g = Output(UInt(4.W))
    val video_b = Output(UInt(4.W))
    val video_hbl = Output(Bool())
    val video_vbl = Output(Bool())
    /** {V30, H40}. */
    val video_resolution = Output(UInt(2.W))

    val audio_l = Output(UInt(16.W))
    val audio_r = Output(UInt(16.W))

    val dbg_m68k_a = Output(UInt(24.W))

    // Save states: the R58 engine (see md_gamebub_core.sv and [[MdSaveState]]).
    /** A rising edge starts a save / a load of `ss_slot`. */
    val ss_save = Input(Bool())
    val ss_load = Input(Bool())
    val ss_slot = Input(UInt(2.W))
    val ss_rom_identity = Input(UInt(64.W))
    val ss_rom_ready = Input(Bool())
    val ss_config_identity = Input(UInt(64.W))
    /** The slot memory channel: 64-bit words, toggle handshake ([[MdSaveStatePort]]). */
    val ss_mem_req = Output(Bool())
    val ss_mem_rnw = Output(Bool())
    val ss_mem_addr = Output(UInt(22.W))
    val ss_mem_din = Output(UInt(64.W))
    val ss_mem_dout = Input(UInt(64.W))
    val ss_mem_ack = Input(Bool())
    val ss_busy = Output(Bool())
    val ss_pass = Output(Bool())
    val ss_fail = Output(Bool())
    /** The engine's error code (0 none; the list is in md_gamebub_core.sv). */
    val ss_error = Output(UInt(8.W))
    val ss_capture_error = Output(UInt(4.W))
    val ss_slot_valid = Output(Bool())
    /** The engine is resetting the machine after a failed import. */
    val ss_recover = Output(Bool())
    /** This cartridge can have save states. */
    val ss_supported = Output(Bool())
    /** Diagnostics: the engine's state machines and the safe-point terms (md_gamebub_core.sv). */
    val ss_dbg = Output(UInt(32.W))
    /** Diagnostics 2: the VDP's nine memory-idle terms, 1 = busy (md_gamebub_core.sv). */
    val ss_dbg2 = Output(UInt(32.W))
  })
}
