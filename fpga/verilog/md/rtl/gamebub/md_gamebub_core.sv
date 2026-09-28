//
// Game Bub rev2 top level for the vendored MiSTer Genesis machine.
// Part of the Mega Drive / Genesis port; see ../../README.md and
// docs/md-port-design.md. GPL-3.0-only, as the core it wraps.
//
// This is a port adapter, nothing more: it instantiates `system` (rtl/system.sv)
// with every input the Game Bub does not have tied off, and passes the ROM
// mailbox, the save RAM's host port, the video port and the DAC straight
// through to the Chisel glue (bound there as the ExtModule `MdCore`).
//
// Everything that is a design decision of the port -- the SDRAM ROM store, the
// video capture, the audio resampling, the host protocol, the settings -- is in
// Chisel, in fpga/src/main/scala/net/gamebub/core/md/.
//
// Tied off here (docs/md-port-design.md section 11): the multitap, the 4-way
// adapter, the Team Player, the J-Cart pads, the mouse, the light gun, the
// serial joystick, the Miracle Piano, the cheat engine, the SVP and the Pier
// Solar EEPROM. The last three are compiled out with MD_NO_CHEATS, MD_NO_SVP
// and MD_NO_PIER because they hold block RAM; the rest keep their upstream
// source and disappear because their enable is a constant zero.
//
// Save states (design section 12): keFEAR89's Genesis_MiSTer_Savestates R58
// engine (rtl/savestate, and its changes to system.sv, vdp.vhd, the T80 and
// gen_io.sv). The glue below is that fork's Genesis.sv glue without its OSD
// tests (the RAM, Z80 and DDR ping tests, the M68K reset test) and LED codes.
// The commands, the slot and the cartridge identity come from the Chisel glue
// (MdSaveState.scala), which also puts the engine's slot memory channel (a
// MiSTer's DDR3) on the SDRAM and reads the engine's status.
//

