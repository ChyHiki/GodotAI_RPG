# 在 Blender 里怎么做游戏角色动画

> 这份指南不是"Blender 动画入门教程"，而是**本项目的实战手册**：
> 所有结论都来自 `E:\blender\blenderproject\` 里已经跑通的 19 段动画，
> 每一条坑都真的踩过、都有对应的脚本或断言在守着。
> 读完它，你应该能独立给这个骑士加第 20 段动画。

---

## 0. 先建立正确的心智模型

大部分人学 Blender 动画的路径是：看教程 → 学"怎么打关键帧" → 然后卡住，因为
**教程教的是"怎么用软件"，而做游戏动画真正难的是另外三件事**：

| 你以为的难点 | 真正的难点 |
| --- | --- |
| 怎么插关键帧 | 骨架的**轴朝向**是什么（角度填多少才对） |
| 怎么让动作流畅 | **姿势怎么定**（"手要够到剑柄"这种约束怎么解） |
| 怎么导出 | **引擎和 Blender 的契约**（时长、循环、骨骼集合、位移归谁管） |

本项目在这三件事上都建立了方法。下面按"一次完整的工作流"来组织：

```
①  摸清骨架（一次性，但决定后面一切）
        ↓
②  定姿势：写"意图"而不是写角度
        ↓
③  排时序：关键帧 / 解析式 / 相位表
        ↓
④  贴地：root.z 反解
        ↓
⑤  循环与首尾帧：无缝拼接
        ↓
⑥  建 Action + NLA 轨
        ↓
⑦  导出 GLB（顺序有讲究）
        ↓
⑧  Godot 侧接线 + 断言验收
        ↓
⑨  出片：抓帧/GIF 看节奏
```

---

## 1. 第一步永远是"摸骨架"，不是"打关键帧"

这是整份指南最重要的一条。

**Blender 里 pose bone 的旋转，全部是"绕它自己 rest 姿势下的局部轴"**。
所以 `thigh.L.rotation_euler.x = 30°` 到底表示"抬腿"还是"劈叉"，
取决于这根骨骼静止时局部轴指向哪 —— **而这完全没有统一答案**，
取决于当初绑骨骼的人怎么建的。

本工程的骨架里就有四种不同的局部轴约定：

| 骨骼 | 静置旋转 | 局部轴含义 |
| --- | --- | --- |
| `hips` / `chest` / `spine` | `(90°, 0, 0)` | `ry` = 骨盆/胸腔**扭转**，`rz` = 重心**侧倾**，`rx` = 俯仰 |
| `thigh.L/R` | `(-90°, 0, 0)` | 局部 X == 世界 X（**前后摆**），局部 Z == 世界 Y（**外展/开合**） |
| `upperarm.L/R` / `forearm` / `hand` | 单位阵 | `X'` = 世界右、`Y'` = 世界下、`Z'` = 世界前 |
| `root` | 单位阵 + head 在原点 | **局部轴 == 世界轴** → `rz` 就是偏航、`rx` 就是前滚翻 |

### 怎么摸？—— 写一个探针脚本，别靠猜

本项目有现成的两个：

| 脚本 | 作用 |
| --- | --- |
| `scripts/probe_axes.py` | 逐根骨骼转一个小角度，打印它把子节点带到哪去（**定性**：哪个轴管哪个方向） |
| `scripts/probe_axes_num.py` | **定量**：打印每根骨骼静止时的局部基向量（在世界系里的分量） |

`probe_axes_num.py` 的输出就是 `combo_pose_lib.py` 顶部那段"解析模型"的依据：

```
本骨架肩/肘/腕三根骨骼的 rest 局部轴**完全一致**：
    X' = 世界 +X（角色右侧）   Y' = 世界 −Z（下）   Z' = 世界 +Y（前）
（实测逐条核对过，单轴误差 < 0.01）
```

> ★ **一次 20 分钟的探针，省掉几十小时的瞎填角度。**
> 只要换骨架、换角色（本工程的 `brute_01` 是另一套 21 骨骼），就必须重跑一次。

### ★★ 骨架特有的硬约束：剑刃恒与小臂垂直

这是本骨架**最重要的一个事实**，不知道它在里面填角度会填到崩溃：

