package net.gamebub.core.md

import chisel3._
import chisel3.util._
import lib.audio.AudioRateAdapter
import lib.mem.{MemoryInterface, MemoryMap, PipelineInterfaceBridge, PipelineMemoryArbiter, PipelineMemoryLowPriorityMux, RegisterMap}
import lib.mem.sdram.BurstSdramController
import lib.audio.AudioDecimator
import net.gamebub.framework.Core
import net.gamebub.framework.interface._
import xilinx.{BUFG, MMCM, PLL}

object HandheldMd {
  //////////////////////////////////
  // Clock tree (docs/md-port-design.md section 1): 53.693175 MHz, the Mega
  // Drive's master clock, is 50 MHz x 189/176 to 0.13 ppm, and 189/176 =
  // (21/11) x (9/16) splits across the MMCM and the PLL with integer dividers
  // only. MMCM 50 x 21 = 1050 MHz VCO -> /11 = 95.4545 MHz -> PLL x9 =
  // 859.0909 MHz VCO -> /16 = 53.6932 MHz (machine, glue, SDRAM controller at
  // 1x), /16 phase-shifted for the SDRAM chip's clock pin, /5 = 171.8 MHz host
  // SPI; display clock from the MMCM's VCO.
  //////////////////////////////////
  val ClockInHz = 50_000_000
  val MmcmDivide = 1
  val MmcmMultiply = 21.0
  val MmcmVcoHz = ClockInHz.toDouble / MmcmDivide * MmcmMultiply
  val PllInputDivider = 11
  val PllMultiply = 9
  val PllVcoHz = MmcmVcoHz / PllInputDivider * PllMultiply
  val SysDivider = 16
  val SdramDivider = 16
  val SpiDivider = 5
  /**
   * Delay of the SDRAM chip's clock behind the controller's. The period here is
   * 18.62 ns, shorter than the PCE's 23.28, so the PCE's 14 ns would leave only
   * 3.6 ns of output hold; 11.93 ns balances the four pin checks (design
   * section 1).
   */
  val SdramClockPhaseNs = 11.93
  val ClockSystemHz = (PllVcoHz / SysDivider).round.toInt
  val ClockSpiHz = (PllVcoHz / SpiDivider).toInt
  val SdramClockPhaseDegrees = {
    val step = 360.0 / (8 * SdramDivider)
    (360.0 * SdramClockPhaseNs * ClockSystemHz / 1e9 / step).round * step
  }
  require(math.abs(ClockSystemHz - 53_693_175) < 100, s"system clock $ClockSystemHz")
  require(ClockSpiHz > 160_000_000)

  /** One NTSC frame: 262 lines x 3420 master clocks (vdp.vhd's HV_PIXDIV). */
  val FrameClocks = 262 * 3420
  val FramePeriod = FrameClocks.toDouble / ClockSystemHz

  val Width = MdVideoCapture.Width
  val Height = MdVideoCapture.Height

  /** A warm reset (register 0x0000) holds the machine in reset this many clocks. */
  val WarmResetBits = 16
  /**
   * The memory clear runs this long. `ram_rst_a` increments once a clock and
   * the widest user is the work RAM's `ram_rst_a[15:1]`, so 2^16 clocks (1.22
   * ms) walks every address of the work RAM, the VRAM and the save RAM.
   */
  val RamInitClocks = 1 << 16
  /** ROM answers slower than this cost the 68000 a wait state (design section 4). */
  val SlowAnswerCycles = 11

  /** The largest cartridge: 4 MiB plus the SSF2 mapper's banks. */
  val RomBytes = 0xA00000
  /** The cartridge save RAM, as MiSTer sizes its `.sav`. */
  val SaveBytes = 0x10000

  object FileId {
    val Cartridge = 0
    val Save = 1
    /** The save-state slots, 4 x 256 KiB in the SDRAM ([[MdSaveState]]). */
    val States = 2
  }

  /** The engine's busy, stretched so the firmware's poll sees it (100 ms). */
  val SsBusyStretchCycles = ClockSystemHz / 10
  /** A save-state request that has not finished after this long is given up (the engine's own watchdog is 2.5 s). */
  val SsTimeoutCycles = ClockSystemHz * 3
  /**
   * The engine edge-detects its commands and misses an edge that lands while it drains a probe of
   * the slot header, so an unanswered request is re-edged every 2^SsRetryBits clocks.
   */
  val SsRetryBits = 10

  object CommandState extends ChiselEnum {
    val idle, busy, error, done = Value
  }

  object Region {
    val Auto = 0
    val Japan = 1
    val Usa = 2
    val Europe = 3
  }

  /** Register 0x0010. N.B. the last field is bit 0. */
  class ConfigBits extends Bundle {
    val reserved31 = UInt(15.W)
    /** Bit 16: show the VDP's border instead of the active area only. */
    val border = Bool()
    /** Bit 15: 1 = YM3438 (no DAC ladder effect). */
    val ym3438 = Bool()
    /** Bit 14: interpolate PCM samples. */
    val hifiPcm = Bool()
    /** Bit 13: CRAM dots (the colour bus artefact). */
    val cramDots = Bool()
    /** Bit 12: raise the per-line sprite limit. */
    val spriteLimitHigh = Bool()
    /** Bit 11: mute the PSG. */
    val psgOff = Bool()
    /** Bit 10: mute the FM. */
    val fmOff = Bool()
    /** Bit 9: mix both channels to mono. */
    val mono = Bool()
    /** Bits 8:7: MiSTer's Audio Filter -- 0 Model 1, 1 Model 2, 2 Minimal, 3 None. */
    val lpfMode = UInt(2.W)
    /** Bits 6:5: which Game Bub buttons carry A / B / C (0 = Y B A, 1 = B A X). */
    val buttons = UInt(2.W)
    /** Bit 4: 1 = a three-button pad. */
    val pad3Button = Bool()
    /** Bits 3:2: 0 from the region, 1 = 60 Hz, 2 = 50 Hz. */
    val video = UInt(2.W)
    /** Bits 1:0: 0 Auto (from the header), 1 Japan, 2 USA, 3 Europe. */
    val region = UInt(2.W)
  }
  val ConfigResetValue = 0x0

  /** The cartridge serials `Genesis.sv` keys its quirks on: header bytes 0x183-0x18A. */
  def serial(s: String): BigInt = {
    require(s.length == 8)
    s.getBytes("US-ASCII").foldLeft(BigInt(0))((acc, b) => (acc << 8) | BigInt(b & 0xFF))
  }
}

