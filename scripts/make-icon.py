#!/usr/bin/env python3
"""Draw Centik's app icon. The system applies the macOS squircle mask."""

import struct
import zlib
from pathlib import Path


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def blend(dst, src, alpha: float):
    return tuple(int(d * (1 - alpha) + s * alpha) for d, s in zip(dst, src))


def round_rect(px, py, x, y, w, h, r, bottom_only=False) -> bool:
    if px < x or py < y or px > x + w or py > y + h:
        return False
    corners = []
    if not bottom_only:
        corners.append((x + r, y + r, px < x + r and py < y + r))
        corners.append((x + w - r, y + r, px > x + w - r and py < y + r))
    corners.append((x + r, y + h - r, px < x + r and py > y + h - r))
    corners.append((x + w - r, y + h - r, px > x + w - r and py > y + h - r))
    for cx, cy, active in corners:
        if active:
            return (px - cx) ** 2 + (py - cy) ** 2 <= r * r
    return True


def coverage(test, x, y) -> float:
    hits = 0
    for oy in (0.25, 0.75):
        for ox in (0.25, 0.75):
            if test(x + ox, y + oy):
                hits += 1
    return hits / 4


def main() -> None:
    size = 1024
    rows = []
    notch = (292, 318, 440, 168)
    cards = [
        (292, 548, 128, 150, 28),
        (448, 526, 128, 172, 30),
        (604, 548, 128, 150, 28),
    ]
    for y in range(size):
        row = bytearray([0])
        t = y / (size - 1)
        base = (
            int(28 * (1 - t) + 10 * t),
            int(28 * (1 - t) + 10 * t),
            int(32 * (1 - t) + 14 * t),
        )
        for x in range(size):
            color = base
            color = blend(color, (244, 244, 246), coverage(lambda px, py: round_rect(px, py, *notch, 78, True), x, y))
            for card in cards:
                cx, cy, cw, ch, radius = card
                color = blend(color, (255, 255, 255), coverage(lambda px, py, cx=cx, cy=cy, cw=cw, ch=ch, radius=radius: round_rect(px, py, cx, cy, cw, ch, radius), x, y) * 0.94)
            row.extend(color)
        rows.append(bytes(row))
    raw = b"".join(rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    destination = Path(__file__).resolve().parents[1] / "Centik" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    destination.write_bytes(png)
    print(f"Wrote {destination} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