静置时小臂朝**下**、剑尖朝**前**，正好差 90° → **这两者的夹角在任何姿势下都不变**。
"剑刃方向和手臂方向"不是两个独立自由度。

后果：`hand.R.rx = 0` 时，你把大臂抬到某个角度，剑尖就跟着翻上去 ——
**不掰腕子，剑尖永远指不到下方**。

这正是既有 `Slash` 在收招帧给了 `hand.R.rx = −52°` 的原因：
把剑尖从"前上方 28°"压到"前下方 23°"，那一刀才读得出来是劈砍。

---

## 2. 定姿势：写"意图"，让脚本反解角度

**不要手填角度。** 本项目第一版就是手填的，结果是：

> 第一版填出来的横扫，两帧剑尖都指上天了。

因为人脑没法同时跟踪
"大臂 rx/ry/rz + 肘 + 腕 = 5 个角度 → 剑尖最终指向哪个方向"
这条 5 维映射。改一个角度想修剑尖，手臂姿势又歪了。

### 解法：拆成纯 Python 的解析库

`scripts/combo_pose_lib.py` —— **不导入 bpy**，所以能在项目 Python 里
**0.2 秒**跑一次（对比：跑一次 Blender 30 秒起 + 渲图几分钟）。

它做的事：

```
你写：  arm  = (0.62, -0.32, -0.72)   # 大臂要指向：右、后、下
        blade = (0.78, -0.50, 0.36)    # 剑尖要指向：右后上（像扛在肩上）
        elbow = 18                      # 屈肘角度，作者指定
             ↓  solve()
它给：  ua_rx, ua_ry, ua_rz, fa_rx, hand_rx   + 解算误差（度）
```

**试错从"跑一次 Blender 几分钟"变成"改一行方向 → 0.2 秒看结果"。**

### solve() 为什么是两步搜索

5 个自由度的网格搜索，6° 步进要 2000 万次评估，慢到没法迭代。拆开：

| 步骤 | 搜索什么 | 为什么能拆 |
| --- | --- | --- |
| 第一步 | `(ua_rx, ua_ry, ua_rz)` → 够**大臂朝向** | 大臂朝向**只由这三个决定**；保留误差最小的 300 组候选（它们构成一条"大臂不动、肩部自转"的流形） |
| 第二步 | 每组候选里搜 `(fa_rx, hand_rx)` → 够**剑尖朝向** | 这两个**不动大臂**，一个屈肘一个掰腕，合起来正好补掉"剑刃恒垂直小臂"这条硬约束 |

然后跑两轮局部细化（1.0° → 0.25°）。

### 三条设计约束（都是踩坑换来的）

1. **肘必须限成 `[0, 80]`（只许往前弯）**
   若让肘自由取负，解算器会发现"把偏移塞进肘"更便宜（绕同一根轴、罚项一样），
   于是解出 **−14° 的反关节** —— 大臂朝向是对的，胳膊看着却是折的。
2. **剑尖权重最高**（`w_blade=2.0` vs `w_arm=1.0`）
   玩家眼睛跟着**剑刃**走。大臂稍偏剪影仍成立，剑尖偏 20° 就变成砍空。
3. **腕子限幅 ±62°**
   超过这个角度，刚性蒙皮会明显像"断手"；而且既有 Slash 最深也只到 −52°。

### 姿势表长什么样

`combo_pose_lib.py` 里的 `SLASH3_ROWS`，每一行就是**一帧的意图**：

```python
# ⑥ 下砸触地（峰值）：俯身压上、大臂前下方送出、**掰腕**把剑尖压到前下方、深屈膝承重
row(12, yaw=360.0,
    hips=(-17, -4, 0), chest=(-23, -6, 0), head=(8, 0, 0),
    a=(0.20, 0.80, -0.57), b=(0.06, 0.92, -0.39),
    uaL=(30, 0, 26), faL=(28, 0, 0),
    legL=(32, -38, 0), legR=(26, -34, 0)),
```

读起来就是导演批注：**俯身、大臂往前下送、剑尖压到前下、腿深蹲承重**。
改动作只需要改语义，不用碰角度 `→` 这就是这套设计最大的价值。