/**
 * Mega Drive / Genesis core, wrapping the vendored MiSTer Genesis machine
 * ([[MdCore]], `fpga/verilog/md`); docs/md-port-design.md.
 *
 * One clock, 53.693175 MHz, for the machine, this glue and the SDRAM
 * controller.
 *
 * Host windows: registers 0x0xxx_xxxx; cartridge 0x3xxx_xxxx (into the SDRAM at
 * 0, as the file is on the card); `.sav` 0x4xxx_xxxx (the save RAM's B port);
 * `.ss` 0x5xxx_xxxx (the save-state slots, SDRAM 0x1000000, [[MdSaveState]]);
 * commands 0xF0xx_xxxx.
 *
 * Registers:
 *  - 0x0000 (w) bit 0: reset the machine
 *  - 0x0004 (r) cartridge serial, bytes 0x187-0x18A
 *  - 0x0008 (r) cartridge serial, bytes 0x183-0x186
 *  - 0x000C (r) cartridge file size
 *  - 0x0010 (rw) configuration, see [[HandheldMd.ConfigBits]]
 *  - 0x0014 save states (the NES / PCE layout): write bit 0 save / bit 1 load
 *           (slot in bits 3:2, or from 0x0018 with bit 4 set); reads back
 *           the slot of the last request in bits 3:2
 *  - 0x0018 (rw) the save-state slot (bits 1:0; the State Slot setting)
 *  - 0x001C (r) detected quirks and header region
 *  - 0x0020 (r) save-state diagnostics, live (md_gamebub_core.sv `ss_dbg`)
 *  - 0x0024 (r) the same, held: at the clock the 68000 capture handler gave up (its state
 *           1 / 2 / 3 says which wait timed out, the low bits which terms were false) when
 *           the last request failed there, else as it was at the end of the last request
 *  - 0x0028 (r) a clock counter of the condition selected by 0x002C, free-running
 *  - 0x002C (rw) the condition: a mask of `ss_dbg` bits 15:0; a write restarts the count of
 *           clocks in which every masked bit is 1 (0x8000 = the engine's safe point,
 *           0x007F = its 68000 / VDP half, 0x0001 = VBL, and so on)
 *  - 0x0030 (r) diagnostics 2, live: bits 8:0 the VDP's nine memory-idle terms, 1 = busy
 *           ([0] FIFO not empty, [1] DMA in progress, [2] data-transfer controller busy,
 *           [3] DMA controller busy, [4] VRAM data access, [5] VDP on the 68000 bus,
 *           [6] CRAM write, [7] VSRAM0 write, [8] VSRAM1 write): which one keeps the
 *           engine's "VDP memory idle" term false during a hold (r2.18)
 *  - 0x0034 (r) the same, held as 0x0024 is
 *  - 0x0100 (r) status: 0 setup, 1 halted, 2 focus, 3 in setup, 4 setup
 *           complete, 6 save states available for this cartridge, 7 a save
 *           or load runs (busy, >= 100 ms), 8 the last save completed, 9 a
 *           request waits for the engine, 10 a request is in progress,
 *           14:11 slots holding a state, 15 the last request failed;
 *           16 clearing memory, 17 cartridge present, 18 `.sav` loaded,
 *           19 save RAM written, 20 PAL, 21 export region, 23:22 VDP
 *           resolution {V30,H40}, 31:24 the engine's last error code
 *  - 0x1000-0x1020 statistics (write clears)
 */
class HandheldMd extends Module with Core {
  import HandheldMd._

  val displayDivider = (MmcmVcoHz / ClocksV0.getClockDisplayHz(FramePeriod)._1).floor.toInt

  val io = IO(new Bundle {
    val clocks = new ClocksV0(
      clockSystemHz = ClockSystemHz,
      clockDisplayHz = (MmcmVcoHz / displayDivider).toInt,
      clockSpiHz = ClockSpiHz,
    )
    val video = new VideoV0(
      videoWidth = Width,
      videoHeight = Height,
      colorDepthR = 5,
      colorDepthG = 6,
      colorDepthB = 5,
      framePeriod = FramePeriod,
    )
    val audio = new AudioV0()
    val host = new HostV0()
    val input = new InputV0()
    val sdram = new SdramV0()
  })

  //////////////////////////////////
  // Clocks
  //////////////////////////////////
  val mmcm = Module(new MMCM(
    clockInHz = ClockInHz,
    divide = MmcmDivide,
    multiply = MmcmMultiply,
    clockOutConfig = Seq(
      MMCM.ClockOut(PllInputDivider), // PLL input, 95.4545 MHz
      MMCM.ClockOut(displayDivider),  // Display
    )
  ))
  mmcm.io.clockIn := io.clocks.clockIn50M
  mmcm.io.powerDown := false.B
  // core_md.xdc names this instance's SDRAM pin clock output (core/pll/pll/CLKOUT1).
  val pll = Module(new PLL(
    clockInHz = (MmcmVcoHz / PllInputDivider).round.toInt,
    divide = 1,
    multiply = PllMultiply,
    clockOutConfig = Seq(
      PLL.ClockOut(SysDivider),                                   // System = machine = SDRAM controller (1x)
      PLL.ClockOut(SdramDivider, phase = SdramClockPhaseDegrees), // SDRAM chip (forwarded)
      PLL.ClockOut(SpiDivider),                                   // Host SPI
    )
  ))
  pll.io.clockIn := BUFG(mmcm.io.clockOuts(0))
  pll.io.powerDown := false.B
  pll.io.reset := !mmcm.io.locked
  io.clocks.clockOutSystem := pll.io.clockOuts(0)
  val clockSdramPin = BUFG(pll.io.clockOuts(1))
  io.clocks.clockOutDisplay := mmcm.io.clockOuts(1)
  io.clocks.clockOutSpi := pll.io.clockOuts(2)
  io.clocks.locked := mmcm.io.locked && pll.io.locked

  //////////////////////////////////
  // Framework state
  //////////////////////////////////
  val regCoreSetup = RegInit(false.B)
  val regCoreReset = RegInit(true.B)
  val regCoreFocus = RegInit(false.B)
  /** From a cartridge transfer until SetupComplete: the machine is held in reset. */
  val coldReset = RegInit(true.B)
  val warmResetCounter = RegInit(0.U(WarmResetBits.W))
  val warmResetWrite = WireDefault(false.B)

  val cartLoaded = RegInit(false.B)
  val cartFileSize = RegInit(0.U(25.W))
  val savLoaded = RegInit(false.B)
  val saveDirty = RegInit(false.B)

  /** The memory clear (`RAM_INIT`), which owns the save RAM's B port while it runs. */
  val ramInitCounter = RegInit(0.U((log2Ceil(RamInitClocks) + 1).W))
  val ramInitStart = WireDefault(false.B)
  val ramInit = ramInitCounter =/= 0.U
  when (ramInitStart) {
    ramInitCounter := RamInitClocks.U
  } .elsewhen (ramInit) {
    ramInitCounter := ramInitCounter - 1.U
  }

