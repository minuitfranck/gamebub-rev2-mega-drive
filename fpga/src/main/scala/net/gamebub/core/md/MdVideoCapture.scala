package net.gamebub.core.md

import chisel3._
import chisel3.util._

/**
 * Turns the VDP's output port into the framework's framebuffer stream
 * (docs/md-port-design.md section 6).
 *
 * With `BORDER_EN` low the VDP's blanks are exactly the active area: `hbl` is
 * low over `H_DISP_WIDTH` pixels (320 in H40, 256 in H32) and `vbl` is low over
 * `V_DISP_HEIGHT` lines (224 in V28, 240 in V30). `ce` is a one-clock enable at
 * the pixel rate and pulses across the whole line, blanking included -- which
 * is what makes the borders below possible.
 *
 * The framework's framebuffer is a compile-time [[MdVideoCapture.Width]] x
 * [[MdVideoCapture.Height]], and its own X and Y counters advance on
 * `dataEnable` and on the rising edge of `hblank`. So this module presents a
 * synthetic raster of exactly `Width` pixels on each of `Height` lines:
 *
 *  - **H32 is centred.** The window opens at the VDP's first active pixel and
 *    runs `Width` slots; the picture is emitted from a `Border`-deep delay of
 *    the VDP's colour, so VDP pixel 0 lands at column `Border`, and columns
 *    outside `[Border, Border + 256)` are black. A line has 342 pixel slots in
 *    H32 and 420 in H40, both more than the 320 the window needs, so the window
 *    always closes before the next line's active area.
 *  - **V30 is centred.** The middle 224 of the 240 lines are kept. NTSC V30 has
 *    no vertical blanking on real hardware and no game ships in it; a PAL V30
 *    game loses 8 lines top and bottom.
 *  - **The frame is framed on whole lines.** Whether a line is captured is
 *    decided from `vbl` at the moment its active area starts, never in the
 *    middle: the VDP's V counter advances at `H_INT_POS`, which is inside the
 *    active window, so `vbl` changes 15 pixels before the end of a line. Taking
 *    it at the start of the line keeps line 223 whole and keeps the 15-pixel
 *    sliver at the end of the line before line 0 out of the picture.
 *
 * Colour is `Genesis.sv`'s `color_lut`: the VDP's 4-bit channel is one of 16
 * real Mega Drive DAC levels, not a linear 0-15.
 */
class MdVideoCapture extends Module {
  import MdVideoCapture._

  val io = IO(new Bundle {
    /** The VDP's port. */
    val ce = Input(Bool())
    val r = Input(UInt(4.W))
    val g = Input(UInt(4.W))
    val b = Input(UInt(4.W))
    val hbl = Input(Bool())
    val vbl = Input(Bool())
    /** {V30, H40}. */
    val resolution = Input(UInt(2.W))

    /** The framework's stream. */
    val dataEnable = Output(Bool())
    val hblank = Output(Bool())
    val vblank = Output(Bool())
    val outR = Output(UInt(8.W))
    val outG = Output(UInt(8.W))
    val outB = Output(UInt(8.W))

    /** One pulse per captured frame, at the end. */
    val frame = Output(Bool())
  })

  val h40 = io.resolution(0)
  val v30 = io.resolution(1)

  // ---- raster edges, sampled at the pixel rate -------------------------
  val hblPrev = RegInit(true.B)
  when (io.ce) { hblPrev := io.hbl }
  val lineStart = io.ce && hblPrev && !io.hbl

  // ---- which lines are captured ---------------------------------------
  /** A frame is in progress: some line has been captured and none has ended it. */
  val capturing = RegInit(false.B)
  /** Active lines seen so far in this frame. */
  val rawLine = RegInit(0.U(9.W))
  /** The window is open and `col` is counting. */
  val inWindow = RegInit(false.B)
  val col = RegInit(0.U(log2Ceil(Width).W))
  /** Latched for the line: where the picture sits inside the window. */
  val lineBorder = RegInit(0.U(log2Ceil(Width).W))
  val lineWidth = RegInit(Width.U(log2Ceil(Width + 1).W))

