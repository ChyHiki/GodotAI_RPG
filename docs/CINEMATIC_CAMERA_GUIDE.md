# 自己调处决特写分镜

> 这份不是"电影运镜理论"，而是**本项目的调参手册**。
> 所有数字都来自已经跑通并出片复核过的那一版处决特写，
> 每一条坑都真的踩过、都有断言或抓帧在守着。
> 读完它，你应该能自己改分镜表、加刀、改节奏，并且知道改完怎么验证。
>
> 配套阅读：`docs/BLENDER_ANIMATION_GUIDE.md`（动画侧怎么出动作）、
> `docs/GAME_DESIGN.md`（这一层为什么这么设计）、`README.md`（总览）。

---

## 0. 先建立正确的心智模型

大部分人以为"做招式特写"的难点是"把镜头摆到一个帅的位置"。不是。

| 你以为的难点 | 真正的难点 |
| --- | --- |
| 找一个帅的机位 | 相机被追尾 rig **每帧独占** —— 特写必须先"夺权"，结束还得**无缝交还** |
| 把坐标写对 | 演员会走动、被击退、前冲 —— 写死世界坐标的分镜**只有固定舞台能用** |
| 把切点对到动作上 | 动作时长会改、慢动作会插进来 —— 切点必须钉在**比例**上而不是秒数上 |
| 断言跑绿就完事 | 断言只能证明"骨架正确"，**证明不了好不好看** —— 必须出片目视 |

一次处决特写的完整链路：

```
玩家按处决键
      ↓
player.gd::_try_start_execute()      播 Execute 动画 + 起手金光
      ↓
CinematicDirector.play(EXECUTE_SHOTS, execute_time, 玩家, 目标)
      ↓
┌─ 每帧 ─────────────────────────────────────────────┐
│  ① 重新采样两个锚点（玩家胸口 / 敌人胸口）           │
│  ② 按当前 t 查出"在哪一刀"（硬切，不插值）           │
│  ③ 算出机位 + 注视点 + fov，写进相机                │
│  ④ 遮幅黑边滑入（真实时间 0.15s）                   │
└───────────────────────────────────────────────────┘
      ↓
t=0.32 命中：硬切近景 + 触发慢动作 + 震屏 + 金爆闪
      ↓
player.gd::_end_execute() → director.stop()   交还相机、遮幅滑出
```

**三条核心机制**（后面每一节都在展开这三条）：

1. **相机控制权交接** —— 追尾 rig 每帧无条件覆盖相机位姿，特写必须夺权再交还。
2. **相对取景** —— 分镜表存的是"相对演员的方位/仰角/距离"，每帧现算，演员动镜头跟着动。
3. **归一化时间 + 硬切** —— `t` 是相对整段时长的比例；机位之间硬切，只在进场做平滑。

---

## 1. 文件在哪、分镜表长什么样

| 文件 | 干什么 |
| --- | --- |
| `scripts/camera/cinematic_director.gd` | **导演本体 + 分镜表 `EXECUTE_SHOTS`** ← 你要改的基本只有这个文件 |
| `scripts/camera/third_person_camera.gd` | 追尾相机，被接管的一方（`driven` / `apply_driven_pose` / `release_driven`） |
| `scripts/player/player.gd` | 起手时 `play()`、收招时 `stop()`；慢动作/震屏/金爆闪的 `@export` |
| `tools/anim_capture/execute_cine_capture.tscn` | 抓整段成片（逐帧落 PNG） |
| `tools/anim_capture/cine_frame_sweep.tscn` | **候选取景横向对比**（省时间的利器，见 §7） |

分镜表本体（`cinematic_director.gd:76`）：

```gdscript
const EXECUTE_SHOTS := [
	{"t": 0.00, "pivot": "mid",    "azimuth": 58.0, "elev":  22.0, "dist": 4.2, "fov": 62.0},
	{"t": 0.32, "pivot": "enemy",  "azimuth": 18.0, "elev":   8.0, "dist": 3.6, "fov": 50.0},
	{"t": 0.62, "pivot": "player", "azimuth": 18.0, "elev":  20.0, "dist": 4.6, "fov": 58.0},
]
```

**加一刀 = 往这个数组里加一行。** 不需要改任何其它代码，不需要动相机、不需要动状态机。

### 1.1 每个字段什么意思