  //////////////////////////////////
  // Cartridge header, captured from the host stream
  //
  // `Genesis.sv` keys its quirk table on the eight header bytes 0x183-0x18A
  // (the product code) and its region on 0x1F0-0x1F2. A 32-bit host word at
  // byte address A holds file byte A in bits 7:0, so the three words 0x180,
  // 0x184 and 0x188 carry the serial and the word 0x1F0 the region.
  //////////////////////////////////
  val cartSerialHigh = RegInit(0.U(32.W)) // bytes 0x183-0x186
  val cartSerialLow = RegInit(0.U(32.W))  // bytes 0x187-0x18A
  val byte183 = RegInit(0.U(8.W))
  val word180 = RegInit(0.U(32.W))
  val word184 = RegInit(0.U(32.W))
  val word188 = RegInit(0.U(32.W))
  /** Bytes 0x18C-0x18F: the end of the serial and the header checksum. */
  val word18C = RegInit(0.U(32.W))
  val hdrJ = RegInit(false.B)
  val hdrU = RegInit(false.B)
  val hdrE = RegInit(false.B)

  //////////////////////////////////
  // Host registers and windows
  //////////////////////////////////
  val configReg = RegInit(ConfigResetValue.U(32.W).asTypeOf(new ConfigBits))
  val statFrames = RegInit(0.U(32.W))
  val statTransactions = RegInit(0.U(32.W))
  val statHits = RegInit(0.U(32.W))
  val statSdramReads = RegInit(0.U(32.W))
  val statSdramWrites = RegInit(0.U(32.W))
  val statPrefetches = RegInit(0.U(32.W))
  val statMaxLatency = RegInit(0.U(32.W))
  val statSlowAnswers = RegInit(0.U(32.W))
  val statRunClocks = RegInit(0.U(32.W))
  /** Where the 68000 is: its last bus address, and the range it visited recently. */
  val statAddrLast = RegInit(0.U(24.W))
  val statAddrMin = RegInit(0.U(24.W))
  val statAddrMax = RegInit(0.U(24.W))
  val addrMinAcc = RegInit(~0.U(24.W))
  val addrMaxAcc = RegInit(0.U(24.W))
  val addrWindow = RegInit(0.U(6.W))
  /** Which exception fired, and where the 68000 was just before it. */
  val statAddrPrev = RegInit(0.U(24.W))
  val statVecAddr = RegInit(0.U(24.W))
  val statVecCount = RegInit(0.U(32.W))
  /**
   * The last few distinct addresses the 68000 put on the bus, newest first, ignoring this ROM's
   * `BRA *` stub at 0x202. Once the machine is parked there this stops moving and holds the run-up
   * to the fault: the exception's stack writes, the vector fetch, and before them the access that
   * went wrong.
   */
  val AddrHistory = 20
  val addrHistory = RegInit(VecInit(Seq.fill(AddrHistory)(0.U(24.W))))
  val statusWire = Wire(UInt(32.W))
  val quirkWire = Wire(UInt(32.W))
  val ssControlWrite = WireDefault(false.B)
  val ssControlWriteData = WireDefault(0.U(32.W))
  /** The slot of the last save-state request (what the engine gets). */
  val ssSlot = RegInit(0.U(2.W))
  /** The State Slot setting (register 0x0018). */
  val ssSlotReg = RegInit(0.U(2.W))
  val ssDbgWire = Wire(UInt(32.W))
  val ssDbgHold = RegInit(0.U(32.W))
  val ssDbgCount = RegInit(0.U(32.W))
  val ssDbgMask = RegInit(0x8000.U(16.W))
  val ssDbgMaskWrite = WireDefault(false.B)
  val ssDbg2Wire = Wire(UInt(32.W))
  val ssDbg2Hold = RegInit(0.U(32.W))

  val registerInterface = Wire(new MemoryInterface(addressWidth = 16, dataWidth = 32))
  val cartHost = Wire(new MemoryInterface(addressWidth = 24, dataWidth = 32))
  val savHost = Wire(new MemoryInterface(addressWidth = 17, dataWidth = 32))
  val statesHost = Wire(new MemoryInterface(addressWidth = 24, dataWidth = 32))
  val commandInterface = Wire(new MemoryInterface(addressWidth = 16, dataWidth = 32))
  val memoryMap = MemoryMap(
    addressWidth = 32,
    dataWidth = 32,
    entries = Seq(
      0x0.U(4.W) -> registerInterface,
      0x3.U(4.W) -> cartHost,
      0x4.U(4.W) -> savHost,
      0x5.U(4.W) -> statesHost,
      0xF0.U(8.W) -> commandInterface,
    ))
  io.host.mem.unsafe :<>= memoryMap.unsafe
  memoryMap.writeStrobe := "b1111".U

  registerInterface <> RegisterMap(
    addressWidth = 16,
    dataWidth = 32,
    entries = Seq(
      0x0000 -> RegisterMap.Entry(32, RegisterMap.ReadFn(), RegisterMap.WriteFn((write, data) => {
        when (write && data(0)) { warmResetWrite := true.B }
      })),
      0x0004 -> RegisterMap.Entry.r(cartSerialLow),
      0x0008 -> RegisterMap.Entry.r(cartSerialHigh),
      0x000C -> RegisterMap.Entry.r(cartFileSize),
      0x0010 -> RegisterMap.Entry.rw(configReg),
      0x0014 -> RegisterMap.Entry(32,
        RegisterMap.ReadFn(_ => Cat(ssSlot, 0.U(2.W))),
        RegisterMap.WriteFn((write, data) => {
          ssControlWrite := write
          ssControlWriteData := data
        })),
      0x0018 -> RegisterMap.Entry.rw(ssSlotReg),
      0x0020 -> RegisterMap.Entry.r(ssDbgWire),
      0x0024 -> RegisterMap.Entry.r(ssDbgHold),
      0x0028 -> RegisterMap.Entry.r(ssDbgCount),
      0x002C -> RegisterMap.Entry(32,
        RegisterMap.ReadFn(_ => ssDbgMask),
        RegisterMap.WriteFn((write, data) => {
          when (write) {
            ssDbgMask := data(15, 0)
            ssDbgMaskWrite := true.B
          }
        })),
      0x0030 -> RegisterMap.Entry.r(ssDbg2Wire),
      0x0034 -> RegisterMap.Entry.r(ssDbg2Hold),
      0x001C -> RegisterMap.Entry.r(quirkWire),
      0x0100 -> RegisterMap.Entry.r(statusWire),
      0x1000 -> RegisterMap.Entry.rw(statFrames),
      0x1004 -> RegisterMap.Entry.rw(statTransactions),
      0x1008 -> RegisterMap.Entry.rw(statHits),
      0x100C -> RegisterMap.Entry.rw(statSdramReads),
      0x1010 -> RegisterMap.Entry.rw(statSdramWrites),
      0x1014 -> RegisterMap.Entry.rw(statPrefetches),
      0x1018 -> RegisterMap.Entry.rw(statMaxLatency),
      0x101C -> RegisterMap.Entry.rw(statSlowAnswers),
      0x1020 -> RegisterMap.Entry.rw(statRunClocks),
      0x1024 -> RegisterMap.Entry.r(statAddrLast),
      0x1028 -> RegisterMap.Entry.r(statAddrMin),
      0x102C -> RegisterMap.Entry.r(statAddrMax),
      0x1030 -> RegisterMap.Entry.r(statAddrPrev),
      0x1034 -> RegisterMap.Entry.r(statVecAddr),
      0x1038 -> RegisterMap.Entry.r(statVecCount),
    ) ++ (0 until AddrHistory).map(i => (0x1040 + 4 * i) -> RegisterMap.Entry.r(addrHistory(i)))
  )

