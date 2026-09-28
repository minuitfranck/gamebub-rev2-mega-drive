package platform.handheld.display

import chisel3._
import chisel3.util._

object ILI9488 {
    def getClockDisplayHz(framePeriod: Double): (Int, Int) = {
        // TODO: this is for 60 Hz, calculate dynamically
        (12_000_000, 17_000_000)
    }
}

/** Display Driver for the ILI9488 */
class ILI9488(
  /** Display clock (Hz) */
  clockHz: Int,
  /** Typical source frame period (seconds)  */
  sourceFramePeriod: Double,
) extends Module {
  val hActive = 320
  val vActive = 480

  val io = IO(new DisplayDriverIO(hActive, vActive))

  val currentFrame = RegInit(0.U(1.W))
  /// Whether the display is currently synchronized with the render
  val regLocked = RegInit(true.B)
  // A picture finished since the current refresh began. The source flips lastRenderedFrame at every finished
  // picture, so each change of it is one. (Comparing the index with the one shown missed two pictures within one
  // refresh, which flip it back: the driver then waited for the maximum height, unlocked and cut the next refresh
  // short, like a half-rate source does. A refresh cut short leaves its last rows, the right edge of the rotated
  // rev2 screen, with one polarity of the panel's inversion: a ghost and a flickering band. Checked by
  // ILI9488RefreshSpec in core-gbam, 2026-09-26.)
  val regLastRendered = RegNext(io.lastRenderedFrame, 0.U)
  val pictureFinished = io.lastRenderedFrame =/= regLastRendered
  val regNewPicture = RegInit(false.B)
  when (pictureFinished) {
    regNewPicture := true.B
  }
  val newFrameReady = regNewPicture || pictureFinished
  io.displayFrame := currentFrame
  io.refreshStart := false.B
  io.refreshRepeat := false.B

  val regHsync = RegInit(true.B)
  val regVsync = RegInit(true.B)
  val regActive = RegInit(false.B)
  io.signals.dotclk := clock
  io.signals.hsync := regHsync
  io.signals.vsync := regVsync
  io.signals.enable := regActive

  /*
  ILI9488:
  hsync + hbp < 192
  hfp <= 255
  vsync + vbp + vfp < 32

  "Recommendation: The porch number of VBP + VFP must be even."
  */

  // Calculate timing
  val vSync = 1
  val vBackPorch = 2
  val vFrontPorchMin = 2
  val vFrontPorchMax = 32 - vSync - vBackPorch - 1
  val hSync = 3
  val hBackPorch = 3

  val totalHeightMin = vActive + vSync + vBackPorch + vFrontPorchMin
  val totalHeightMax = vActive + vSync + vBackPorch + vFrontPorchMax

  // With minimum height, target 99% of the sourceFramePeriod
  val minFrameCycles = 0.99 * clockHz * sourceFramePeriod
  val totalWidth = (minFrameCycles / totalHeightMin).round.toInt
  val hFrontPorch = totalWidth - (hActive + hSync + hBackPorch)

  assert(hFrontPorch >= 3)
  assert(hFrontPorch <= 255)
  assert(hBackPorch >= 3)
  assert(hSync + hBackPorch < 192)
  assert(totalWidth * totalHeightMin / sourceFramePeriod < clockHz)
  assert(totalWidth * totalHeightMax / sourceFramePeriod > clockHz)

  val x = RegInit(0.U(log2Ceil(totalWidth).W))
  val y = RegInit(0.U(log2Ceil(totalHeightMax).W))
  io.pixelX := x - (hSync + hBackPorch).U
  io.pixelY := y - (vSync + vBackPorch).U

  when (x === (totalWidth - 1).U) {
    // Scanline is done
    regHsync := true.B
    x := 0.U
    y := y + 1.U

    val startFrame = WireDefault(false.B)
    when (startFrame) {
      regVsync := true.B
      y := 0.U
      currentFrame := io.lastRenderedFrame
      regNewPicture := false.B
      io.refreshStart := true.B
    }

    when (y === (vSync - 1).U) {
      regVsync := false.B
    } .elsewhen ((y >= (totalHeightMin - 1).U) && newFrameReady) {
      // New frame available, start rendering. Also when unlocked: a picture that comes in while the panel repeats
      // the last one waits for that refresh to reach its minimum height (it used to start at once, cutting the
      // refresh short), then the driver is locked again.
      regLocked := true.B
      startFrame := true.B
    } .elsewhen (y === (totalHeightMax - 1).U) {
      // Hit the maximum allowed total height without a new frame coming in:
      // source is too slow, switch to rapid refresh (no longer locked)
      regLocked := false.B
      startFrame := true.B
      io.refreshRepeat := true.B
    }
  } .otherwise {
    x := x + 1.U
    when (x === (hSync - 1).U) {
      regHsync := false.B
    }
    val isVActive = (y >= (vSync + vBackPorch).U) && (y < (vSync + vBackPorch + vActive).U)
    when (x === (hSync + hBackPorch - 1).U && isVActive) {
      regActive := true.B
    }
    when (x === (hSync + hBackPorch + hActive - 1).U) {
      regActive := false.B
    }
  }
}