| 字段 | 单位 | 语义 | 备注 |
| --- | --- | --- | --- |
| `t` | 0..1 | 这一刀**从归一化时间的哪一刻开始**（不是秒） | 必须**递增**；第一个建议 0.00 |
| `pivot` | 字符串 | 注视锚点：`"player"` / `"enemy"` / `"mid"`（两者中点） | 决定"画面中心是谁" |
| `azimuth` | 度 | 方位角。**0 = 相机在"玩家背后"（正对敌人）**，正角 = 往角色**右手边**绕 | 90 ≈ 正侧面；180 ≈ 完全绕到敌人背后 |
| `elev` | 度 | 仰角。**正 = 相机更高（俯视）**，负 = 仰拍 | 约 -20 ~ +35 是舒服区间 |
| `dist` | 米 | 相机到**注视锚点**的直线距离 | 见下面那条 ⚠️，这是最容易翻车的字段 |
| `fov` | 度 | 该刀使用的视野角度。**小 fov = 长焦特写**（压缩空间、突出主体、不穿模） | 默认追尾是 70 |

### 1.2 ★ 方向为什么是"反"的：`back = -axis`

取景轴是 `axis = 敌人胸口 − 玩家胸口`（水平方向）。**但相机不能站在轴上**——
站在轴上就是正对着玩家后脑勺。所以导演用 `back = -axis`，也就是**"从敌人指向玩家"**那个方向当 0 度：

```gdscript
var axis := b_chest - a_chest          # 玩家 → 敌人
var back := -axis                       # 敌人 → 玩家（azimuth = 0 时相机在这个方向）
var dir_h := back.rotated(Vector3.UP, deg_to_rad(azimuth))
var elev_axis := dir_h.cross(Vector3.UP)
var dir := dir_h.rotated(elev_axis, deg_to_rad(elev))
var pos := pivot + dir * dist
```

于是：

- `azimuth = 0` → 相机在**玩家背后**，正对敌人（过肩视角）。
- `azimuth = +58`（第 1 刀）→ 相机绕到玩家**右手边**，变成侧上方俯视。
- `elev` 的正负由 `dir_h × UP` 这根轴保证：绕它转正角，`dir_h` 朝 `+Y` 抬起 → 相机升高 → 俯视。

### 1.3 ⚠️⚠️ `pivot = "enemy"` 时，`dist` 是"从敌人胸口朝玩家方向退多少米"

这是本文最重要的一条算术。

`pos = 敌人胸口 + back × dist`，而 `back` 指向玩家。所以 **`dist` 不是"相机到敌人的距离"，
而是"相机沿着玩家方向、退到敌人胸口后面多远"**。玩家本身就在这条线上，离敌人约 **1.4 ~ 1.5m**：

| `dist` | 相机实际在哪 | 观感 |
| --- | --- | --- |
| `1.9`（修之前的第 2 刀） | 敌人胸口沿玩家方向退 1.9m → 只比玩家远 **0.5m** | **相机还在玩家身体里** → 画面被玩家模型糊满，剑、敌人反应全看不见 |
| `3.6`（现在） | 退 3.6m → 玩家在相机前 **2.2m** | 玩家成为左侧前景（过肩），敌人全身入画 ✓ |

**经验公式**：`pivot = "enemy"` 时，要求 **`dist ≥ 玩家到敌人的水平距离 + 1.5m`**，
否则相机压在玩家身上。近战处决的水平间距约 1.4m，所以 **`dist` 不要小于 3.0**。

> 同一把"画面高度"的尺子也用来判断特效大小，见 §6.3。

---

## 2. 相机是怎么被"接管"的（为什么不能直接改机位）

追尾相机 `third_person_camera.gd::_process()` 每帧**无条件**重算并覆盖 `global_position` 与 `look_at`。
你如果只是"某一帧把相机挪过去"，下一帧就被它拽回去了。所以必须**夺权**：

```gdscript
# cinematic_director.gd::play()
_cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
if _cam != null:
    _entry_pos = _cam.global_position       # 记下接管瞬间的位姿（进场平滑的起点）
    _entry_dir = -_cam.global_basis.z       # 相机局部 -Z 就是它看向的方向
    _entry_fov = _cam.get_fov()
    _cam.driven = true                      # ★ 交出控制权

# third_person_camera.gd::_process()
_apply_shake(delta)                         # ★ 震屏照算（加在子节点上）
if driven:
    return                                  # ★ 被接管时不覆盖位姿

# third_person_camera.gd::_input()
if driven:
    return                                  # ★ 接管期间鼠标/滚轮不抢镜头
```

接管期间由导演每帧调：