  //////////////////////////////////
  // SDRAM: the host's cartridge window (0), the host's `.ss` window (1), and
  // the ROM store (2) with the save-state traffic behind it on a low-priority
  // side port (the slot scanner and the engine's slot memory channel): a slot
  // probe never delays a ROM fetch, and the engine only transfers a state
  // while it holds the CPUs. Only the store and the side port are active once
  // the core is running.
  //////////////////////////////////
  val sdramArbiter = Module(new PipelineMemoryArbiter(addressWidth = 25, dataWidth = 32, n = 3))
  locally {
    val bridge = Module(new PipelineInterfaceBridge(addressWidth = 25, dataWidth = 32))
    bridge.io.source.enable := cartHost.enable
    bridge.io.source.write := cartHost.write
    bridge.io.source.address := cartHost.address
    bridge.io.source.dataWrite := cartHost.dataWrite
    bridge.io.source.writeStrobe := "b1111".U
    cartHost.done := bridge.io.source.done
    cartHost.dataRead := bridge.io.source.dataRead
    bridge.io.dest <> sdramArbiter.io.initiator(0)
  }
  locally {
    val bridge = Module(new PipelineInterfaceBridge(addressWidth = 25, dataWidth = 32))
    bridge.io.source.enable := statesHost.enable
    bridge.io.source.write := statesHost.write
    // The 1 MiB slot area at SDRAM 0x1000000 (MdSaveState.SlotsBase).
    bridge.io.source.address := Cat(1.U(1.W), 0.U(4.W), statesHost.address(19, 0))
    bridge.io.source.dataWrite := statesHost.dataWrite
    bridge.io.source.writeStrobe := "b1111".U
    statesHost.done := bridge.io.source.done
    statesHost.dataRead := bridge.io.source.dataRead
    bridge.io.dest <> sdramArbiter.io.initiator(1)
  }
  val sidePort = Module(new PipelineMemoryLowPriorityMux(addressWidth = 25, dataWidth = 32))
  sidePort.io.target <> sdramArbiter.io.initiator(2)
  val ssScanner = Module(new MdSaveSlotScanner)
  val ssPort = Module(new MdSaveStatePort)
  val ssScanFromFile = WireDefault(false.B)
  val ssRescan = WireDefault(false.B)
  val ssInvalidate = WireDefault(false.B)
  ssScanner.io.invalidate := ssInvalidate
  // The scanner and the engine's channel share the side port one at a time (an arbiter there
  // would close a combinational loop through the mux's ready): a scan waits for the channel to
  // be idle, and the channel waits while a scan runs or is about to.
  val ssScanStartPending = RegInit(false.B)
  val ssScanLoadedSize = RegInit(0.U((log2Ceil(MdSaveState.FullSize) + 1).W))
  ssScanner.io.start := ssScanStartPending && !ssPort.io.busy
  ssScanner.io.loadedSize := ssScanLoadedSize
  ssPort.io.hold := ssScanner.io.busy || ssScanStartPending
  when (ssScanner.io.start) {
    ssScanStartPending := false.B
  }
  when (ssScanFromFile || ssRescan) {
    ssScanStartPending := true.B
  }
  val scannerOwns = ssScanner.io.busy
  sidePort.io.side.enable := Mux(scannerOwns, ssScanner.io.mem.enable, ssPort.io.mem.enable)
  sidePort.io.side.address := Mux(scannerOwns, ssScanner.io.mem.address, ssPort.io.mem.address)
  sidePort.io.side.isWrite := Mux(scannerOwns, ssScanner.io.mem.isWrite, ssPort.io.mem.isWrite)
  sidePort.io.side.writeStrobe := Mux(scannerOwns, ssScanner.io.mem.writeStrobe, ssPort.io.mem.writeStrobe)
  sidePort.io.side.dataWrite := Mux(scannerOwns, ssScanner.io.mem.dataWrite, ssPort.io.mem.dataWrite)
  ssScanner.io.mem.ready := sidePort.io.side.ready && scannerOwns
  ssScanner.io.mem.dataRead := sidePort.io.side.dataRead
  ssPort.io.mem.ready := sidePort.io.side.ready && !scannerOwns
  ssPort.io.mem.dataRead := sidePort.io.side.dataRead

  when (cartHost.enable && cartHost.write) {
    switch (cartHost.address) {
      is (0x180.U) { byte183 := cartHost.dataWrite(31, 24); word180 := cartHost.dataWrite }
      is (0x184.U) { word184 := cartHost.dataWrite }
      is (0x188.U) { word188 := cartHost.dataWrite }
      is (0x18C.U) { word18C := cartHost.dataWrite }
      is (0x1F0.U) {
        // `Genesis.sv` reads byte 0x1F0 (letter, digit or hex nibble), then
        // 0x1F2, then 0x1F1, each overriding the last where they overlap.
        val b0 = cartHost.dataWrite(7, 0)
        val b1 = cartHost.dataWrite(15, 8)
        val b2 = cartHost.dataWrite(23, 16)
        val hrgn = b0(3, 0) - 7.U
        when (b0 === 'J'.U) { hdrJ := true.B }
          .elsewhen (b0 === 'U'.U) { hdrU := true.B }
          .elsewhen (b0 === 'E'.U) { hdrE := true.B }
          .elsewhen (b0 >= '0'.U && b0 <= '9'.U) { hdrE := b0(3); hdrU := b0(2); hdrJ := b0(0) }
          .elsewhen (b0 >= 'A'.U && b0 <= 'F'.U) { hdrE := hrgn(3); hdrU := hrgn(2); hdrJ := hrgn(0) }
        when (b2 === 'J'.U) { hdrJ := true.B }
          .elsewhen (b2 === 'U'.U) { hdrU := true.B }
          .elsewhen (b2 === 'E'.U) { hdrE := true.B }
        when (b1 === 'J'.U) { hdrJ := true.B }
          .elsewhen (b1 === 'U'.U) { hdrU := true.B }
          .elsewhen (b1 === 'E'.U) { hdrE := true.B }
      }
    }
  }
  cartSerialHigh := Cat(byte183, word184(7, 0), word184(15, 8), word184(23, 16))
  cartSerialLow := Cat(word184(31, 24), word188(7, 0), word188(15, 8), word188(23, 16))
  val cartSerial = Cat(cartSerialHigh, cartSerialLow)

