// Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
// Copyright (c) 2018 Sorgelig
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.

module system
(
	input         RESET_N,
	input         MCLK,

	input   [1:0] LPF_MODE,
	input         ENABLE_FM,
	input         ENABLE_PSG,
	output [15:0] DAC_LDATA,
	output [15:0] DAC_RDATA,

	input         LOADING,
	// Game Bub: upstream clears the work RAM, VRAM and cartridge save RAM
	// through their B ports for as long as LOADING is high (the whole
	// cartridge download). We need that port free for the host's `.sav`
	// window while the core is still in setup, so the clear has its own
	// input and the glue pulses it for 65,536 clocks (docs/md-port-design.md
	// sections 2 and 5). LOADING keeps every other role it has.
	input         RAM_INIT,
	input         PAL,
	input         EXPORT,
	input         FAST_FIFO,
	input         SRAM_QUIRK,
	input         SRAM00_QUIRK,
	input         EEPROM_QUIRK,
	input         NORAM_QUIRK,
	input         PIER_QUIRK,
	input         SVP_QUIRK, 
	input         FMBUSY_QUIRK,
	input         SCHAN_QUIRK,

	input   [1:0] TURBO,

	input         GG_RESET,
	input         GG_EN,
	input [128:0] GG_CODE,
	output        GG_AVAILABLE,

	input  [14:0] BRAM_A,
	input  [15:0] BRAM_DI,
	output [15:0] BRAM_DO,
	input         BRAM_WE,
	output        BRAM_CHANGE,

	output  [3:0] RED,
	output  [3:0] GREEN,
	output  [3:0] BLUE,
	output        VS,
	output        HS,
	output        HBL,
	output        VBL,
	output        CE_PIX,
	input         BORDER,
	input         CRAM_DOTS,

	output        INTERLACE,
	output        FIELD,
	output  [1:0] RESOLUTION,

	input         J3BUT,
	input  [11:0] JOY_1,
	input  [11:0] JOY_2,
	input  [11:0] JOY_3,
	input  [11:0] JOY_4,
	input  [11:0] JOY_5,
	input   [2:0] MULTITAP,

	input  [24:0] MOUSE,
	input   [2:0] MOUSE_OPT,
	
	input         GUN_OPT,
	input         GUN_TYPE,
	input         GUN_SENSOR,
	input         GUN_A,
	input         GUN_B,
	input         GUN_C,
	input         GUN_START,

	input   [7:0] SERJOYSTICK_IN,
	output  [7:0] SERJOYSTICK_OUT,
	input   [1:0] SER_OPT,

	input  [24:1] ROMSZ,
	output [24:1] ROM_ADDR,
	input  [15:0] ROM_DATA,
	output [15:0] ROM_WDATA,
	output reg    ROM_WE,
	output  [1:0] ROM_BE,
	output reg    ROM_REQ,
	input         ROM_ACK,

	output [24:1] ROM_ADDR2,
	input  [15:0] ROM_DATA2,
	output        ROM_REQ2,
	input         ROM_ACK2, 
	
	input         EN_HIFI_PCM,
	input         LADDER,
	input         OBJ_LIMIT_HIGH,

	output		  TRANSP_DETECT,
	
	// save-state freeze handshake (v0.1)
	input         SS_FREEZE_REQ,
	output        SS_FREEZE_ACK,
	output        SS_FREEZE_CAPTURE,

	// v0.5 Z80 architectural state interface
	output [229:0] SS_Z80_REG,
	input  [229:0] SS_Z80_DIR,
	input          SS_Z80_SET,

	// v0.6 FX68K architectural-state handler diagnostic
	input          SS_M68K_TEST_REQ,
	output         SS_M68K_TEST_BUSY,
	output         SS_M68K_TEST_PASS,
	output         SS_M68K_TEST_FAIL,

	// v0.8 staged M68K save/hold/restore handshake
	input          SS_M68K_ORCH_REQ,
	input          SS_M68K_ORCH_RESTORE,
	output         SS_M68K_CAPTURE_START,
	output         SS_M68K_CAPTURE_READY,
	output         SS_M68K_MEM_SAFE,
	output         SS_VDP_VBL,
	output         SS_VDP_RENDER_IDLE,
    output         SS_VDP_SCAN_IDLE,
	// R56 diagnostic mode selector. Latched on SS_M68K_CAPTURE_START so
	// changing the OSD switch after a request cannot alter an in-flight restore.
	input          SS_VDP_AUDIO_REPLAY_ENABLE,
	output         SS_SYS_PASS,
	output         SS_SYS_FAIL,
	// Game Bub: save-state diagnostics: [19:16] the 68000 capture handler state, [15] the safe point,
	// [14] INTACK, [13] the handler holds the 68000 in reset, [12] IRQ7 forced, [11] Z80_BUSRQ_N,
	// [10] Z80_RESET_N, [9] Z80 ISET 0, [8] Z80 MREQ, [7] Z80 M1, [6] no hold, [5] VDP renderer idle,
	// [4] VDP memory idle, [3] no VBUS, [2] 68000 AS high, [1] MBUS idle, [0] VBL.
	output  [19:0] SS_DBG,
	// Game Bub: the VDP's nine SS_MEM_IDLE terms, 1 = busy (vdp.vhd SS_MEM_TERMS; register 0x0030).
	output   [8:0] SS_MEM_TERMS,

    input         SS_SLOT_ACTIVE,
    input         SS_SLOT_SAVE_RETURN,
    input  [17:0] SS_SLOT_ADDR,
    input   [7:0] SS_SLOT_DI,
    input         SS_SLOT_WE,
    output reg [7:0] SS_SLOT_DO,
    output        SS_SLOT_SUPPORTED,

	input  [17:0] SS_MEM_ADDR,
	input   [7:0] SS_MEM_DI,
	output  [7:0] SS_MEM_DO,
	input         SS_MEM_WE,

	//debug
	input         PAUSE_EN,
	input         BGA_EN,
	input         BGB_EN,
	input         SPR_EN,
	output [23:0] DBG_M68K_A,
	output [23:0] DBG_VBUS_A
);

reg reset;
reg hard_reset;
always @(posedge MCLK) if(M68K_CLKENn) begin
	reset <= ~RESET_N | LOADING;
	hard_reset <= LOADING;
end

//--------------------------------------------------------------
// CLOCK ENABLERS
//--------------------------------------------------------------
wire ss_hold;
wire ss_m68k_pause_aux;
// v1.4 audio replay must keep the YM2612 external CEN cadence running while
// the CPUs remain frozen. The replay engine asserts this only during its
// private reset/register-replay phase.
wire ss_audio_clock_override;
wire core_pause = PAUSE_EN | ss_hold;
wire aux_pause = core_pause | ss_m68k_pause_aux;

wire M68K_CLKEN = M68K_CLKENp;
reg  M68K_CLKENp, M68K_CLKENn;
reg  Z80_CLKENp, Z80_CLKENn, PSG_CLKEN;
reg  FM_CLKEN;

always @(negedge MCLK) begin
	static reg [3:0] FCLKCNT = 0;
	static reg [3:0] VCLKCNT = 0;
	static reg [3:0] ZCLKCNT = 0;
	static reg [3:0] PCLKCNT = 0;
	static reg [3:0] VCLKMAX = 0;
	static reg [3:0] VCLKMID = 0;

	if(~RESET_N | LOADING) begin
		VCLKCNT <= 0;
		PCLKCNT <= 0;
		FCLKCNT <= 0;
		Z80_CLKENp <= 1;
		Z80_CLKENn <= 1;
		PSG_CLKEN <= 1;
		M68K_CLKENp <= 1;
		M68K_CLKENn <= 1;
		VCLKMAX = 6;
		VCLKMID = 3;
	end
	else begin
		Z80_CLKENn <= 0;
		ZCLKCNT <= ZCLKCNT + 1'b1;
		if (ZCLKCNT == 14) begin
			ZCLKCNT <= 0;
			Z80_CLKENn <= ~aux_pause;
		end
		
		Z80_CLKENp <= 0;
		if (ZCLKCNT == 7) begin
			Z80_CLKENp <= ~aux_pause;
		end

		PSG_CLKEN <= 0;
		PCLKCNT <= PCLKCNT + 1'b1;
		if (PCLKCNT == 14) begin
			PCLKCNT <= 0;
			PSG_CLKEN <= ~aux_pause;
		end

		M68K_CLKENp <= 0;
		VCLKCNT <= VCLKCNT + 1'b1;
		if (VCLKCNT == VCLKMAX) begin
			VCLKCNT <= 0;
			M68K_CLKENp <= ~core_pause;
			VCLKMAX <= (TURBO == 2) ? 4'd1 : (TURBO == 1) ? 4'd3 : 4'd6;
			VCLKMID <= (TURBO == 2) ? 4'd0 : (TURBO == 1) ? 4'd1 : 4'd3;
		end

		M68K_CLKENn <= 0;
		if (VCLKCNT == VCLKMID) begin
			M68K_CLKENn <= ~core_pause;
		end

		FM_CLKEN <= 0;
		FCLKCNT <= FCLKCNT + 1'b1;
		if (FCLKCNT == 6) begin
			FCLKCNT <= 0;
			FM_CLKEN <= (~aux_pause | ss_audio_clock_override);
		end
	end
end

reg [16:1] ram_rst_a;
always @(posedge MCLK) ram_rst_a <= ram_rst_a + RAM_INIT; // Game Bub: RAM_INIT was LOADING


//--------------------------------------------------------------
// CPU 68000
//--------------------------------------------------------------
wire [23:1] M68K_A;
wire [15:0] M68K_DO;
wire        M68K_AS_N;
wire        M68K_UDS_N;
wire        M68K_LDS_N;
wire        M68K_RNW;
wire  [2:0] M68K_FC;
wire        M68K_BG_N;
wire        M68K_BR_N;
wire        M68K_BGACK_N;

wire        ss_m68k_irq7;
wire        ss_m68k_cpu_reset;
wire  [3:0] ss_m68k_dbg_state; // Game Bub: diagnostics
wire        ss_m68k_din_en;
wire [15:0] ss_m68k_din_data;
wire [31:0] ss_m68k_saved_ssp;

reg   [2:0] M68K_IPL_N;
always @(posedge MCLK) begin
	static reg       old_as;
	static reg [1:0] scnt;
	
	if(reset) M68K_IPL_N <= 3'b111;
	else if (M68K_CLKEN) begin
		old_as <= M68K_AS_N;
		scnt <= scnt + 1'd1;
		if(~M68K_AS_N) scnt <= 0;
		if((~old_as & M68K_AS_N) || &scnt) begin
			if (M68K_VINT) M68K_IPL_N <= 3'b001;
			else if (M68K_HINT) M68K_IPL_N <= 3'b011;
			else if (M68K_EXINT) M68K_IPL_N <= 3'b101;
			else M68K_IPL_N <= 3'b111;
		end
	end
end

wire M68K_INTACK = &M68K_FC;
wire [2:0] M68K_IPL_IN_N = ss_m68k_irq7 ? 3'b000 : M68K_IPL_N;

assign M68K_BR_N = VBUS_BR_N & Z80_BR_N;
assign M68K_BGACK_N = VBUS_BGACK_N & Z80_BGACK_N;

fx68k M68K
(
	.clk(MCLK),
	.extReset(reset | ss_m68k_cpu_reset),
	.pwrUp(hard_reset | ss_m68k_cpu_reset),
	.enPhi1(M68K_CLKENp),
	.enPhi2(M68K_CLKENn),

	.eRWn(M68K_RNW),
	.ASn(M68K_AS_N),
	.UDSn(M68K_UDS_N),
	.LDSn(M68K_LDS_N),

	.FC0(M68K_FC[0]),
	.FC1(M68K_FC[1]),
	.FC2(M68K_FC[2]),

	.BGn(M68K_BG_N),
	.BRn(M68K_BR_N),
	.BGACKn(M68K_BGACK_N),
	.HALTn(1),

	.DTACKn(M68K_MBUS_DTACK_N),
	.VPAn(~M68K_INTACK),
	.BERRn(1),
	.IPL0n(M68K_IPL_IN_N[0]),
	.IPL1n(M68K_IPL_IN_N[1]),
	.IPL2n(M68K_IPL_IN_N[2]),
	.iEdb(ss_m68k_din_en ? ss_m68k_din_data : genie_data),
	.oEdb(M68K_DO),
	.eab(M68K_A)
);