```gdscript
_cam.apply_driven_pose(pos, look, fov)      # 写父节点的位姿 + 子相机的 fov
```

### 2.1 ★ 收回来才是坑：不反推 yaw/pitch 就会"弹回"

追尾 rig 内部缓存着 `yaw` / `pitch` / `_current_pos` / `_current_look`。
如果特写结束直接 `driven = false`，rig 会拿**特写之前的旧角度**去重算期望位置 →
镜头在交还那一瞬间**猛地摆回去**（"弹回"）。

`release_driven()` 的做法是：**从当前实际位姿反推 yaw/pitch**，再让 rig 从当前位置无缝续上。

```gdscript
# third_person_camera.gd::release_driven()
driven = false
if _cam:
    _cam.fov = DEFAULT_FOV                  # fov 也要复位，否则一直停长焦上
yaw = atan2(off_h.x, off_h.z)               # 从当前偏移反推
pitch = clampf(atan2(off.y, off_h.length()), min_pitch, max_pitch)
_current_pos = global_position              # 缓冲同步到当下，防弹回
_current_look = look
```

`m1_autotest` 有**两条强断言**专门守这个：交还后 `camera.yaw` / `camera.pitch`
必须与"从实际位姿反推出来的值"一致。你把 `release_driven` 里那两行注释掉，这两条立刻 FAIL。

### 2.2 震屏为什么在特写期间还看得见

震屏不是改父节点位置，而是改**子相机** `_cam` 的 `h_offset` / `v_offset` / `rotation.z`：

```
ThirdPersonCamera (Node3D)   ← 导演每帧写这里（位置 + look_at）
        └── Camera3D         ← 震屏写这里（局部偏移）
```

所以"夺权写父节点"和"震屏写子节点"天然互不干扰。**不要为了特写去改这个结构**，改坏了震屏就没了。

---

## 3. 时间：为什么用归一化 `t`，切点为什么钉在 0.32

### 3.1 归一化时间

`t` 不是秒，是 `已经过时间 / execute_time`：

```gdscript
_elapsed += delta                       # ★ 注意用的是"被 time_scale 缩放过的 delta"
var nt := clampf(_elapsed / _duration, 0.0, 1.0)
var shot := _shot_at(nt)                # 返回最后一个 t <= nt 的那一刀
```

好处：把 `execute_time` 从 1.0 调到 1.2，**三段分镜自动等比伸缩**，
不用重排任何一刀的秒数，也不会出现"改了时长导致切镜落后于动画"。

> ⚠️ 时间轴用的是 `_process` 传进来的 `delta`（**已被 `Engine.time_scale` 缩放**）。
> 处决命中会触发慢动作（0.35 倍），如果用真实时间推进，慢动作期间"画面走得慢、
> 机位走得快"，镜头会滑得比人物快 —— 一眼穿帮。

### 3.2 切点为什么是 0.32

`execute_hit_time = 0.32`（`player.gd:304`）是 **Execute 动画的"前刺命中"帧**：
它定在第 9 帧，相对进度 `(9 − 1) / 25 = 0.32`（分母 25 = 总帧数）。

> 口径说明：这里的除法用的是 **"÷ 总帧数"**（`8 / 25`）。另一种常见口径是 **"÷ 间隔数"**
> （`(9 − 1) / (25 − 1) = 0.3333`）。两者差 0.013，**本工程的代码、注释、分镜表三处统一用前者**，
> 你若要自己重算，请跟着用 `÷ 总帧数`，否则会和 `EXECUTE_SHOTS` 里的 `0.32` 对不上。
所以第 2 刀的 `t = 0.32` 就是**命中那一帧**。

**切点藏在命中帧上**，这是刻意的：观众注意力这时全在动作上，**切得没人察觉**。
同一个 0.32 还同时触发了慢动作、震屏、金爆闪 —— 全部对齐在同一帧。

> ⚠️ 如果你改了动画的命中帧或改了 `execute_time`，`execute_hit_time` 和分镜里的
> `t = 0.32` 都要**一起重算**，否则"切镜那一拍"和"命中那一拍"会错开。
> `m1_autotest` 有断言盯着这两个值的关系。

### 3.3 两种"切"不要混

| 场合 | 用什么 | 为什么 |
| --- | --- | --- |
| **机位之间**（第 1 刀 → 第 2 刀） | **硬切**（`_shot_at` 直接换，不插值） | 真实剪接就是瞬间跳机位，硬切才有节奏感 |
| **进入特写**（追尾 → 第 1 刀） | **平滑接管** `INTRO_TIME = 0.15s`，smoothstep | 一按左键就"啪"地瞬移会有硬跳帧 |
| **退出特写**（第 3 刀 → 追尾） | `release_driven()` 反推 yaw/pitch | 交还后追尾从当前位姿续上，不是插值 |