**快速迭代方式**：直接 `python combo_pose_lib.py`，它会打印每帧的角度、
解算误差、以及最终的大臂/小臂/剑尖朝向。

---

## 3. 排时序：三种手法，选最简单的那种

| 手法 | 用在哪 | 例子 |
| --- | --- | --- |
| **手写关键帧** | 姿势变化剧烈、不需要人脑推公式 | Hurt（4 帧）/ Death（6 帧）/ Dodge |
| **解析式正弦** | 周期性、要"数学上保证无缝" | Idle：`s = sin(2πp)`，49 帧取相位 0/.25/.5/.75/1.0 |
| **相位表 / 步态函数** | 步态、开合这类"每周期重复一次"的运动 | 侧移三段 |

### ★ 相位表的关键：两条曲线别共用同一条正弦

侧移的步态函数：

```python
strafe_gait(u) = (
    (1 - cos(2πu)) / 2,      # 开合量：一周期只开合一次 → 必须用 1-cos
    max(0, sin(2πu)),        # 前腿腾空：横向速度为正的那半个周期
    max(0, -sin(2πu)),       # 后腿腾空
)
```

**开合用 `1-cos`、抬腿用 `max(0, ±sin)`** —— 两者共用同一条 `sin` 会差 1/4 周期，
结果变成"一腿在前一腿在后"（第一版就做成了弓步）。

### ★ 姿势混合不要"抄角度"，要"插值"

脚本里统一用 `mix(a, b, t)` 在两个**姿势字典**之间线性插值，
而不是逐骨骼手写中间帧 —— 这样加一帧不用重算所有骨骼。

---

## 4. 贴地：root.z 用二分反解，不手填

**每帧算一次**：搜索一个 root 高度，使**整个模型的最低顶点**落在 `y = 0.005`。

```python
def solve_root_z(arm, lo=-0.90, hi=0.90, iters=48):
    # 二分：改 root.location.z → 重新求值 depsgraph → 量最低顶点 → 收敛
    ...
```

为什么必须反解：

- 膝盖一弯，身体自然要下沉 → 手填 z 会和腿的姿势打架
- Idle 里膝盖轻微张合 → 反解出的高度跟着变 → **身体自然有极小的上下起伏**（免费的手感）

### ★★ 必须加收敛自检

```
（就是"手插地"那个坑逼出来的保险）
搜完残差 > 2mm 就打印 ⚠ root.z 未收敛
```

`life_anim.py` 的 Death 第一版手臂前伸（`ua_rx=30`），root 绕 X 翻转 90° 后
手臂直接插进地面，`solve_root_z` 撞到搜索上界**静默饱和**，
最低顶点掉到 **−0.30 m**（尸体沉进地面 30cm）。

**"静默饱和"是最危险的一类 bug** —— 脚本没报错、数字看着正常、图是错的。
任何"搜索/迭代求解"都要回头验一次残差。

### ★ 脚踝角度按"目标世界角"反算

脚掌世界角 = `大臂...` 不对，是 `大腿 + 小腿 + 脚踝` 的累加：

```python
foot.rx = -(hips.rx + thigh.rx + shin.rx) + foot_extra
```

不给这个补偿，骨盆一前倾脚尖就戳进地里，`solve_root_z` 为了不穿地把整个人抬起来 →
看起来"人物浮在地面上方"。

---

## 5. 循环与首尾帧：两件不同的事

| 目标 | 做法 | 自检 |
| --- | --- | --- |
| **循环无缝**（Idle / Walk / BlockHold） | 首尾帧取自**同一相位**，逐位完全相同 | 实测差 `0.000000°` |
| **切段不跳帧**（单次动作之间） | 首末帧都取**同一个中立站架**（`NEUTRAL_STANCE`） | 与 dodge/strafe/life 一致 |

### ★ 中立站架全工程统一

```python
NEUTRAL = {
    "hips": (-4.0, 0.0, 0.0),  "chest": (-4.0, 0.0, 0.0),  "head": (2.0, 0.0, 0.0),
    "uaR": (8.0, 0.0, -9.0),   "faR": (20.0, 0.0, 0.0),    "handR": (0.0, 0.0, 0.0),
    "uaL": (8.0, 0.0, 9.0),    "faL": (18.0, 0.0, 0.0),
    "legL": (6.0, -10.0, 0.0), "legR": (0.0, -8.0, 0.0),   # (thigh_rx, shin_rx, foot_extra)
}
```