  /** `Genesis.sv`'s quirk table, minus the hardware this port does not build. */
  def serialIs(codes: String*): Bool = VecInit(codes.map(c => cartSerial === serial(c).U(64.W))).asUInt.orR
  val sramQuirk = serialIs("T-081276", "T-81406 ", "T-081586", "T-81576 ", "T-81476 ")
  val sram00Quirk = serialIs(" GM 0000")
  val eepromQuirk = serialIs("MK-1215 ", "G-4060  ", "00001211", "MK-1228 ", "G-5538  ",
                             "00004076", "T-12046 ", "T-12053 ", "G-4524  ")
  val noramQuirk = serialIs("T-113016")
  val fifoQuirk = serialIs("T-89016 ")
  val fmbusyQuirk = serialIs("T-35036 ", "T-25073 ", "MK-1137-")
  val schanQuirk = serialIs("T-68???-")
  quirkWire := Cat(0.U(22.W), hdrE, hdrU, hdrJ,
    schanQuirk, fmbusyQuirk, fifoQuirk, noramQuirk, eepromQuirk, sram00Quirk, sramQuirk)

  //////////////////////////////////
  // Region: `Genesis.sv`'s header rule with its default US > EU > JP priority,
  // or a forced region. PAL and EXPORT are straps: a change resets the machine.
  //////////////////////////////////
  val autoRegion = Mux(hdrU, Region.Usa.U, Mux(hdrE, Region.Europe.U,
    Mux(hdrJ, Region.Japan.U, Region.Usa.U)))
  val region = Mux(configReg.region === Region.Auto.U, autoRegion, configReg.region)
  val regionExport = region =/= Region.Japan.U
  val regionPal = MuxLookup(configReg.video, region === Region.Europe.U)(Seq(
    1.U -> false.B,
    2.U -> true.B,
  ))

  //////////////////////////////////
  // Framework command interface
  //////////////////////////////////
  val commandHostState = RegInit(CommandState.idle)
  val regCommandHost = Reg(Vec(4, UInt(32.W)))
  commandInterface <> RegisterMap(
    addressWidth = 16,
    dataWidth = 32,
    entries =
      regCommandHost.zipWithIndex.map { case (reg, i) => (0x0000 + (4 * i) -> RegisterMap.Entry.rw(reg)) }
  )
  val setupReady = regCoreSetup && !ramInit

  io.host.commandHost.busy := commandHostState === CommandState.busy
  io.host.commandHost.done := commandHostState === CommandState.done
  io.host.commandHost.error := commandHostState === CommandState.error
  when (io.host.commandHost.request) {
    when (commandHostState === CommandState.idle) {
      val command = regCommandHost(0)(15, 0)
      val fileId = regCommandHost(1)(15, 0)
      val fileSize = regCommandHost(2)
      for (reg <- regCommandHost) {
        reg := 0.U
      }
      commandHostState := CommandState.done

      when (command === HostV0.CommandGetStatus.U) {
        when (setupReady) {
          regCommandHost(0) := Mux(regCoreReset, HostV0.StatusCoreHalt.U, HostV0.StatusCoreRun.U)
        } .otherwise {
          regCommandHost(0) := HostV0.StatusSetup.U
        }
      } .elsewhen (command === HostV0.CommandSetupComplete.U) {
        // Without a cartridge there is nothing to run: the firmware reports a
        // core error instead of a black screen.
        when (!cartLoaded) {
          commandHostState := CommandState.error
        } .otherwise {
          regCoreSetup := true.B
          coldReset := false.B
        }
      } .elsewhen (command === HostV0.CommandCoreRun.U) {
        regCoreReset := false.B
      } .elsewhen (command === HostV0.CommandCoreHalt.U) {
        regCoreReset := true.B
      } .elsewhen (command === HostV0.CommandNotifyFocus.U) {
        regCoreFocus := regCommandHost(1)(0)
      } .elsewhen (command === HostV0.CommandFileWriteStart.U) {
        when (fileId === FileId.Cartridge.U) {
          regCoreSetup := false.B
          coldReset := true.B
          cartLoaded := false.B
          cartFileSize := 0.U
          byte183 := 0.U
          word180 := 0.U
          word184 := 0.U
          word188 := 0.U
          word18C := 0.U
          hdrJ := false.B
          hdrU := false.B
          hdrE := false.B
          savLoaded := false.B
          saveDirty := false.B
          // Another cartridge: its slots come with its States file.
          ssInvalidate := true.B
          // The memory clear runs now, so the save RAM is at its power-on
          // value before the `.sav` window (file 1, loaded after this one)
          // writes anything into it.
          ramInitStart := true.B
          commandHostState := CommandState.busy
        }
      } .elsewhen (command === HostV0.CommandFileWriteEnd.U) {
        when (fileId === FileId.Cartridge.U) {
          cartFileSize := fileSize(24, 0)
          cartLoaded := fileSize =/= 0.U && fileSize <= RomBytes.U
        } .elsewhen (fileId === FileId.Save.U) {
          savLoaded := fileSize === SaveBytes.U
        } .elsewhen (fileId === FileId.States.U) {
          // Which slots the file filled; the rest are cleared (MdSaveSlotScanner).
          ssScanFromFile := true.B
          commandHostState := CommandState.busy
        }
      } .elsewhen (command === HostV0.CommandFileReadStart.U) {
        when (fileId === FileId.Save.U) {
          // A game without a battery never leaves a file behind.
          regCommandHost(0) := Mux(cartLoaded && (savLoaded || saveDirty), SaveBytes.U, 0.U)
        } .elsewhen (fileId === FileId.States.U) {
          // The slots up to the last one holding a state: an unused file stays empty.
          regCommandHost(0) := ssScanner.io.usedSlots << log2Ceil(MdSaveState.SlotSize)
        }
      } .elsewhen (command === HostV0.CommandFileReadEnd.U) {
        // Nothing to do: the save RAM and the slots stay live.
      } .otherwise {
        commandHostState := CommandState.error
      }
    } .elsewhen (commandHostState === CommandState.busy) {
      when (!ramInit && !ssScanner.io.busy && !ssScanStartPending) {
        commandHostState := CommandState.done
      }
    }
  } .otherwise {
    commandHostState := CommandState.idle
  }
  io.host.commandCore.request := false.B
  // The size the scan is told, kept until the scan starts (the command's words are cleared at once).
  when (ssRescan) {
    ssScanLoadedSize := MdSaveState.FullSize.U
  }
  when (ssScanFromFile) {
    ssScanLoadedSize := regCommandHost(2)(log2Ceil(MdSaveState.FullSize), 0)
  }

