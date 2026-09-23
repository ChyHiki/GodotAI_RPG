# -*- coding: utf-8 -*-
"""把一串同尺寸的预览 PNG **横向拼成一张对比条**，用来一眼看完整段动作。

【为什么要它】
  出片脚本一渲就是十几二十张（每个机位 × 每个关键帧），逐张打开看**既慢又看不出"动"**：
  动作的对错往往在"帧与帧之间"（比如"抬腿的相位反了""脚被甩到身后"），
  单看任一张都正常。拼成一条横排，肌肉记忆一样一眼扫过去就能发现问题 ——
  2026-09-20 做闪避时就是靠它一次看完整段前冲/后撤的。

【用法】
  python montage.py <out.png> <图1> <图2> ... [--label f1,f3,f6,f8,f10]
  也支持通配：把所有名字里含指定前缀的图按文件名排序后拼接
  ⚠️ 张数一多单行就会变成又扁又长的带子（9 张 1280 宽的实拍帧 = 11520px），
     要左右拖着看、缩到全屏每格又小得看不清 —— 这时改用 **`grid.py`**（同样在本目录，
     功能就是"网格排布"，是这个脚本的竖排补充版），别指望用本脚本拼网格

  例：
  python montage.py .tmp_sheet.png .tmp_dodge_preview/fwd_side_*.png
  python montage.py docs/preview_combo_poses.png .tmp_combo/frame*.png   # 只放 3~4 张时才合适

【依赖】Pillow（本项目用隔离 venv 里的 python，不污染系统环境）：
  C:\\Users\\chy\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe montage.py ...
"""
import os
import sys

from PIL import Image, ImageDraw

LABEL_H = 22
BG = (34, 34, 38)


def load(paths):
    imgs = [Image.open(p).convert("RGB") for p in paths]
    if not imgs:
        raise SystemExit("没有可拼接的图片")
    return imgs


def main():
    args = sys.argv[1:]
    labels = None
    if "--label" in args:
        i = args.index("--label")
        labels = args[i + 1].split(",")
        del args[i:i + 2]
    if len(args) < 2:
        raise SystemExit("用法: montage.py <out.png> <图...> [--label a,b,c]")
    out, srcs = args[0], args[1:]

    srcs = [p for p in srcs if os.path.exists(p)]
    if not srcs:
        raise SystemExit("输入图都不存在")
    imgs = load(srcs)

    w, h = imgs[0].size
    sheet = Image.new("RGB", (w * len(imgs), h + LABEL_H), BG)
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(imgs):
        if im.size != (w, h):
            im = im.resize((w, h))            # 兜底：尺寸不一致时拉伸对齐，不报错中断
        sheet.paste(im, (i * w, LABEL_H))
        text = labels[i] if labels and i < len(labels) else os.path.basename(srcs[i])
        d.text((i * w + 6, 5), text, fill=(230, 230, 230))
    sheet.save(out)
    print("montage -> %s  (%d 张, %dx%d)" % (out, len(imgs), *sheet.size))


main()