assign DBG_M68K_A = {M68K_A,1'b0};
assign DBG_VBUS_A = {VBUS_A,1'b0};

//--------------------------------------------------------------
// CHEAT CODES
//--------------------------------------------------------------

// Game Bub: MD_NO_CHEATS leaves the cheat engine out. It sits on the 68000
// read path and holds block RAM tables, so constant propagation would not
// remove it, and nothing on this handheld can deliver a code file.
wire [15:0] genie_data;
`ifdef MD_NO_CHEATS
assign genie_data = M68K_MBUS_D;
assign GG_AVAILABLE = 0;
`else
CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) codes
(
	.clk(MCLK),
	.reset(LOADING | GG_RESET),
	.enable(~GG_EN),
	.code(GG_CODE),
	.available(GG_AVAILABLE),
	.addr_in({M68K_A[23:1], 1'b0}),
	.data_in(M68K_MBUS_D),
	.data_out(genie_data)
);
`endif


//--------------------------------------------------------------
// VDP + PSG
//--------------------------------------------------------------
reg         VDP_SEL;
wire [15:0] VDP_DO;
wire        VDP_DTACK_N;

wire [23:1] VBUS_A;
wire        VBUS_SEL;
wire        VBUS_BR_N;
wire        VBUS_BGACK_N;

wire        M68K_EXINT;
wire        VDP_SS_MEM_IDLE;
wire  [8:0] VDP_SS_MEM_TERMS;
wire        VDP_SS_RENDER_IDLE;
wire        VDP_SS_SCAN_IDLE;
wire        VDP_SS_SCAN_BLANK;
wire        ss_vdp_mem_sel;
wire  [7:0] ss_vdp_mem_do;
wire        ss_vram_sel;

// v1.2 VDP-memory snapshot shadow + replay engine. Keeping it inside system.sv
// preserves the proven top-level SS interface from v1.1.
// Game Bub: distributed (LUT) RAM, not block RAM: the build has 1.5 of 135 block RAM tiles
// free and this shadow alone would take 16 (R58 marks it M10K for Quartus).
(* ram_style = "distributed" *) reg [7:0] ss_vram_shadow [0:65535];
(* ram_style = "distributed" *) reg [7:0] ss_vdp_local_shadow [0:767]; // Game Bub: LUT RAM (see above)
reg         ss_vdp_shadow_capture;
reg         ss_vdp_shadow_valid;
reg         ss_vdp_mem_restore_active;
reg         ss_vdp_mem_restore_primed;
reg         ss_vdp_mem_restore_finalize;
reg         ss_vdp_mem_restore_final_pulse;
reg  [16:0] ss_vdp_restore_rd_index;
reg  [16:0] ss_vdp_restore_wr_index;
// R57 fix1: each RAM owns a dedicated synchronous output register.
// Select the bank AFTER those registers, using the equally delayed bank tag.
// A common resettable register fed by both arrays prevents Quartus 18.1
// from absorbing the read registers into M10K RAMs (Error 276003).
reg [7:0] ss_vram_shadow_q;
reg [7:0] ss_vdp_local_shadow_q;
reg       ss_shadow_read_bank_q;
wire [7:0] ss_vdp_restore_data_q = ss_shadow_read_bank_q ?
    ss_vdp_local_shadow_q : ss_vram_shadow_q;
wire [16:0] ss_slot_shadow_read_index = SS_SLOT_ACTIVE ?
    (SS_SLOT_ADDR < 18'h30000 ? {1'b0,SS_SLOT_ADDR[15:0]} :
                              17'd65536 + {7'd0,SS_SLOT_ADDR[9:0]}) : ss_vdp_restore_rd_index;
reg  [17:0] ss_mem_addr_ext_d;
wire [17:0] ss_shadow_write_addr = SS_SLOT_WE ? SS_SLOT_ADDR : ss_mem_addr_ext_d;
wire [7:0] ss_shadow_write_data = SS_SLOT_WE ? SS_SLOT_DI : SS_MEM_DO;
wire ss_shadow_write_en = SS_SLOT_WE || (ss_vdp_shadow_capture && !ss_vdp_mem_restore_active);
wire ss_shadow_vram_we = ss_shadow_write_en && ss_shadow_write_addr[17:16] == 2'b10;
wire ss_shadow_local_we = ss_shadow_write_en && ss_shadow_write_addr >= 18'h30000 &&
                         ss_shadow_write_addr <= 18'h302FF;


wire [17:0] ss_vdp_restore_addr =
    (ss_vdp_restore_wr_index < 17'd65536) ?
        (18'h20000 + ss_vdp_restore_wr_index) :
        (18'h30000 + (ss_vdp_restore_wr_index - 17'd65536));

wire ss_slot_cpu = SS_SLOT_ACTIVE && SS_SLOT_ADDR < 18'h12000;
wire [17:0] ss_mem_addr_user = ss_slot_cpu ? SS_SLOT_ADDR : SS_MEM_ADDR;
wire [7:0] ss_mem_di_user = ss_slot_cpu ? SS_SLOT_DI : SS_MEM_DI;
wire ss_mem_we_user = ss_slot_cpu ? SS_SLOT_WE : SS_MEM_WE;
wire [17:0] ss_mem_addr_eff = ss_vdp_mem_restore_active ? ss_vdp_restore_addr : ss_mem_addr_user;
wire  [7:0] ss_mem_di_eff   = ss_vdp_mem_restore_active ? ss_vdp_restore_data_q : ss_mem_di_user;
wire        ss_mem_we_eff   = ss_vdp_mem_restore_active ? ss_vdp_mem_restore_primed : ss_mem_we_user;

// v1.4: a full VDP test now restores audio after the 66,304-byte VDP memory
// replay and before releasing FX68K/Z80/VDP architectural state. CPU-only
// tests retain the old immediate path. This keeps audio restore completely
// inside the already-proven frozen interval.
wire ss_audio_restore_done_pulse;
// R56 isolates VDP memory replay from architectural YM2612/PSG replay.
// Full mode preserves the v1.4 path. In no-audio mode the exact same
// 66,304-byte VDP memory replay completes first, then the common VDP/M68K
// restore pulse is released immediately instead of entering SSA_* replay.
// The mode is latched on the capture edge below and cannot change mid-cycle.
reg  ss_vdp_audio_replay_latched;
wire ss_restore_common_pulse =
    ss_audio_restore_done_pulse |
    (ss_vdp_mem_restore_final_pulse & ~ss_vdp_audio_replay_latched) |
    (SS_M68K_ORCH_RESTORE & (~ss_vdp_shadow_valid | SS_SLOT_SAVE_RETURN));

wire        M68K_HINT;
wire        M68K_VINT;
wire        Z80_VINT;

wire        vram_req;
wire        vram_we_u = vram_we & ~vram_u_n;
wire        vram_we_l = vram_we & ~vram_l_n;
wire        vram_we;
wire        vram_u_n;
wire        vram_l_n;
wire [15:1] vram_a;
wire [15:0] vram_d;
wire [15:0] vram_q1, vram_q2;

wire        vram32_req;
wire [15:1] vram32_a;
wire [31:0] vram32_q;

assign ss_vram_sel    = (ss_mem_addr_eff[17:16] == 2'b10);
assign ss_vdp_mem_sel = (ss_mem_addr_eff[17:16] == 2'b11);

dpram #(14) vram_l1
(
	.clock(MCLK),
	// Game Bub: the Xilinx dpram is VHDL with defaulted enable/cs ports. Vivado does not
	// apply a VHDL port default to an instance made from Verilog (xsim does), so left
	// unconnected they tie low, q_a reads as all ones and the memory is optimized away.
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[7:0]),
	.wren_a(vram_we_l & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[7:0]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[14:1] : (ss_vram_sel ? ss_mem_addr_eff[15:2] : vram32_a[15:2])),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & ss_vram_sel & (ss_mem_addr_eff[1:0] == 2'b00))),
	.q_b(vram32_q[7:0])
);

dpram #(14) vram_u1
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[15:8]),
	.wren_a(vram_we_u & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[15:8]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[14:1] : (ss_vram_sel ? ss_mem_addr_eff[15:2] : vram32_a[15:2])),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & ss_vram_sel & (ss_mem_addr_eff[1:0] == 2'b01))),
	.q_b(vram32_q[15:8])
);

dpram #(14) vram_l2
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[7:0]),
	.wren_a(vram_we_l & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[7:0]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[14:1] : (ss_vram_sel ? ss_mem_addr_eff[15:2] : vram32_a[15:2])),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & ss_vram_sel & (ss_mem_addr_eff[1:0] == 2'b10))),
	.q_b(vram32_q[23:16])
);

dpram #(14) vram_u2
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[15:8]),
	.wren_a(vram_we_u & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[15:8]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[14:1] : (ss_vram_sel ? ss_mem_addr_eff[15:2] : vram32_a[15:2])),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & ss_vram_sel & (ss_mem_addr_eff[1:0] == 2'b11))),
	.q_b(vram32_q[31:24])
);

reg vram_ack;
always @(posedge MCLK) vram_ack <= vram_req;

reg vram32_ack;
always @(posedge MCLK) vram32_ack <= vram32_req;

wire VDP_hs, VDP_vs;
assign HS = ~VDP_hs;
assign VS = ~VDP_vs;

wire HL;

vdp vdp
(
	.RST_n(~hard_reset),
	.CLK(MCLK),

	.SEL(VDP_SEL),
	.A({MBUS_A[4:1], 1'b0}),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO),
	.DO(VDP_DO),
	.DTACK_n(VDP_DTACK_N),

	.VRAM_req(vram_req),
	.VRAM_ack(vram_ack),
	.VRAM_we(vram_we),
	.VRAM_u_n(vram_u_n),
	.VRAM_l_n(vram_l_n),
	.VRAM_a(vram_a),
	.VRAM_d(vram_d),
	.VRAM_q(vram_a[1] ? vram_q2 : vram_q1),

	.VRAM32_req(vram32_req),
	.VRAM32_ack(vram32_ack),
	.VRAM32_a(vram32_a),
	.VRAM32_q(vram32_q),
	
	.EXINT(M68K_EXINT),
	.HL(HL),
	
	.HINT(M68K_HINT),
	.VINT_TG68(M68K_VINT),
	.INTACK(M68K_INTACK),

	.VINT_T80(Z80_VINT),

	.VBUS_addr(VBUS_A),
	.VBUS_data(VDP_MBUS_D),
	.VBUS_sel(VBUS_SEL),
	.VBUS_dtack_n(VDP_MBUS_DTACK_N),

	.BG_N(M68K_BG_N),
	.BR_N(VBUS_BR_N),
	.BGACK_N(VBUS_BGACK_N),

	.VRAM_SPEED(~(FAST_FIFO|(|TURBO))), // Game Bub: |TURBO, so the expression is 1 bit
	.VSCROLL_BUG(1'b0), // Game Bub: sized, the VHDL port is one std_logic
	.BORDER_EN(BORDER),
	.CRAM_DOTS(CRAM_DOTS),
	.SVP_QUIRK(SVP_QUIRK),
	.OBJ_LIMIT_HIGH_EN(OBJ_LIMIT_HIGH),

	.FIELD_OUT(FIELD),
	.INTERLACE(INTERLACE),
	.RESOLUTION(RESOLUTION),

	.PAL(PAL),
	.R(RED),
	.G(GREEN),
	.B(BLUE),
	.HS(VDP_hs),
	.VS(VDP_vs),
	.CE_PIX(CE_PIX),
	.HBL(HBL),
	.VBL(VBL),

	.TRANSP_DETECT(TRANSP_DETECT),
	.SS_MEM_IDLE(VDP_SS_MEM_IDLE),
	.SS_MEM_TERMS(VDP_SS_MEM_TERMS),
	.SS_RENDER_IDLE(VDP_SS_RENDER_IDLE),
    .SS_SCAN_IDLE(VDP_SS_SCAN_IDLE),
    .SS_SCAN_BLANK(VDP_SS_SCAN_BLANK),
	.SS_STATE_CAPTURE(SS_M68K_CAPTURE_START),
	.SS_STATE_RESTORE(ss_restore_common_pulse & ~SS_SLOT_SAVE_RETURN),
    .SS_SLOT_EN(SS_SLOT_ACTIVE),
    .SS_SLOT_WE(SS_SLOT_WE && SS_SLOT_ADDR[17:6] == (18'h30300 >> 6)),
    .SS_SLOT_ADDR(SS_SLOT_ADDR[5:0]), .SS_SLOT_DI(SS_SLOT_DI),
    .SS_SLOT_DO(ss_slot_vdp_do),
	.SS_MEM_EN(ss_vdp_mem_sel),
	.SS_MEM_ADDR(ss_mem_addr_eff[9:0]),
	.SS_MEM_DI(ss_mem_di_eff),
	.SS_MEM_DO(ss_vdp_mem_do),
	.SS_MEM_WE(ss_mem_we_eff),
	
	.BGA_EN(BGA_EN),
	.BGB_EN(BGB_EN),
	.SPR_EN(SPR_EN)
);

// PSG 0x10-0x17 in VDP space
wire signed [10:0] PSG_SND;
wire psg_bus_wr_n = MBUS_RNW | ~VDP_SEL | ~MBUS_A[4] | MBUS_A[3];

// v1.4 normalized PSG architectural mirror. The original JT89 interface is
// write-only, so mirror the eight visible configuration registers here.
// Oscillator/noise phase is intentionally canonicalized by reset+replay in
// this first audio-state milestone; a later phase-perfect pass can serialize
// tone counters/LFSR without changing this external format.
reg [9:0] ss_psg_tone0, ss_psg_tone1, ss_psg_tone2;
reg [3:0] ss_psg_vol0, ss_psg_vol1, ss_psg_vol2, ss_psg_vol3;
reg [2:0] ss_psg_ctrl3, ss_psg_regn;

wire       ss_audio_restore_active;
wire       ss_audio_psg_reset;
wire       ss_audio_filter_reset;
wire       ss_audio_psg_wr_n;
wire [7:0] ss_audio_psg_din;
wire       psg_wr_n_eff = ss_audio_restore_active ? ss_audio_psg_wr_n : psg_bus_wr_n;
wire [7:0] psg_din_eff  = ss_audio_restore_active ? ss_audio_psg_din  : MBUS_DO[15:8];

wire [2:0] ss_psg_bus_reg_sel = MBUS_DO[15] ? MBUS_DO[14:12] : ss_psg_regn;
always @(posedge MCLK) begin
    if (reset) begin
        ss_psg_tone0 <= 10'd0;
        ss_psg_tone1 <= 10'd0;
        ss_psg_tone2 <= 10'd0;
        ss_psg_vol0  <= 4'hF;
        ss_psg_vol1  <= 4'hF;
        ss_psg_vol2  <= 4'hF;
        ss_psg_vol3  <= 4'hF;
        ss_psg_ctrl3 <= 3'b100;
        ss_psg_regn  <= 3'd0;
    end
    else if (SS_SLOT_WE && SS_SLOT_ADDR >= 18'h30600 && SS_SLOT_ADDR < 18'h30680) begin
        case (SS_SLOT_ADDR[6:0])
            7'd85: begin ss_psg_tone0[1:0] <= SS_SLOT_DI[7:6]; end
            7'd86: begin ss_psg_tone0[9:2] <= SS_SLOT_DI[7:0]; end
            7'd87: begin ss_psg_tone1[7:0] <= SS_SLOT_DI[7:0]; end
            7'd88: begin ss_psg_tone1[9:8] <= SS_SLOT_DI[1:0]; ss_psg_tone2[5:0] <= SS_SLOT_DI[7:2]; end
            7'd89: begin ss_psg_tone2[9:6] <= SS_SLOT_DI[3:0]; ss_psg_vol0[3:0] <= SS_SLOT_DI[7:4]; end
            7'd90: begin ss_psg_vol1[3:0] <= SS_SLOT_DI[3:0]; ss_psg_vol2[3:0] <= SS_SLOT_DI[7:4]; end
            7'd91: begin ss_psg_vol3[3:0] <= SS_SLOT_DI[3:0]; ss_psg_ctrl3[2:0] <= SS_SLOT_DI[6:4]; ss_psg_regn[0] <= SS_SLOT_DI[7]; end
            7'd92: begin ss_psg_regn[2:1] <= SS_SLOT_DI[1:0]; end
            default: ;
        endcase
    end
    else if (!ss_audio_restore_active && !psg_bus_wr_n) begin
        ss_psg_regn <= ss_psg_bus_reg_sel;
        case (ss_psg_bus_reg_sel)
            3'd0: if (MBUS_DO[15]) ss_psg_tone0[3:0] <= MBUS_DO[11:8]; else ss_psg_tone0[9:4] <= MBUS_DO[13:8];
            3'd1: ss_psg_vol0  <= MBUS_DO[11:8];
            3'd2: if (MBUS_DO[15]) ss_psg_tone1[3:0] <= MBUS_DO[11:8]; else ss_psg_tone1[9:4] <= MBUS_DO[13:8];
            3'd3: ss_psg_vol1  <= MBUS_DO[11:8];
            3'd4: if (MBUS_DO[15]) ss_psg_tone2[3:0] <= MBUS_DO[11:8]; else ss_psg_tone2[9:4] <= MBUS_DO[13:8];
            3'd5: ss_psg_vol2  <= MBUS_DO[11:8];
            3'd6: ss_psg_ctrl3 <= MBUS_DO[10:8];
            3'd7: ss_psg_vol3  <= MBUS_DO[11:8];
        endcase
    end
end

jt89 psg
(
	.rst(reset | ss_audio_psg_reset),
	.clk(MCLK),
	.clk_en(PSG_CLKEN),

	.wr_n(psg_wr_n_eff),
	.din(psg_din_eff),

	.sound(PSG_SND)
);


//--------------------------------------------------------------
// Gamepads
//--------------------------------------------------------------
reg         IO_SEL;
wire  [7:0] IO_DO;
wire        IO_DTACK_N;

reg         JCART_SEL;
wire [15:0] JCART_DO;
wire        JCART_DTACK_N;

multitap multitap
(
	.SS_RESTORE(ss_sys_restore),
	.SS_STATE_IN(ss_sys_saved[251:53]),
	.SS_STATE_OUT(ss_io_live),
	.RESET(hard_reset),
	.CLK(MCLK),
	.CE(M68K_CLKEN),

	.J3BUT(J3BUT),

	.P1_UP(~JOY_1[3]),
	.P1_DOWN(~JOY_1[2]),
	.P1_LEFT(~JOY_1[1]),
	.P1_RIGHT(~JOY_1[0]),
	.P1_A(~JOY_1[4]),
	.P1_B(~JOY_1[5]),
	.P1_C(~JOY_1[6]),
	.P1_START(~JOY_1[7]),
	.P1_MODE(~JOY_1[8]),
	.P1_X(~JOY_1[9]),
	.P1_Y(~JOY_1[10]),
	.P1_Z(~JOY_1[11]),

	.P2_UP(~JOY_2[3]),
	.P2_DOWN(~JOY_2[2]),
	.P2_LEFT(~JOY_2[1]),
	.P2_RIGHT(~JOY_2[0]),
	.P2_A(~JOY_2[4]),
	.P2_B(~JOY_2[5]),
	.P2_C(~JOY_2[6]),
	.P2_START(~JOY_2[7]),
	.P2_MODE(~JOY_2[8]),
	.P2_X(~JOY_2[9]),
	.P2_Y(~JOY_2[10]),
	.P2_Z(~JOY_2[11]),

	.P3_UP(~JOY_3[3]),
	.P3_DOWN(~JOY_3[2]),
	.P3_LEFT(~JOY_3[1]),
	.P3_RIGHT(~JOY_3[0]),
	.P3_A(~JOY_3[4]),
	.P3_B(~JOY_3[5]),
	.P3_C(~JOY_3[6]),
	.P3_START(~JOY_3[7]),
	.P3_MODE(~JOY_3[8]),
	.P3_X(~JOY_3[9]),
	.P3_Y(~JOY_3[10]),
	.P3_Z(~JOY_3[11]),

	.P4_UP(~JOY_4[3]),
	.P4_DOWN(~JOY_4[2]),
	.P4_LEFT(~JOY_4[1]),
	.P4_RIGHT(~JOY_4[0]),
	.P4_A(~JOY_4[4]),
	.P4_B(~JOY_4[5]),
	.P4_C(~JOY_4[6]),
	.P4_START(~JOY_4[7]),
	.P4_MODE(~JOY_4[8]),
	.P4_X(~JOY_4[9]),
	.P4_Y(~JOY_4[10]),
	.P4_Z(~JOY_4[11]),
	
	.P5_UP(~JOY_5[3]),
	.P5_DOWN(~JOY_5[2]),
	.P5_LEFT(~JOY_5[1]),
	.P5_RIGHT(~JOY_5[0]),
	.P5_A(~JOY_5[4]),
	.P5_B(~JOY_5[5]),
	.P5_C(~JOY_5[6]),
	.P5_START(~JOY_5[7]),
	.P5_MODE(~JOY_5[8]),
	.P5_X(~JOY_5[9]),
	.P5_Y(~JOY_5[10]),
	.P5_Z(~JOY_5[11]),

	.FOURWAY_EN(MULTITAP == 1),
	.TEAMPLAYER_EN({MULTITAP == 3,MULTITAP == 2}),

	.MOUSE(MOUSE),
	.MOUSE_OPT(MOUSE_OPT),
	
	.GUN_OPT(GUN_OPT),
	.GUN_TYPE(GUN_TYPE),
	.GUN_SENSOR(GUN_SENSOR),
	.GUN_A(GUN_A),
	.GUN_B(GUN_B),
	.GUN_C(GUN_C),
	.GUN_START(GUN_START),

	.SERJOYSTICK_IN(SERJOYSTICK_IN),
	.SERJOYSTICK_OUT(SERJOYSTICK_OUT),
	.SER_OPT(SER_OPT),

	.PAL(PAL),
	.EXPORT(EXPORT),

	.SEL(IO_SEL),
	.A(MBUS_A[4:1]),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO[7:0]),
	.DO(IO_DO),
	.DTACK_N(IO_DTACK_N),
	.HL(HL),

	.JCART_SEL(JCART_SEL),
	.JCART_DO(JCART_DO),
	.JCART_DTACK_N(JCART_DTACK_N)
);


//-----------------------------------------------------------------------
// ROM
//-----------------------------------------------------------------------

assign ROM_ADDR = BANK_ROM ? {BANK_REG[MBUS_A[21:19]], MBUS_A[18:1]} : MBUS_A;
assign ROM_BE = ~{MBUS_UDS_N, MBUS_LDS_N};
assign ROM_WDATA = MBUS_DO;

//-----------------------------------------------------------------------
// 64KB SRAM / 128KB SVP DRAM
//-----------------------------------------------------------------------
reg SRAM_SEL;
// Game Bub: `logic`, not `wire`: they are driven from an always_comb block,
// which Quartus allows on a net and Vivado does not.
logic [15:0] sram_addr;
logic [7:0] sram_di;
logic sram_wren;

always_comb begin
`ifdef MD_NO_PIER
	// Game Bub: without the Pier Solar EEPROM the 68000 is the only owner.
	begin
`else
	if (PIER_QUIRK) begin
		sram_addr = {4'b0000, m95_addr};
		sram_di = m95_di;
		sram_wren = m95_rnw;
	end else begin
`endif
		sram_addr = MBUS_A[16:1];
		sram_di = MBUS_DO[7:0];
		sram_wren = SRAM_SEL & ~MBUS_RNW;
	end
end

// Game Bub: 64 KiB, not 128. The upstream shape is sized for the SVP's DRAM
// on port B; the cartridge save RAM itself is 64 KiB (port A addresses a byte
// with MBUS_A[16:1], port B a 16-bit word with BRAM_A[14:0]), and with
// MD_NO_SVP the upper half was dead storage worth 16 block RAM tiles.
dpram_dif #(16,8,15,16) sram
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(sram_addr),
	.data_a(sram_di),
	.wren_a(sram_wren),
	.q_a(sram_q),

	// Game Bub: RAM_INIT was LOADING, and without the SVP this port is the
	// clear and the host's `.sav` window only.
	.address_b(RAM_INIT ? ram_rst_a[15:1] : BRAM_A),
	// Initializes SRAM to 0x0 for Sonic 1 Remastered, all other games have SRAM initialized to 0xFF
	.data_b(RAM_INIT ? (SRAM00_QUIRK ? 16'h0000 : 16'hFFFF) : BRAM_DI),
	.wren_b(RAM_INIT | BRAM_WE),
	.q_b(BRAM_DO)
);

wire [7:0] sram_q;
assign BRAM_CHANGE = sram_wren;

//-----------------------------------------------------------------------
// EEPROM Handling
//-----------------------------------------------------------------------
reg ep_si, m95_so, ep_sck, ep_hold, ep_cs;
wire [7:0] m95_di, m95_q;
wire [11:0] m95_addr;
wire m95_rnw;

// Game Bub: MD_NO_PIER leaves out the Pier Solar SPI EEPROM (one homebrew
// game); it owns the save RAM's A port when PIER_QUIRK is set.
`ifdef MD_NO_PIER
assign m95_di = 8'h00;
assign m95_addr = 12'h000;
assign m95_rnw = 1'b0;
`else
STM95XXX pier_eeprom
(
	.clk(MCLK),
	.enable(PIER_QUIRK),
	.so(m95_so),
	.si(ep_si),
	.sck(ep_sck),
	.hold_n(ep_hold),
	.cs_n(ep_cs),
	.wp_n(1'b1),
	.ram_addr(m95_addr),
	.ram_q(sram_q),
	.ram_di(m95_di),
	.ram_RnW(m95_rnw)
);
`endif

//-----------------------------------------------------------------------
// SVP
//-----------------------------------------------------------------------
reg         SVP_SEL;
wire [15:0] SVP_DO;
wire        SVP_DTACK_N;

wire [15:0] SVP_DRAM_A;
wire [15:0] SVP_DRAM_DO;
wire        SVP_DRAM_WE;
wire [15:0] SVP_DRAM_DI = BRAM_DO;

// Game Bub: MD_NO_SVP leaves out the SVP (Virtua Racing only): a second
// DSP with its own instruction RAM and ROM, which constant propagation
// could not remove. SVP_QUIRK is never set in this build.
`ifdef MD_NO_SVP
assign SVP_DO = 16'h0000;
assign SVP_DTACK_N = 1'b1;
assign SVP_DRAM_A = 16'h0000;
assign SVP_DRAM_DO = 16'h0000;
assign SVP_DRAM_WE = 1'b0;
assign ROM_ADDR2 = 24'h000000;
assign ROM_REQ2 = 1'b0;
`else
reg SVP_CLKEN;
always @(posedge MCLK) SVP_CLKEN <= ~reset & ~SVP_CLKEN;

SVP svp
(
	.CLK(MCLK),
	.CE(SVP_CLKEN),
	.RST_N(~reset & SVP_QUIRK),
	.ENABLE(1),

	.BUS_A(MBUS_A[23:1]),
	.BUS_DO(SVP_DO),
	.BUS_DI(MBUS_DO),
	.BUS_SEL(SVP_SEL),
	.BUS_RNW(MBUS_RNW),
	.BUS_DTACK_N(SVP_DTACK_N),
	.DMA_ACTIVE(VBUS_SEL),

	.ROM_A(ROM_ADDR2),
	.ROM_DI(ROM_DATA2),
	.ROM_REQ(ROM_REQ2),
	.ROM_ACK(ROM_ACK2),

	.DRAM_A(SVP_DRAM_A),
	.DRAM_DI(SVP_DRAM_DI),
	.DRAM_DO(SVP_DRAM_DO),
	.DRAM_WE(SVP_DRAM_WE)
);
`endif


//-----------------------------------------------------------------------
// 68K RAM
//-----------------------------------------------------------------------
reg RAM_SEL;

wire [7:0] ss_ram68k_u_q;
wire [7:0] ss_ram68k_l_q;

dpram #(15) ram68k_u
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[15:8]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_UDS_N),
	.q_a(ram68k_q[15:8]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[15:1] : ss_mem_addr_eff[15:1]),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & (ss_mem_addr_eff[17:16] == 2'b00) & ~ss_mem_addr_eff[0])),
	.q_b(ss_ram68k_u_q)
);

dpram #(15) ram68k_l
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1), .enable_b(1'b1), .cs_b(1'b1),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[7:0]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_LDS_N),
	.q_a(ram68k_q[7:0]),

	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.address_b(RAM_INIT ? ram_rst_a[15:1] : ss_mem_addr_eff[15:1]),
	.data_b(RAM_INIT ? 8'h00 : ss_mem_di_eff),
	.wren_b(RAM_INIT | (ss_mem_we_eff & (ss_mem_addr_eff[17:16] == 2'b00) & ss_mem_addr_eff[0])),
	.q_b(ss_ram68k_l_q)
);
wire [15:0] ram68k_q;

// v1.5 System/I/O diagnostic image. Capture AFTER the save handler and
// its final MBUS transaction drain, so the last game instruction's mapper
// or I/O writes are included. This is a held-cycle diagnostic, not a file.
wire [198:0] ss_io_live;
wire [251:0] ss_sys_saved;
wire [251:0] ss_sys_live = {ss_io_live, BANK_REG[7], BANK_REG[6],
    BANK_REG[5], BANK_REG[4], BANK_REG[3], BANK_REG[2], BANK_REG[1],
    BANK_REG[0], BANK_ROM, BANK_SRAM, BAR, Z80_BUSRQ_N, Z80_RESET_N};
wire ss_sys_restore;
wire [7:0] ss_slot_vdp_do;
wire [255:0] ss_slot_sys_image = {4'd0,ss_sys_saved};
assign SS_SLOT_SUPPORTED = ss_sys_supported;
wire [7:0] ss_sys_read;
// Special peripherals remain outside the v1.5 diagnostic scope. This
// gate controls the new restore only; it does not modify v1.4 sequencing.
wire ss_sys_supported = (MULTITAP == 0) && !(|MOUSE_OPT[1:0]) &&
    !GUN_OPT && !(|SER_OPT) && !PIER_QUIRK && !SVP_QUIRK && !SCHAN_QUIRK;
ss_system_state ss_system_state (
    .clk(MCLK), .reset(reset), .begin_capture(SS_M68K_CAPTURE_START),
    .capture_safe(SS_M68K_MEM_SAFE && ss_sys_supported),
    .restore_req(ss_restore_common_pulse & ~SS_SLOT_SAVE_RETURN), .live_state(ss_sys_live),
    .slot_we(SS_SLOT_WE && SS_SLOT_ADDR >= 18'h30340 && SS_SLOT_ADDR < 18'h30360),
    .slot_addr(SS_SLOT_ADDR[4:0]), .slot_din(SS_SLOT_DI),
    .saved_state(ss_sys_saved), .restore_apply(ss_sys_restore),
    .pass(SS_SYS_PASS), .fail(SS_SYS_FAIL),
    .read_addr(SS_MEM_ADDR[5:0]), .read_data(ss_sys_read)
);

reg [1:0] ss_mem_region_d;
reg [1:0] ss_mem_byte_d;
always @(posedge MCLK) begin
	ss_mem_region_d <= ss_mem_addr_eff[17:16];
	ss_mem_byte_d   <= ss_mem_addr_eff[1:0];
	ss_mem_addr_ext_d <= SS_MEM_ADDR;
end

assign SS_MEM_DO =
    (ss_mem_addr_ext_d[17:6] == (18'h30340 >> 6)) ? ss_sys_read :
    (ss_mem_region_d == 2'b00) ? (ss_mem_byte_d[0] ? ss_ram68k_l_q : ss_ram68k_u_q) :
    (ss_mem_region_d == 2'b01) ? ss_zram_q :
    (ss_mem_region_d == 2'b10) ? (
        (ss_mem_byte_d == 2'b00) ? vram32_q[7:0]   :
        (ss_mem_byte_d == 2'b01) ? vram32_q[15:8]  :
        (ss_mem_byte_d == 2'b10) ? vram32_q[23:16] :
                                   vram32_q[31:24]
    ) :
    ss_vdp_mem_do;

// Standard single-clock simple-dual-port RAM templates. Neither the arrays
// nor their output registers have a reset. Reset gates writes and read enable;
// the existing replay PRIME cycle initializes data before the first write.
// DDR export already waits four clocks, so its byte-read latency is unchanged.
wire ss_shadow_read_en = !reset && (SS_SLOT_ACTIVE || ss_vdp_mem_restore_active);
always @(posedge MCLK) begin
    if (!reset && ss_shadow_vram_we)
        ss_vram_shadow[ss_shadow_write_addr[15:0]] <= ss_shadow_write_data;
    if (ss_shadow_read_en)
        ss_vram_shadow_q <= ss_vram_shadow[ss_slot_shadow_read_index[15:0]];
end
always @(posedge MCLK) begin
    if (!reset && ss_shadow_local_we)
        ss_vdp_local_shadow[ss_shadow_write_addr[9:0]] <= ss_shadow_write_data;
    if (ss_shadow_read_en)
        ss_vdp_local_shadow_q <= ss_vdp_local_shadow[ss_slot_shadow_read_index[9:0]];
end
always @(posedge MCLK) begin
    if (ss_shadow_read_en)
        ss_shadow_read_bank_q <= ss_slot_shadow_read_index[16];
end

// v1.2 captures exactly the bytes consumed by the orchestrator's initial VDP
// scan. A complete image is 64 KiB VRAM + 0x300 bytes of VDP-local memory
// (CRAM, VSRAM and the 512-byte persistent SAT cache) = 66,304 bytes.
always @(posedge MCLK) begin
    ss_vdp_mem_restore_final_pulse <= 1'b0;

    if (reset) begin
        ss_vdp_shadow_capture        <= 1'b0;
        ss_vdp_shadow_valid          <= 1'b0;
        ss_vdp_mem_restore_active    <= 1'b0;
        ss_vdp_mem_restore_primed    <= 1'b0;
        ss_vdp_mem_restore_finalize  <= 1'b0;
        ss_vdp_mem_restore_final_pulse <= 1'b0;
        ss_vdp_restore_rd_index      <= 17'd0;
        ss_vdp_restore_wr_index      <= 17'd0;
        ss_vdp_audio_replay_latched <= 1'b0;
    end
    else begin
        // Every new multicore capture invalidates the previous video image.
        // R56 also freezes the requested replay mode on this exact edge.
        if (SS_M68K_CAPTURE_START) begin
            ss_vdp_shadow_capture       <= 1'b1;
            ss_vdp_shadow_valid         <= 1'b0;
            ss_vdp_audio_replay_latched <= SS_VDP_AUDIO_REPLAY_ENABLE;
        end

        // SS_MEM_DO and ss_mem_addr_ext_d are aligned to the same one-clock
        // external read pipeline while the replay engine is inactive.
        if (ss_vdp_shadow_capture && !ss_vdp_mem_restore_active &&
            ss_mem_addr_ext_d == 18'h302FF) begin
            ss_vdp_shadow_capture <= 1'b0;
            ss_vdp_shadow_valid <= 1'b1;
        end

        if (SS_M68K_ORCH_RESTORE && !SS_SLOT_SAVE_RETURN) begin
            ss_vdp_shadow_capture <= 1'b0;
            if (ss_vdp_shadow_valid && !ss_vdp_mem_restore_active) begin
                ss_vdp_mem_restore_active   <= 1'b1;
                ss_vdp_mem_restore_primed   <= 1'b0;
                ss_vdp_mem_restore_finalize <= 1'b0;
                ss_vdp_restore_rd_index     <= 17'd0;
                ss_vdp_restore_wr_index     <= 17'd0;
            end
        end

        if (ss_vdp_mem_restore_active) begin
            // Synchronous shadow-RAM read. Once primed, ss_mem_we_eff writes
            // the previous cycle's data to the matching restore address.

            if (!ss_vdp_mem_restore_primed) begin
                ss_vdp_mem_restore_primed <= 1'b1;
                ss_vdp_restore_rd_index   <= 17'd1;
            end
            else begin
                if (ss_vdp_restore_wr_index == 17'd66303) begin
                    // The last byte is physically written on this edge. Drop
                    // port ownership now and issue the architectural/CPU
                    // restore pulse on the following edge.
                    ss_vdp_mem_restore_active   <= 1'b0;
                    ss_vdp_mem_restore_primed   <= 1'b0;
                    ss_vdp_mem_restore_finalize <= 1'b1;
                end
                else begin
                    ss_vdp_restore_wr_index <= ss_vdp_restore_wr_index + 1'b1;
                    if (ss_vdp_restore_rd_index < 17'd66303)
                        ss_vdp_restore_rd_index <= ss_vdp_restore_rd_index + 1'b1;
                end
            end
        end

        if (ss_vdp_mem_restore_finalize) begin
            ss_vdp_mem_restore_finalize    <= 1'b0;
            ss_vdp_mem_restore_final_pulse <= 1'b1;
        end
    end
end

//-----------------------------------------------------------------------
// MBUS Handling
//-----------------------------------------------------------------------
reg        M68K_MBUS_DTACK_N;
reg        Z80_MBUS_DTACK_N;
reg        VDP_MBUS_DTACK_N;

reg [15:0] M68K_MBUS_D;
reg  [7:0] Z80_MBUS_D;
reg [15:0] VDP_MBUS_D;

reg [23:1] MBUS_A;
reg [15:0] MBUS_DO;

reg        MBUS_RNW;
reg        MBUS_UDS_N;
reg        MBUS_LDS_N;

reg [15:0] NO_DATA;

reg  [4:0] BANK_REG[0:7];
reg        BANK_ROM;
reg        BANK_SRAM;

reg  [3:0] mstate;
reg  [1:0] msrc;
	
localparam	MSRC_NONE = 0,
				MSRC_M68K = 1,
				MSRC_Z80  = 2,
				MSRC_VDP  = 3;

localparam 	MBUS_IDLE         = 0,
				MBUS_SELECT       = 1,
				MBUS_RAM_READ     = 2,
				MBUS_ROM_READ     = 3,
				MBUS_ROM_WRITE    = 4,
				MBUS_VDP_READ     = 5,
				MBUS_IO_READ      = 6,
				MBUS_JCRT_READ    = 7,
				MBUS_SRAM_READ    = 8,
				MBUS_ZBUS_PRE     = 9,
				MBUS_ZBUS_WS 	   = 10,
				MBUS_ZBUS_READ    = 11,
				MBUS_SVP_READ     = 12,
				MBUS_REFRESH      = 13,
				MBUS_FINISH       = 14,
				MBUS_Z80_PREREAD  = 15; 

// ----------------------------------------------------------------------
// v0.6 FX68K handler diagnostic.
//
// Start only during VBlank at an externally quiet point. Unlike the normal
// savestate freeze, the 68000 itself remains running because it must execute
// the injected handler. This version is intentionally a short round-trip
// diagnostic; full memory freeze/restore comes in the next stage.
// v1.3: start the FX68K save handler only after the VDP is fully
// quiescent as well as memory-idle. This makes SS_STATE_CAPTURE occur in a
// canonical VBlank phase where no renderer/VRAM32/cache work is outstanding,
// which allows the saved live raster phase to be restored safely.
// Game Bub: the 68000 side of the point (the CPU between bus cycles, no DMA in flight, the VDP's
// FIFO empty and its memory ports quiet) and the Z80 side (an opcode fetch in the base instruction
// set) are what the capture needs; VBlank and an idle renderer are what the fork adds so that the
// raster counters it latches with the CPU describe a renderer-safe point.
wire ss_m68k_point_cpu =
    (mstate == MBUS_IDLE) &&
    M68K_AS_N &&
    !VBUS_SEL &&
    VDP_SS_MEM_IDLE &&
    !ss_hold &&
    // v0.8: begin the multicore snapshot on the same Z80 boundary
    // already proven by the v0.5 state-restore test.
    Z80_CLKENn &&
    !Z80_M1_N &&
    !Z80_MREQ_N &&
    (Z80_ISET == 2'b00);
wire ss_m68k_point_strict = ss_m68k_point_cpu && VBL && VDP_SS_RENDER_IDLE;
// Game Bub: a game that runs a DMA through every vertical blank (Comix Zone's intro: measured
// 2026-09-27, VBlank with the VDP memory idle 0.000 % of the time) never offers the strict point,
// and the fork's capture then times out. So after about five frames of waiting the capture also
// accepts the relaxed point, outside the blank: the CPU is still frozen between bus cycles with no
// DMA or FIFO write pending, the VDP memory snapshot is still taken in a following blank (a
// frozen CPU starts no new DMA), and the latched raster counters put the VDP back mid-frame on a
// load, which costs one partial frame of picture.
reg [22:0] ss_safe_wait;
always @(posedge MCLK) begin
    if (!SS_M68K_ORCH_REQ || ss_hold) ss_safe_wait <= 23'd0;
    else if (!ss_safe_wait[22]) ss_safe_wait <= ss_safe_wait + 23'd1;
end
wire ss_m68k_safe_start = ss_m68k_point_strict || (ss_safe_wait[22] && ss_m68k_point_cpu);

// After FX68K is held reset, wait once more for any VDP work that may
// have been launched while the 68000 finished the instruction preceding IRQ7.
assign SS_M68K_MEM_SAFE =
    SS_M68K_CAPTURE_READY &&
    (mstate == MBUS_IDLE) &&
    M68K_AS_N &&
    !VBUS_SEL &&
    VDP_SS_MEM_IDLE;

// Orchestrator window follows renderer activity, not cropped video blanking.
assign SS_VDP_VBL         = VDP_SS_SCAN_BLANK;
assign SS_VDP_RENDER_IDLE = VDP_SS_RENDER_IDLE;
assign SS_VDP_SCAN_IDLE = VDP_SS_SCAN_IDLE;

ss_m68k_handler_test ss_m68k_handler_test
(
    .clk        (MCLK),
    .reset      (reset),
    .start      (SS_M68K_TEST_REQ | SS_M68K_ORCH_REQ),
    .safe_start (ss_m68k_safe_start),
    .m68k_ce     (M68K_CLKENp),

    .orchestrated(SS_M68K_ORCH_REQ),
    .restore_req (ss_restore_common_pulse),
    .slot_we(SS_SLOT_WE && SS_SLOT_ADDR[17:2] == (18'h30380 >> 2)),
    .slot_addr(SS_SLOT_ADDR[1:0]), .slot_din(SS_SLOT_DI),
    .capture_start(SS_M68K_CAPTURE_START),
    .capture_ready(SS_M68K_CAPTURE_READY),

    .m68k_addr  ({M68K_A,1'b0}),
    .m68k_dout  (M68K_DO),
    .m68k_as_n  (M68K_AS_N),
    .m68k_ds_n  ({M68K_UDS_N,M68K_LDS_N}),
    .m68k_rw    (M68K_RNW),
    .m68k_fc    (M68K_FC),
    .m68k_dtack_n(M68K_MBUS_DTACK_N),
    .m68k_intack(M68K_INTACK),

    .irq7       (ss_m68k_irq7),
    .cpu_reset  (ss_m68k_cpu_reset),
    .pause_aux  (ss_m68k_pause_aux),
    .din_en     (ss_m68k_din_en),
    .din_data   (ss_m68k_din_data),

    .busy       (SS_M68K_TEST_BUSY),
    .pass       (SS_M68K_TEST_PASS),
    .fail       (SS_M68K_TEST_FAIL),
    .saved_ssp  (ss_m68k_saved_ssp),
    .dbg_state  (ss_m68k_dbg_state)
);

				
// v0.1 safe point:
// - MBUS is idle
// - 68000 is not in an active bus cycle
// - Z80 is not requesting the main bus
// - VDP is not requesting the main bus
// - freeze is accepted in VBlank for a predictable frame boundary
wire ss_safe_point =
    (mstate == MBUS_IDLE) &&
    M68K_AS_N &&
    !VBUS_SEL &&
    VDP_SS_MEM_IDLE &&
    VBL &&

    // Match the proven MiSTer T80 save boundary:
    // actual CPU tick + normal M1 opcode fetch + no active prefix.
    Z80_CLKENn &&
    !Z80_M1_N &&
    !Z80_MREQ_N &&
    (Z80_ISET == 2'b00);

assign SS_FREEZE_CAPTURE = SS_FREEZE_REQ && ss_safe_point && !ss_hold;

// Block the MBUS FSM on the *same* edge on which a freeze request is
// accepted. Without this term the controller and MBUS always blocks both
// see the old ss_hold=0 value, so MBUS could launch a new transaction while
// ss_freeze_ctrl raises hold. This closes that one-clock acceptance race.
wire ss_block_now = ss_hold || (SS_FREEZE_REQ && ss_safe_point);

ss_freeze_ctrl ss_freeze
(
    .clk        (MCLK),
    .reset      (reset),
    .req        (SS_FREEZE_REQ),
    .safe_point (ss_safe_point),
    .hold       (ss_hold),
    .ack        (SS_FREEZE_ACK)
);

always @(posedge MCLK) begin
	static reg [15:0] data;
	static reg  [3:0] pier_count;
	static reg [8:0] refresh_timer;
	static reg rfs_pend;
	static reg [1:0] rfs_wait;
	static reg [1:0] cycle_cnt;

	if (reset) begin
		M68K_MBUS_DTACK_N <= 1;
		Z80_MBUS_DTACK_N  <= 1;
		VDP_MBUS_DTACK_N  <= 1;
		VDP_SEL <= 0;
		IO_SEL <= 0;
		SVP_SEL <= 0; 
		ZBUS_SEL <= 0;
		BANK_ROM <= 0;
		BANK_SRAM <= 0;
		mstate <= MBUS_IDLE;
		pier_count <= 0;
		MBUS_RNW <= 1;
		NO_DATA <= 'h4E71;
		BANK_REG <= '{0,1,2,3,4,5,6,7};
		// Game Bub: the ROM toggle handshake needs a defined power-on and
		// post-reset state. MdRomStore resets its ack to 0 to match, so the
		// two halves are always consistent and no transaction is invented.
		ROM_REQ <= 0;
		ROM_WE <= 0;
	end
    else if (ss_sys_restore) begin
        {BANK_REG[7], BANK_REG[6], BANK_REG[5], BANK_REG[4],
         BANK_REG[3], BANK_REG[2], BANK_REG[1], BANK_REG[0],
         BANK_ROM, BANK_SRAM} <= ss_sys_saved[52:11];
    end
	else if (!ss_block_now) begin
	/*
		refresh_timer <= refresh_timer + 1'd1;
		if (refresh_timer == 'h17F) begin
			refresh_timer <= 0;
			rfs_pend <= 1;
		end
	*/	
		if (M68K_CLKENp) begin
			if (cycle_cnt) cycle_cnt = cycle_cnt - 1'd1;
		end

		if (M68K_AS_N) M68K_MBUS_DTACK_N <= 1;
		if (~Z80_IO)   Z80_MBUS_DTACK_N  <= 1;
		if (~VBUS_SEL) VDP_MBUS_DTACK_N  <= 1;

		case(mstate)
		MBUS_IDLE:
			begin
				CTRL_SEL <= 0;
				SRAM_SEL <= 0;
				RAM_SEL <= 0;
				MBUS_RNW <= 1;
				MBUS_UDS_N <= 1;
				MBUS_LDS_N <= 1;
				
				/*if (rfs_pend) begin
					rfs_pend <= 0;
					mstate <= MBUS_REFRESH;
				end
				else*/ if (!M68K_AS_N && M68K_MBUS_DTACK_N) begin
					msrc <= MSRC_M68K;
					MBUS_A <= M68K_A[23:1];
					data <= NO_DATA;
					MBUS_DO <= M68K_DO;
					MBUS_RNW <= M68K_RNW;
					mstate <= MBUS_SELECT;
				end
				else if (VBUS_SEL && VDP_MBUS_DTACK_N) begin
					msrc <= MSRC_VDP;
					MBUS_A <= VBUS_A;
					data <= NO_DATA;
					MBUS_DO <= 0;
					mstate <=  MBUS_SELECT;
					//rfs_pend <= 0;
					//refresh_timer <= 0;
				end
				else if (Z80_IO && !Z80_ZBUS && Z80_MBUS_DTACK_N && !Z80_BGACK_N && Z80_BR_N) begin
					msrc <= MSRC_Z80;
					MBUS_A <= Z80_A[15] ? {BAR[23:15],Z80_A[14:1]} : {16'hC000, Z80_A[7:1]};
					data <= 16'hFFFF;
					MBUS_DO <= {Z80_DO,Z80_DO};
					MBUS_RNW <= Z80_WR_N;
					mstate <= MBUS_Z80_PREREAD;
					cycle_cnt <= 2'd1;
				end
			end
			
		MBUS_Z80_PREREAD:
			begin
				if (!cycle_cnt) begin
					mstate <= MBUS_SELECT;
					cycle_cnt <= 2'd1;
				end
			end

		MBUS_SELECT:
			begin
				//NO DEVICE (usually lockup on real HW)
				mstate <= MBUS_FINISH;

				if (MBUS_A[23:20]<'hA || (msrc == MSRC_Z80 && MBUS_A[23:20]<'hE && ROMSZ[24:20]>='hA)) begin
					//ROM: 000000-9FFFFF (A00000-DFFFFF)
					if (BANK_SRAM && MBUS_A[23:21] == 1) begin
						// 200000-3FFFFF SRAM overrides ROM when bank is selected
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if (PIER_QUIRK && ({MBUS_A,1'b0} == 'h0015E6 || {MBUS_A,1'b0} == 'h0015E8)) begin
						if (pier_count < 'h6) begin
							pier_count <= pier_count + 1'h1;
							data <= MBUS_A[1] ? 16'h0 : 16'h0010;
						end else begin
							data <= MBUS_A[1] ? 16'h0001 : 16'h8010;
						end
					end
					else if (EEPROM_QUIRK && {MBUS_A,1'b0} == 'h200000) begin
						data <= 0;
						mstate <= MBUS_FINISH;
					end
					else if ((SRAM_QUIRK | SRAM00_QUIRK) && {MBUS_A,1'b0} == 'h200000) begin
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if(SVP_QUIRK && MBUS_A[23:20] == 3) begin
						// 300000-37FFFF (+mirrors) SVP DRAM
						// 390000-39FFFF SVP DRAM cell arrange 1
						// 3A0000-3AFFFF SVP DRAM cell arrange 2
						SVP_SEL <= 1;
						mstate <= MBUS_SVP_READ;
					end 
					else if (SCHAN_QUIRK && ~MBUS_RNW && (MBUS_A < 'h400000)) begin
						mstate <= MBUS_ROM_WRITE;
					end
					else if (MBUS_A < ROMSZ) begin
						if (SVP_QUIRK && msrc == MSRC_VDP) MBUS_A <= MBUS_A - 1'd1;
						ROM_WE <= 0;
						ROM_REQ <= ~ROM_ACK;
						mstate <= MBUS_ROM_READ;
					end
					else if ((MULTITAP == 4) && ({MBUS_A,1'b0} == 'h3FFFFE || {MBUS_A,1'b0} == 'h38FFFE)) begin
						JCART_SEL <= 1;
						mstate <= MBUS_JCRT_READ;
					end
					else if(MBUS_A[23:21] == 1 && ~&MBUS_A[20:19] && ~NORAM_QUIRK) begin
						// 200000-37FFFF
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else begin
						data <= 0;
						mstate <= MBUS_FINISH;
					end
				end

				//ZBUS: A00000-A07FFF (A08000-A0FFFF)
				else if(MBUS_A[23:16] == 'hA0) mstate <= !Z80_BUSRQ_N ? MBUS_ZBUS_PRE : MBUS_FINISH;

				//I/O: A10000-A1001F (+mirrors)
				else if(MBUS_A[23:5] == {16'hA100, 3'b000}) begin
					IO_SEL <= 1;
					mstate <= MBUS_IO_READ;
				end

				//CTL: A11100, A11200
				else if(MBUS_A[23:12] == 12'hA11 && !MBUS_A[7:1]) begin
					CTRL_SEL <= 1;
					data <= CTRL_DO;
					mstate <= MBUS_FINISH;
				end

				// BANK Register A13XXX
				else if (MBUS_A[23:8] == 'hA130) begin
					if (~MBUS_RNW) begin
						if (ROMSZ > 'h200000) begin // SSF2/Pier Solar ROM banking
							if (MBUS_A[3:1]) begin
								BANK_ROM <= 1;
								if (~PIER_QUIRK) begin // SSF2
									BANK_REG[MBUS_A[3:1]] <= MBUS_DO[4:0];
								end
								else if (MBUS_A[3:1] == 4) begin // Pier EEPROM
									{ep_cs, ep_hold , ep_sck, ep_si} <= MBUS_DO[3:0];
								end
								else if (~MBUS_A[3]) begin // Pier Banks
									BANK_REG[{1'b1,MBUS_A[2:1]}] <= MBUS_DO[3:0];
								end
							end
							else if (~PIER_QUIRK) begin // SRAM control only in the first register on SSF2 mapper
							   BANK_SRAM <= {MBUS_DO[0]};
							end
						end else begin
							BANK_SRAM <= {MBUS_DO[0]};
						end
					end else if (PIER_QUIRK && MBUS_A[3:1] == 'h5) begin
						data <= {15'h7FFF, m95_so};
					end
					mstate <= MBUS_FINISH;
				end
				
				//SVP: A15000-A5000F 
				else if(MBUS_A[23:4] == 20'hA1500) begin
					SVP_SEL <= 1;
					mstate <= MBUS_SVP_READ;
				end 

				//VDP: C00000-C0001F (+mirrors)
				else if(MBUS_A[23:21] == 3'b110 && !MBUS_A[18:16] && !MBUS_A[7:5]) begin
					VDP_SEL <= 1;
					mstate <= MBUS_VDP_READ;
				end

				//RAM: E00000-FFFFFF
				else if(&MBUS_A[23:21]) begin
					RAM_SEL <= 1;
					mstate <= MBUS_RAM_READ;
				end
			end
			
		MBUS_ZBUS_PRE:
			case(msrc)
			MSRC_M68K:
				if(M68K_AS_N | (~M68K_UDS_N | ~M68K_LDS_N)) begin
					MBUS_UDS_N <= M68K_UDS_N;
					MBUS_LDS_N <= M68K_LDS_N;
					ZBUS_SEL <= 1;
					mstate <= MBUS_RNW ? MBUS_ZBUS_WS : MBUS_ZBUS_READ;
				end

			MSRC_Z80:
				begin
					MBUS_UDS_N <= Z80_A[0];
					MBUS_LDS_N <= ~Z80_A[0];
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end

			MSRC_VDP:
				begin
					MBUS_UDS_N <= 0;
					MBUS_LDS_N <= 0;
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end
			endcase

		MBUS_ZBUS_WS:
			begin
				if (M68K_CLKENp) begin
					mstate <= MBUS_ZBUS_READ;
				end
			end
			
		MBUS_ZBUS_READ:
			begin
				if(~MBUS_ZBUS_DTACK_N) begin
					ZBUS_SEL <= 0;
					data <= {MBUS_ZBUS_D, MBUS_ZBUS_D};
					mstate <= MBUS_FINISH;
				end
			end

		MBUS_RAM_READ:
			begin
				data <= ram68k_q;
				if(msrc == MSRC_M68K) NO_DATA <= ram68k_q;
				mstate <= MBUS_FINISH;
			end

		MBUS_ROM_WRITE:
			case(msrc)
			MSRC_M68K:
				if(M68K_AS_N | (~M68K_UDS_N | ~M68K_LDS_N)) begin
					MBUS_UDS_N <= M68K_UDS_N;
					MBUS_LDS_N <= M68K_LDS_N;
					ROM_WE <= 1;
					ROM_REQ <= ~ROM_ACK;
					mstate <= MBUS_ROM_READ;
				end

			MSRC_Z80:
				begin
					MBUS_UDS_N <= Z80_A[0];
					MBUS_LDS_N <= ~Z80_A[0];
					ROM_WE <= 1;
					ROM_REQ <= ~ROM_ACK;
					mstate <= MBUS_ROM_READ;
				end
			endcase

		MBUS_ROM_READ:
			if (ROM_REQ == ROM_ACK) begin
				data <= ROM_DATA;
				if(msrc == MSRC_M68K) NO_DATA <= ROM_DATA;
				if (msrc != MSRC_Z80 || !cycle_cnt)
					mstate <= MBUS_FINISH;
			end

		MBUS_SRAM_READ:
			begin
				data <= {sram_q,sram_q};
				if(msrc == MSRC_M68K) NO_DATA <= {sram_q,sram_q};
				SRAM_SEL <= 0;
				mstate <= MBUS_FINISH;
			end

		MBUS_VDP_READ:
			if (~VDP_DTACK_N) begin
				VDP_SEL <= 0;
				data <= VDP_DO;
				if(MBUS_A[4:2] == 1) data[15:10] <= NO_DATA[15:10]; //unused status bits
				else if(MBUS_A[4]) data <= NO_DATA; // PSG/debug registers
				mstate <= MBUS_FINISH;
			end

		MBUS_IO_READ:
			if(~IO_DTACK_N) begin
				IO_SEL <= 0;
				data <= {IO_DO, IO_DO};
				mstate <= MBUS_FINISH;
			end

		MBUS_JCRT_READ:
			if(~JCART_DTACK_N) begin
				JCART_SEL <= 0;
				data <= JCART_DO & 16'h3F7F;
				mstate <= MBUS_FINISH;
			end

		MBUS_SVP_READ:
			if(~SVP_DTACK_N) begin
				SVP_SEL <= 0;
				data <= SVP_DO;
				mstate <= MBUS_FINISH;
			end 

		MBUS_REFRESH:
			if (M68K_CLKENp) begin
				rfs_wait <= rfs_wait + 1'd1;
				if (rfs_wait == 1) begin
					rfs_wait <= 0;
					mstate <= MBUS_IDLE;
				end
			end

		MBUS_FINISH:
			begin
				case(msrc)
				MSRC_M68K:
					begin
						M68K_MBUS_D <= data;
						M68K_MBUS_DTACK_N <= 0;
						if((M68K_AS_N | MBUS_RNW | ~M68K_UDS_N | ~M68K_LDS_N)) begin
							MBUS_UDS_N <= M68K_UDS_N;
							MBUS_LDS_N <= M68K_LDS_N;
							mstate <= MBUS_IDLE;
						end
					end

				MSRC_Z80:
					begin
						if (Z80_CLKENp) begin
							Z80_MBUS_D <= Z80_A[0] ? data[7:0] : data[15:8];
							Z80_MBUS_DTACK_N <= 0;
							MBUS_UDS_N <= Z80_A[0];
							MBUS_LDS_N <= ~Z80_A[0];
							mstate <= MBUS_IDLE;
						end
					end

				MSRC_VDP:
					begin
						VDP_MBUS_D <= data;
						VDP_MBUS_DTACK_N <= 0;
						mstate <= MBUS_IDLE;
					end
				endcase
			end
		endcase
	end
end


//--------------------------------------------------------------
// CPU Z80
//--------------------------------------------------------------
reg         Z80_RESET_N;
reg         Z80_BUSRQ_N;
wire        Z80_BUSAK_N;
wire        Z80_MREQ_N;
wire        Z80_RD_N;
wire        Z80_WR_N;
wire        Z80_M1_N;
wire  [1:0] Z80_ISET;
wire [229:0] Z80_REG;
wire [15:0] Z80_A;
wire  [7:0] Z80_DO;
wire        Z80_IO = ~Z80_MREQ_N & (~Z80_RD_N | ~Z80_WR_N);
assign SS_Z80_REG = Z80_REG;

T80s #(.T2Write(1)) Z80
//T80pa Z80
(
	.RESET_n(Z80_RESET_N),
	// Game Bub: a VHDL input left unconnected from Verilog ties low in Vivado; the
	// Mega Drive has no NMI source, so hold it high.
	.NMI_n(1'b1),
	.CLK(MCLK),
//	.CEN_p(Z80_CLKENp),
//	.CEN_n(Z80_CLKENn),
	.CEN(Z80_CLKENn),
	.BUSRQ_n(Z80_BUSRQ_N),
	.BUSAK_n(Z80_BUSAK_N),
	.WAIT_n(~Z80_MBUS_DTACK_N | ~Z80_ZBUS_DTACK_N | ~Z80_IO),
	.INT_n(~Z80_VINT),
	.M1_n(Z80_M1_N),
	.MREQ_n(Z80_MREQ_N),
	.RD_n(Z80_RD_N),
	.WR_n(Z80_WR_N),
	.A(Z80_A),
	.DI((~Z80_MBUS_DTACK_N) ? Z80_MBUS_D : Z80_ZBUS_D),
	.DO(Z80_DO),
	.REG(Z80_REG),
	.DIRSet(SS_Z80_SET),
	.DIR(SS_Z80_DIR),
	.ISet_out(Z80_ISET)
);


wire        CTRL_F  = (MBUS_A[11:8] == 1) ? Z80_BUSAK_N : (MBUS_A[11:8] == 2) ? Z80_RESET_N : NO_DATA[8];
wire [15:0] CTRL_DO = {NO_DATA[15:9], CTRL_F, NO_DATA[7:0]};
reg         CTRL_SEL;
always @(posedge MCLK) begin
	if (reset) begin
		Z80_BUSRQ_N <= 1;
		Z80_RESET_N <= 0;
	end
	else if(ss_sys_restore) begin
		{Z80_BUSRQ_N, Z80_RESET_N} <= ss_sys_saved[1:0];
	end
	else if(CTRL_SEL & ~MBUS_RNW & ~MBUS_UDS_N) begin
		if (MBUS_A[11:8] == 1) Z80_BUSRQ_N <= ~MBUS_DO[8];
		if (MBUS_A[11:8] == 2) Z80_RESET_N <=  MBUS_DO[8];
	end
end

//-----------------------------------------------------------------------
// ZBUS Handling
//-----------------------------------------------------------------------
// Z80:   0000-7EFF
// 68000: A00000-A07FFF (A08000-A0FFFF)

wire       Z80_ZBUS  = ~Z80_A[15] && ~&Z80_A[14:8];

wire       ZBUS_NO_BUSY = ZBUS_A[14] && ~|ZBUS_A[13:2] && |ZBUS_A[1:0] && FMBUSY_QUIRK;

reg        ZBUS_SEL;
reg [14:0] ZBUS_A;
reg        ZBUS_WE;
reg  [7:0] ZBUS_DO;
wire [7:0] ZBUS_DI = ZRAM_SEL ? ZRAM_DO : (FM_SEL ? (ZBUS_NO_BUSY ? {1'b0, FM_DO[6:0]} : FM_DO) : 8'hFF);

reg  [7:0] MBUS_ZBUS_D;
reg  [7:0] Z80_ZBUS_D;

reg        MBUS_ZBUS_DTACK_N;
reg        Z80_ZBUS_DTACK_N;

reg        Z80_BR_N;
reg        Z80_BGACK_N;

wire       Z80_ZBUS_SEL = Z80_ZBUS & Z80_IO;
wire       ZBUS_FREE = ~Z80_BUSRQ_N & Z80_RESET_N;

wire       Z80_MBUS_SEL = Z80_IO & ~Z80_ZBUS;

// RAM 0000-1FFF (2000-3FFF)
wire ZRAM_SEL = ~ZBUS_A[14];

wire  [7:0] ZRAM_DO;
wire  [7:0] ss_zram_q;
dpram #(13) ramZ80
(
	.clock(MCLK),
	// Game Bub: enables driven explicitly (see the VRAM note).
	.enable_a(1'b1), .cs_a(1'b1),
	.address_a(ZBUS_A[12:0]),
	.data_a(ZBUS_DO),
	.wren_a(ZBUS_WE & ZRAM_SEL),
	// Game Bub sim: RAM_INIT was LOADING (as in our port); the rest is R58.
	.q_a(ZRAM_DO),

	.address_b(ss_mem_addr_eff[12:0]),
	.data_b(ss_mem_di_eff),
	.wren_b(ss_mem_we_eff & (ss_mem_addr_eff[17:16] == 2'b01) & ~|ss_mem_addr_eff[15:13]),
	.q_b(ss_zram_q), .enable_b(1'b1), .cs_b(1'b1)
);

always @(posedge MCLK) begin
	static reg [1:0] zstate;
	static reg [1:0] zsrc;
	static reg Z80_BGACK_DIS;

	localparam 	ZSRC_MBUS = 0,
					ZSRC_Z80  = 1;

	localparam	ZBUS_IDLE   = 0,
					ZBUS_READ   = 1,
					ZBUS_FINISH = 2;

	ZBUS_WE <= 0;
	
	if (reset) begin
		MBUS_ZBUS_DTACK_N <= 1;
		Z80_ZBUS_DTACK_N  <= 1;
		zstate <= ZBUS_IDLE;
		
		Z80_BR_N <= 1;
		Z80_BGACK_N <= 1;
		Z80_BGACK_DIS <= 0;
	end
	else begin
		if (~ZBUS_SEL)     MBUS_ZBUS_DTACK_N <= 1;
		if (~Z80_ZBUS_SEL) Z80_ZBUS_DTACK_N  <= 1;

		case (zstate)
		ZBUS_IDLE:
			begin
				if (Z80_RD_N)      Z80_ZBUS_D <= 8'hFF;

				if (ZBUS_SEL & MBUS_ZBUS_DTACK_N) begin
					ZBUS_A <= {MBUS_A[14:1], MBUS_UDS_N};
					ZBUS_DO <= (~MBUS_UDS_N) ? MBUS_DO[15:8] : MBUS_DO[7:0];
					ZBUS_WE <= ~MBUS_RNW & ZBUS_FREE;
					zsrc <= ZSRC_MBUS;
					zstate <= ZBUS_READ;
				end
				else if (Z80_ZBUS_SEL & Z80_ZBUS_DTACK_N) begin
					ZBUS_A <= Z80_A[14:0];
					ZBUS_DO <= Z80_DO;
					ZBUS_WE <= ~Z80_WR_N;
					zsrc <= ZSRC_Z80;
					zstate <= ZBUS_READ;
				end
			end

		ZBUS_READ:
			zstate <= ZBUS_FINISH;

		ZBUS_FINISH:
			begin
				case(zsrc)
				ZSRC_MBUS:
					begin
						MBUS_ZBUS_D <= ZBUS_FREE ? ZBUS_DI : 8'hFF;
						MBUS_ZBUS_DTACK_N <= 0;
					end

				ZSRC_Z80:
					begin
						Z80_ZBUS_D <= ZBUS_DI;
						Z80_ZBUS_DTACK_N <= 0;
					end
				endcase
				zstate <= ZBUS_IDLE;
			end
		endcase
		
		if (Z80_MBUS_SEL && Z80_BR_N && Z80_BGACK_N && VBUS_BR_N && VBUS_BGACK_N && M68K_CLKENp) begin
			Z80_BR_N <= 0;
		end
		else if (!Z80_BR_N && !M68K_BG_N && M68K_AS_N && M68K_CLKENn) begin
			Z80_BGACK_N <= 0;
		end
		else if (!Z80_BGACK_N && !Z80_BR_N && !M68K_BG_N && M68K_CLKENp) begin
			Z80_BR_N <= 1;
		end
		else if (!Z80_BGACK_DIS && !Z80_BGACK_N && Z80_BR_N && !Z80_MBUS_SEL && M68K_CLKENn) begin
			Z80_BGACK_DIS <= 1;
		end
		else if (!Z80_BGACK_N && Z80_BGACK_DIS && M68K_CLKENn) begin
			Z80_BGACK_N <= 1;
			Z80_BGACK_DIS <= 0;
		end
	end
end


//-----------------------------------------------------------------------
// Z80 BANK REGISTER
//-----------------------------------------------------------------------
// 6000-60FF

wire BANK_SEL = ZBUS_A[14:8] == 7'h60;
reg [23:15] BAR;

always @(posedge MCLK) begin
	if (reset) BAR <= 0;
	else if (ss_sys_restore) BAR <= ss_sys_saved[10:2];
	else if (BANK_SEL & ZBUS_WE) BAR <= {ZBUS_DO[0], BAR[23:16]};
end


//--------------------------------------------------------------
// YM2612
//--------------------------------------------------------------
// 4000-4003 (4000-5FFF)

wire        FM_SEL = ZBUS_A[14:13] == 2'b10;
wire  [7:0] FM_DO;
wire signed [15:0] FM_right;
wire signed [15:0] FM_left;
wire signed [15:0] FM_LPF_right;
wire signed [15:0] FM_LPF_left;
wire signed [15:0] PRE_LPF_L;
wire signed [15:0] PRE_LPF_R;

// -------------------------------------------------------------------------
// v1.4 YM2612/JT12 architectural mirror + canonical replay
// -------------------------------------------------------------------------
// JT12 is a deeply pipelined implementation. Rather than serializing every
// operator/envelope pipeline register in the first audio milestone, mirror
// the CPU-visible register file and key state, reset JT12 while CPUs are held,
// then replay only registers that were actually written. Every data write
// waits for JT12 BUSY to clear before the next one. This restores musical
// configuration deterministically while intentionally restarting FM phase/EG.
(* ram_style = "distributed" *) reg [7:0] ss_fm_shadow [0:511]; // Game Bub: LUT RAM (see ss_vram_shadow)
reg [511:0] ss_fm_written;
reg  [7:0] ss_fm_selected_reg;
reg        ss_fm_selected_part;
reg  [3:0] ss_fm_keymask [0:5];
// YM2612 frequency writes use a shared 6-bit high-byte latch. Mirror the
// committed channel frequencies explicitly so replay does not depend on the
// historical ordering of A4-A6/AC-AE versus A0-A2/A8-AA writes.
reg  [5:0] ss_fm_fnum_latch;
reg [13:0] ss_fm_freq [0:5];
reg  [5:0] ss_fm_freq_valid;
reg [13:0] ss_fm_ch3freq [0:2];
reg  [2:0] ss_fm_ch3freq_valid;

wire       fm_bus_write = FM_SEL & ZBUS_WE;
// R57 byte-serialized v1.4 mirror metadata and PSG architectural state.
wire [1023:0] ss_slot_audio_image = {286'd0,ss_psg_regn,ss_psg_ctrl3,ss_psg_vol3,ss_psg_vol2,ss_psg_vol1,ss_psg_vol0,ss_psg_tone2,ss_psg_tone1,ss_psg_tone0,ss_fm_ch3freq_valid,ss_fm_ch3freq[2],ss_fm_ch3freq[1],ss_fm_ch3freq[0],ss_fm_freq_valid,ss_fm_freq[5],ss_fm_freq[4],ss_fm_freq[3],ss_fm_freq[2],ss_fm_freq[1],ss_fm_freq[0],ss_fm_keymask[5],ss_fm_keymask[4],ss_fm_keymask[3],ss_fm_keymask[2],ss_fm_keymask[1],ss_fm_keymask[0],ss_fm_fnum_latch,ss_fm_selected_part,ss_fm_selected_reg,ss_fm_written};
always @(posedge MCLK) begin
    if (SS_SLOT_ADDR < 18'h12000) SS_SLOT_DO <= SS_MEM_DO;
    else if (SS_SLOT_ADDR < 18'h30300) SS_SLOT_DO <= ss_vdp_restore_data_q;
    else if (SS_SLOT_ADDR < 18'h30340) SS_SLOT_DO <= ss_slot_vdp_do;
    else if (SS_SLOT_ADDR < 18'h30360) SS_SLOT_DO <= ss_slot_sys_image[{SS_SLOT_ADDR[4:0],3'b000} +: 8];
    else if (SS_SLOT_ADDR >= 18'h30380 && SS_SLOT_ADDR < 18'h30384)
        SS_SLOT_DO <= ss_m68k_saved_ssp[{SS_SLOT_ADDR[1:0],3'b000} +: 8];
    else if (SS_SLOT_ADDR >= 18'h30400 && SS_SLOT_ADDR < 18'h30600)
        SS_SLOT_DO <= ss_fm_written[SS_SLOT_ADDR[8:0]] ? ss_fm_shadow[SS_SLOT_ADDR[8:0]] : 8'd0;
    else if (SS_SLOT_ADDR >= 18'h30600 && SS_SLOT_ADDR < 18'h30680)
        SS_SLOT_DO <= ss_slot_audio_image[{SS_SLOT_ADDR[6:0],3'b000} +: 8];
    else SS_SLOT_DO <= 8'd0;
end

integer ss_fm_i;
always @(posedge MCLK) begin
    if (reset || !Z80_RESET_N) begin
        ss_fm_written       <= 512'd0;
        ss_fm_selected_reg  <= 8'd0;
        ss_fm_selected_part <= 1'b0;
        ss_fm_fnum_latch    <= 6'd0;
        ss_fm_freq_valid    <= 6'd0;
        ss_fm_ch3freq_valid <= 3'd0;
        for (ss_fm_i = 0; ss_fm_i < 6; ss_fm_i = ss_fm_i + 1) begin
            ss_fm_keymask[ss_fm_i] <= 4'd0;
            ss_fm_freq[ss_fm_i]    <= 14'd0;
        end
        for (ss_fm_i = 0; ss_fm_i < 3; ss_fm_i = ss_fm_i + 1)
            ss_fm_ch3freq[ss_fm_i] <= 14'd0;
    end
    else if (SS_SLOT_WE && SS_SLOT_ADDR >= 18'h30400 && SS_SLOT_ADDR < 18'h30680) begin
        if (SS_SLOT_ADDR < 18'h30600)
            ss_fm_shadow[SS_SLOT_ADDR[8:0]] <= SS_SLOT_DI;
        else case (SS_SLOT_ADDR[6:0])
            7'd0: begin ss_fm_written[7:0] <= SS_SLOT_DI[7:0]; end
            7'd1: begin ss_fm_written[15:8] <= SS_SLOT_DI[7:0]; end
            7'd2: begin ss_fm_written[23:16] <= SS_SLOT_DI[7:0]; end
            7'd3: begin ss_fm_written[31:24] <= SS_SLOT_DI[7:0]; end
            7'd4: begin ss_fm_written[39:32] <= SS_SLOT_DI[7:0]; end
            7'd5: begin ss_fm_written[47:40] <= SS_SLOT_DI[7:0]; end
            7'd6: begin ss_fm_written[55:48] <= SS_SLOT_DI[7:0]; end
            7'd7: begin ss_fm_written[63:56] <= SS_SLOT_DI[7:0]; end
            7'd8: begin ss_fm_written[71:64] <= SS_SLOT_DI[7:0]; end
            7'd9: begin ss_fm_written[79:72] <= SS_SLOT_DI[7:0]; end
            7'd10: begin ss_fm_written[87:80] <= SS_SLOT_DI[7:0]; end
            7'd11: begin ss_fm_written[95:88] <= SS_SLOT_DI[7:0]; end
            7'd12: begin ss_fm_written[103:96] <= SS_SLOT_DI[7:0]; end
            7'd13: begin ss_fm_written[111:104] <= SS_SLOT_DI[7:0]; end
            7'd14: begin ss_fm_written[119:112] <= SS_SLOT_DI[7:0]; end
            7'd15: begin ss_fm_written[127:120] <= SS_SLOT_DI[7:0]; end
            7'd16: begin ss_fm_written[135:128] <= SS_SLOT_DI[7:0]; end
            7'd17: begin ss_fm_written[143:136] <= SS_SLOT_DI[7:0]; end
            7'd18: begin ss_fm_written[151:144] <= SS_SLOT_DI[7:0]; end
            7'd19: begin ss_fm_written[159:152] <= SS_SLOT_DI[7:0]; end
            7'd20: begin ss_fm_written[167:160] <= SS_SLOT_DI[7:0]; end
            7'd21: begin ss_fm_written[175:168] <= SS_SLOT_DI[7:0]; end
            7'd22: begin ss_fm_written[183:176] <= SS_SLOT_DI[7:0]; end
            7'd23: begin ss_fm_written[191:184] <= SS_SLOT_DI[7:0]; end
            7'd24: begin ss_fm_written[199:192] <= SS_SLOT_DI[7:0]; end
            7'd25: begin ss_fm_written[207:200] <= SS_SLOT_DI[7:0]; end
            7'd26: begin ss_fm_written[215:208] <= SS_SLOT_DI[7:0]; end
            7'd27: begin ss_fm_written[223:216] <= SS_SLOT_DI[7:0]; end
            7'd28: begin ss_fm_written[231:224] <= SS_SLOT_DI[7:0]; end
            7'd29: begin ss_fm_written[239:232] <= SS_SLOT_DI[7:0]; end
            7'd30: begin ss_fm_written[247:240] <= SS_SLOT_DI[7:0]; end
            7'd31: begin ss_fm_written[255:248] <= SS_SLOT_DI[7:0]; end
            7'd32: begin ss_fm_written[263:256] <= SS_SLOT_DI[7:0]; end
            7'd33: begin ss_fm_written[271:264] <= SS_SLOT_DI[7:0]; end
            7'd34: begin ss_fm_written[279:272] <= SS_SLOT_DI[7:0]; end
            7'd35: begin ss_fm_written[287:280] <= SS_SLOT_DI[7:0]; end
            7'd36: begin ss_fm_written[295:288] <= SS_SLOT_DI[7:0]; end
            7'd37: begin ss_fm_written[303:296] <= SS_SLOT_DI[7:0]; end
            7'd38: begin ss_fm_written[311:304] <= SS_SLOT_DI[7:0]; end
            7'd39: begin ss_fm_written[319:312] <= SS_SLOT_DI[7:0]; end
            7'd40: begin ss_fm_written[327:320] <= SS_SLOT_DI[7:0]; end
            7'd41: begin ss_fm_written[335:328] <= SS_SLOT_DI[7:0]; end
            7'd42: begin ss_fm_written[343:336] <= SS_SLOT_DI[7:0]; end
            7'd43: begin ss_fm_written[351:344] <= SS_SLOT_DI[7:0]; end
            7'd44: begin ss_fm_written[359:352] <= SS_SLOT_DI[7:0]; end
            7'd45: begin ss_fm_written[367:360] <= SS_SLOT_DI[7:0]; end
            7'd46: begin ss_fm_written[375:368] <= SS_SLOT_DI[7:0]; end
            7'd47: begin ss_fm_written[383:376] <= SS_SLOT_DI[7:0]; end
            7'd48: begin ss_fm_written[391:384] <= SS_SLOT_DI[7:0]; end
            7'd49: begin ss_fm_written[399:392] <= SS_SLOT_DI[7:0]; end
            7'd50: begin ss_fm_written[407:400] <= SS_SLOT_DI[7:0]; end
            7'd51: begin ss_fm_written[415:408] <= SS_SLOT_DI[7:0]; end
            7'd52: begin ss_fm_written[423:416] <= SS_SLOT_DI[7:0]; end
            7'd53: begin ss_fm_written[431:424] <= SS_SLOT_DI[7:0]; end
            7'd54: begin ss_fm_written[439:432] <= SS_SLOT_DI[7:0]; end
            7'd55: begin ss_fm_written[447:440] <= SS_SLOT_DI[7:0]; end
            7'd56: begin ss_fm_written[455:448] <= SS_SLOT_DI[7:0]; end
            7'd57: begin ss_fm_written[463:456] <= SS_SLOT_DI[7:0]; end
            7'd58: begin ss_fm_written[471:464] <= SS_SLOT_DI[7:0]; end
            7'd59: begin ss_fm_written[479:472] <= SS_SLOT_DI[7:0]; end
            7'd60: begin ss_fm_written[487:480] <= SS_SLOT_DI[7:0]; end
            7'd61: begin ss_fm_written[495:488] <= SS_SLOT_DI[7:0]; end
            7'd62: begin ss_fm_written[503:496] <= SS_SLOT_DI[7:0]; end
            7'd63: begin ss_fm_written[511:504] <= SS_SLOT_DI[7:0]; end
            7'd64: begin ss_fm_selected_reg[7:0] <= SS_SLOT_DI[7:0]; end
            7'd65: begin ss_fm_selected_part <= SS_SLOT_DI[0]; ss_fm_fnum_latch[5:0] <= SS_SLOT_DI[6:1]; ss_fm_keymask[0][0] <= SS_SLOT_DI[7]; end
            7'd66: begin ss_fm_keymask[0][3:1] <= SS_SLOT_DI[2:0]; ss_fm_keymask[1][3:0] <= SS_SLOT_DI[6:3]; ss_fm_keymask[2][0] <= SS_SLOT_DI[7]; end
            7'd67: begin ss_fm_keymask[2][3:1] <= SS_SLOT_DI[2:0]; ss_fm_keymask[3][3:0] <= SS_SLOT_DI[6:3]; ss_fm_keymask[4][0] <= SS_SLOT_DI[7]; end
            7'd68: begin ss_fm_keymask[4][3:1] <= SS_SLOT_DI[2:0]; ss_fm_keymask[5][3:0] <= SS_SLOT_DI[6:3]; ss_fm_freq[0][0] <= SS_SLOT_DI[7]; end
            7'd69: begin ss_fm_freq[0][8:1] <= SS_SLOT_DI[7:0]; end
            7'd70: begin ss_fm_freq[0][13:9] <= SS_SLOT_DI[4:0]; ss_fm_freq[1][2:0] <= SS_SLOT_DI[7:5]; end
            7'd71: begin ss_fm_freq[1][10:3] <= SS_SLOT_DI[7:0]; end
            7'd72: begin ss_fm_freq[1][13:11] <= SS_SLOT_DI[2:0]; ss_fm_freq[2][4:0] <= SS_SLOT_DI[7:3]; end
            7'd73: begin ss_fm_freq[2][12:5] <= SS_SLOT_DI[7:0]; end
            7'd74: begin ss_fm_freq[2][13] <= SS_SLOT_DI[0]; ss_fm_freq[3][6:0] <= SS_SLOT_DI[7:1]; end
            7'd75: begin ss_fm_freq[3][13:7] <= SS_SLOT_DI[6:0]; ss_fm_freq[4][0] <= SS_SLOT_DI[7]; end
            7'd76: begin ss_fm_freq[4][8:1] <= SS_SLOT_DI[7:0]; end
            7'd77: begin ss_fm_freq[4][13:9] <= SS_SLOT_DI[4:0]; ss_fm_freq[5][2:0] <= SS_SLOT_DI[7:5]; end
            7'd78: begin ss_fm_freq[5][10:3] <= SS_SLOT_DI[7:0]; end
            7'd79: begin ss_fm_freq[5][13:11] <= SS_SLOT_DI[2:0]; ss_fm_freq_valid[4:0] <= SS_SLOT_DI[7:3]; end
            7'd80: begin ss_fm_freq_valid[5] <= SS_SLOT_DI[0]; ss_fm_ch3freq[0][6:0] <= SS_SLOT_DI[7:1]; end
            7'd81: begin ss_fm_ch3freq[0][13:7] <= SS_SLOT_DI[6:0]; ss_fm_ch3freq[1][0] <= SS_SLOT_DI[7]; end
            7'd82: begin ss_fm_ch3freq[1][8:1] <= SS_SLOT_DI[7:0]; end
            7'd83: begin ss_fm_ch3freq[1][13:9] <= SS_SLOT_DI[4:0]; ss_fm_ch3freq[2][2:0] <= SS_SLOT_DI[7:5]; end
            7'd84: begin ss_fm_ch3freq[2][10:3] <= SS_SLOT_DI[7:0]; end
            7'd85: begin ss_fm_ch3freq[2][13:11] <= SS_SLOT_DI[2:0]; ss_fm_ch3freq_valid[2:0] <= SS_SLOT_DI[5:3]; end
            default: ;
        endcase
    end
    else if (!ss_audio_restore_active && fm_bus_write) begin
        if (!ZBUS_A[0]) begin
            ss_fm_selected_reg  <= ZBUS_DO;
            ss_fm_selected_part <= ZBUS_A[1];
        end
        else begin
            ss_fm_shadow[{ss_fm_selected_part, ss_fm_selected_reg}] <= ZBUS_DO;
            ss_fm_written[{ss_fm_selected_part, ss_fm_selected_reg}] <= 1'b1;

            case (ss_fm_selected_reg)
                8'hA4, 8'hA5, 8'hA6, 8'hAC, 8'hAD, 8'hAE:
                    ss_fm_fnum_latch <= ZBUS_DO[5:0];
                8'hA0: begin
                    ss_fm_freq[ss_fm_selected_part ? 3 : 0] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_freq_valid[ss_fm_selected_part ? 3 : 0] <= 1'b1;
                end
                8'hA1: begin
                    ss_fm_freq[ss_fm_selected_part ? 4 : 1] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_freq_valid[ss_fm_selected_part ? 4 : 1] <= 1'b1;
                end
                8'hA2: begin
                    ss_fm_freq[ss_fm_selected_part ? 5 : 2] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_freq_valid[ss_fm_selected_part ? 5 : 2] <= 1'b1;
                end
                8'hA8: if (!ss_fm_selected_part) begin
                    ss_fm_ch3freq[0] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_ch3freq_valid[0] <= 1'b1;
                end
                8'hA9: if (!ss_fm_selected_part) begin
                    ss_fm_ch3freq[1] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_ch3freq_valid[1] <= 1'b1;
                end
                8'hAA: if (!ss_fm_selected_part) begin
                    ss_fm_ch3freq[2] <= {ss_fm_fnum_latch, ZBUS_DO};
                    ss_fm_ch3freq_valid[2] <= 1'b1;
                end
                default: ;
            endcase

            if (!ss_fm_selected_part && ss_fm_selected_reg == 8'h28) begin
                case (ZBUS_DO[2:0])
                    3'd0: ss_fm_keymask[0] <= ZBUS_DO[7:4];
                    3'd1: ss_fm_keymask[1] <= ZBUS_DO[7:4];
                    3'd2: ss_fm_keymask[2] <= ZBUS_DO[7:4];
                    3'd4: ss_fm_keymask[3] <= ZBUS_DO[7:4];
                    3'd5: ss_fm_keymask[4] <= ZBUS_DO[7:4];
                    3'd6: ss_fm_keymask[5] <= ZBUS_DO[7:4];
                    default: ;
                endcase
            end
        end
    end
end

localparam [4:0]
    SSA_IDLE          = 5'd0,
    SSA_RESET         = 5'd1,
    SSA_PSG_LOW       = 5'd2,
    SSA_PSG_HIGH      = 5'd3,
    SSA_FM_SCAN       = 5'd4,
    SSA_FM_ADDR_LOW   = 5'd5,
    SSA_FM_ADDR_HIGH  = 5'd6,
    SSA_FM_DATA_LOW   = 5'd7,
    SSA_FM_DATA_HIGH  = 5'd8,
    SSA_FM_WAIT_BUSY  = 5'd9,
    SSA_KEY_SCAN      = 5'd10,
    SSA_KEY_ADDR_LOW  = 5'd11,
    SSA_KEY_ADDR_HIGH = 5'd12,
    SSA_KEY_DATA_LOW  = 5'd13,
    SSA_KEY_DATA_HIGH = 5'd14,
    SSA_KEY_WAIT_BUSY = 5'd15,
    SSA_LATCH_LOW     = 5'd16,
    SSA_LATCH_HIGH    = 5'd17,
    SSA_WAIT_ACTIVE   = 5'd18,
    SSA_WAIT_VBL      = 5'd19,
    SSA_DONE          = 5'd20,
    SSA_FREQ_SCAN     = 5'd21,
    SSA_FREQ_HA_LOW   = 5'd22,
    SSA_FREQ_HA_HIGH  = 5'd23,
    SSA_FREQ_HD_LOW   = 5'd24,
    SSA_FREQ_HD_HIGH  = 5'd25,
    SSA_FREQ_H_WAIT   = 5'd26,
    SSA_FREQ_LA_LOW   = 5'd27,
    SSA_FREQ_LA_HIGH  = 5'd28,
    SSA_FREQ_LD_LOW   = 5'd29,
    SSA_FREQ_LD_HIGH  = 5'd30,
    SSA_FREQ_L_WAIT   = 5'd31;

reg [4:0] ss_audio_state;
reg [3:0] ss_audio_reset_cens;
reg [3:0] ss_audio_psg_index;
reg [8:0] ss_audio_fm_index;
reg [2:0] ss_audio_key_index;
reg [3:0] ss_audio_freq_index;
reg [7:0] ss_fm_replay_data_q;
reg       ss_audio_done_q;

assign ss_audio_restore_active = (ss_audio_state != SSA_IDLE);
assign ss_audio_clock_override = ss_audio_restore_active &&
                                 (ss_audio_state != SSA_WAIT_ACTIVE) &&
                                 (ss_audio_state != SSA_WAIT_VBL) &&
                                 (ss_audio_state != SSA_DONE);
assign ss_audio_psg_reset       = (ss_audio_state == SSA_RESET);
assign ss_audio_filter_reset    = (ss_audio_state == SSA_RESET);
assign ss_audio_restore_done_pulse = ss_audio_done_q;

function automatic [7:0] ss_psg_replay_byte(input [3:0] idx);
begin
    case (idx)
        4'd0:  ss_psg_replay_byte = 8'h80 | {4'd0, ss_psg_tone0[3:0]};
        4'd1:  ss_psg_replay_byte = {2'b00, ss_psg_tone0[9:4]};
        4'd2:  ss_psg_replay_byte = 8'h90 | {4'd0, ss_psg_vol0};
        4'd3:  ss_psg_replay_byte = 8'hA0 | {4'd0, ss_psg_tone1[3:0]};
        4'd4:  ss_psg_replay_byte = {2'b00, ss_psg_tone1[9:4]};
        4'd5:  ss_psg_replay_byte = 8'hB0 | {4'd0, ss_psg_vol1};
        4'd6:  ss_psg_replay_byte = 8'hC0 | {4'd0, ss_psg_tone2[3:0]};
        4'd7:  ss_psg_replay_byte = {2'b00, ss_psg_tone2[9:4]};
        4'd8:  ss_psg_replay_byte = 8'hD0 | {4'd0, ss_psg_vol2};
        4'd9:  ss_psg_replay_byte = 8'hE0 | {5'd0, ss_psg_ctrl3};
        4'd10: ss_psg_replay_byte = 8'hF0 | {4'd0, ss_psg_vol3};
        default: begin
            case (ss_psg_regn)
                3'd0: ss_psg_replay_byte = 8'h80 | {4'd0, ss_psg_tone0[3:0]};
                3'd1: ss_psg_replay_byte = 8'h90 | {4'd0, ss_psg_vol0};
                3'd2: ss_psg_replay_byte = 8'hA0 | {4'd0, ss_psg_tone1[3:0]};
                3'd3: ss_psg_replay_byte = 8'hB0 | {4'd0, ss_psg_vol1};
                3'd4: ss_psg_replay_byte = 8'hC0 | {4'd0, ss_psg_tone2[3:0]};
                3'd5: ss_psg_replay_byte = 8'hD0 | {4'd0, ss_psg_vol2};
                3'd6: ss_psg_replay_byte = 8'hE0 | {5'd0, ss_psg_ctrl3};
                default: ss_psg_replay_byte = 8'hF0 | {4'd0, ss_psg_vol3};
            endcase
        end
    endcase
end
endfunction

function automatic [2:0] ss_fm_key_code(input [2:0] ch);
begin
    case (ch)
        3'd0: ss_fm_key_code = 3'd0;
        3'd1: ss_fm_key_code = 3'd1;
        3'd2: ss_fm_key_code = 3'd2;
        3'd3: ss_fm_key_code = 3'd4;
        3'd4: ss_fm_key_code = 3'd5;
        default: ss_fm_key_code = 3'd6;
    endcase
end
endfunction

function automatic ss_fm_is_freq_reg(input [7:0] r);
begin
    case (r)
        8'hA0,8'hA1,8'hA2,8'hA4,8'hA5,8'hA6,
        8'hA8,8'hA9,8'hAA,8'hAC,8'hAD,8'hAE: ss_fm_is_freq_reg = 1'b1;
        default: ss_fm_is_freq_reg = 1'b0;
    endcase
end
endfunction

function automatic [7:0] ss_fm_freq_hi_reg(input [3:0] i);
begin
    case (i)
        4'd0,4'd3: ss_fm_freq_hi_reg = 8'hA4;
        4'd1,4'd4: ss_fm_freq_hi_reg = 8'hA5;
        4'd2,4'd5: ss_fm_freq_hi_reg = 8'hA6;
        4'd6: ss_fm_freq_hi_reg = 8'hAC;
        4'd7: ss_fm_freq_hi_reg = 8'hAD;
        default: ss_fm_freq_hi_reg = 8'hAE;
    endcase
end
endfunction

function automatic [7:0] ss_fm_freq_lo_reg(input [3:0] i);
begin
    case (i)
        4'd0,4'd3: ss_fm_freq_lo_reg = 8'hA0;
        4'd1,4'd4: ss_fm_freq_lo_reg = 8'hA1;
        4'd2,4'd5: ss_fm_freq_lo_reg = 8'hA2;
        4'd6: ss_fm_freq_lo_reg = 8'hA8;
        4'd7: ss_fm_freq_lo_reg = 8'hA9;
        default: ss_fm_freq_lo_reg = 8'hAA;
    endcase
end
endfunction

wire ss_fm_freq_item_valid = (ss_audio_freq_index < 4'd6) ?
                              ss_fm_freq_valid[ss_audio_freq_index] :
                              ss_fm_ch3freq_valid[ss_audio_freq_index - 4'd6];
wire [13:0] ss_fm_freq_item = (ss_audio_freq_index < 4'd6) ?
                               ss_fm_freq[ss_audio_freq_index] :
                               ss_fm_ch3freq[ss_audio_freq_index - 4'd6];
wire ss_fm_freq_part = (ss_audio_freq_index >= 4'd3 && ss_audio_freq_index < 4'd6);

wire [3:0] ss_fm_replay_keymask = ss_fm_keymask[ss_audio_key_index];

reg  [1:0] ss_audio_fm_addr;
reg  [7:0] ss_audio_fm_din;
reg        ss_audio_fm_wr_n;
reg        ss_audio_psg_wr_n_r;
reg  [7:0] ss_audio_psg_din_r;
assign ss_audio_psg_wr_n = ss_audio_psg_wr_n_r;
assign ss_audio_psg_din  = ss_audio_psg_din_r;

always @* begin
    ss_audio_fm_addr    = 2'b00;
    ss_audio_fm_din     = 8'h00;
    ss_audio_fm_wr_n    = 1'b1;
    ss_audio_psg_wr_n_r = 1'b1;
    ss_audio_psg_din_r  = 8'h00;

    case (ss_audio_state)
        SSA_PSG_LOW: begin
            ss_audio_psg_wr_n_r = 1'b0;
            ss_audio_psg_din_r  = ss_psg_replay_byte(ss_audio_psg_index);
        end
        SSA_FM_ADDR_LOW: begin
            ss_audio_fm_addr = {ss_audio_fm_index[8], 1'b0};
            ss_audio_fm_din  = ss_audio_fm_index[7:0];
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_FM_DATA_LOW: begin
            ss_audio_fm_addr = {ss_audio_fm_index[8], 1'b1};
            ss_audio_fm_din  = ss_fm_replay_data_q;
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_FREQ_HA_LOW: begin
            ss_audio_fm_addr = {ss_fm_freq_part, 1'b0};
            ss_audio_fm_din  = ss_fm_freq_hi_reg(ss_audio_freq_index);
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_FREQ_HD_LOW: begin
            ss_audio_fm_addr = {ss_fm_freq_part, 1'b1};
            ss_audio_fm_din  = {2'b00, ss_fm_freq_item[13:8]};
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_FREQ_LA_LOW: begin
            ss_audio_fm_addr = {ss_fm_freq_part, 1'b0};
            ss_audio_fm_din  = ss_fm_freq_lo_reg(ss_audio_freq_index);
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_FREQ_LD_LOW: begin
            ss_audio_fm_addr = {ss_fm_freq_part, 1'b1};
            ss_audio_fm_din  = ss_fm_freq_item[7:0];
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_KEY_ADDR_LOW: begin
            ss_audio_fm_addr = 2'b00;
            ss_audio_fm_din  = 8'h28;
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_KEY_DATA_LOW: begin
            ss_audio_fm_addr = 2'b01;
            ss_audio_fm_din  = {ss_fm_replay_keymask, 1'b0, ss_fm_key_code(ss_audio_key_index)};
            ss_audio_fm_wr_n = 1'b0;
        end
        SSA_LATCH_LOW: begin
            ss_audio_fm_addr = {ss_fm_selected_part, 1'b0};
            ss_audio_fm_din  = ss_fm_selected_reg;
            ss_audio_fm_wr_n = 1'b0;
        end
        default: ;
    endcase
end

// Reset/replay is deliberately serialized after VDP-memory replay. With CPUs
// frozen there can be no competing sound-chip writes. The reset is held for
// eight external FM CEN pulses (JT12 requires at least six), PSG is rebuilt in
// 12 edge-separated writes, and each JT12 data write observes its real BUSY.
always @(posedge MCLK) begin
    ss_audio_done_q <= 1'b0;

    if (reset) begin
        ss_audio_state      <= SSA_IDLE;
        ss_audio_reset_cens <= 4'd0;
        ss_audio_psg_index  <= 4'd0;
        ss_audio_fm_index   <= 9'd0;
        ss_audio_key_index  <= 3'd0;
        ss_audio_freq_index <= 4'd0;
        ss_fm_replay_data_q <= 8'd0;
        ss_audio_done_q     <= 1'b0;
    end
    else begin
        case (ss_audio_state)
            SSA_IDLE: begin
                // R56 status[61] deliberately skips architectural audio replay
                // after an otherwise identical VDP-memory restore. This is an
                // A/B liveness diagnostic for the Streets of Rage 2 hang.
                if (ss_vdp_mem_restore_final_pulse && ss_vdp_audio_replay_latched) begin
                    ss_audio_reset_cens <= 4'd0;
                    ss_audio_psg_index  <= 4'd0;
                    ss_audio_fm_index   <= 9'd0;
                    ss_audio_key_index  <= 3'd0;
                    ss_audio_freq_index <= 4'd0;
                    ss_audio_state      <= SSA_RESET;
                end
            end

            SSA_RESET: begin
                if (FM_CLKEN) begin
                    if (ss_audio_reset_cens == 4'd7) begin
                        ss_audio_psg_index <= 4'd0;
                        ss_audio_state     <= SSA_PSG_LOW;
                    end
                    else
                        ss_audio_reset_cens <= ss_audio_reset_cens + 1'b1;
                end
            end

            SSA_PSG_LOW:  ss_audio_state <= SSA_PSG_HIGH;
            SSA_PSG_HIGH: begin
                if (ss_audio_psg_index == 4'd11) begin
                    ss_audio_fm_index <= 9'd0;
                    ss_audio_state    <= SSA_FM_SCAN;
                end
                else begin
                    ss_audio_psg_index <= ss_audio_psg_index + 1'b1;
                    ss_audio_state     <= SSA_PSG_LOW;
                end
            end

            SSA_FM_SCAN: begin
                if (ss_fm_written[ss_audio_fm_index] &&
                    ss_audio_fm_index[7:0] != 8'h28 &&
                    !ss_fm_is_freq_reg(ss_audio_fm_index[7:0])) begin
                    // Registered read encourages a single M10K instead of a
                    // wide 512:1 LUT mux on the already-tight MCLK paths.
                    ss_fm_replay_data_q <= ss_fm_shadow[ss_audio_fm_index];
                    ss_audio_state <= SSA_FM_ADDR_LOW;
                end
                else if (ss_audio_fm_index == 9'h1FF) begin
                    ss_audio_freq_index <= 4'd0;
                    ss_audio_state      <= SSA_FREQ_SCAN;
                end
                else
                    ss_audio_fm_index <= ss_audio_fm_index + 1'b1;
            end

            SSA_FM_ADDR_LOW:  ss_audio_state <= SSA_FM_ADDR_HIGH;
            SSA_FM_ADDR_HIGH: ss_audio_state <= SSA_FM_DATA_LOW;
            SSA_FM_DATA_LOW:  ss_audio_state <= SSA_FM_DATA_HIGH;
            SSA_FM_DATA_HIGH: ss_audio_state <= SSA_FM_WAIT_BUSY;

            SSA_FM_WAIT_BUSY: begin
                if (!FM_DO[7]) begin
                    if (ss_audio_fm_index == 9'h1FF) begin
                        ss_audio_freq_index <= 4'd0;
                        ss_audio_state      <= SSA_FREQ_SCAN;
                    end
                    else begin
                        ss_audio_fm_index <= ss_audio_fm_index + 1'b1;
                        ss_audio_state    <= SSA_FM_SCAN;
                    end
                end
            end

            // Rebuild committed normal-channel and CH3-special frequencies
            // as explicit high->low pairs. JT12 models the YM2612's single
            // shared FNUM high-byte latch, so simple numeric register replay
            // would otherwise assign the wrong block/FNUM high bits.
            SSA_FREQ_SCAN: begin
                if (ss_fm_freq_item_valid)
                    ss_audio_state <= SSA_FREQ_HA_LOW;
                else if (ss_audio_freq_index == 4'd8) begin
                    ss_audio_key_index <= 3'd0;
                    ss_audio_state     <= SSA_KEY_SCAN;
                end
                else
                    ss_audio_freq_index <= ss_audio_freq_index + 1'b1;
            end

            SSA_FREQ_HA_LOW:  ss_audio_state <= SSA_FREQ_HA_HIGH;
            SSA_FREQ_HA_HIGH: ss_audio_state <= SSA_FREQ_HD_LOW;
            SSA_FREQ_HD_LOW:  ss_audio_state <= SSA_FREQ_HD_HIGH;
            SSA_FREQ_HD_HIGH: ss_audio_state <= SSA_FREQ_H_WAIT;
            SSA_FREQ_H_WAIT: begin
                if (!FM_DO[7])
                    ss_audio_state <= SSA_FREQ_LA_LOW;
            end
            SSA_FREQ_LA_LOW:  ss_audio_state <= SSA_FREQ_LA_HIGH;
            SSA_FREQ_LA_HIGH: ss_audio_state <= SSA_FREQ_LD_LOW;
            SSA_FREQ_LD_LOW:  ss_audio_state <= SSA_FREQ_LD_HIGH;
            SSA_FREQ_LD_HIGH: ss_audio_state <= SSA_FREQ_L_WAIT;
            SSA_FREQ_L_WAIT: begin
                if (!FM_DO[7]) begin
                    if (ss_audio_freq_index == 4'd8) begin
                        ss_audio_key_index <= 3'd0;
                        ss_audio_state     <= SSA_KEY_SCAN;
                    end
                    else begin
                        ss_audio_freq_index <= ss_audio_freq_index + 1'b1;
                        ss_audio_state      <= SSA_FREQ_SCAN;
                    end
                end
            end

            SSA_KEY_SCAN: begin
                if (ss_fm_replay_keymask != 4'd0)
                    ss_audio_state <= SSA_KEY_ADDR_LOW;
                else if (ss_audio_key_index == 3'd5)
                    ss_audio_state <= SSA_LATCH_LOW;
                else
                    ss_audio_key_index <= ss_audio_key_index + 1'b1;
            end

            SSA_KEY_ADDR_LOW:  ss_audio_state <= SSA_KEY_ADDR_HIGH;
            SSA_KEY_ADDR_HIGH: ss_audio_state <= SSA_KEY_DATA_LOW;
            SSA_KEY_DATA_LOW:  ss_audio_state <= SSA_KEY_DATA_HIGH;
            SSA_KEY_DATA_HIGH: ss_audio_state <= SSA_KEY_WAIT_BUSY;

            SSA_KEY_WAIT_BUSY: begin
                if (!FM_DO[7]) begin
                    if (ss_audio_key_index == 3'd5)
                        ss_audio_state <= SSA_LATCH_LOW;
                    else begin
                        ss_audio_key_index <= ss_audio_key_index + 1'b1;
                        ss_audio_state     <= SSA_KEY_SCAN;
                    end
                end
            end

            SSA_LATCH_LOW:  ss_audio_state <= SSA_LATCH_HIGH;
            SSA_LATCH_HIGH: ss_audio_state <= SSA_WAIT_ACTIVE;

            // Audio replay can outlast the VBlank in which restore began.
            // Freeze the rebuilt audio core, observe active display, then wait
            // for a genuinely fresh VBlank before releasing VDP/CPUs. This
            // preserves the v1.3 safe-boundary guarantee.
            SSA_WAIT_ACTIVE: begin
                if (!VBL)
                    ss_audio_state <= SSA_WAIT_VBL;
            end

            SSA_WAIT_VBL: begin
                if (VBL && VDP_SS_RENDER_IDLE)
                    ss_audio_state <= SSA_DONE;
            end

            SSA_DONE: begin
                ss_audio_done_q <= 1'b1;
                ss_audio_state  <= SSA_IDLE;
            end

            default: ss_audio_state <= SSA_IDLE;
        endcase
    end
end

wire [1:0] fm_addr_eff = ss_audio_restore_active ? ss_audio_fm_addr : ZBUS_A[1:0];
wire [7:0] fm_din_eff  = ss_audio_restore_active ? ss_audio_fm_din  : ZBUS_DO;
wire       fm_wr_n_eff = ss_audio_restore_active ? ss_audio_fm_wr_n : ~(FM_SEL & ZBUS_WE);
wire       fm_rst_eff  = ~Z80_RESET_N | (ss_audio_state == SSA_RESET);

jt12 fm
(
	.rst(fm_rst_eff),
	.clk(MCLK),
	.cen(FM_CLKEN),

	.cs_n(0),
	.addr(fm_addr_eff),
	.wr_n(fm_wr_n_eff),
	.din(fm_din_eff),
	.dout(FM_DO),
	.en_hifi_pcm( EN_HIFI_PCM ),
	.ladder(LADDER),
	.snd_left(FM_left),
	.snd_right(FM_right)
);

wire signed [15:0] fm_adjust_l = (FM_left  << 4) + (FM_left  << 2) + (FM_left  << 1) + (FM_left  >>> 2);
wire signed [15:0] fm_adjust_r = (FM_right << 4) + (FM_right << 2) + (FM_right << 1) + (FM_right >>> 2);

genesis_fm_lpf fm_lpf_l
(
	.clk(MCLK),
	.reset(reset | ss_audio_filter_reset),
	.in(fm_adjust_l),
	.out(FM_LPF_left)
);

genesis_fm_lpf fm_lpf_r
(
	.clk(MCLK),
	.reset(reset | ss_audio_filter_reset),
	.in(fm_adjust_r),
	.out(FM_LPF_right)
);

wire signed [15:0] fm_select_l = ((LPF_MODE == 2'b01) ? FM_LPF_left : fm_adjust_l);
wire signed [15:0] fm_select_r = ((LPF_MODE == 2'b01) ? FM_LPF_right : fm_adjust_r);

wire signed [10:0] psg_adjust = PSG_SND - (PSG_SND >>> 5);

jt12_genmix genmix
(
	.rst(reset | ss_audio_filter_reset),
	.clk(MCLK),
	.fm_left(fm_select_l),
	.fm_right(fm_select_r),
	.psg_snd(psg_adjust),
	.fm_en(ENABLE_FM),
	.psg_en(ENABLE_PSG),
	.snd_left(PRE_LPF_L),
	.snd_right(PRE_LPF_R)
);

genesis_lpf lpf_right
(
	.clk(MCLK),
	.reset(reset | ss_audio_filter_reset),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_R),
	.out(DAC_RDATA)
);

genesis_lpf lpf_left
(
	.clk(MCLK),
	.reset(reset | ss_audio_filter_reset),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_L),
	.out(DAC_LDATA)
);


assign SS_MEM_TERMS = VDP_SS_MEM_TERMS;

// Game Bub: the save-state diagnostics word (see the port comment).
assign SS_DBG = {ss_m68k_dbg_state, ss_m68k_safe_start, M68K_INTACK, ss_m68k_cpu_reset, ss_m68k_irq7,
                 Z80_BUSRQ_N, Z80_RESET_N, Z80_ISET == 2'b00, ~Z80_MREQ_N, ~Z80_M1_N, ~ss_hold,
                 VDP_SS_RENDER_IDLE, VDP_SS_MEM_IDLE, ~VBUS_SEL, M68K_AS_N, mstate == MBUS_IDLE, VBL};

endmodule