---

## 4. ★ 调参速查表（最常用的一页）

改的都是 `cinematic_director.gd` 里 `EXECUTE_SHOTS` 的字段。

| 我想要的效果 | 动哪个字段 | 怎么动 |
| --- | --- | --- |
| 主体更大 / 更小 | `fov` ↓ / ↑，或 `dist` ↓ / ↑ | **优先动 `fov`**：改 fov 只推近，**不会穿模** |
| 更有"压迫感" | `elev` ↓（负角仰拍）+ `fov` ↓ | 仰拍 + 长焦 = 敌人显得高大 |
| 更"剧场感"俯视 | `elev` ↑ 到 25~35 | 太高（>40）会变上帝视角，失去代入 |
| 换成另一个主体在画面中心 | `pivot` | `mid` 交代关系 / `enemy` 打人 / `player` 看招式 |
| 从另一侧拍 | `azimuth` ± | 正角往角色**右手边**绕；想完全换边就加减 180 |
| 看"剑砍进去"的交叉动作 | `pivot: "mid"` + `azimuth` 75~85 + `elev` 0~10 | 接近正侧面剖视，两个角色的身体会交叉 |
| 加第 4 刀 | 往数组加一行 | 只需保证 `t` 递增且 ≤ 1.0 |
| 改变"这一刀占多长时间" | 改**下一刀**的 `t` | 第 N 刀的时长 = `t(N+1) − t(N)` |
| 整体节奏更快 / 更慢 | `player.gd` 的 `execute_time` | 分镜会自动等比伸缩，**不用改分镜表** |

### 4.1 三条可直接抄的配方

**配方 A —— 全景交代**（开场，让观众看清"谁在哪、要干什么"）

```gdscript
{"t": 0.00, "pivot": "mid", "azimuth": 58.0, "elev": 22.0, "dist": 4.2, "fov": 62.0},
```

> 侧上方俯视，两人都完整。`fov` 保持 58~64（别用长焦，交代要宽）。

**配方 B —— 过肩命中近景**（当前第 2 刀）

```gdscript
{"t": 0.32, "pivot": "enemy", "azimuth": 18.0, "elev": 8.0, "dist": 3.6, "fov": 50.0},
```

> `azimuth` 小（18°）→ 相机基本在玩家正后方 → 玩家成为**左侧前景**，敌人正对镜头。
> `elev` 取正小角度（8°）避免下巴朝天；`dist` 必须 ≥ 3.0（见 §1.3）。
> ⚠️ **这个机位下画面可视高度只有 ~3.36m**，命中特效必须收敛（见 §6.3）。

**配方 C —— 侧面剖视**（想读清"剑怎么进肉"）

```gdscript
{"t": 0.32, "pivot": "mid", "azimuth": 78.0, "elev": 6.0, "dist": 3.0, "fov": 44.0},
```

> 接近正侧面，两个身体会**交叉**，剑的轨迹最清楚。
> ⚠️ 副作用：`elev` 低 + 遮幅会**裁到两个角色的头**（我用这条配方时两个头都被上黑边切了）。
> 想用就把 `elev` 抬到 10~14，或把遮幅比例调小（§5）。

**配方 D —— 仰拍压迫**（敌人显得高大、玩家显得"以小搏大"）

```gdscript
{"t": 0.32, "pivot": "enemy", "azimuth": 40.0, "elev": -14.0, "dist": 2.8, "fov": 44.0},
```

> ⚠️ 副作用：`elev` 负 + `dist` 小 → 相机贴近地面，地面遮挡物（草、石块）容易入画挡镜头。

---

## 5. 遮幅黑边（Letterbox）

导演**自建**一个 `CanvasLayer(layer = 0)` + 上下两条 `ColorRect`，不占用 HUD 的层级：

| 常量 | 默认 | 说明 |
| --- | --- | --- |
| `LETTERBOX_RATIO` | `0.12` | 每条黑边占视口高度的比例（上下各 12% → 有效画面 76%，约 2.35:1） |
| `LETTERBOX_IN_TIME` | `0.15` | 滑入时长（**真实秒**，`set_ignore_time_scale`） |
| `LETTERBOX_OUT_TIME` | `0.15` | 滑出时长（真实秒） |

