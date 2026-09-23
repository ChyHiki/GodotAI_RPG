# -*- coding: utf-8 -*-
"""在抓帧图里找"某个颜色的东西到底有没有画出来"，并给出它的屏幕尺寸与位置。

【什么时候该用它】
  抓帧图是"画面里有没有那个东西"的**模糊证人**：1280×720 里一个 20px 的小点，肉眼很容易看漏，
  也容易误认成别的几何体（本工程就因为一块浅色面板把锁定标记看大了一圈）。
  数像素则给出确定答案 —— 尤其适合验证：
    · 锁定标记（白色亮点）是否真的渲染出来、屏幕尺寸对不对
    · 某种特效的开关（同一场景"有/无"两帧对比：一个有色、一个 0 像素）

【用法】
  <venv>/Scripts/python.exe find_marker.py <有特效.png> [无特效.png]
  · 第一个参数：期望"有"的帧
  · 第二个参数（可选）：期望"没有"的帧，用于对照
  放大图输出到**第一张图所在目录**下的 marker_zoom.png。

【依赖】Pillow（**不要装进项目运行时依赖**，用隔离 venv 即可）
  建 venv：
    C:/Users/chy/.workbuddy/binaries/python/versions/3.13.12/python.exe -m venv \
        C:/Users/chy/.workbuddy/binaries/python/envs/default
    C:/Users/chy/.workbuddy/binaries/python/envs/default/Scripts/python.exe -m pip install pillow

⚠️ 抓帧 PNG 的实际尺寸**未必**等于 `--resolution` 传的值（本项目实测传 960×540、出图 1280×720），
   所以下面的扫描区域是写死的像素值，换分辨率要重新标定；也**别把坐标按 960×540 硬编码**。

【本工程的实测结论（2026-09-20，锁定标记）】
  锁定帧：近白像素 288 个、包围盒 20×20、质心 (639.5, 282.4)
  解除帧：0 个            → 标记确实只在锁定时存在
"""
import os
import sys

from PIL import Image

# 只扫 3D 视口：排除顶部 HUD 血条/标题与画面最底部，避免把 UI 的白色算进来
Y0, Y1 = 62, 520
# "近白"判据：三通道都很亮，且三通道彼此接近（排除偏色的彩光）
WHITE_MIN = 238
WHITE_SPREAD = 22


def near_white_pixels(img, thresh=WHITE_MIN, spread=WHITE_SPREAD):
    px = img.convert("RGB").load()
    w, h = img.size
    hits = []
    for y in range(Y0, min(Y1, h)):
        for x in range(w):
            r, g, b = px[x, y]
            if r >= thresh and g >= thresh and b >= thresh:
                if max(r, g, b) - min(r, g, b) <= spread:
                    hits.append((x, y))
    return hits


def report(path):
    img = Image.open(path)
    hits = near_white_pixels(img)
    print("%s  %dx%d" % (path, img.size[0], img.size[1]))
    print("  近白像素数 = %d" % len(hits))
    if not hits:
        print("  → 没有近白像素")
        return hits
    xs = [p[0] for p in hits]
    ys = [p[1] for p in hits]
    print("  包围盒 = x[%d..%d] y[%d..%d]  尺寸 %dx%d"
          % (min(xs), max(xs), min(ys), max(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1))
    print("  质心 = (%.1f, %.1f)" % (sum(xs) / len(xs), sum(ys) / len(ys)))
    return hits


def crop_zoom(path, hits, out, pad=70, scale=4):
    """裁一块并最近邻放大，方便肉眼复核（nearest 保持像素块边界，不引入插值假象）。"""
    if not hits:
        return
    w, h = Image.open(path).size
    xs = [p[0] for p in hits]
    ys = [p[1] for p in hits]
    box = (max(0, min(xs) - pad), max(0, min(ys) - pad),
           min(w, max(xs) + pad), min(h, max(ys) + pad))
    img = Image.open(path).convert("RGB").crop(box)
    img = img.resize((img.size[0] * scale, img.size[1] * scale), Image.NEAREST)
    # 输出到"第一张图所在目录"，避免污染调用方的工作目录
    out = os.path.join(os.path.dirname(os.path.abspath(path)), out)
    img.save(out)
    print("  放大图 → %s (裁剪框 %s, %d 倍)" % (out, box, scale))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    locked = sys.argv[1]
    hl = report(locked)
    crop_zoom(locked, hl, "marker_zoom.png")
    if len(sys.argv) > 2:
        released = sys.argv[2]
        print()
        hr = report(released)
        print()
        verdict = ("特效确实只在目标状态存在" if len(hl) > 50 and len(hr) < 10
                   else "需要人工复核（两组差异不明显）")
        print("结论：有/无 两帧的近白像素 %d / %d 个 → %s" % (len(hl), len(hr), verdict))