  //////////////////////////////////
  // Machine: resets, straps, focus pause
  //////////////////////////////////
  // PAL and EXPORT are not straps in upstream -- the VDP uses PAL live for its
  // line count and the I/O chip uses EXPORT live -- so a change has to reset
  // the machine rather than take effect mid-frame. The pad width does not:
  // `J3BUT` only limits the six-button sequence, so it can change while the
  // game runs, and changing the Pad setting should not restart it.
  val strap = Cat(regionPal, regionExport)
  val lastStrap = RegNext(strap, 0.U)
  when (warmResetWrite || lastStrap =/= strap) {
    warmResetCounter := ~0.U(WarmResetBits.W)
  } .elsewhen (warmResetCounter =/= 0.U) {
    warmResetCounter := warmResetCounter - 1.U
  }
  val machineReset = regCoreReset || coldReset || warmResetCounter =/= 0.U
  /** Upstream's cartridge-download reset: held through setup. */
  val loading = coldReset || ramInit

  val core = Module(new MdCore)
  core.io.clk_sys := clock
  core.io.machine_reset := RegNext(machineReset, true.B)
  core.io.loading := RegNext(loading, true.B)
  core.io.ram_init := RegNext(ramInit, false.B)
  // Never pause while the machine is in reset: `system.sv` clocks its own reset
  // register with a 68000 clock enable, and the pause withholds those. Nor
  // while a save or load runs: the engine needs the 68000 to enter its
  // interrupt handler and the VDP to reach a blank, and the menu that asked
  // for the state is open, so the game runs unfocused for those few frames
  // (as in the PCE port).
  /** A save-state request is in progress: the machine runs without focus until the engine is done. */
  val ssRunPending = RegInit(false.B)
  /** The focus pause, one register late so it is a clean edge for everything that uses it. */
  val paused = RegNext(!regCoreFocus && !machineReset && !ssRunPending, false.B)
  core.io.pause := paused

  core.io.pal := regionPal
  core.io.region_export := regionExport
  core.io.pad_3button := configReg.pad3Button

  core.io.sram_quirk := sramQuirk
  core.io.sram00_quirk := sram00Quirk
  core.io.eeprom_quirk := eepromQuirk
  core.io.noram_quirk := noramQuirk
  core.io.fifo_quirk := fifoQuirk
  core.io.fmbusy_quirk := fmbusyQuirk
  core.io.schan_quirk := schanQuirk

  core.io.lpf_mode := configReg.lpfMode
  core.io.enable_fm := !configReg.fmOff
  core.io.enable_psg := !configReg.psgOff
  core.io.en_hifi_pcm := configReg.hifiPcm
  core.io.ladder := !configReg.ym3438
  core.io.obj_limit_high := configReg.spriteLimitHigh
  core.io.border := configReg.border
  core.io.cram_dots := configReg.cramDots
  core.io.rom_size := Mux(cartLoaded, cartFileSize(24, 1), 0.U)

  //////////////////////////////////
  // Cartridge ROM store
  //////////////////////////////////
  val store = Module(new MdRomStore)
  sidePort.io.main <> store.io.sdram
  store.io.req := core.io.rom_req
  store.io.addr := core.io.rom_addr
  store.io.we := core.io.rom_we
  store.io.be := core.io.rom_be
  store.io.wdata := core.io.rom_wdata
  store.io.invalidate := RegNext(coldReset, true.B)
  core.io.rom_ack := store.io.ack
  core.io.rom_data := store.io.rdata

  //////////////////////////////////
  // Cartridge save RAM: the host's `.sav` window on its B port
  //////////////////////////////////
  val saveWindow = Module(new MdSaveRamWindow)
  saveWindow.io.host.enable := savHost.enable
  saveWindow.io.host.write := savHost.write
  saveWindow.io.host.address := savHost.address
  saveWindow.io.host.dataWrite := savHost.dataWrite
  saveWindow.io.host.writeStrobe := "b1111".U
  savHost.done := saveWindow.io.host.done
  savHost.dataRead := saveWindow.io.host.dataRead
  saveWindow.io.ramInit := ramInit
  core.io.bram_a := saveWindow.io.bramAddr
  core.io.bram_di := saveWindow.io.bramDataWrite
  core.io.bram_we := saveWindow.io.bramWrite
  saveWindow.io.bramDataRead := core.io.bram_do
  when (core.io.bram_change && !machineReset) {
    saveDirty := true.B
  }

  //////////////////////////////////
  // Save states (design section 12; the NES / PCE ports' control logic and
  // register layout, the R58 engine behind `md_gamebub_core`)
  //////////////////////////////////
  // The engine edge-detects its commands, so a request is a level it sees a
  // rising edge of; if the edge falls into the few clocks the engine spends
  // draining a probe of the slot header it is missed (nothing happens), so
  // the level is re-edged until the engine answers with busy or a failure.
  // The machine runs without the focus pause meanwhile (`ssRunPending`);
  // the engine parks the CPUs itself. A load of an empty slot is refused
  // here (the slot scanner knows), which the firmware shows as "No state in
  // slot"; the engine's own checks (cartridge, straps, CRCs) are behind that.
  val ssSaveRequest = RegInit(false.B)
  val ssLoadRequest = RegInit(false.B)
  val ssTaken = RegInit(false.B)
  val ssRetry = RegInit(0.U(SsRetryBits.W))
  val ssSaveDone = RegInit(false.B)
  val ssFailed = RegInit(false.B)
  val ssLastWasSave = RegInit(false.B)
  val ssTimeout = RegInit(0.U(log2Ceil(SsTimeoutCycles + 1).W))
  core.io.ss_save := ssSaveRequest
  core.io.ss_load := ssLoadRequest
  core.io.ss_slot := ssSlot
  // The cartridge: its size and the header's serial and checksum words (0x180-0x18F), which the
  // glue latches from the host stream; the straps, which reset the machine when they change.
  core.io.ss_rom_identity := Cat(0.U(7.W), cartFileSize, word180 ^ word184 ^ word188 ^ word18C)
  core.io.ss_rom_ready := cartLoaded
  core.io.ss_config_identity := Cat(0.U(62.W), regionExport, regionPal)
  ssPort.io.req := core.io.ss_mem_req
  ssPort.io.rnw := core.io.ss_mem_rnw
  ssPort.io.address := core.io.ss_mem_addr
  ssPort.io.dataWrite := core.io.ss_mem_din
  core.io.ss_mem_dout := ssPort.io.dataRead
  core.io.ss_mem_ack := ssPort.io.ack

  val ssAvailable = setupReady && cartLoaded && core.io.ss_supported
  val ssSlotValid = ssScanner.io.valid
  val ssRequestSlot = Mux(ssControlWriteData(4), ssSlotReg, ssControlWriteData(3, 2))
  val ssSaveWrite = ssControlWrite && ssControlWriteData(0) && ssAvailable && !ssRunPending
  val ssLoadWrite = ssControlWrite && ssControlWriteData(1) && ssAvailable && !ssRunPending && ssSlotValid(ssRequestSlot)