**层级语义别搞错**：遮幅 `layer = 0`，HUD 是 `layer = 10`。
所以遮幅压在 **HUD 之下、3D 世界之上** —— 有意为之，**不能挡血条**。

> ⚠️ 改 `LETTERBOX_RATIO` 会连带改变"画面可视高度"，而命中特效的大小是按可视高度判断的
> （§6.3）。遮得越多 → 可视高度越小 → 同样的特效占比更大 → 越容易糊屏。

> ⚠️ 滑入/滑出用**真实时间**，是因为处决后半段还在慢动作里；若用缩放时间，遮幅会
> "慢吞吞地"滑进来，节奏就散了。**位置/震动用缩放时间，时长计时用真实时间** —— 方向相反，别写反。

---

## 6. 命中反馈三件套：慢动作 / 震屏 / 金爆闪

全部在 `scripts/player/player.gd` 的 `@export` 里，Inspector 可直接调。

### 6.1 慢动作

```gdscript
@export var cinematic_slowmo_scale: float = 0.35   # 倍率（1.0 = 常速）
@export var cinematic_slowmo_hold:  float = 0.28   # 保持时长（真实秒）
@export var cinematic_slowmo_fade:  float = 0.40   # 平滑回升时长（真实秒）
```

- `hold` / `fade` 按**真实秒**计时（`set_ignore_time_scale`），所以减速本身不会把它们拖长。
- **倍率为什么是 0.35 而不是更狠**：0.35 仍能看清"前刺 → 上划"，再慢就成 PPT 了。
- 起点就是 `execute_hit_time`（0.32），**天然与第 2 刀的硬切点对齐** —— 切到近景的同一帧，时间恰好慢下来。
- 与完美闪避的子弹时间**共用同一套机制**（`_start_bullet_time`），只是传不同参数。

### 6.2 震屏 与 可选顿帧

```gdscript
@export var execute_shake: float = 0.085        # 振幅(米)
@export var execute_shake_time: float = 0.16    # 时长(秒)
@export var execute_hitstop: float = 0.0        # 0 = 关；0.11 = 收尾重击那种"顿"一下
```

- 振幅参考：`0.03` ≈ 轻击，`0.09` ≈ 收尾重击。处决取 `0.085`，对齐三段连击的收尾重击。
- 多次触发**取 max 不叠加**（一刀扫中两个敌人不会把画面甩飞）；振幅按 `(剩余/总)²` 衰减（像余震）。
- `execute_hitstop` **默认关**（0.0）。理由：顿帧会改变处决的打击节奏，那是另一套打击感偏好，
  属于"可选加强"，不该默认叠在所有人身上。想开调 `0.11`。

### 6.3 ★ 金爆闪的大小必须按"镜头距离"算，不能拍脑袋

命中金爆闪在 `player.gd:1156`：

```gdscript
HitFlash.spawn(_vfx_root(), target.global_position + Vector3(0, 1.1, 0),
    Color(1.0, 0.8, 0.25), 0.95, 0.30, 7.5)
#                          ^颜色      ^半径 ^时长 ^光强
```

**参数是 `（父节点, 世界坐标, 颜色, 半径, 时长, 光强）`。**

同一个半径，在追尾视角（相机距角色 ~5.5m、fov 70）里看着正常，
换到特写（`dist = 3.6`、`fov = 50`）就会**糊满全屏**。算法：

```
锚点处画面可视高度  H = 2 × dist × tan(fov / 2)

第 2 刀：H = 2 × 3.6 × tan(25°) ≈ 3.36 m
原半径 1.4 → 直径 2.8m → 2.8 / 3.36 ≈ 83%   ← 整块糊掉，剑和敌人反应全看不见
现半径 0.95 → 直径 1.9m → 1.9 / 3.36 ≈ 57%  ← 仍是全场最亮的金爆闪，但不糊屏
```

**经验阈值**：命中类特效的**直径控制在画面可视高度的 50% ~ 60%**。
再大就会盖住"剑砍进去"这个关键动作；再小就没有冲击力。

> 这条公式是**通用的**：任何时候你改了任一刀的 `dist` 或 `fov`，
> 都要重算一遍 `H`，检查画面里的特效/角色占比还合不合适。

> ⚠️ `HitFlash` 是 `UNSHADED` + 加法混合的亮球 + 扩散光环 + 点光源。
> 因为是加法混合，**多个特效重叠处会直接过曝成白**。
> 抓帧脚本用完美格挡把敌人顶进失衡时迸的那圈格挡黄光（半径 1.1）会在这里叠上来 ——
> 那是**抓帧脚本的现场**造成的，真实流程里"格挡完立刻处决"本来也会看到，属正常。