  val vOffset = Mux(v30, ((V30Height - Height) / 2).U, 0.U)
  io.frame := false.B

  /** This line's first active pixel is in this very cycle, so the window has to
    * open combinationally: `inWindow` and `col` only take effect next cycle. */
  val lineNumber = Mux(capturing, rawLine + 1.U, 0.U)
  val openNow = lineStart && !io.vbl && lineNumber < MaxLines.U &&
    lineNumber >= vOffset && lineNumber < (vOffset +& Height.U)
  val windowActive = inWindow || openNow
  val curCol = Mux(openNow, 0.U, col)
  // NTSC with V30 never blanks vertically on real hardware, and nothing ships
  // in it; the line limit keeps the display swapping buffers anyway.
  val frameEnd = lineStart && capturing && (io.vbl || lineNumber >= MaxLines.U)
  val capturingNow = (capturing || (lineStart && !io.vbl)) && !frameEnd

  when (frameEnd) {
    capturing := false.B
    rawLine := 0.U
    io.frame := true.B
  } .elsewhen (lineStart && !io.vbl) {
    capturing := true.B
    rawLine := lineNumber
    when (openNow) {
      inWindow := true.B
      col := 1.U
      lineBorder := Mux(h40, 0.U, Border.U)
      lineWidth := Mux(h40, Width.U, H32Width.U)
    }
  } .elsewhen (io.ce && inWindow) {
    when (col === (Width - 1).U) {
      inWindow := false.B
    }
    col := col + 1.U
  }

  // ---- the picture, delayed so H32 lands in the middle ------------------
  // A 32-deep enabled shift register per channel; Vivado maps each bit to one
  // SRL32, so the whole delay is a dozen LUTs.
  val delayedR = ShiftRegister(io.r, Border, io.ce)
  val delayedG = ShiftRegister(io.g, Border, io.ce)
  val delayedB = ShiftRegister(io.b, Border, io.ce)
  val pixR = Mux(h40, io.r, delayedR)
  val pixG = Mux(h40, io.g, delayedG)
  val pixB = Mux(h40, io.b, delayedB)
  // The latched pair only takes effect on the cycle after the window opens, and
  // column 0 is emitted on the opening cycle itself, so take the live values
  // there (otherwise a line right after a mode change gets one wrong pixel).
  val curBorder = Mux(openNow, Mux(h40, 0.U, Border.U), lineBorder)
  val curWidth = Mux(openNow, Mux(h40, Width.U, H32Width.U), lineWidth)
  val inPicture = curCol >= curBorder && curCol < (curBorder +& curWidth)

  val lut = VecInit(ColorLut.map(_.U(8.W)))
  io.outR := RegNext(Mux(inPicture, lut(pixR), 0.U), 0.U)
  io.outG := RegNext(Mux(inPicture, lut(pixG), 0.U), 0.U)
  io.outB := RegNext(Mux(inPicture, lut(pixB), 0.U), 0.U)
  io.dataEnable := RegNext(io.ce && windowActive, false.B)
  io.hblank := RegNext(!windowActive, true.B)
  io.vblank := RegNext(!capturingNow, true.B)
}

object MdVideoCapture {
  /** The framebuffer, sized for H40 / V28 (Comix Zone's mode). */
  val Width = 320
  val Height = 224
  /** H32 and PAL V30. */
  val H32Width = 256
  val V30Height = 240
  /** Safety bound on the lines in a frame (PAL is 313 total, 240 active). */
  val MaxLines = 288
  /** Black columns on each side of an H32 picture. */
  val Border = (Width - H32Width) / 2

  /**
   * `Genesis.sv`'s `color_lut`: the 16 levels a Mega Drive's video DAC puts out
   * for a 4-bit channel (3 bits of CRAM plus the shadow / highlight dimension).
   */
  val ColorLut = Seq(
    0, 27, 49, 71,
    87, 103, 119, 130,
    146, 157, 174, 190,
    206, 228, 255, 255,
  )
}
