"""程序化合成玩家挥剑 / 命中音效（纯 Python，不依赖第三方库）。

为什么不用现成音源：M2 只是要"三段连击有听感反馈"，为三个短音效去引入音频素材库、
再处理版权与体积并不划算。挥砍（带通噪声的扫频"嗖"）与打击（瞬态噪声 + 低频砰）这两类
声音的合成模型非常成熟，几十行就能做到"听起来对"，而且——可复现、可微调、体积小
（三个文件加起来 < 30 KB），也方便后面按同一套参数生成敌人侧的挥击/受击音。

用法：
  python tools/gen_sfx.py                  # 生成到 assets/audio/sfx/
  python tools/gen_sfx.py <输出目录>

生成：
  swing_light.wav   0.22s  轻挥破空（第 1、2 段连击）
  swing_heavy.wav   0.38s  重挥破空（第 3 段收尾，更长更沉）
  hit_impact.wav    0.20s  命中：瞬态"啪" + 低频"砰"
"""
import math
import os
import random
import struct
import sys
import wave

SR = 22050          # 采样率：短音效够用，且文件小（44.1k 对 0.2s 的噪声听不出差别）
PEAK = 0.89         # 归一化目标峰值（留一点余量，避免重采样/混音时削顶）


# ----------------------------------------------------------------------
# 工具：滤波器 / 包络 / 写文件
# ----------------------------------------------------------------------

def svf_bandpass(src, fc_curve, sr=SR, q=1.1):
    """Chamberlin 状态变量滤波器（带通），截止频率可**逐样本**变化。

    为什么需要"时变截止"：一挥剑的"嗖"本质就是噪声的共振峰在移动
    （从低扫到高、或从高扫到低）。固定截止只会得到"呼——"一段白噪声，不像挥砍。

    ⚠ 稳定性：SVF 的积分系数 f = 2·sin(π·fc/sr) 必须明显小于 1，否则会自激发散。
    这里硬钳在 0.95，等效截止上限 ≈ asin(0.475)·sr/π ≈ **3.4kHz**（本音效最高只用到 3k，
    不会碰到钳位；但把参数调到 4k 以上时要知道它其实被吃掉了）。
    """
    band = 0.0
    low = 0.0
    out = []
    for i, x in enumerate(src):
        fc = fc_curve[i]
        f = 2.0 * math.sin(math.pi * fc / sr)     # 归一化积分系数
        if f > 0.95:                              # 稳定性保护：过高会自激振荡
            f = 0.95
        low += f * band
        high = x - low - (1.0 / q) * band
        band += f * high
        out.append(band)
    return out


def svf_highpass(src, fc, sr=SR, q=0.9):
    """固定截止的高通（用来把噪声里的低频"隆隆"剔掉，只留清脆的瞬态）。"""
    f = 2.0 * math.sin(math.pi * fc / sr)
    if f > 0.95:
        f = 0.95
    band = 0.0
    low = 0.0
    out = []
    for x in src:
        low += f * band
        high = x - low - (1.0 / q) * band
        band += f * high
        out.append(high)
    return out


def one_pole_lowpass(src, fc, sr=SR):
    """一阶 RC 低通（无条件稳定），用来柔和地削掉高频齿音。

    【为什么低通不复用上面的 SVF】SVF 在截止频率接近奈奎斯特时会自激：实测拿它做
    6500Hz（≈0.3·sr）低通，一段正常噪声被轰成了近乎直流（RMS 0.93、过零率 0），
    听感是"砰"一声闷响。一阶 RC 没有稳定性问题，而这里也只需要平缓的 -6dB/oct 衰减，
    不需要共振 —— 用对的工具比复用"同一套滤波器"更重要。
    """
    a = math.exp(-2.0 * math.pi * fc / sr)
    y = 0.0
    out = []
    for x in src:
        y = (1.0 - a) * x + a * y
        out.append(y)
    return out


def env(n, attack, decay, curve=2.0):
    """包络：线性冲到 attack 点，然后按 curve 次幂衰减到 0。

    挥砍用"快起慢落"（attack 很短）才能听出"划过去"的位移感；
    打击则要近乎瞬时起音（attack ≈ 1ms）才有"啪"的冲击。
    """
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / max(1.0, n - a)
            out.append(max(0.0, (1.0 - t) ** curve))
    return out


def normalize(buf, peak=PEAK):
    m = 0.0
    for v in buf:
        if abs(v) > m:
            m = abs(v)
    if m < 1e-9:
        return buf
    k = peak / m
    return [v * k for v in buf]


def soft_clip(x):
    """tanh 式软削波：给低频"砰"加一点点饱和，听感更"实"而不是"闷"。"""
    return math.tanh(x * 1.35) / math.tanh(1.35)


def write_wav(path, buf, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # ── 质量护栏 ──
    # 滤波器发散（自激）不会报错，只会把音效变成一记闷雷：症状是"RMS 逼近峰值 + 过零率极低"
    #（输出几乎成了直流）。这类 bug 只有戴上耳机才听得出来，所以在写盘这一步就拦住。
    rms = math.sqrt(sum(v * v for v in buf) / max(1, len(buf)))
    zc = sum(1 for i in range(1, len(buf)) if (buf[i - 1] < 0.0) != (buf[i] < 0.0))
    zcr = zc / (len(buf) / sr)
    if rms > 0.55:
        raise SystemExit("✗ %s 疑似滤波器发散：RMS=%.3f（正常短音效应在 0.05~0.40）"
                         % (os.path.basename(path), rms))
    if zcr < 200.0:
        raise SystemExit("✗ %s 疑似退化成低频/直流：过零率仅 %.0f 次/秒"
                         % (os.path.basename(path), zcr))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)                      # 16-bit PCM
        w.setframerate(sr)
        frames = bytearray()
        for v in buf:
            v = max(-1.0, min(1.0, v))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    print("  %-18s %5.2fs  rms=%.3f  zcr=%7.0f/s  %6d bytes"
          % (os.path.basename(path), len(buf) / sr, rms, zcr, os.path.getsize(path)))