---

## 7. 改完怎么验证（三层，缺一层都不行）

### 第 1 层：断言 —— 守"骨架正确"

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path D:\GodotProject\first-game `
  'res://tools/autotest/m1_autotest.tscn'
```

分镜相关的断言在 `tools/autotest/m1_autotest.gd:739` 起（第 **1f-2** 节），覆盖：

- 处决起手后导演接管（`is_active()`）、相机进入 `driven`
- 特写期间 `fov` 被改动；遮幅**可见 / 纯黑 / `layer == 0`**
- 越过命中切点后**机位确实改变**、`fov` 变小（近景刀用长焦）
- 慢动作 `time_scale < 1` 且能**自行回升到 1.0**
- 震屏振幅 > 0
- ★★ **交还后 `yaw` / `pitch` 与"从实际位姿反推"的值一致（防弹回）**
- ★ 目标失效时导演**安全退出**（相机交还、处决提前收招）
- ★ 场景里**没有导演**时处决照常跑完（优雅降级）
- 结束后 `fov` 复位 **70**

全绿的标准：`AUTOTEST RESULT: ALL PASS`、`exit=0`、零 `SCRIPT ERROR`。
当前基线 **339 条**；另外三套探针是 `lock_toggle_probe` 62 / `possess_probe` 36 / `quest_probe` 113。

### 第 2 层：抓帧出片 —— 看"节奏与取景"

⚠️ **绝对不能加 `--headless`**（headless 用空渲染驱动，出不来图）。

```powershell
# ① 输出目录必须先建好（Godot 不会自己 mkdir，缺失时静默不出图）
New-Item -ItemType Directory -Force -Path D:\GodotProject\first-game\.tmp_cine | Out-Null

# ② 真跑一遍处决，让分镜导演自己驱动相机，逐帧落盘
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --path D:\GodotProject\first-game --fixed-fps 60 `
  --write-movie D:\GodotProject\first-game\.tmp_cine\frame.png `
  'res://tools/anim_capture/execute_cine_capture.tscn'
```

抓帧脚本会**在关键时刻打印帧号**，拿号去取图即可（`--write-movie` 每帧写 `frame%08d.png`）：

| 事件 | 打印内容 |
| --- | --- |
| 特写接管 | `★ 特写接管（导演 is_active→true）帧=…` |
| 遮幅到位 | `遮幅滑入到位（bar_k=1.00）帧=…` |
| 慢动作谷底 | `★ 慢动作进入最深（time_scale=0.35）帧=…` |
| **命中硬切** | `★★ 命中切点·硬切近景（fov 62→50.0）帧=…` |
| 拉回收招 | `切到拉回收招刀（fov→58.0）帧=…` |
| 相机交还 | `★ 相机交还（导演 is_active→false）帧=…` |

合成 GIF 与网格图（`Pillow` 已装在隔离 venv 里）：

```powershell
$py = 'C:\Users\chy\.workbuddy\binaries\python\envs\default\Scripts\python.exe'
$root = 'D:\GodotProject\first-game'

# 整段 GIF（--every 2 抽帧、--width 520 缩放，不然 GIF 太大）
& $py "$root\tools\img_probe\make_gif.py" "$root\docs\preview_execute_cine.gif" `
  "$root\.tmp_cine\frame*.png" --fps 30 --every 2 --width 520

# 关键帧网格（<out.png> <每行张数> <图...>）
& $py "$root\tools\img_probe\grid.py" "$root\docs\preview_execute_cine_poses.png" 2 `
  "$root\.tmp_cine\frame00000084.png" "$root\.tmp_cine\frame00000093.png" `
  "$root\.tmp_cine\frame00000104.png" "$root\.tmp_cine\frame00000105.png" `
  "$root\.tmp_cine\frame00000126.png" "$root\.tmp_cine\frame00000141.png" `
  "$root\.tmp_cine\frame00000163.png" "$root\.tmp_cine\frame00000229.png"