  val regEngineBusy = RegNext(core.io.ss_busy, false.B)
  val ssFinished = ssRunPending && ssTaken && !core.io.ss_busy && (regEngineBusy || core.io.ss_fail || core.io.ss_pass)
  val ssTimedOut = ssRunPending && ssTimeout === SsTimeoutCycles.U
  ssTimeout := Mux(ssRunPending, ssTimeout + 1.U, 0.U)
  when (ssRunPending && !ssTaken) {
    when (core.io.ss_busy || core.io.ss_fail) {
      // The engine took it (busy), or refused it at once (blocked / unsupported / no state).
      ssTaken := true.B
      ssSaveRequest := false.B
      ssLoadRequest := false.B
    } .otherwise {
      ssRetry := ssRetry + 1.U
      when (ssRetry.andR) {
        ssSaveRequest := ssLastWasSave && !ssSaveRequest
        ssLoadRequest := !ssLastWasSave && !ssLoadRequest
      }
    }
  }
  when (ssFinished) {
    ssRunPending := false.B
    ssFailed := core.io.ss_fail || !core.io.ss_pass
    when (ssLastWasSave) {
      ssSaveDone := core.io.ss_pass && !core.io.ss_fail
      // The slot just written: the scanner's picture and the States file's size follow.
      ssRescan := true.B
    }
  }
  when (ssTimedOut) {
    ssSaveRequest := false.B
    ssLoadRequest := false.B
    ssRunPending := false.B
    ssFailed := true.B
  }
  when (ssControlWrite && (ssSaveWrite || ssLoadWrite)) {
    ssSaveRequest := ssSaveWrite
    ssLoadRequest := ssLoadWrite
    ssLastWasSave := ssSaveWrite
    ssSaveDone := false.B
    ssFailed := false.B
    ssTaken := false.B
    ssRetry := 0.U
    ssSlot := ssRequestSlot
    ssRunPending := true.B
  }
  when (machineReset) {
    ssSaveRequest := false.B
    ssLoadRequest := false.B
    ssSaveDone := false.B
    ssRunPending := false.B
  }
  val ssBusyStretch = RegInit(0.U(log2Ceil(SsBusyStretchCycles + 1).W))
  when (core.io.ss_busy) {
    ssBusyStretch := SsBusyStretchCycles.U
  } .elsewhen (ssBusyStretch =/= 0.U) {
    ssBusyStretch := ssBusyStretch - 1.U
  }
  val ssBusy = core.io.ss_busy || ssBusyStretch =/= 0.U

  // Diagnostics (registers 0x0020-0x002C): what the engine waits on. `ssDbgHold` follows the
  // live word while a request runs and keeps its last value afterwards, except that when the
  // 68000 capture handler times out (its state goes from a wait, 1 / 2 / 3, straight to done,
  // 7; a capture that goes through leaves the waits for the hold, 8) it keeps the word of the
  // handler's last waiting clock until the next request: which wait, and which terms were
  // false (r2.16; one load in five had timed out with only the end of the request on record).
  // `ssDbgCount` counts, all the time, the clocks in which every bit of the mask in 0x002C is
  // 1 in the live word (a write of the mask restarts it), so any combination of the safe
  // point's terms can be measured while a game runs, without a request. (r2.12 counted the
  // safe point and its 68000 / VDP half during a request only: in the intro of Comix Zone the
  // half never came.)
  ssDbgWire := core.io.ss_dbg
  ssDbg2Wire := core.io.ss_dbg2
  val ssDbgPrev = RegNext(core.io.ss_dbg, 0.U(32.W))
  val ssDbg2Prev = RegNext(core.io.ss_dbg2, 0.U(32.W))
  val ssHandlerState = core.io.ss_dbg(19, 16)
  val ssHandlerPrevState = ssDbgPrev(19, 16)
  val ssHandlerGaveUp = ssHandlerState === 7.U &&
    (ssHandlerPrevState === 1.U || ssHandlerPrevState === 2.U || ssHandlerPrevState === 3.U)
  val ssDbgFailHeld = RegInit(false.B)
  when (ssControlWrite && (ssSaveWrite || ssLoadWrite)) {
    ssDbgFailHeld := false.B
  }
  when (ssRunPending && ssHandlerGaveUp) {
    ssDbgFailHeld := true.B
    ssDbgHold := ssDbgPrev
    ssDbg2Hold := ssDbg2Prev
  } .elsewhen (ssRunPending && !ssDbgFailHeld) {
    ssDbgHold := core.io.ss_dbg
    ssDbg2Hold := core.io.ss_dbg2
  }
  when (ssDbgMaskWrite) {
    ssDbgCount := 0.U
  } .elsewhen ((core.io.ss_dbg(15, 0) & ssDbgMask) === ssDbgMask && !ssDbgCount.andR) {
    ssDbgCount := ssDbgCount + 1.U
  }

  //////////////////////////////////
  // Controls (design section 8). The Mega Drive's A / B / C sit on a row; the
  // Game Bub's face buttons are a diamond, so which row is which is a setting.
  //////////////////////////////////
  val buttons = RegNext(io.input.buttons)
  // Layout 0 ("Y B A", the usual mapping of a Mega Drive pad onto a diamond):
  //   A B C on Y B A, X Y Z on L X R. Comix Zone and Rocket Knight both put jump
  //   on B and attack on A (and C), so they play with jump on B and attack on A
  //   and Y, like a SNES game.
  // Layout 1 ("B A X"): A B C on B A X, X Y Z on Y L R.
  val layout1 = configReg.buttons === 1.U
  val padA = Mux(layout1, buttons.b, buttons.y)
  val padB = Mux(layout1, buttons.a, buttons.b)
  val padC = Mux(layout1, buttons.x, buttons.a)
  val padX = Mux(layout1, buttons.y, buttons.l)
  val padY = Mux(layout1, buttons.l, buttons.x)
  val padZ = buttons.r
  core.io.joy_1 := Cat(
    padZ,           // 11 Z
    padY,           // 10 Y
    padX,           //  9 X
    buttons.select, //  8 Mode
    buttons.start,  //  7 Start
    padC,           //  6 C
    padB,           //  5 B
    padA,           //  4 A
    // `system.sv` reads the d-pad as JOY[3] Up, [2] Down, [1] Left, [0] Right.
    buttons.up,     //  3 Up
    buttons.down,   //  2 Down
    buttons.left,   //  1 Left
    buttons.right,  //  0 Right
  )

  //////////////////////////////////
  // Video
  //////////////////////////////////
  val capture = Module(new MdVideoCapture)
  capture.io.ce := core.io.video_ce
  capture.io.r := core.io.video_r
  capture.io.g := core.io.video_g
  capture.io.b := core.io.video_b
  capture.io.hbl := core.io.video_hbl
  capture.io.vbl := core.io.video_vbl
  capture.io.resolution := core.io.video_resolution
  io.video.data.r := capture.io.outR(7, 3)
  io.video.data.g := capture.io.outG(7, 2)
  io.video.data.b := capture.io.outB(7, 3)
  // Screenshots and the menu read the framework's framebuffer while the core is paused, but
  // upstream's PAUSE_EN leaves the VDP running (a MiSTer has a TV signal to keep alive), so the
  // picture kept being rewritten under the reader. Hold the video outputs at their last values
  // while paused: no pixel writes and no vblank edge, which is what a frozen handheld core
  // looks like, and the framework shows its last complete frame.
  val heldHblank = RegInit(false.B)
  val heldVblank = RegInit(true.B)
  when (!paused) {
    heldHblank := capture.io.hblank
    heldVblank := capture.io.vblank
  }
  io.video.dataEnable := capture.io.dataEnable && !paused
  io.video.hblank := Mux(paused, heldHblank, capture.io.hblank)
  io.video.vblank := Mux(paused, heldVblank, capture.io.vblank)