左腿略前、右腿略后的**战斗站架**。19 段动画全部首末帧回到这里
（或回到与它视觉一致的角度）→ 引擎里怎么切段都不会"啪"一下。

> ⚠️ **特例：Slash3 的 root 偏航走满 360°**。
> 360° ≡ 0°，所以**净朝向变化为 0**，游戏侧不需要任何补偿，末帧与 Idle 视觉一致。
> 如果只转 180° 就走人，切回 Idle 时会瞬移半圈。

---

## 6. 建 Action + NLA 轨（导出前的必经步骤）

### ★★ glTF 导出器只导出"被 NLA 轨道引用的 Action"

只存在于 `bpy.data.actions` 里的 Action 会被**静默丢弃**。
每段动画都要建一条 NLA 轨道。

### ★★ `strip.influence` 默认是 0.0 —— 这个坑极其隐蔽

```python
track = ad.nla_tracks.new()
strip = track.strips.new(act.name, 1, act)
strip.influence = 1.0        # ← 忘了这行，症状如下
```

不写这行 = **轨道建了但没接管**。症状：

> GLB 导出正常、游戏里动画照播，**但 Blender 内预览是冻结的静止姿势**。

（因为导出器只认"NLA 里有没有这个 Action"，不 care influence 是多少；
而 Blender 自己求值时 influence=0 等于没这条轨道。）

### ★★ 渲染时 NLA 会覆盖手摆的姿势（排查最久的坑）

在 `bpy.ops.render.render()` 期间，动画系统会重新求值 NLA 轨道，
把手工摆的姿势盖回静止姿势。**诊断误导性极强**：

| 检查手段 | 结果 |
| --- | --- |
| 上下文依赖图 `evaluated_get(depsgraph)` 里的包围盒 | ✅ 确实变了（姿势生效了） |
| 数值测量（脚底接触、刃向、手腕位置） | ✅ 全部正确 |
| **渲染出来的 PNG** | ❌ 静止姿势 |

修法 —— 摆姿势/渲染前 **`silence_animation()`**：

```python
def silence_animation(arm):
    ad = arm.animation_data
    if ad is not None:
        ad.action = None
        for tr in ad.nla_tracks:
            tr.mute = True
```

（导出 GLB 前**不需要**恢复 —— 导出器只认 NLA 里的 Action。）

### ★ Blender 4.4+ 分层 Action 的 API 变化

`Action.fcurves` **已移除**，要改用：

```python
act.layers[*].strips[*].channelbags[*].fcurves
```

`add_action` 必须同时建 slot 并赋 `ad.action_slot`。

### ★★ 骨骼集合必须与已有动画"取并集"，一根都不能少

```python
KEY_BONES = [
    "hips", "chest", "head",
    "upperarm.R", "forearm.R", "hand.R", "weapon.R",
    "upperarm.L", "forearm.L",
    "thigh.R", "shin.R", "foot.R",
    "thigh.L", "shin.L", "foot.L",
]
KEY_ROOT_ROT = True      # 只有需要 root 旋转的段落才开
```

**少 key 一根** → 从新动画切回旧动画时那根骨骼会**保留上一个动画残留下来的姿势**，
表现为"某个肢体卡在格挡姿势"。

> `root` 的**旋转**通道是本工程后期才加的（`life_anim.py` 的 Death 首次使用）。
> 加了之后，新脚本要显式把 root 旋转也 key 成 0，保持通道集合一致。

---

## 7. 导出 GLB：顺序决定成败

### ★★ 导出/存盘必须在"导入预览用武器"之前

本工程**踩过两次**：先 import 剑再导出，剑被烘进角色 GLB（网格数 5 → 6），
游戏里角色手上多出一把钉死的剑。

正确顺序，脚本里用注释钉死：

```
① 建 Action
② 建 NLA 轨（influence=1.0）
③ 导出 GLB          ← 必须在④之前
④ save_as_mainfile  ← 必须在④之前
⑤ 再 import 剑（只为渲染预览）
⑥ 渲染预览
```

### ★★ 预览渲染路径必须 `os.path.abspath()`