```

### 第 3 层：目视 —— 看"好不好看"

**断言只能证明骨架正确，证明不了观感。** 用这张清单逐格过：

- [ ] 每个角色的**头有没有被上遮幅裁到**？（这是最常翻的一条）
- [ ] 主体是**全身入画**，还是被截成半个身子？
- [ ] 命中的那一拍，**剑/武器看得见**吗？有没有被特效或队友身体挡住？
- [ ] 命中特效是**有界的光环**，还是糊满全屏的色块？
- [ ] 三个机位之间**切得够清楚**吗（还是看起来像同一台机位在做微调）？
- [ ] 交还那一帧有没有"猛摆一下"（弹回）？

### 省时间的做法：先 sweep 再定稿

**别一上来就改分镜表然后抓整段**（每次都要抓 200+ 帧）。先用 sweep 工具横向比：

```powershell
New-Item -ItemType Directory -Force -Path D:\GodotProject\first-game\.tmp_sweep | Out-Null
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --path D:\GodotProject\first-game --fixed-fps 60 --resolution 800x450 `
  --write-movie D:\GodotProject\first-game\.tmp_sweep\frame.png `
  'res://tools/anim_capture/cine_frame_sweep.tscn'
```

它把**同一现场、同一姿势**（玩家摆到命中那一拍并冻结双方）用 6 组候选取景各渲 12 帧，
一次出片就能横向对比，还会打印每个候选的**代表帧号**：

```
CAPTURE: CAND E pivot=enemy az=18 elev=8 dist=3.6 fov=50  rep_frame=…
CAPTURE: rep_frames = [...]
```

改 `cine_frame_sweep.gd` 顶部的 `CANDIDATES` 数组就能换成你自己的候选，
再用 `grid.py` 拼成对比图。**选定之后**才回去改 `EXECUTE_SHOTS` 并抓整段。

> ⚠️ sweep 里**刻意不跑处决状态机**，所以没有命中特效 —— 那一步测的是**纯几何构图**。
> 黄闪糊不糊屏要等整段重抓才能判断（见 §6.3）。

---

## 8. ★★ 三个会让你白干的坑

### 坑 1：抓帧 PNG 序号 = `Engine.get_frames_drawn() − 1`（差一帧）

`execute_cine_capture.gd` 文件头里写着"序号 == `Engine.get_frames_drawn()`"——**这是错的**。

实测：日志打印"命中切点 帧=106"，但**那一帧落盘为 `frame00000105.png`**。
取"切点前 1 帧 / 切点当帧 / 切点后 N 帧"时，**一律用 `PNG(对数 − 1)`**，
否则每张都取到相邻的那一刀 —— 而差一帧正好差在"第 1 刀末"和"第 2 刀首"之间，观感完全不同。

> （`cine_frame_sweep.gd` 里那句"窗口 ≈ [施加帧, 施加帧 + N − 1]"的描述才是对的，
> 两个文件的注释自相矛盾，信 sweep 那个。）

### 坑 2：抓帧脚本的 fov 门限是硬编码的，改 fov 会让它**静默失效**

`execute_cine_capture.gd:38`：

```gdscript
const FOV_NEAR_CUT := 54.0      # 第 1 刀(62) 与 第 2 刀(50) 之间
const FOV_PULL_BACK := 55.0     # 第 2 刀(50) 与 第 3 刀(58) 之间
```

脚本靠**fov 跳变**识别切点。它不会因为"你改了分镜表"而报错，只会**静默地不再打印**：

- 把第 2 刀的 `fov` 调到 **≥ 54** → `cam3d.fov < 54` 永不成立 → "命中切点"这条日志消失；
- 而"切到拉回收招刀"那条被 `printed_cut` 门控 → **也跟着消失**；
- 抓帧本身照跑、日志看着一切正常 → **你手里就有一份假日志**。

**所以：改任何一刀的 `fov`，都要先回头核这两个常量**，让它们分别落在相邻两刀之间。

### 坑 3：特效大小是"世界尺寸"，镜头一推近就糊屏

见 §6.3。追尾视角里正常的半径，在特写里就是一块糊满全屏的色块。
**改 `dist` / `fov` 之后，一定要回头检查命中特效与角色的画面占比。**

---

## 9. 一次完整的调参流程（照着做）

```
1. 决定要改哪一刀、想要什么效果（查 §4 速查表）
2. 用 §7「先 sweep 再定稿」跑 6 组候选取景，拼 grid 对比    ← 省掉反复抓整段
3. 选定 → 改 cinematic_director.gd 的 EXECUTE_SHOTS
4. ★ 回头核 execute_cine_capture.gd 的 FOV_NEAR_CUT / FOV_PULL_BACK   ← 坑 2
5. ★ 按新 dist/fov 重算画面可视高度，检查命中特效占比是否 ≤ ~60%      ← 坑 3
6. 跑 m1_autotest（应 339 条全过、exit=0、零 SCRIPT ERROR）
7. 抓整段成片（不加 --headless），注意取图要用 PNG(对数 − 1)          ← 坑 1
8. 拼 GIF + 关键帧 grid，按 §7 第 3 层的清单逐格目视
9. 不满意 → 回 3；满意 → 收工
```

---

## 10. 附：参数与文件索引

### 10.1 分镜导演 `cinematic_director.gd`

| 名字 | 值 | 说明 |
| --- | --- | --- |
| `EXECUTE_SHOTS` | 3 刀 | ★ 分镜表本体 |
| `PIVOT_HEIGHT` | `player 1.15` / `enemy 1.50` | 锚点高度（米）。player 对齐 `_effect_point()`；enemy 按 2.66m 身高的胸口 |
| `INTRO_TIME` | `0.15` | 进场平滑接管时长（缩放时间） |
| `LOOK_AHEAD` | `10.0` | 把"注视方向"表达成"注视点"用的远距离常量 |
| `LETTERBOX_RATIO` | `0.12` | 每条黑边占视口高度比例 |
| `LETTERBOX_IN_TIME` / `OUT_TIME` | `0.15` / `0.15` | 遮幅滑入/滑出（**真实秒**） |

### 10.2 追尾相机 `third_person_camera.gd`

| 名字 | 值 | 说明 |
| --- | --- | --- |
| `DEFAULT_FOV` | `70.0` | 交还控制权时 fov 复位到这个值 |
| `distance` | `5.5` | 追尾默认距离（特写不受它影响） |
| `look_height` | `1.25` | 追尾注视点抬高量 |
| `min_pitch` / `max_pitch` | `-0.30` / `0.95` | 俯仰限位（弧度），`release_driven()` 反推时会 clamp |
| `driven` | `false` | ★ 是否被导演接管 |
| `apply_driven_pose(pos, look, fov_deg)` | — | 导演每帧调用 |
| `release_driven()` | — | 交还控制权（反推 yaw/pitch，防弹回） |
| `shake(amount, duration)` | — | 震屏；多次触发取 max；振幅按 `(剩余/总)²` 衰减 |

### 10.3 玩家侧 `player.gd`

| 名字 | 值 | 说明 |
| --- | --- | --- |
| `execute_time` | `1.0` | 整段处决时长；分镜的 `t` 相对它归一化 |
| `execute_hit_time` | `0.32` | 命中时刻；**分镜第 2 刀的切点 = 这个值** |
| `execute_range` | `2.6` | 触发处决所需的水平距离 |
| `cinematic_slowmo_scale` / `hold` / `fade` | `0.35` / `0.28` / `0.40` | 命中慢动作 |
| `execute_shake` / `execute_shake_time` | `0.085` / `0.16` | 命中震屏 |
| `execute_hitstop` | `0.0` | 可选顿帧（默认关） |
| 起手金光 | `:1109` | `HitFlash.spawn(self, …, Color(1.0,0.86,0.3), 1.1, 0.32, 6.0)` |
| 命中金爆闪 | `:1156` | `HitFlash.spawn(…, Color(1.0,0.8,0.25), 0.95, 0.30, 7.5)` |
| 起手接线 | `:1114` | `get_first_node_in_group("cinematic") as CinematicDirector` → `play(...)` |
| 收招接线 | `:1196` | 同上 → `stop()` |

### 10.4 相关测试与工具

| 文件 | 作用 |
| --- | --- |
| `tools/autotest/m1_autotest.gd:739` | 分镜断言（第 1f-2 节），全场 339 条 |
| `tools/anim_capture/execute_cine_capture.tscn` | 抓整段特写成片（**不加 `--headless`**） |
| `tools/anim_capture/cine_frame_sweep.tscn` | 候选取景横向对比（改 `CANDIDATES`） |
| `tools/img_probe/grid.py` | 多帧拼网格（`<out.png> <每行张数> <图...>`） |
| `tools/img_probe/make_gif.py` | 帧序列合成 GIF（`--fps` / `--every` / `--width`） |
| `docs/preview_execute_cine.gif` | 整段预览（119 帧 520×292） |
| `docs/preview_execute_cine_poses.png` | 关键帧网格（8 帧 2560×2960） |

> ⚠️ `docs/preview*` 已在 `.gitignore` 里（为了压 GitHub 推送体积加的）
> → **预览图不会进版本库**，改完只在本机可见，要给人看得另外发。
