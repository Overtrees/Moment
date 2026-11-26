#!/usr/bin/env python3
"""合成开屏静态帧：background 打底 + logo + tagline 按 bounds.json 合成。

开屏设计是两段式：系统静态帧（UILaunchScreen 的 LaunchBackground
imageset）先显示约 500ms，再由 app 内 NativeSplashView 接管动效。
静态帧必须与矢量开屏的首帧逐像素同构，否则接管瞬间会跳变——所以
这里按 bounds.json 记录的 viewBox(1179x2556) 与各层 (x, y, w, h)
把分层 PNG 原位合成，不缩放、不重排。

输入：splash-layers/ 下的 bounds.json 与
      MynoteSplash-{light,dark}-{background,logo,tagline}.png
输出：LaunchBackground-light.png / LaunchBackground-dark.png
      （1179x2556，写入本脚本同目录）

用法：python3 composite_launch.py
依赖：Pillow。
"""
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
LAYERS_DIR = HERE / "splash-layers"


def composite(appearance: str, spec: dict) -> Path:
    vb_w, vb_h = spec["viewBox"]
    layers = spec["layers"][appearance]

    def load(name: str) -> Image.Image:
        path = LAYERS_DIR / f"MynoteSplash-{appearance}-{name}.png"
        img = Image.open(path).convert("RGBA")
        want = (layers[name]["width"], layers[name]["height"])
        if img.size != want:
            raise SystemExit(f"{path.name}: 尺寸 {img.size} != bounds {want}")
        return img

    canvas = load("background")
    if canvas.size != (vb_w, vb_h):
        raise SystemExit(f"background 尺寸 {canvas.size} != viewBox {(vb_w, vb_h)}")
    for name in ("logo", "tagline"):
        layer = load(name)
        x, y = layers[name]["x"], layers[name]["y"]
        canvas.alpha_composite(layer, dest=(x, y))

    out = HERE / f"LaunchBackground-{appearance}.png"
    canvas.save(out)
    return out


def main() -> int:
    spec = json.loads((LAYERS_DIR / "bounds.json").read_text())
    for appearance in ("light", "dark"):
        out = composite(appearance, spec)
        with Image.open(out) as check:
            print(f"{out.name}: {check.size[0]}x{check.size[1]} {check.mode}")
            assert check.size == tuple(spec["viewBox"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