出片模式先做过 `save_as_mainfile`，之后"相对路径"会被解析到**别的地方**
（本工程图全写进了 `C:\previews\...`）。

### ★ 多机位预览必须用不同的文件名前缀

否则后一个机位覆盖前一个（21 张图最后只剩 7 张）。

### 其它导出相关

- **`export_yup=True`** 时 Blender `+Y` → Godot `−Z`，正好是 Godot 的前向，**不用额外加旋转**
- 渲染引擎 ID 是 **`BLENDER_EEVEE`**（没有 `BLENDER_EEVEE_NEXT`）
- 日志里出现 **`Saved:`** 才说明真出图了
- `frame_set` 后直接读 `arm.pose.bones` 拿到的是**陈旧姿势**（无头尤甚）
  → 用 `arm.evaluated_get(depsgraph).pose.bones[...]`，或 `ad.action = act; ad.action_slot = act.slots[0]`

### 无头运行的样子

```bash
E:\blender\blender.exe --background --factory-startup --python scripts/combo_anim.py -- \
    <in.blend> <sword_01.glb> <out.glb> <preview_dir> [save_blend]
```

日志一律重定向到 `.tmp_*`（已 gitignore）。

---

## 8. Godot 侧接线：五个必须对齐的契约

动画做完了，但**能不能用**取决于这五条：

### ① 帧偏移约定 —— 别当 bug 修

Blender Action 帧 `1..N` → GLB 时间轴首帧**不在 0**；
Godot 导入平移到 t=0 + fps=30 重采样
→ **`Animation.length = N/24 = 内容时长 + 1/24`**。

**校验断言写 `length − 1/24`。**
⚠️ 别为消掉这 1 帧去改 Blender 帧区间 —— 会连带改 `length`，打破已固化的断言。

### ② 时长要铺满状态机的时间

| 段 | 帧 | 内容时长 | Godot 侧 |
| --- | --- | --- | --- |
| Hurt | 1–9 | 0.333s | 按 `length / hurt_time` 调倍速铺满硬直 |
| Execute | 1–25 | 1.000s | `execute_time = 1.0`，命中帧第 9 帧 → `execute_hit_time = 0.32 × execute_time` |

★ **改命中帧必须同步改 Godot 侧那个系数**（有断言钉住）。
敌人 `brute_01` 的动画时长是**刻意对齐** `enemy.gd` 状态机的：
Idle 2.0 / Walk 1.0 / AttackWindup 0.5 / Attack 0.25 / Hit 0.417。

### ③ 动画不含净水平位移

位移由 `player.gd` 负责。切换动画不会残留偏移。
（所以 `DodgeForward` / `DodgeBack` 都是**原地**动作，"冲出去"是代码给的。）

### ④ 命名要能被识别链认出来，且顺序敏感

Godot 侧匹配方式是**小写 + 忽略下划线**，但识别链**顺序敏感**：

```
exec 最前；
blockhold / blockimpact 必须先于裸 block；
walkstrafeleft / walkstraferight / walkback 必须先于裸 walk；
slash2 / slash3 必须先于裸 slash；
idle / hurt|damage / death|die
```

**顺序写反 = 后 key 覆盖先匹配的段**，`Slash2` 会被当成 `Slash`。
（`_setup_animations()` 里已按这个顺序排。）

### ⑤ 生命周期：停播后骨骼冻在那一帧

动画停播后骨骼**冻在停播那一帧** → 通常调 `_anim_to_rest()` 复位。
**死亡是唯一例外**（`Death` 播完故意不复位）。

---

## 9. 验收：断言 + 抓帧，两件事都要做

### 断言能证明的（数值）

- 帧偏移：`length − 1/24`
- 时长换算、倍速、冷却
- 段号、状态、伤害数值
- 骨骼通道齐不齐

### ★ 断言**证明不了**"好不好看"

这是本项目反复吃到的教训：

> 这是纯观感改动，最可疑的点是：从站立的 `Idle` 直接切到 `JumpAir` 第 0 帧
> 会不会"啪"地硬切。

去抓帧看，日志把关键事实钉死：

```
起跳前（站立 Idle）帧=78 动画=Idle
★ 起跳瞬间        帧=78 状态=5(JUMP) 动画=JumpAir vy=7.40     ← 同一个帧号！
```

