#!/usr/bin/env python3
"""Write the testbenches' cartridge images.

Usage: make_hex.py <rom file> <work dir>

Two views of the same file, and one place that defines the byte order:

  cart16.hex     16-bit big-endian words in word-address order, which is how
                 the Mega Drive's ROM bus and the behavioural store in
                 tb_core.sv see the cartridge.
  cart_words.hex 32-bit host words as the firmware writes them through the
                 file window (tb_system.sv). A host word at byte address A
                 holds file byte A in bits 7:0, so its four bytes appear
                 MSB-first as A+3, A+2, A+1, A.
  cart.args      the plusargs the benches need for this file.

An odd-sized file is padded with 0xFF, as an unpopulated bus reads.
"""

import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    rom = bytearray(pathlib.Path(sys.argv[1]).read_bytes())
    work = pathlib.Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)

    if len(rom) % 4:
        rom += b"\xFF" * (4 - len(rom) % 4)
    words = [(rom[i] << 8) | rom[i + 1] for i in range(0, len(rom), 2)]

    lines = []
    for i in range(0, len(words), 16):
        lines.append(" ".join(f"{w:04x}" for w in words[i:i + 16]))
    (work / "cart16.hex").write_text("\n".join(lines) + "\n", newline="\n")

    host = [
        f"{rom[i + 3]:02x}{rom[i + 2]:02x}{rom[i + 1]:02x}{rom[i]:02x}"
        for i in range(0, len(rom), 4)
    ]
    (work / "cart_words.hex").write_text("\n".join(host) + "\n", newline="\n")

    (work / "cart.args").write_text(
        f"+rom_bytes{len(rom)} +rom_words{len(words)}\n", newline="\n")
    print(f"cart16.hex: {len(words)} words, cart_words.hex: {len(host)} host "
          f"words ({len(rom)} bytes)")


if __name__ == "__main__":
    main()
