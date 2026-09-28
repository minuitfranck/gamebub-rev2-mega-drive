package net.gamebub.core.md

import net.gamebub.core.pce.PceTreadle
import org.scalatest.freespec.AnyFreeSpec

import scala.util.Random

/**
 * The cartridge store against a model SDRAM holding a known image.
 *
 * The whole-machine simulation runs the Mega Drive against a behavioural store, so this component
 * -- the cache, the prefetcher and the big-endian halving -- has never been exercised anywhere
 * else. Every read is checked against the image, because a store that returns one wrong word turns
 * the 68000 loose on data it believes is code. Runs on treadle2 through [[PceTreadle]].
 */
class MdRomStoreSpec extends AnyFreeSpec {
  /** The image, as bytes of the file: what the host wrote into the SDRAM. */
  def fileByte(address: Int): Int = (((address * 2654435761L + 17) & 0xFFFFFFFFL) >>> 13).toInt & 0xFF

  /**
   * A 32-bit SDRAM word at a 4-aligned byte address, little-endian, exactly as the host's
   * cartridge window leaves it.
   */
  def sdramWord(byteAddress: Int): BigInt =
    (0 until 4).map(i => BigInt(fileByte(byteAddress + i)) << (8 * i)).sum

  /** What the 68000 must see at a word address: the big-endian 16-bit word of the file. */
  def expected(wordAddress: Int): BigInt =
    (BigInt(fileByte(wordAddress * 2)) << 8) | BigInt(fileByte(wordAddress * 2 + 1))

  /**
   * The SDRAM side, AHB-Lite style: a request is accepted on a cycle where `ready` and `enable`
   * are both high, and its data is presented on the next accepted cycle. `latency` cycles of
   * `ready` held low model a controller that is busy.
   */
  class Sdram(sim: PceTreadle.Sim, latency: Int) {
    private var dataPhase: Option[Int] = None
    private var waiting = 0
    var reads = 0

    /** Drive the SDRAM side for this cycle. Call once before every step. */
    def service(): Unit = {
      val ready = waiting == 0
      sim.poke("io_sdram_ready", ready)
      sim.poke("io_sdram_dataRead", dataPhase.map(sdramWord).getOrElse(BigInt(0)))
      if (!ready) {
        waiting -= 1
        return
      }
      dataPhase = None
      if (sim.peekBool("io_sdram_enable")) {
        val address = sim.peek("io_sdram_address").toInt
        assert((address & 3) == 0, f"SDRAM access at $address%06X is not 4-aligned")
        dataPhase = Some(address)
        reads += 1
        waiting = latency
      }
    }
  }

  /** One transaction on the upstream toggle handshake; returns the word read. */
  def read(sim: PceTreadle.Sim, sdram: Sdram, wordAddress: Int): BigInt = {
    val was = sim.peek("io_ack")
    sim.poke("io_addr", wordAddress)
    sim.poke("io_we", false)
    sim.poke("io_be", 3)
    sim.poke("io_req", if (was == 0) 1 else 0)
    var cycles = 0
    while (sim.peek("io_ack") == was) {
      sdram.service()
      sim.step()
      cycles += 1
      assert(cycles < 500, f"no answer for word address $wordAddress%06X")
    }
    sim.peek("io_rdata")
  }

  /** A fresh store whose lines start empty. */
  def start(name: String, latency: Int): (PceTreadle.Sim, Sdram) = {
    val sim = PceTreadle(new MdRomStore(), name)
    val sdram = new Sdram(sim, latency)
    sim.poke("reset", 1)
    sim.poke("io_req", false)
    sim.poke("io_we", false)
    sim.poke("io_invalidate", false)
    sdram.service()
    sim.step()
    sim.poke("reset", 0)
    (sim, sdram)
  }

  /** Check a list of word addresses, in the order given. */
  def check(sim: PceTreadle.Sim, sdram: Sdram, addresses: Seq[Int]): Unit =
    for (a <- addresses) {
      val got = read(sim, sdram, a)
      assert(got == expected(a), f"word $a%06X: store said $got%04X, image has ${expected(a)}%04X")
    }

  for (latency <- Seq(0, 1, 4, 9)) {
    s"reads the image back, SDRAM latency $latency" - {
      def fixture(name: String) = start(s"MdRomStoreSpec-$latency-$name", latency)

      "one word at a time, far apart (every access a miss)" in {
        val (sim, sdram) = fixture("far")
        check(sim, sdram, Seq(0, 0x1000, 0x2000, 0x40, 0x5555, 0x80000))
      }

      "sequentially, as the 68000 fetches code" in {
        val (sim, sdram) = fixture("seq")
        check(sim, sdram, 0x100 until 0x180)
      }

      "sequentially from an odd word, so the first access is the high half" in {
        val (sim, sdram) = fixture("seqodd")
        check(sim, sdram, 0x101 until 0x141)
      }

      "two sequential streams at once, as DMA interleaves with instruction fetch" in {
        val (sim, sdram) = fixture("two")
        val fetch = (0x200 until 0x240).iterator
        val dma = (0x8000 until 0x8040).iterator
        check(sim, sdram, fetch.zip(dma).flatMap { case (a, b) => Seq(a, b) }.toSeq)
      }

      "five streams at once, more than the store has lines" in {
        val (sim, sdram) = fixture("five")
        val streams = (0 until 5).map(i => (0x1000 * i until 0x1000 * i + 0x10).iterator)
        check(sim, sdram, (0 until 0x10).flatMap(_ => streams.map(_.next())))
      }

      "backwards, which the prefetcher cannot help with" in {
        val (sim, sdram) = fixture("back")
        check(sim, sdram, 0x400 to 0x3C0 by -1)
      }

      "at random" in {
        val (sim, sdram) = fixture("random")
        val random = new Random(1234 + latency)
        check(sim, sdram, Seq.fill(120)(random.nextInt(0x80000)))
      }

      "revisiting a small window, so every access is a hit" in {
        val (sim, sdram) = fixture("hot")
        val random = new Random(99)
        check(sim, sdram, Seq.fill(80)(0x600 + random.nextInt(4)))
      }
    }
  }

  "a request that arrives while a prefetch is in flight still gets its own word" in {
    // One idle cycle between transactions is exactly when the store starts a prefetch, so the
    // next request lands in the middle of one.
    val (sim, sdram) = start("MdRomStoreSpec-midprefetch", 4)
    for (a <- 0x2000 until 0x2040) {
      val got = read(sim, sdram, a)
      assert(got == expected(a), f"word $a%06X: store said $got%04X, image has ${expected(a)}%04X")
      sdram.service()
      sim.step()
    }
  }

  "a sequential run costs about one SDRAM read per four bytes" in {
    val (sim, sdram) = start("MdRomStoreSpec-cost", 0)
    val before = sdram.reads
    check(sim, sdram, 0x3000 until 0x3040)
    // 0x40 words are 0x80 bytes, so 0x20 windows; the prefetcher may fetch one beyond the end.
    assert(sdram.reads - before <= 0x21, s"${sdram.reads - before} SDRAM reads for 0x40 words")
  }
}
