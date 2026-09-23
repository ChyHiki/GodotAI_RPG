# -*- coding: utf-8 -*-
"""把一串同尺寸的帧 PNG **横向拼成一张对比条**（见 montage.py）之外，再提供"动图"版本。

【为什么还要一个 GIF 工具】
  montage.py 拼出来的是**静态横条**，看"姿势对不对"很好用，但它天生表达不了
  **节奏**——而连击/顿帧这类东西的对错恰恰在时间轴上：
    「第 2 段是在第 1 段后摇里被"掐"出来接上的」「命中那一帧之后有 ~0.1s 几乎定格」，
    这些在横条上完全看不出来（横条上相邻两格可能是隔着十几帧的关键姿势）。
  GIF 能把**每一帧**按原始顺序放出来，节奏一眼可见 —— 与横条互补，不是替代。

【用法】
  python make_gif.py <out.gif> <图1> <图2> ... [--fps 20] [--every 2] [--loop 0] [--width 480]
    --fps     播放帧率（默认 20；抓帧脚本是逐渲染帧出图，顿帧会让同一秒内的帧变多，
              所以想要"接近观感"就该偏低一点，别用 60）
    --every   每 N 帧取 1 帧（默认 1 = 全取；图太多想让 GIF 小一点时用）
    --loop    循环次数，0 = 无限循环（默认 0）
    --width   统一缩放到该宽度（默认 480，保持宽高比；0 = 不缩放）

  例：
  python make_gif.py .tmp_combo_combo.gif .tmp_combo/frame*.png --fps 20 --width 480

【依赖】Pillow（本项目用隔离 venv 里的 python，不污染系统环境）：
  C:\\Users\\chy\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe make_gif.py ...
"""
import glob
import os
import sys

from PIL import Image


def main():
    args = sys.argv[1:]
    opts = {"fps": 20.0, "every": 1, "loop": 0, "width": 480}

    # 解析 --key value 形式的可选参数（就地消费，剩下的是位置参数）
    keys = list(opts.keys())
    for k in keys:
        flag = "--" + k
        if flag in args:
            i = args.index(flag)
            try:
                opts[k] = float(args[i + 1])
            except (IndexError, ValueError):
                raise SystemExit("%s 需要一个数值" % flag)
            del args[i:i + 2]

    if len(args) < 2:
        raise SystemExit("用法: make_gif.py <out.gif> <图...> [--fps 20] [--every 2] [--width 480]")

    out, srcs = args[0], args[1:]

    # 允许 shell 没展开通配的情况（Windows 下常见）：自己再 glob 一遍并自然排序
    expanded = []
    for p in srcs:
        hits = sorted(glob.glob(p))
        expanded.extend(hits if hits else ([p] if os.path.exists(p) else []))
    # 去重但保持顺序
    seen = set()
    srcs = [p for p in expanded if not (p in seen or seen.add(p))]
    if not srcs:
        raise SystemExit("输入图都不存在")

    every = max(1, int(opts["every"]))
    srcs = srcs[::every]

    frames = [Image.open(p).convert("RGB") for p in srcs]

    width = int(opts["width"])
    if width > 0 and frames[0].size[0] != width:
        h = max(1, round(frames[0].size[1] * width / frames[0].size[0]))
        frames = [f.resize((width, h), Image.LANCZOS) for f in frames]

    delay = max(10, int(round(1000.0 / max(1.0, opts["fps"]))))   # Pillow 的 delay 单位是毫秒
    frames[0].save(
        out,
        save_all=True,
        append_images=frames[1:],
        duration=delay,
        loop=int(opts["loop"]),
        optimize=True,
    )
    print("gif -> %s  (%d 帧, %dx%d, %.0ffps=%dms/帧, loop=%d)"
          % (out, len(frames), frames[0].size[0], frames[0].size[1],
             opts["fps"], delay, int(opts["loop"])))


main()
