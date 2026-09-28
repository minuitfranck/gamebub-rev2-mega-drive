#!/usr/bin/env python3
"""Convert Mega Drive testbench frame dumps to PNG.

Usage: frames_to_png.py <dump dir> <out dir> [prefix]

  frame_NNNN.hex     tb_core.sv: 152 rows of 160 RGB444 values (3 hex digits,
                     r g b nibbles), written as 8-bit PNG by nibble replication
  sysframe_NNNN.hex  tb_system.sv: RGB565 values (4 hex digits), what the Game
                     Bub framebuffer holds, expanded by bit replication as the
                     framework does for the LCD

PNG names are <prefix><original name>.png (pure-Python writer, no dependencies).
"""
import struct
import sys
import zlib
from pathlib import Path


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def rgb888(v: int) -> bytes:
    return bytes(((v >> 16) & 255, (v >> 8) & 255, v & 255))


def rgb565(v: int) -> bytes:
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return bytes(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    prefix = sys.argv[3] if len(sys.argv) > 3 else ""
    dst.mkdir(parents=True, exist_ok=True)
    count = 0
    for pattern, conv in (("frame_*.hex", rgb888), ("sysframe_*.hex", rgb565)):
        for f in sorted(src.glob(pattern)):
            rows = []
            for line in f.read_text().splitlines():
                values = line.split()
                if values:
                    rows.append(b"".join(conv(int(v, 16)) for v in values))
            if not rows:
                continue
            write_png(dst / f"{prefix}{f.stem}.png", len(rows[0]) // 3, len(rows), rows)
            count += 1
    print(f"{count} PNG files in {dst}")


if __name__ == "__main__":
    main()