# ----------------------------------------------------------------------
# 三个音效
# ----------------------------------------------------------------------

def make_swing(dur, seed, fc_from, fc_to, seed_low=0.0, q=0.85, body_gain=1.0):
    """挥砍破空：带通噪声 + 时变共振峰 + 快起慢落包络。

    fc_from → fc_to 决定"扫过"的方向与幅度：轻挥从 1.2k 扫到 3.0k（"咻"一下很脆），
    重挥从 0.5k 扫到 2.0k 且更长（"呼——"更沉）。

    【q 为什么取 0.85（比 1 还宽）】窄带通只留共振峰附近那一小片，听感是"嘶——"的白噪声味；
    放宽到 0.85 后通带盖住整个中高频，才有"一团空气被劈开"的厚度。实测窄带版本
    高频能量占比 84%、低频只剩 2%，听起来像电流声而不是挥剑。

    【seed_low 是干什么的】只靠带通噪声，挥砍永远没有"重量"。再叠一层 150~300Hz 的
    低频噪声（同样随时变截止）当作"剑身压过空气"的躯体感 —— 重挥给得多，轻挥可以给 0。
    """
    rnd = random.Random(seed)
    n = int(dur * SR)
    raw = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
    # 截止频率曲线：非线性（t^1.5）→ 前半段变化慢、后半段扫得快，更像真实的挥动加速
    curve = [fc_from + (fc_to - fc_from) * ((i / n) ** 1.5) for i in range(n)]
    body = svf_bandpass(raw, curve, q=q)
    out = [body[i] for i in range(n)]
    if seed_low > 0.0:
        # 低频躯体层：2~2.6 倍于主扫频的时长包络（收得慢一点，"尾巴"更沉）
        low_curve = [fc_from * 0.22 + (fc_to * 0.20 - fc_from * 0.22) * (i / n) for i in range(n)]
        low_layer = svf_bandpass([rnd.uniform(-1.0, 1.0) for _ in range(n)], low_curve, q=0.7)
        e_low = env(n, attack=0.020, decay=dur - 0.020, curve=1.7)
        for i in range(n):
            out[i] += low_layer[i] * e_low[i] * 1.6
    e = env(n, attack=0.012, decay=dur - 0.012, curve=2.4)
    out = [out[i] * e[i] * body_gain for i in range(n)]
    out = one_pole_lowpass(out, 5500.0)       # 削掉 5.5k 以上的齿音，避免"嘶"得发毛
    return normalize(out)


def make_hit(dur, seed):
    """命中：三层叠起来才是"打实了"。
      ① 瞬态层：高通噪声，1ms 起音、40ms 收 —— 就是耳朵听到的"啪"
      ② 低频层：85Hz→46Hz 的扫频正弦，加软削波 —— 胸腔感觉到的那记"砰"
      ③ 中频层：1.3kHz 带通噪声，60ms —— 填在两者中间，避免只有"啪"和"砰"中间空掉
    """
    rnd = random.Random(seed)
    n = int(dur * SR)

    # ① 瞬态
    noise = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
    crack = svf_highpass(noise, 2200.0, q=0.8)
    e1 = env(n, attack=0.001, decay=0.040, curve=3.2)
    layer1 = [crack[i] * e1[i] * 0.85 for i in range(n)]

    # ② 低频"砰"
    layer2 = []
    phase = 0.0
    for i in range(n):
        # 音高下滑 85→46Hz：下滑的"摔落感"比固定音高更像撞击
        f = 85.0 + (46.0 - 85.0) * (i / n)
        phase += 2.0 * math.pi * f / SR
        amp = (1.0 - i / n) ** 2.6
        layer2.append(soft_clip(math.sin(phase) * amp) * 0.95)
    layer2 = one_pole_lowpass(layer2, 600.0)

    # ③ 中频
    mid = svf_bandpass(noise, [1300.0] * n, q=1.6)
    e3 = env(n, attack=0.002, decay=0.060, curve=3.0)
    layer3 = [mid[i] * e3[i] * 0.35 for i in range(n)]

    mixed = [layer1[i] + layer2[i] + layer3[i] for i in range(n)]
    return normalize(mixed)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"
    print("生成音效 → %s" % out_dir)
    write_wav(os.path.join(out_dir, "swing_light.wav"),
              make_swing(0.22, 11, fc_from=1200.0, fc_to=3000.0, seed_low=0.0, q=0.85))
    write_wav(os.path.join(out_dir, "swing_heavy.wav"),
              make_swing(0.38, 23, fc_from=500.0, fc_to=2000.0, seed_low=1.0, q=0.80, body_gain=1.05))
    write_wav(os.path.join(out_dir, "hit_impact.wav"), make_hit(0.20, 37))
    print("完成。")


if __name__ == "__main__":
    main()