module md_gamebub_core
(
	input         clk_sys,

	// Held through setup: upstream's cartridge-download reset (it also resets
	// the VDP through `hard_reset`).
	input         loading,
	// The machine's own reset (framework reset, CoreHalt, the Reset action, a
	// region strap change). Active high.
	input         machine_reset,
	// Clears the work RAM, VRAM and save RAM through their B ports. The glue
	// pulses it for 65,536 clocks at the start of setup, before the `.sav`
	// window can write anything.
	input         ram_init,
	// Focus pause: withholds every machine clock enable (upstream PAUSE_EN).
	input         pause,

	// Straps, sampled while the machine is in reset.
	input         pal,
	input         region_export,
	// 1 = a three-button pad (upstream J3BUT).
	input         pad_3button,

	// Cartridge quirks, from the header the glue captured.
	input         sram_quirk,
	input         sram00_quirk,
	input         eeprom_quirk,
	input         noram_quirk,
	input         fifo_quirk,
	input         fmbusy_quirk,
	input         schan_quirk,

	// Options.
	input   [1:0] lpf_mode,
	input         enable_fm,
	input         enable_psg,
	input         en_hifi_pcm,
	input         ladder,
	input         obj_limit_high,
	input         border,
	input         cram_dots,

	// Cartridge ROM, upstream's toggle handshake: a transaction is outstanding
	// while rom_req != rom_ack (see MdRomStore).
	input  [24:1] rom_size,
	output [24:1] rom_addr,
	input  [15:0] rom_data,
	output [15:0] rom_wdata,
	output        rom_we,
	output  [1:0] rom_be,
	output        rom_req,
	input         rom_ack,

	// Cartridge save RAM, host side (16-bit words; word n is save bytes 2n
	// and 2n+1, low byte first).
	input  [14:0] bram_a,
	input  [15:0] bram_di,
	output [15:0] bram_do,
	input         bram_we,
	// The machine wrote the save RAM.
	output        bram_change,

	// {Z,Y,X,Mode,Start,C,B,A,Right,Left,Down,Up}, active high.
	input  [11:0] joy_1,

	// Video, as the VDP presents it (BORDER_EN low: the blanks are the active
	// area). MdVideoCapture turns this into the framework's framebuffer stream.
	output        video_ce,
	output  [3:0] video_r,
	output  [3:0] video_g,
	output  [3:0] video_b,
	output        video_hbl,
	output        video_vbl,
	output  [1:0] video_resolution,

	// Signed 16-bit, updated on clk_sys, MiSTer's whole filter chain applied.
	output [15:0] audio_l,
	output [15:0] audio_r,

	// Statistics / debugging.
	output [23:0] dbg_m68k_a,

	// ---- save states (the R58 engine)
	// A rising edge starts a save or a load of `ss_slot` (the engine
	// edge-detects; a level is fine, and one it misses is simply not started).
	input         ss_save,
	input         ss_load,
	input   [1:0] ss_slot,
	// Stored with a state and compared before a load: the cartridge (the
	// glue's header words and file size) and the straps.
	input  [63:0] ss_rom_identity,
	input         ss_rom_ready,
	input  [63:0] ss_config_identity,
	// The engine's slot memory: 64-bit words, toggle handshake (a request is
	// outstanding while ss_mem_req != ss_mem_ack; address, data and rnw hold
	// until then). ss_mem_addr counts 64-bit words from MiSTer's 0x3E000000:
	// slot n is at word 0x20000 + n * 0x8000.
	output        ss_mem_req,
	output        ss_mem_rnw,
	output [21:0] ss_mem_addr,
	output [63:0] ss_mem_din,
	input  [63:0] ss_mem_dout,
	input         ss_mem_ack,
	// Busy while a command runs; pass or fail afterwards, with the engine's
	// error code (ss_slot_engine.sv error_code: 1 blocked, 2 unsupported, 3 no
	// state in the slot, 4 bad header, 5 capture failed -- then
	// ss_capture_error says which check --, 6 slot data CRC, 7 restore, 0x0A
	// timeout, 0x0B imported data CRC, 0x1A another cartridge, 0x1B other
	// straps).
	output        ss_busy,
	output        ss_pass,
	output        ss_fail,
	output  [7:0] ss_error,
	output  [3:0] ss_capture_error,
	// The engine's own probe of the selected slot: it holds a state for this
	// cartridge.
	output        ss_slot_valid,
	// The engine is resetting the machine after a failed import.
	output        ss_recover,
	// Save states are possible with this cartridge (`system.sv`
	// SS_SLOT_SUPPORTED: no SVP, Pier Solar or S-chan quirk, no peripherals).
	output        ss_supported,
	// Diagnostics: [31:26] the orchestrator state, [23:20] its capture error,
	// [19:0] system.sv SS_DBG (the capture handler state and the safe-point terms).
	output [31:0] ss_dbg,
	// Diagnostics 2 (register 0x0030): [8:0] the VDP's nine memory-idle terms, 1 = busy (system.sv
	// SS_MEM_TERMS: FIFO, DMA, DTC, DMAC, VRAM data access, VBUS, CRAM, VSRAM0, VSRAM1 writes).
	output [31:0] ss_dbg2
);

wire [7:0] serjoystick_out_unused;
wire       transp_detect_unused;
wire       gg_available_unused;
wire [23:0] dbg_vbus_a_unused;
wire        video_hs_unused, video_vs_unused;
wire        interlace_unused, field_unused;

