# -*- coding: utf-8 -*-
"""把一批同尺寸预览 PNG 拼成 **网格对比图**（montage.py 的竖排补充版）。

【为什么还要一个它】montage.py 是"横向一条"，帧数一多就拼成 6000px 的细长条，
读图时会被压到看不清。轴探针/多机位对比这种"十几张平铺"的场景，网格版更合适。

【用法】
  python grid.py <out.png> <每行张数> <图1> <图2> ... [--label a,b,c]
"""
import os
import sys

from PIL import Image, ImageDraw

LABEL_H = 20
BG = (34, 34, 38)


def main():
    args = sys.argv[1:]
    labels = None
    if "--label" in args:
        i = args.index("--label")
        labels = args[i + 1].split(",")
        del args[i:i + 2]
    if len(args) < 3:
        raise SystemExit("用法: grid.py <out.png> <每行张数> <图...> [--label a,b,c]")
    out = args[0]
    cols = max(1, int(args[1]))
    srcs = [p for p in args[2:] if os.path.exists(p)]
    if not srcs:
        raise SystemExit("输入图都不存在")

    imgs = [Image.open(p).convert("RGB") for p in srcs]
    w, h = imgs[0].size
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, (h + LABEL_H) * rows), BG)
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(imgs):
        r, c = divmod(i, cols)
        if im.size != (w, h):
            im = im.resize((w, h))
        sheet.paste(im, (c * w, r * (h + LABEL_H) + LABEL_H))
        text = labels[i] if labels and i < len(labels) else os.path.basename(srcs[i])
        d.text((c * w + 6, r * (h + LABEL_H) + 4), text, fill=(235, 235, 235))
    sheet.save(out)
    print("grid -> %s  (%d 张, %d 列, %dx%d)" % (out, len(imgs), cols, *sheet.size))


main()