再放大对比连续帧：

- f77 → **f78 姿态几乎一样**（脚仍在地上、影子连着）→ **没有硬切**
- f79 才开始收腿、影子开始分离；f80 明显腾空

★ 教训：**"去掉中间那段"是否会造成硬切，取决于"后一段的起始帧离前一段有多远"，
不是取决于少了多少帧。**

### 模糊的观感问题 → 换成可量化的判据

| 含糊的问题 | 量化判据 | 工具 |
| --- | --- | --- |
| "这是横着走还是竖着走？" | `foot.L/R` 逐帧坐标 + **X/Y 位移比**（侧移 Y/X ≈ 0.06~0.10；WalkBack ≈ 12.75；Walk ≈ 8.28） | `probe_foot_travel.py` |
| "脚有没有在原地？" | 脚相对髋的前后偏移（m） | 脚本结尾自检 |
| "有没有穿地？" | 每帧最低顶点（应 = +0.005） | `solve_root_z` 残差 |
| "左右对称吗？" | `worst_pose_diff(mirror_pose(姿势(+1)), 姿势(−1))` 应 = 0.000000° | 镜像自检 |

> ⚠️ **镜像检查必须真的先换 L↔R 再比**。比"同名骨骼的同相位姿势"只会报出膝弯差（17.5°），
> 那是**检查器写错了**而非姿势错了 —— 这次差点被它误导去改没错的姿势。

### ★ 右移不手写，用镜像严格生成

```python
mirror_pose(pose)   # 换 L↔R 骨名、ry/rz 取负、rx 不动
```

避免左右符号抄错。

### 出片：静态图看姿势，GIF 看节奏

| 工具 | 看什么 |
| --- | --- |
| `tools/img_probe/grid.py` | 多张关键姿势拼成**网格** → 一眼看出剪影互不相同 |
| `tools/img_probe/make_gif.py` | 一串抓帧合成 **GIF** → 看**节奏**（"第 2 段是在第 1 段后摇里被掐出来接上的"这类东西横条上根本看不出来） |
| `tools/anim_capture/*.tscn` | 运行时抓帧（带"帧号停滞"看门狗） |

---

## 10. 一次完整的新增动画，按这个清单走

以"给骑士加第 20 段动画"为例：

```
□ 1. 用 probe_axes_num.py 确认要用的骨骼轴朝向（换了骨架才需要）
□ 2. 在 combo_pose_lib.py（或新建同类库）里写"意图表"：
        arm / blade 方向 + hips/chest/head + legs + lift + yaw
□ 3. 纯 Python 迭代姿势（0.2s 一次），跑到解算误差可接受
□ 4. 写 <name>_anim.py 出片脚本：
        - KEY_BONES 抄现有并集，KEY_ROOT_ROT 按需
        - NEUTRAL 用统一站架
        - solve_root_z 贴地 + 收敛自检
        - 首末帧回到 NEUTRAL
□ 5. 建 Action → 建 NLA 轨（influence=1.0）→ silence_animation
□ 6. 导出 GLB → save_as_mainfile → 再 import 剑 → 渲染预览
□ 7. 归档 versions/knight-<name>-v0NN.blend
□ 8. 覆盖 Godot 侧 assets/characters/player_knight/player_knight.glb
□ 9. Godot --import → tools/split_player_animations.gd
□ 10. player.gd 加识别链（注意顺序！）+ 状态机接线
□ 11. m1_autotest 加断言（帧偏移 / 时长 / 通道数 / 段号）
□ 12. 重跑全部：m1_autotest + lock_toggle_probe + possess_probe + 240 帧冒烟
□ 13. 抓帧出 GIF 看节奏，静态图看姿势
□ 14. 更新 README / GAME_DESIGN / 资产 README / memory
```

---

## 11. 坑清单（速查）

### Blender 无头脚本