// ---------------------------------------------------------------- save states
wire         ss_freeze_ack;
wire         ss_freeze_capture_unused;
wire [17:0]  ss_orch_mem_addr;
wire         ss_orch_mem_active;
wire  [7:0]  ss_tmem_dout;
// The engine's byte port into the machine (system.sv SS_MEM_*): the
// orchestrator reads its CRC passes through it; nothing writes it here.
wire [17:0]  ss_tmem_addr = ss_orch_mem_active ? ss_orch_mem_addr : 18'd0;
wire [229:0] ss_z80_reg;
wire [229:0] ss_orch_z80_dir;
wire         ss_orch_z80_set;
wire         ss_orch_z80_drive;
wire [229:0] ss_z80_dir = ss_orch_z80_drive ? ss_orch_z80_dir : 230'd0;
wire         ss_z80_set = ss_orch_z80_drive & ss_orch_z80_set;
wire         ss_m68k_busy, ss_m68k_pass, ss_m68k_fail;
wire         ss_orch_m68k_req, ss_orch_m68k_restore_req;
wire         ss_m68k_capture_start, ss_m68k_capture_ready, ss_m68k_mem_safe;
wire         ss_vdp_vbl, ss_vdp_render_idle, ss_vdp_scan_idle;
wire         ss_sys_pass, ss_sys_fail;
wire         ss_snapshot_busy, ss_snapshot_pass, ss_snapshot_fail;
wire [31:0]  ss_snapshot_crc_first_unused, ss_snapshot_crc_second_unused, ss_snapshot_vdp_crc_unused;
wire         ss_orch_start, ss_orch_enable, ss_orch_ready, ss_orch_done, ss_orch_failed;
wire         ss_slot_active, ss_slot_we, ss_slot_load, ss_slot_save_return, ss_slot_bad, ss_slot_recover;
wire [17:0]  ss_slot_addr;
wire  [7:0]  ss_slot_di, ss_slot_do, ss_slot_z80_do;
wire  [7:0]  ss_slot_read = (ss_slot_addr >= 18'h303A0 && ss_slot_addr < 18'h303C0) ? ss_slot_z80_do : ss_slot_do;
wire  [7:0]  ss_mem_be_unused;
wire [31:0]  ss_source_crc_unused, ss_checked_crc_unused;
wire  [5:0]  ss_orch_dbg_state;
wire [19:0]  ss_sys_dbg;
assign ss_dbg = {ss_orch_dbg_state, 2'b00, ss_capture_error, ss_sys_dbg};
wire  [8:0]  ss_vdp_mem_terms;
assign ss_dbg2 = {23'b0, ss_vdp_mem_terms};

// Genesis.sv: `reset = reset_base | ss_slot_recover` for the machine and the
// orchestrator; the slot engine itself only sees reset_base. Both also reset
// with the cartridge download.
wire ss_reset = machine_reset | ss_slot_recover;
assign ss_recover = ss_slot_recover;

// No periodic header probe (r2.16): the glue's slot scanner knows the slots, and the probe's
// two DDR reads every 19.5 ms delayed a few ROM fetches a second by a few clocks.
ss_slot_engine #(.PROBE(0)) ss_slot_engine
(
	.clk(clk_sys), .reset(machine_reset | loading),
	.save_cmd(ss_save), .load_cmd(ss_load), .ping_cmd(1'b0),
	.selected_slot(ss_slot), .rom_identity(ss_rom_identity),
	.config_identity(ss_config_identity),
	.blocked(ss_snapshot_busy | ss_m68k_busy | ss_freeze_ack),
	.supported(ss_supported & ss_rom_ready),
	.orch_start(ss_orch_start),
	.persistent_enable(ss_orch_enable),
	.persistent_ready(ss_orch_ready), .persistent_bad(ss_slot_bad),
	.persistent_done(ss_orch_done), .persistent_failed(ss_orch_failed),
	.orch_busy(ss_snapshot_busy), .orch_pass(ss_snapshot_pass),
	.orch_fail(ss_snapshot_fail), .sys_fail(ss_sys_fail),
	.load_mode(ss_slot_load), .save_return(ss_slot_save_return),
	.mem_active(ss_slot_active), .mem_addr(ss_slot_addr),
	.mem_din(ss_slot_di), .mem_we(ss_slot_we), .mem_dout(ss_slot_read),
	.ddr_req(ss_mem_req), .ddr_rnw(ss_mem_rnw),
	.ddr_addr(ss_mem_addr), .ddr_din(ss_mem_din),
	.ddr_be(ss_mem_be_unused), .ddr_dout(ss_mem_dout), .ddr_ack(ss_mem_ack),
	.busy(ss_busy), .pass(ss_pass), .fail(ss_fail),
	.slot_valid(ss_slot_valid), .recover_reset(ss_slot_recover),
	.source_crc(ss_source_crc_unused), .checked_crc(ss_checked_crc_unused), .error_code(ss_error)
);

ss_snapshot_orchestrator ss_snapshot_orchestrator
(
	.clk                (clk_sys),
	.reset              (ss_reset | loading),
	.start              (ss_orch_start),
	.vdp_scan_enable    (ss_orch_start),

	.persistent_enable  (ss_orch_enable),
	.persistent_done    (ss_orch_done),
	.persistent_failed  (ss_orch_failed),
	.persistent_ready   (ss_orch_ready),
	.persistent_bad     (ss_slot_bad), .capture_error(ss_capture_error), .persistent_load(ss_slot_load),
	.slot_z80_we        (ss_slot_we && ss_slot_addr >= 18'h303A0 && ss_slot_addr < 18'h303C0),
	.slot_z80_addr      (ss_slot_addr[4:0]), .slot_z80_din(ss_slot_di),
	.slot_z80_dout      (ss_slot_z80_do),

	.m68k_req           (ss_orch_m68k_req),
	.m68k_restore_req   (ss_orch_m68k_restore_req),
	.m68k_capture_start (ss_m68k_capture_start),
	.m68k_capture_ready (ss_m68k_capture_ready),
	.m68k_mem_safe      (ss_m68k_mem_safe),
	.m68k_busy          (ss_m68k_busy),
	.m68k_pass          (ss_m68k_pass),
	.m68k_fail          (ss_m68k_fail),

	.vdp_vbl            (ss_vdp_vbl),
	.vdp_render_idle    (ss_vdp_render_idle),
	.vdp_scan_idle      (ss_vdp_scan_idle),

	.z80_reg            (ss_z80_reg),
	.z80_dir            (ss_orch_z80_dir),
	.z80_set            (ss_orch_z80_set),
	.z80_drive          (ss_orch_z80_drive),

	.mem_active         (ss_orch_mem_active),
	.mem_addr           (ss_orch_mem_addr),
	.mem_dout           (ss_tmem_dout),

	.busy               (ss_snapshot_busy),
	.pass               (ss_snapshot_pass),
	.fail               (ss_snapshot_fail),
	.crc_first          (ss_snapshot_crc_first_unused),
	.crc_second         (ss_snapshot_crc_second_unused),
	.vdp_crc            (ss_snapshot_vdp_crc_unused),
	.dbg_state          (ss_orch_dbg_state)
);

system system
(
	.RESET_N(~ss_reset),
	.MCLK(clk_sys),

	.LOADING(loading),
	.RAM_INIT(ram_init),
	.PAUSE_EN(pause),

	.PAL(pal),
	.EXPORT(region_export),

	.SRAM_QUIRK(sram_quirk),
	.SRAM00_QUIRK(sram00_quirk),
	.EEPROM_QUIRK(eeprom_quirk),
	.NORAM_QUIRK(noram_quirk),
	.FAST_FIFO(fifo_quirk),
	.FMBUSY_QUIRK(fmbusy_quirk),
	.SCHAN_QUIRK(schan_quirk),
	// Hardware this port does not build (docs/md-port-design.md section 11).
	.PIER_QUIRK(1'b0),
	.SVP_QUIRK(1'b0),

	.TURBO(2'b00),

	// Audio
	.LPF_MODE(lpf_mode),
	.ENABLE_FM(enable_fm),
	.ENABLE_PSG(enable_psg),
	.EN_HIFI_PCM(en_hifi_pcm),
	.LADDER(ladder),
	.DAC_LDATA(audio_l),
	.DAC_RDATA(audio_r),

	// Cheats: compiled out by MD_NO_CHEATS.
	.GG_RESET(1'b0),
	.GG_EN(1'b0),
	.GG_CODE(129'd0),
	.GG_AVAILABLE(gg_available_unused),

	// Cartridge save RAM host port.
	.BRAM_A(bram_a),
	.BRAM_DI(bram_di),
	.BRAM_DO(bram_do),
	.BRAM_WE(bram_we),
	.BRAM_CHANGE(bram_change),

	// Video
	.RED(video_r),
	.GREEN(video_g),
	.BLUE(video_b),
	.VS(video_vs_unused),
	.HS(video_hs_unused),
	.HBL(video_hbl),
	.VBL(video_vbl),
	.CE_PIX(video_ce),
	.BORDER(border),
	.CRAM_DOTS(cram_dots),
	.INTERLACE(interlace_unused),
	.FIELD(field_unused),
	.RESOLUTION(video_resolution),
	.OBJ_LIMIT_HIGH(obj_limit_high),
	.TRANSP_DETECT(transp_detect_unused),

	// Controls: one pad on port 1, nothing on port 2.
	.J3BUT(pad_3button),
	.JOY_1(joy_1),
	.JOY_2(12'd0),
	.JOY_3(12'd0),
	.JOY_4(12'd0),
	.JOY_5(12'd0),
	.MULTITAP(3'd0),
	.MOUSE(25'd0),
	.MOUSE_OPT(3'd0),
	.GUN_OPT(1'b0),
	.GUN_TYPE(1'b0),
	.GUN_SENSOR(1'b0),
	.GUN_A(1'b0),
	.GUN_B(1'b0),
	.GUN_C(1'b0),
	.GUN_START(1'b0),
	.SERJOYSTICK_IN(8'd0),
	.SERJOYSTICK_OUT(serjoystick_out_unused),
	.SER_OPT(2'b00),

	// Cartridge ROM
	.ROMSZ(rom_size),
	.ROM_ADDR(rom_addr),
	.ROM_DATA(rom_data),
	.ROM_WDATA(rom_wdata),
	.ROM_WE(rom_we),
	.ROM_BE(rom_be),
	.ROM_REQ(rom_req),
	.ROM_ACK(rom_ack),

	// The SVP's second ROM port: compiled out by MD_NO_SVP.
	.ROM_ADDR2(),
	.ROM_DATA2(16'd0),
	.ROM_REQ2(),
	.ROM_ACK2(1'b0),

	// Save states, as the fork's Genesis.sv connects them. The test requests
	// are tied off; the orchestrated path is what a save and a load use.
	.SS_FREEZE_REQ(1'b0),
	.SS_FREEZE_ACK(ss_freeze_ack),
	.SS_FREEZE_CAPTURE(ss_freeze_capture_unused),
	.SS_Z80_REG(ss_z80_reg),
	.SS_Z80_DIR(ss_z80_dir),
	.SS_Z80_SET(ss_z80_set),
	.SS_M68K_TEST_REQ(1'b0),
	.SS_M68K_TEST_BUSY(ss_m68k_busy),
	.SS_M68K_TEST_PASS(ss_m68k_pass),
	.SS_M68K_TEST_FAIL(ss_m68k_fail),
	.SS_M68K_ORCH_REQ(ss_orch_m68k_req),
	.SS_M68K_ORCH_RESTORE(ss_orch_m68k_restore_req),
	.SS_M68K_CAPTURE_START(ss_m68k_capture_start),
	.SS_M68K_CAPTURE_READY(ss_m68k_capture_ready),
	.SS_M68K_MEM_SAFE(ss_m68k_mem_safe),
	.SS_VDP_VBL(ss_vdp_vbl),
	.SS_VDP_RENDER_IDLE(ss_vdp_render_idle),
	.SS_VDP_SCAN_IDLE(ss_vdp_scan_idle),
	.SS_VDP_AUDIO_REPLAY_ENABLE(ss_orch_start),
	.SS_SYS_PASS(ss_sys_pass),
	.SS_SYS_FAIL(ss_sys_fail),
	.SS_DBG(ss_sys_dbg),
	.SS_MEM_TERMS(ss_vdp_mem_terms),
	.SS_SLOT_ACTIVE(ss_slot_active),
	.SS_SLOT_SAVE_RETURN(ss_slot_save_return),
	.SS_SLOT_ADDR(ss_slot_addr),
	.SS_SLOT_DI(ss_slot_di),
	.SS_SLOT_WE(ss_slot_we),
	.SS_SLOT_DO(ss_slot_do),
	.SS_SLOT_SUPPORTED(ss_supported),
	.SS_MEM_ADDR(ss_tmem_addr),
	.SS_MEM_DI(8'd0),
	.SS_MEM_DO(ss_tmem_dout),
	.SS_MEM_WE(1'b0),

	// Debug layer toggles stay on.
	.BGA_EN(1'b1),
	.BGB_EN(1'b1),
	.SPR_EN(1'b1),
	.DBG_M68K_A(dbg_m68k_a),
	.DBG_VBUS_A(dbg_vbus_a_unused)
);

endmodule
