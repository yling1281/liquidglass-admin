#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 App 图标（纯标准库，无第三方依赖）。

用 zlib + struct 手写 PNG，输出 1024×1024。
在 CI 里于 `xcodegen generate` **之前**执行，产物 `Assets.xcassets/` 不入库。

构图约束（iOS 会把图标裁成圆角方形）：
沿对角线方向的可视半径约 0.42 × 边长 ≈ 430px。
所有装饰元素（外环、边框）都必须落在这个半径以内，否则四角会被切掉。

用法：
    python scripts/make_icon.py
"""

import os
import struct
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT_DIR = os.path.join(ROOT, "LiquidGlassAdmin", "Resources", "Assets.xcassets")
SIZE = 1024

# 配色：深蓝紫渐变底 + 青色高光 + 白色锁形
BG_TOP = (58, 82, 168)
BG_BOTTOM = (22, 30, 74)
GLOW = (86, 214, 255)
LOCK = (255, 255, 255)
LOCK_SHADE = (198, 216, 255)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def mix(c1, c2, t):
    return (
        lerp(c1[0], c2[0], t),
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
    )


def render():
    """逐像素渲染 RGB 缓冲。"""
    pixels = bytearray()
    cx = cy = SIZE / 2.0

    # 锁形参数
    body_w = 300
    body_h = 240
    body_top = cy + 40
    shackle_w = 170
    shackle_h = 190
    shackle_center_y = body_top - shackle_h * 0.45
    shackle_thickness = 42
    keyhole_r = 34

    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            t = y / float(SIZE - 1)
            color = mix(BG_TOP, BG_BOTTOM, t)

            # 左上角径向高光
            dx = x - SIZE * 0.30
            dy = y - SIZE * 0.22
            glow_d = (dx * dx + dy * dy) ** 0.5
            if glow_d < SIZE * 0.62:
                g = (1.0 - glow_d / (SIZE * 0.62)) ** 2 * 0.42
                color = mix(color, GLOW, g)

            # 主体：锁体
            in_body = (
                abs(x - cx) <= body_w / 2
                and body_top <= y <= body_top + body_h
            )

            # 锁梁：圆环上半部分
            in_shackle = False
            ring_outer = shackle_w / 2
            ring_inner = ring_outer - shackle_thickness
            if y <= body_top + 10 and y >= shackle_center_y - ring_outer:
                ox = x - cx
                oy = y - shackle_center_y
                d = (ox * ox + oy * oy) ** 0.5
                if ring_inner <= d <= ring_outer and oy <= 12:
                    in_shackle = True

            if in_shackle:
                color = LOCK
            elif in_body:
                # 锁体带一点上浅下深的立体感
                body_t = (y - body_top) / float(body_h)
                color = mix(LOCK, LOCK_SHADE, body_t * 0.55)

                # 锁孔（深色圆 + 下方竖槽）
                kx = x - cx
                ky = y - (body_top + 78)
                if (kx * kx + ky * ky) <= keyhole_r * keyhole_r:
                    color = BG_BOTTOM
                elif abs(kx) <= 14 and 0 <= ky <= 78:
                    color = BG_BOTTOM

            row += bytes((color[0], color[1], color[2]))
        pixels += b"\x00" + row
    return bytes(pixels)


def write_png(path, width, height, raw):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", header)
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    appicon_dir = os.path.join(OUT_DIR, "AppIcon.appiconset")
    accent_dir = os.path.join(OUT_DIR, "AccentColor.colorset")
    os.makedirs(appicon_dir, exist_ok=True)
    os.makedirs(accent_dir, exist_ok=True)

    print("渲染 %dx%d 图标…" % (SIZE, SIZE))
    raw = render()
    write_png(os.path.join(appicon_dir, "AppIcon1024.png"), SIZE, SIZE, raw)

    with open(os.path.join(appicon_dir, "Contents.json"), "w", encoding="utf-8") as f:
        f.write("""{
  "images" : [
    {
      "filename" : "AppIcon1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""")

    with open(os.path.join(accent_dir, "Contents.json"), "w", encoding="utf-8") as f:
        f.write("""{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.918", "green" : "0.420", "red" : "0.220" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.918", "green" : "0.478", "red" : "0.294" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""")

    with open(os.path.join(OUT_DIR, "Contents.json"), "w", encoding="utf-8") as f:
        f.write("""{
  "info" : { "author" : "xcode", "version" : 1 }
}
""")

    size = os.path.getsize(os.path.join(appicon_dir, "AppIcon1024.png"))
    print("✅ 已生成 Assets.xcassets（图标 %d 字节）" % size)


if __name__ == "__main__":
    main()