| 坑 | 症状 | 修法 |
| --- | --- | --- |
| 无头脚本日志 | 混在 stdout 里 | 一律重定向 `.tmp_*` |
| `strip.influence` 默认 0 | 导出的 GLB 正常，**Blender 内预览冻结** | 显式 `strip.influence = 1.0` |
| 渲染时 NLA 覆盖手摆姿势 | 数值全对，**渲染出来是静止姿势** | `silence_animation()` |
| 先 import 武器再导出 | 武器被烘进角色 GLB | 导出/存盘**必须早于** import 预览武器 |
| 相对路径 | 图写进 `C:\previews\` | `os.path.abspath()` |
| 多机位同名 | 21 张只剩 7 张 | 文件名前缀区分 |
| `Action.fcurves` | Blender 4.4+ 已移除 | `act.layers[*].strips[*].channelbags[*].fcurves` |
| `frame_set` 后读姿势 | 拿到**陈旧**姿势 | `evaluated_get(depsgraph)` 或显式赋 `action` + `action_slot` |
| 渲染引擎 ID | 写成 `BLENDER_EEVEE_NEXT` 报错 | 是 `BLENDER_EEVEE` |
| `parent_type='BONE'` | 子对象原点落在**tail** | 注意 head/tail 区别 |
| 关节点检参考点 | 量握把量错 | `hand.R` 的 **head 是手腕、tail 才是手心** |
| 摆姿势时"先移到原点再转" | 肢体弧线漂移（62° 抬腿飘 ~15cm） | 直接转 pose bone（旋转天然绕 bone head） |

### 姿势/数学

| 坑 | 症状 | 修法 |
| --- | --- | --- |
| `hips.rx` 动了但大腿没减 | 后撤腿被甩到**髋后 0.63m**，"脸朝下栽倒" | 大腿"世界角"必须**减掉 `hips.rx`**（髋 −25°、想大腿世界 −44° → 局部写 −19°） |
| 抬膝不补偿骨盆 | 膝盖弯 −36° 把脚甩到身后 0.23m，读成"往前迈一大步" | `planted_hip(knee) = -LS_OVER_SUM × knee`（≈ −0.494×knee） |
| 侧移做成弓步 | "横向开合"变成"前后弓步" | 开合用 `1-cos`、抬腿用 `max(0,±sin)` |
| 肘自由取负 | **反关节**（−14°） | 肘限 `[0, 80]` |
| 倒地手臂前伸 | 最低顶点 −0.30m（尸体沉地 30cm） | `ua_rx ≈ 0`，只手 `rz` 外展 |
| 倒地脚趾不绷 | 尸体浮在地面上方 | `foot_extra ≈ −70` |
| 少 key 一根骨骼 | 某肢体"卡"在上一个动画的姿势 | `KEY_BONES` 取并集 |
| `root` 偏航写成 `.y` / `.x` | 变成侧倾 / 前滚翻 | root 的 **`rz`** 才是偏航 |

### Godot 侧

| 坑 | 症状 | 修法 |
| --- | --- | --- |
| 识别链顺序 | `Slash2` 被当成 `Slash` | 具体名必须排在裸名之前 |
| 帧偏移 | `length` 比内容时长多 1/24 | 断言写 `length − 1/24`，别去改帧区间 |
| `speed_scale` × `custom_speed` | 断言读到错的倍速 | 断言必用 `get_playing_speed()` |
| 循环动画判"停下" | 永远不停 | 用 `_idling()` 之类，不用 `not is_playing()` |

---

## 12. 快速索引

| 我想…… | 看哪个文件 |
| --- | --- |
| 摸骨架轴朝向 | `scripts/probe_axes_num.py` |
| 调姿势（纯 Python，秒级） | `scripts/combo_pose_lib.py`（直接跑它） |
| 学手写关键帧 / 贴地反解 | `scripts/life_anim.py` |
| 学相位表 / 步态 | `scripts/strafe_anim.py`、`scripts/dodge_anim.py` |
| 学 IK 求解（手要够到世界点） | `scripts/block_ik.py`、`scripts/execute_anim.py` |
| 量"横着走还是竖着走" | `scripts/probe_foot_travel.py` |
| 不起引擎核对 GLB | `scripts/probe_glb.py` |
| 全部坑的原始记录 | `player_knight/README.md` |
| 枚举 19 段动画 | `D:\GodotProject\first-game\docs\GAME_DESIGN.md` |
| 引擎侧接线 | `D:\GodotProject\first-game\scripts\player\player.gd` |