  //////////////////////////////////
  // Audio: the machine's own DAC output, sampled on a /8 enable (6.71 MHz,
  // well above the YM2612's 53 kHz) and decimated by a 3-stage CIC of 128 to
  // 52,434 Hz, then re-timed onto the framework's 48 kHz. 53,693,175 is not a
  // multiple of 48,000, so the rate adapter is what closes the gap.
  //////////////////////////////////
  locally {
    val divider = RegInit(0.U(3.W))
    divider := divider + 1.U
    val sampleEnable = divider === 0.U
    val decimators = Seq(core.io.audio_l, core.io.audio_r).map { sample =>
      val d = Module(new AudioDecimator(inWidth = 16, ratio = 128, stages = 3))
      d.io.enable := sampleEnable
      d.io.in := sample.asSInt
      (d.io.out, d.io.outValid)
    }
    val l = decimators(0)._1.pad(17)
    val r = decimators(1)._1.pad(17)
    val mixL = Mux(configReg.mono, (l +& r) >> 1, l)
    val mixR = Mux(configReg.mono, (l +& r) >> 1, r)
    val adapter = Module(new AudioRateAdapter(nominalPeriod = 1024.0, fifoDepth = 256, gainShift = 12))
    adapter.io.inValid := decimators(0)._2
    adapter.io.inLeft := mixL(15, 0).asSInt
    adapter.io.inRight := mixR(15, 0).asSInt
    io.audio.left := Mux(regCoreFocus, adapter.io.outLeft, 0.S)
    io.audio.right := Mux(regCoreFocus, adapter.io.outRight, 0.S)
  }

  //////////////////////////////////
  // Status and statistics
  //////////////////////////////////
  statusWire := Cat(
    core.io.ss_error,                // 31:24
    core.io.video_resolution,        // 23:22
    regionExport,                    // 21
    regionPal,                       // 20
    saveDirty,                       // 19
    savLoaded,                       // 18
    cartLoaded,                      // 17
    ramInit,                         // 16
    ssFailed,                        // 15
    ssSlotValid,                     // 14:11
    ssRunPending,                    // 10
    ssSaveRequest || ssLoadRequest,  // 9
    ssSaveDone,                      // 8
    ssBusy,                          // 7
    ssAvailable,                     // 6
    false.B,                         // 5
    setupReady,                      // 4
    coldReset,                       // 3
    regCoreFocus,                    // 2
    regCoreReset,                    // 1
    regCoreSetup,                    // 0
  )

  when (capture.io.frame) { statFrames := statFrames + 1.U }
  when (store.io.statTransaction) {
    statTransactions := statTransactions + 1.U
    when (store.io.latency > statMaxLatency) { statMaxLatency := store.io.latency }
    when (store.io.latency > SlowAnswerCycles.U) { statSlowAnswers := statSlowAnswers + 1.U }
  }
  when (store.io.statHit) { statHits := statHits + 1.U }
  when (store.io.statSdramRead) { statSdramReads := statSdramReads + 1.U }
  when (store.io.statSdramWrite) { statSdramWrites := statSdramWrites + 1.U }
  when (store.io.statPrefetchRead) { statPrefetches := statPrefetches + 1.U }
  when (regCoreFocus && !machineReset) { statRunClocks := statRunClocks + 1.U }

  // `tb_core.sv` finds a stalled machine by counting how often each 68000 address comes back.
  // On hardware there is no room for a histogram, so keep the last address and the range visited
  // over the last 64 frames (about a second): a machine that is stuck shows a last address that
  // does not move and a range a few bytes wide, which is enough to find the loop in the ROM.
  locally {
    val a = core.io.dbg_m68k_a
    statAddrLast := a
    when (a < addrMinAcc) { addrMinAcc := a }
    when (a > addrMaxAcc) { addrMaxAcc := a }
    when (capture.io.frame) {
      addrWindow := addrWindow + 1.U
      when (addrWindow === 63.U) {
        statAddrMin := addrMinAcc
        statAddrMax := addrMaxAcc
        addrMinAcc := ~0.U(24.W)
        addrMaxAcc := 0.U
      }
    }

    // This ROM parks the 68000 at 0x202 (`BRA *`) when an exception it does not handle fires, so
    // the last address outside that stub is where the machine was when it went wrong.
    when (a < 0x200.U || a > 0x207.U) {
      statAddrPrev := a
      when (a =/= addrHistory(0)) {
        addrHistory(0) := a
        for (i <- 1 until AddrHistory) { addrHistory(i) := addrHistory(i - 1) }
      }
    }
  }

  // The 68000 reads its exception vector out of the cartridge, so the vector fetch is visible on
  // the ROM address bus: anything below byte address 0x100 is a vector, and which one names the
  // exception. The first four word reads are the reset vector; after that it is a real exception.
  when (store.io.statTransaction && core.io.rom_addr < 0x80.U) {
    statVecAddr := core.io.rom_addr
    statVecCount := statVecCount + 1.U
  }

  //////////////////////////////////
  // SDRAM controller (as the PCE and the NGPC): 1x, in the system domain, no
  // CDC and no line cache -- nothing that can serve a stale byte.
  // core_md.xdc relies on the instance name `sdram` and its falling-edge
  // capture register `dataIn`.
  //////////////////////////////////
  val sdram = Module(new BurstSdramController(BurstSdramController.Config(
    clockFrequency = ClockSystemHz,
    accessLength = 2,
    timeRsc = (2 * 1_000_000_000) / ClockSystemHz, /* 2 clocks */
    timeWr = (2 * 1_000_000_000) / ClockSystemHz, /* 2 clocks */
    enableBurst = true,
    readCaptureFalling = true,
  )))
  sdramArbiter.io.target <> sdram.io.mem

  io.sdram.clock := clockSdramPin
  io.sdram.cke := sdram.io.signals.cke
  io.sdram.cs := sdram.io.signals.cs
  io.sdram.ras := sdram.io.signals.ras
  io.sdram.cas := sdram.io.signals.cas
  io.sdram.we := sdram.io.signals.we
  io.sdram.dqm := sdram.io.signals.dqm
  io.sdram.bank := sdram.io.signals.bank
  io.sdram.address := sdram.io.signals.address
  sdram.io.signals.dataIn := io.sdram.dataIn
  io.sdram.dataOut := sdram.io.signals.dataOut
  io.sdram.dataDir := sdram.io.signals.dataDir
}
