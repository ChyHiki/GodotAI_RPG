# player_knight —— 玩家角色资产（Godot 侧）

> ⚠️ **模型源文件不在本目录**，也不在 Godot 项目里。所有 `.blend` 源文件与完整预览图在：
> `E:\blender\blenderproject\player_knight\`（唯一来源，见该目录下的 README.md）
> 这里只放**引擎需要的产物**，按类型分类存放。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `player_knight.glb` | 绑定好的模型：**5 个网格** + 21 根骨骼（Skin）+ **19 段动画**（剑**不在**里面，见下。其中 `RollLeap` 已停用，见 `DodgeForward`/`DodgeBack`；`Slash2`/`Slash3` 是 2026-09-21 新增的三段连击 2/3 段） |
| `animations/` | 从 GLB 抽出的独立动画资源（`*.tres`），便于预览/复用（由 `tools/split_player_animations.gd` 生成） |
| `previews/` | 各动画代表帧。**行走含左右两步 + 侧视**：`walk_side_01_contact_R.png`（右步触地）、`walk_side_07_passing_R.png`、`walk_side_13_contact_L.png`（左步触地）、`walk_side_19_passing_L.png`，另有斜视 `walk_01_contact_R.png` / `walk_13_contact_L.png`；**格挡**：`block_03_raise.png`（起手过半）、`block_07_guard.png`（防护架势）、`hold_01_guard.png` / `hold_13_breath.png`（举剑待机）、`impact_03_recoil.png`（挡下顿挫）；**锁定侧移**：`strafe_left_13_open.png`（开到最大的站姿，正视）、`strafe_left_07_lead_lift.png`（斜视）、`strafe_left_side_07/19.png`（侧视，看摆腿是"原地抬膝"而非后甩）、`strafe_right_13_open.png`、`walk_back_side_07.png`；**闪避**：`dodge_forward_side_01_start.png` / `dodge_forward_side_06_peak.png`（前冲：后腿蹬直、躯干前压）、`dodge_back_side_01_start.png` / `dodge_back_side_08_peak.png`（后撤：剪式腿——前膝抬起、后腿后伸、躯干后倾）；**引擎内实拍**：`lockon_00_free_walk.png`（未锁定：身体扭向移动方向）、`lockon_01_camera_behind.png`（锁定：镜头绕到背后正对敌人）、`lockon_02_strafe_left.png` / `lockon_03_strafe_right.png`（身体保持朝敌人横移）、`lockon_04_marker_body_center.png` / `lockon_05_marker_zoom.png`（**锁定标记**：敌人身体中心的白色亮点，后一张是同帧放大） |

## 模型规格

- 尺寸：身高 **1.87 m**，脚底在原点平面（Y=0），朝向 **-Z**（Godot 默认前向）
- 网格（5 个）：`GEO-knight_body`、`GEO-leg_L/R`、`GEO-arm_L/R`
- ⚠️ **剑不在角色 GLB 里**（不要往这里加）：「武器与角色分离」是既定约定，
  剑是独立资产 `assets/weapons/sword_01/sword_01.glb`，运行时由 `player.gd` 挂到骨架的
  **`weapon.R` 空骨骼**上。骨架里只保留这个挂点骨骼，没有剑的几何体。
  （曾经踩过坑：Blender 导出脚本在导 GLB 之前先把预览用的剑 import 进场景，结果剑被烘进角色 GLB。
   自动测试里有"角色 GLB 含 5 个身体网格"这条断言专门守这个回归。）
- 材质：7 个纯色 Principled 材质（无贴图），低多边形方块风
- 骨骼（21）：`root → hips → spine → chest → neck → head`；`chest → shoulder.L/R → upperarm.L/R → forearm.L/R → hand.L/R →（hand.R → weapon.R）`；`hips → thigh.L/R → shin.L/R → foot.L/R`
- 蒙皮方式：刚性蒙皮（每个部件 100% 绑定 1 根骨骼）

## 动画（24 fps）

| 动画名 | 帧 | 时长 | 循环 | 说明 |
| --- | --- | --- | --- | --- |
| `Walk` | 1–25 | 1.000 s | ✅ 循环 | **完整两步循环**：右脚支撑 f3–f13、左脚支撑 f14–f2（各半周期）；接触帧双脚同时着地（0.005 / 0.035），摆动腿抬起 7.8 cm，身体起伏 4.4 cm；首尾帧完全一致 |
| `Idle` | 1–49 | 2.000 s | ✅ 循环 | **待机呼吸**：胸腔 +2.2°、头部微摆、双臂自然垂落、膝盖微屈（4.0°±1.2°）带 root 微起伏；解析式正弦，首尾帧完全一致（姿态差 0.000000°） |
| `RollLeap` | 1–11 | 0.417 s | 单次 | ⛔ **已停用**：原地腾空前滚翻（0.22 m 腾空弧 + 全身 −360°）。翻滚已被**前冲/后撤闪避**取代（键位让给 Shift），动画仍留在 GLB 里只是为了不改导出流程，`player.gd` 已不再引用 |
| `Slash` | 1–13 | 0.500 s | 单次 | 举剑过顶 → 前下劈；命中窗 0.13–0.30 s 即剑刃最快段（**连击第 1 段**） |
| `Slash2` | 1–11 | 0.417 s | 单次 | **连击第 2 段 · 右手横斩**：起手在身体右上方 → 由右向左扫过身前（剑尖在 f3 偏右、f6/f8 偏左），收招回站姿。命中窗 0.12–0.30 s（剑刃角速度 >峰值一半的区间换算，峰值 2431°/s @f5）；**首末帧回到中立站姿**，所以能从 Slash 的任意时刻"掐掉后摇"直接接上而不跳帧 |
| `Slash3` | 1–15 | 0.583 s | 单次 | **连击第 3 段 · 转身回旋 + 举剑过顶下劈（收尾）**：root 绕 Y 转 360°（**净位移 0** —— 转一圈回到原朝向）→ 剑由右向左→向上→向前下劈。命中窗 0.16–0.42 s（峰值 3582°/s @f7，三段里最快最狠）；首末帧同样回到中立站姿。★ 这段**没有后摇取消点**，是连击的代价 |
| `Hurt` | 1–9 | 0.333 s | 单次 | **受击后仰**：髋 +7° / 胸 +10° / 头 +16°、双臂向后甩，随后回位（f9 回到站姿） |
| `JumpStart` | 1–9 | 0.333 s | 单次 | *（已停用）* 起跳：蹲身（root 自动降到 −0.17 m）→ 爆发 → 踮脚离地。★ **2026-09-21 起跳动画已取消**：游戏里不再播放这段（跳跃改为"按一下立即离地"），但动画本身仍留在 GLB 与 `animations/` 里 —— 把 `jump_prep_time` 调回 >0 就会重新用上 |
| `JumpAir` | 1–13 | 0.500 s | ✅ 循环 | 悬空：收腿 + 双臂外展平衡；首尾帧完全一致 |
| `Block` | 1–7 | 0.250 s | 单次 | **格挡起手**：从站姿把剑举到身前横挡（双手护住 + 重心微沉） |
| `BlockHold` | 1–25 | 1.000 s | ✅ 循环 | **举剑待机**：保持防护架势，带细微呼吸起伏；首尾帧完全一致 |
| `BlockImpact` | 1–9 | 0.333 s | 单次 | **挡下顿挫**：被挡瞬间手臂被压回一点再弹回防护架势 |
| `Execute` | 1–25 | 1.000 s | 单次 | **处决三段**：举剑（f5）→ 前刺（**f9 = 命中帧**）→ 上划撩开（f17）→ 收招（f25） |
| `Death` | 1–14 | 0.542 s | 单次 | **倒地**：膝盖发软下坠（f5）→ 前扑（f9 root −25° / f12 −65°）→ 躺平（f14 root −90°）；末帧定住**不复位** |
| `WalkStrafeLeft` | 1–25 | 1.000 s | ✅ 循环 | **向左侧移**（锁定中按 A）：两腿只**横向开合**、永不交叉；f7 前导腿（左）腾空并向左外展、f13 双脚着地张到最大（±18°）、f19 后随腿（右）腾空内收跟上来。前后漂移仅 0.018 m（Y/X = 0.10）—— 是横着走，不是前后迈步 |
| `WalkStrafeRight` | 1–25 | 1.000 s | ✅ 循环 | **向右侧移**（锁定中按 D）：`WalkStrafeLeft` 的**严格镜像**（`mirror_pose()` 生成，逐帧 foot.L/foot.R 数值对调后完全相等） |
| `WalkBack` | 1–25 | 1.000 s | ✅ 循环 | **后撤**（锁定中按 S）：沿用 `Walk` 的 9 相位腿表（幅度 ×0.85）+ 躯干改成**后仰**；前脚掌先落地，Y/X = 12.75（前后为主，本来就是"倒退走"） |
| `DodgeForward` | 1–10 | 0.375 s | 单次 | **前闪**（按 Shift + 任意方向键；身体会先转向那个方向）：后腿蹬直、躯干明显前压、剑向前探出。落地即收招，**无净位移**（位移由 `player.gd` 给，见 `dodge_forward_speed`） |
| `DodgeBack` | 1–12 | 0.458 s | 单次 | **后闪**（单按 Shift，不按方向键；朝身体正后方、不转身）：**剪式腿** —— 前膝抬起、后腿向后伸出去撑地，躯干后倾；读起来是"向后跳开一步"而不是"坐下来"。同样**无净位移** |

### 连击三段怎么配合（`player.gd` 的 ATTACK 状态）

左键点一下 = 第 1 段；**在取消点之后**再点 = 掐掉剩余收招、接下一段。三段各自有自己的时长 / 判定窗 / 伤害：

| 段 | 动画 | 时长(`*_total`) | 判定窗 | 取消点 | 伤害 | 播放倍速(现算) |
| --- | --- | --- | --- | --- | --- | --- |
| ① 挥砍 | `Slash` | 0.500 s | 0.17–0.28 s | `combo_cancel_1` **0.30 s** | 25 | 0.542 ÷ 0.500 ≈ **1.083** |
| ② 横斩 | `Slash2` | 0.417 s | 0.12–0.30 s | `combo_cancel_2` **0.28 s** | 30 | 0.458 ÷ 0.417 ≈ **1.100** |
| ③ 回旋收尾 | `Slash3` | 0.583 s | 0.16–0.42 s | **无（不可取消）** | 40 | 0.625 ÷ 0.583 ≈ **1.071** |

> ★ **为什么取消点都卡在"判定窗末端之后一点点"**：这样"打到就能接下一刀"，
> 而不是"刚抬剑就被允许接"—— 后者会让连击变成无脑连点。
>
> ★ **第 3 段刻意不可取消**：它是收尾重击，必须站着把 0.583 s 的长后摇演完，
> 这段被对手惩罚的窗口就是"贪连击"的代价。
>
> ★ **三段总伤害 25+30+40 = 95 < 满血 100**：一次完整连击打不死任何敌人，
> 最后仍要补一刀 —— 与"处决 75 之后留恰好一刀的量"是同一条设计原则。
>
> ★ **判定位移全在手臂/根骨骼上，没有净位移**：`Slash2` 用髋/胸的偏航来表达横扫
> （root 不动），`Slash3` 的 root 绕 Y 转 360°（转一圈回来 ≡ 0）。
> 所以接段时角色**不会跳位置**，自动测试里有"首末帧 == 中立站姿（姿态差 0.000000°）"的守卫。
>
> ★ **两端动作都是"由右向左"**：这两段的设计意图就是"顺着第 1 段劈下去的方向继续甩"，
> 所以第 3 段才用"转身一圈"把方向重新兜回来 —— 三段连起来是一道完整的弧。
>
> ⚠️ 改动画帧区间 → `length` 变 → 上表倍速与 `combo*_total` 都要重算；
> `animations/*.tres` 记得重跑 `tools/split_player_animations.gd`。

### 闪避两段怎么配合（`player.gd` 的 DODGE 状态）

按 **Shift** 进入 `DODGE`。★ **播哪一段只看"有没有移动输入"**：

| 情况 | 播哪段 | 身体朝向 | 位移方向 | 参数 |
| --- | --- | --- | --- | --- |
| **按着任意方向键**（W/A/S/D 任一） | `DodgeForward` | ★ **先转向**按键指向的方向 | 顺那个方向冲出去 | `dodge_forward_time` 0.375 s × `dodge_forward_speed` **14.0** m/s ≈ **4.0 m** |
| **单按 Shift**（不按方向键） | `DodgeBack` | 不变（不转身） | 身体正后方 | `dodge_back_time` 0.458 s × `dodge_back_speed` **8.7** m/s ≈ **3.0 m** |

> ⚠️ ★ **距离 = 速度 × 0.725 × 时长**，别只看 `speed` 的数字。
> 速度曲线是"起步满速 → 末段衰减到 45%"，它的**时间均值是 0.725**，不是 1.0。
> 旧值 6.6 / 4.8 看着不小，实际只能挪 **1.8 / 1.6 m** —— 2026-09-20 用户反馈"闪避距离太小"，
> 一算才发现是这句乘法没算。现按目标距离反推成 14.0 / 8.7（实测 **4.02 / 3.01 m**，自动测试钉住 ±20%）。
>
> ⚠️ **方向规则改过一版**：初版是"有 W 才前冲、其余一律后撤"，于是 A/S/D+Shift 全变成后撤，
> 想往左拉开必须先转镜头；现版改成"有输入 = 朝那个方向前闪"，并且**真的转身**。
> ⚠️ **锁定时也照转**（用户明确要求）：`_face_lock_target()` 只在 MOVE / BLOCK 里被调用，
> DODGE 期间没人把朝向拉回去 —— 所以只是"朝向被借走几帧"，**锁定状态与白点标记都不受影响**，
> 闪避结束回 MOVE 时锁定会把朝向拉回敌人（由 `lock_toggle_probe` 的 T10 钉住）。
>
> ⚠️ **闪避动画不带净位移**，位移全靠代码的速度曲线。
> 这样"闪多远"是**一个数**（`dodge_*_speed`），调手感不用回 Blender 改动画；
> 代价是脚步会和地面有一点滑，等 M2 补 **Run / Dodge** 系列时再按实际速度反算动画长度。
>
> 倍速一律**现算** = `动画 length ÷ 对应时长`：`DodgeForward` 0.4167 ÷ 0.375 ≈ **1.111**、
> `DodgeBack` 0.500 ÷ 0.458 ≈ **1.091**（`length` 比"内容时长"多半帧，是老约定，见「帧偏移」一节）。

### 格挡三段动画怎么配合（`player.gd` 的 BLOCK 状态）

按住**鼠标右键**进入格挡，松开立刻收招。三段动画由 `_block_play()` 按时序调度：

```
按下 ──▶ Block(起手 0.25s) ──▶ BlockHold(循环，一直举着)
								   │
						 挡下攻击 ──┴──▶ BlockImpact(顿挫 0.33s，插播) ──▶ 回到 BlockHold
```

| 阶段 | 触发 | 时长来源 |
| --- | --- | --- |
| `Block` | 按下的瞬间 | 固定 0.25 s（播完自动切 `BlockHold`） |
| `BlockHold` | 起手播完 / 顿挫演完 | 循环到松手 |
| `BlockImpact` | `take_damage` 被挡下的瞬间 | 占用 `block_impact_hold` = 0.22 s，之后回到 `BlockHold` |

> ⚠️ **`BlockImpact` 只占 0.22 s 而动画有 0.33 s**：这是故意的——顿挫的"被压回"那一下
> 在动画前段就演完了，后面是缓慢回位；0.22 s 切回循环并用 0.1 s 交叉淡入，看起来更脆。

### 格挡的玩法数值（都在 `player.gd` 顶部的 `@export` 里，编辑器可实时调）

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| `block_damage_reduction` | `0.7` | 普通格挡减伤比例（只吃 30% 伤害，且至少吃 1 点 —— 不是无敌） |
| `perfect_parry_window` | **`0.45`** | 按下后的完美格挡窗口（秒）。沿革 `0.15` → `0.22` → `0.45`：放宽是安全的，因为"一次按住只给一次完美判定"兜住了上限（不会退化成"按住右键就无敌"） |
| `block_guard_angle` | `120.0` | 正面格挡锥形张角（度）；背后/侧后攻击挡不住、吃满伤害 |
| `block_move_scale` | `0.3` | 格挡时的移动速度倍率（举着剑只能挪步） |
| `block_parry_stagger` | `0.8` | 完美格挡把敌人弹进硬直的时长（秒），传给 `enemy.deflect()` |

- 完美格挡 = 窗口内挡下 → **0 伤害** + **黄光特效** + 攻击者 `STAGGER` 0.8 s（普通受击只有 0.4 s）→ 反击窗口；
  同时给**攻击者的失衡条**加一截（数值在敌人侧 `parry_poise_percent`，守卫 34% → 3 次失衡）
- 一次**按住**只给一次完美判定；窗口过了继续按住只是普通格挡
- 格挡中不能攻击 / 闪避 / 跳跃；被打进硬直后若右键仍按住会自动重新举剑（但不白送完美窗口）

### 处决（`player.gd` 的 `EXECUTE` 状态）

**专属动画 `Execute`**（2026-09-20 新增，由 `E:\blender\blenderproject\player_knight\scripts\execute_anim.py` 生成）：
**举剑 → 前刺 → 上划 → 收招**，25 帧 / 1.000 s。
- 三段各有明确剪影：先亮剑让玩家看清要动手了（f5）→ 刺入（**f9 = 命中帧**）→ 向上撩开（f17）→ 收招（f25）
- 姿势不是手掰角度，而是沿用本工程 `block_ik.py` 的做法：先定"腕关节该在世界哪个点"，
  再用带软约束的网格搜索反解 `(upperarm.R rx/rz, forearm.R rx)`，最后解 `weapon.R` 让刃向对准目标
  （实测：腕残差 ≤ 0.089 m、刃向偏差 ≤ 0.01°）
- 解算结果**固化在脚本顶部的 `SOLVED` 字典**里 → 重跑即可复现同一段动画，不会因为求解抖动而跑偏
- 预览：`docs/preview_execute_anim_1_raise.png` / `_2_thrust.png` / `_3_slash.png`（Blender 侧原稿），
  `docs/preview_execute_1_windup.png` / `_2_impact.png` / `_3_slash.png`（引擎内实拍）
- 万一换模型时缺了这段，`player.gd` 会依次退回"慢放 `Slash`"→"全身姿态三段式"，不会没有演出

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| `execute_damage` | `75` | 处决基础伤害。**大量但不致命**：满血 100 的守卫剩 25 = 正好一刀补掉；敌人侧再乘 `execute_damage_scale` |
| `execute_range` | `2.6` | 触发处决的水平距离（米） |
| `execute_time` | `1.0` | 处决整段动作时长（秒）= `Execute` 的内容时长 → 默认 1.0 倍速播放 |
| `execute_hit_time` | `0.32` | 判定时刻（秒）= `0.32 × execute_time`，对齐动画第 9 帧的前刺（**改动画命中帧要同步改**） |
| `execute_approach_speed` | `7.0` | 处决时自动贴近目标的移动速度（米/秒） |
| `execute_anim_speed` | `0.0` | 处决动画倍速：**0 = 自动**（`length ÷ execute_time`），>0 = 手动固定 |

- 触发方式：**左键**。面前 2.6 m 内有**失衡(BROKEN)** 的敌人时左键变成处决，否则仍是普通挥剑
- 处决全程 `health.invincible = true`（不会被杂兵打断）；整段 1.0 s 比普通挥砍的 0.5 s 长一倍，
  怪堆里无脑处决会在收招时挨打 —— 这就是"无敌"换来的代价
- 处决会调用敌人的 `execute()` + `poise.refresh_break()`，把失衡倒计时顶回满，演出不会被打断
- ★ 敌人**扛住**这一击后（非致命！）由 `_end_execute()` 调 `enemy.end_break_after_execution()`
  收掉失衡 → 敌人爬起来。**不能省这一步**：否则玩家能原地连按左键无限连处决（还全程无敌）
- 动作时刻会迸一次更大的 `HitFlash` 金爆闪（`scripts/effects/hit_flash.gd`）

### 生活三段（Idle / 受击 / 死亡）

2026-09-20 补齐，替换掉原先 `player.gd` 里的三种"权宜做法"（待机用绑定姿势 = 木头人、受击用整体后仰、死亡用整体前栽）。
三段由 `E:\blender\blenderproject\player_knight\scripts\life_anim.py` 生成。

| 状态 | 动画 | 接入点 | 兜底（缺动画时） |
| --- | --- | --- | --- |
| 待机 | `Idle`（2.0 s 循环） | `_animate_model` 的 MOVE 分支：速度 ≤ 0.5 时播，0.15 s 淡入 | 绑定姿势 + `_anim_to_rest()` |
| 受击 | `Hurt`（0.333 s 单次） | `_enter_hurt()` 立刻播，**倍速 = `length ÷ hurt_time`**（现算，改 `hurt_time` 不用改动画） | 整体后仰（`_pivot.rotation.x` 正角） |
| 死亡 | `Death`（0.542 s 单次） | `_die()` 立刻播，**倍速 = `length ÷ death_time`** | 整体前栽 −90° |

- ★ **死亡是唯一"不复位"的动画**：`Death` 播完骨骼冻在躺平那帧（自动测试有断言钉住"尸体未复位"），
  所以 `_animate_model` 的 DEAD 分支只**清掉脚本姿态**、不调 `_anim_to_rest()`。其余状态停播后都要复位绑定姿势
- ★ **`root` 骨骼绕 X 轴 −90°** 就是"全身前扑躺平"：`root` 的绑定姿势旋转是单位、骨骼头在原点，
  所以它的局部轴 == 世界轴，直接转它 = 整体翻倒（这也是本工程第一次给 `root` 加**旋转**通道，
  之前 9 段动画只动 `root` 的**位置**）
- ⚠️ 倒地时**手臂要自然垂在身侧**：早期版本手臂前伸（`ua_rx=30`），绕 X 轴翻转 90° 后直接插进地面，
  最低顶点掉到 −0.30 m；改成垂臂 + 手肘微屈 + `foot_extra≈-70`（绷脚背）后，每个关键帧最低顶点都 = +0.005 m（贴地不穿地）
- ⚠️ 生成脚本里 `solve_root_z()` 用二分搜索反解 root 高度使"最低顶点贴地"，
  搜完会自检残差 > 2 mm 就打印 `⚠ root.z 未收敛`（就是上面这个坑逼出来的保险）
- 预览：`docs/preview_anim_idle.png`（呼吸峰值）、`docs/preview_anim_hurt.png`（后仰峰值）、
  `docs/preview_anim_death_1_fall.png`（前扑中）、`docs/preview_anim_death_2_landed.png`（躺平定住）——
  引擎内实拍，由 `tools/life_capture/life_capture.tscn` 逐帧渲染

### 锁定侧移三段（WalkStrafeLeft / WalkStrafeRight / WalkBack）

2026-09-20 随"锁定敌人"（点一次鼠标中键开启、再点一次关闭）一起加的三段。**为什么必须有它们**：锁定后身体要一直面朝敌人，
此时 A/S/D 是"相对敌人的横移/后撤"，再复用 `Walk`（朝移动方向走的动画）会让**身体朝向和移动方向打架**。
三段由 `E:\blender\blenderproject\player_knight\scripts\strafe_anim.py` 生成。

| 状态 | 动画 | 接入点 | 兜底（缺动画时） |
| --- | --- | --- | --- |
| 锁定 + A | `WalkStrafeLeft` | `_locomotion_clip()` 把 `_wish_dir` 投到角色右轴为**负** → 选它 | 退回 `Walk` |
| 锁定 + D | `WalkStrafeRight` | 右轴投影为**正** → 选它 | 退回 `Walk` |
| 锁定 + S | `WalkBack` | 前轴（模型 −Z）投影为负 → 选它 | 退回 `Walk` |

- ★★ **侧移是"横向开合"、不是"前后迈步"** —— 这是整段读不读得对的关键，也是做这段时唯一踩的坑：
  一开始只加屈膝不给髋补偿，脚被甩到**身后**（屈膝 36° → 脚后退 0.23 m，而抬脚只有 0.12 m），
  渲出来是**弓步劈叉**、完全不像侧移。
  修法是 `planted_hip()`：**髋角 = −0.494 × 屈膝角**（比例 = 小腿长 ÷（大腿长 + 小腿长），由骨架**实测**推得），
  让摆动腿"**原地抬膝**"而不是往后蹬。修完后摆动脚的前后漂移只剩 0.018 m
- ★ **判据别靠肉眼盯渲染图，直接量**：`scripts/probe_foot_travel.py` 打印两只脚的 X/Y 行程比 ——
  侧移 `Y/X ≈ 0.06~0.10`（左右为主）、`Walk` `Y/X ≈ 8.3`、`WalkBack` `Y/X ≈ 12.8`（前后为主）。
  这一个比值就能立刻看出"侧移其实在前后迈步"
- ★ **右移完全由左移镜像生成**（`mirror_pose()`：左右骨骼互换 + `ry/rz` 取反、`rx` 保持），
  **不手写第二份表** —— 手写两份必然出左右符号错（第一版就是"反镜像"）。生成脚本里有三条自检：
  镜像差、镜像对合、循环闭合，都必须是 `0.000000°`
- ⚠️ 侧移的**脚掌横向补偿**：`foot.rz = -thigh.rz`，保证外展时**脚尖仍然朝前**（不跟着腿外八）
- ⚠️ **抬腿相位**：摆动相权重必须取"横向速度为正的那半程"（脚本里用 `max(0, ±sin)` 配 `1-cos` 的开合量）。
  第一版用同一个 `sin` 当开合量与抬腿权重，**相位差了 1/4 周期** → "该落地的腿在抬、该抬的在踩"
- ⚠️ **识别顺序**：`WalkStrafe*` / `WalkBack` 的名字里都含 `walk`，`player.gd` 的识别链里必须
  **排在裸 `walk` 之前**，否则 `_walk_anim` 会被后出现的名字覆盖（自动测试有断言专门守这条）
- 预览：`strafe_left_13_open.png`（开到最大的站姿，正视）、`strafe_left_07_lead_lift.png`、
  `strafe_left_side_07/19.png`（侧视：看摆腿是原地抬膝而非后甩）、`strafe_right_13_open.png`、
  `walk_back_side_07.png`；引擎内实拍 `lockon_00~03_*.png` 见上方目录结构表，
  `lockon_04_marker_body_center.png` / `lockon_05_marker_zoom.png` 是**锁定标记**（敌人身体中心的白色亮点）

### 位移约定（接入代码时必须知道）

- **所有动画都不含净水平位移**：前进/冲刺/跳跃弧线由 `player.gd` 的速度逻辑负责，避免播放结束后角色残留偏移。
- `JumpStart` 的 root 高度是"双脚贴地"约束自动反解出来的（脚不穿地也不悬空）；`Walk` 的 root 起伏同样由地面接触约束生成。
- 格挡三段同样不含位移：`Block`/`BlockHold`/`BlockImpact` 的 `root` 只做约 −0.05 m 的下沉（举剑时重心压低），水平位移为 0。
- 动画只驱动骨骼姿势，切换动画不会改变角色位置。

## 在 Godot 里怎么用

```gdscript
# 模型挂到 Player 下后（导入场景内含 AnimationPlayer）
@onready var anim: AnimationPlayer = $PlayerKnight/AnimationPlayer

# 行走（循环）：速度 > 阈值时播放；注意 Walk 为原地动画，位移由代码给
anim.play("Walk")

# 闪避 / 攻击
anim.play("DodgeForward")   # 倍速 = 动画时长 ÷ player.gd 的 dodge_forward_time（按 Shift + 任意方向键）
anim.play("DodgeBack")      # 同上，对 dodge_back_time（单按 Shift，不按方向键）
anim.play("Slash")      # 命中窗 0.13–0.30s，与 attack_active_start/end 对齐

# 跳跃：按一下立即离地 → 循环悬空 → 落地回 Idle/Walk
# ★ 2026-09-21 起跳动画已取消：不再 play("JumpStart")，只播这段滞空循环
anim.play("JumpAir")
# （想把两段式起跳找回来：把 player.gd 的 jump_prep_time 调回 0.18，
#   原先的等价写法是 anim.play("JumpStart") + anim.queue("JumpAir")）

# 格挡（按住右键）：起手 → 循环举剑；被挡下时插播顿挫
# 实际由 player.gd 的状态机统一调度，这里只是"手动播"的等价写法
anim.play("Block")            # 起手 0.25s
anim.queue("BlockHold")       # 之后一直举着（循环）
anim.play("BlockImpact")      # 挡下攻击时插播（会自动回到 BlockHold）

# 生活三段：站住 → Idle 呼吸循环；挨打 → Hurt；阵亡 → Death（末帧定住不复位）
anim.play("Idle")             # 站住时循环（速度 ≈0）
anim.play("Hurt")             # 受击硬直，倍速 = length ÷ player.hurt_time
anim.play("Death")            # 倒地，倍速 = length ÷ player.death_time
```

## 重新生成

- `animations/*.tres`：在项目根目录运行
  `Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tools/split_player_animations.gd`
- `player_knight.glb`：在 Blender 打开 `E:\blender\blenderproject\player_knight\knight-player.blend`
  → File → Export → glTF 2.0 (.glb，勾选 Animation) → 覆盖本目录同名文件

### ⚠️ 覆盖 GLB 之后**必须**重新导入，否则引擎还在用旧的缓存

```powershell
# 强制重新导入（resource 变了但 .godot/imported 里还是旧 scn）
Godot_v4.7.2-stable_win64.exe --headless --path . --import
```

【为什么】Godot 的导入产物缓存在 `.godot/imported/player_knight.glb-<hash>.scn`，
而**非编辑器运行（`--headless <scene>` / `--script`）不会自动重新导入**。
直接跑测试/游戏会拿到上一次导入的旧动画列表，表现为"新加的动画一个都认不出来"
（本项目真踩过：GLB 里明明有 12 段动画，测试却报 5 段、格挡断言全红）。
判据：对比 `player_knight.glb` 与 `.godot/imported/player_knight.glb-*.scn` 的修改时间。
建议随后跑一次 `tools/split_player_animations.gd`，把新动画同步进 `animations/*.tres`。

## 自动化测试

```powershell
Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/autotest/m1_autotest.tscn
```

退出码 0 = 全部通过（当前共 **305 条断言**）。另有**独立的输入边沿对抗性探针** `tools/autotest/lock_toggle_probe.tscn`（62 条断言），覆盖长按中键只翻转一次、仅松开不解锁、奇偶翻转、范围外点击不自锁、目标销毁 / 死亡退化与重找等边界。相关断言覆盖：
Idle/Hurt/Death 三段生活动画的识别 + 时长（设计时长 + 1/24）+ 循环开闭 + 播放倍速（`get_playing_speed()`）+ 
Idle 首尾帧姿态闭环（差 < 0.02 rad）+ 死亡末帧**不复位**（尸体定住，root 俯角 > 60°）、
**闪避两段**（有方向键 = `DodgeForward` 且**转向该方向**、单按 Shift = `DodgeBack`；
时长符合"设计时长 + 1/24"约定、倍速铺满状态时长、
**前闪位移 ≈ 4.0m / 后闪 ≈ 3.0m**（距离断言）、后闪不改朝向）、
**完美闪避**（无敌帧内不吃伤害、一次闪避只认一次、子弹时间 1.00 → 0.35 → 回 1.00、
残影数量、残影材质四条硬指标：半透明/加法混合/不受光/关深度测试 + 起始不透明度 < 1（叠加混合裁纯白）、
播完后全部自毁）、
三段格挡动画识别 + 时长符合"设计时长 + 1/24"约定、角色 GLB 网格数 = 5（剑未烘进角色）、
进入/退出格挡、格挡中禁攻击/闪避、普通格挡按比例减伤、挡下不硬直、背后攻击吃满伤害、
硬直后自动重新举剑、完美格挡 0 伤害 + 敌人 0.8 s 硬直 + **黄光特效**、
**失衡条累积（按百分比）/ BROKEN 不可出手 / 失衡窗口不被多余格挡取消 /
HUD 黄条 / 处决全流程（EXECUTE + 无敌 + `Execute` 动画段与时长 + 判定帧对齐前刺帧 +
伤害远高于普通挥砍 + **不是秒杀** + 演出后收掉失衡防无限连）/ 特效播完自毁**、
**锁定侧移三段**：`lock_on` 绑鼠标中键、三段动画识别正确且**没有覆盖掉 `_walk_anim`**、
三段时长/循环、点一次中键锁定最近敌人、锁定后身体转向敌人（角度误差 < 12°）、
选段映射（自身左/右/前/后 → 侧移/侧移/Walk/后撤）、端到端横移播的是侧移段、
锁定降速（实测 6.14 → 2.53 m/s）、目标被销毁后自动退化为未锁定、再点一次中键解除（仅松开不解除）、
**受击不改面朝向（转了 0.0000 rad）+ 立刻获得朝后的击退速度（≈ `knockback_strength`）**、
**锁定标记 `LockMarker`**：挂在锁定目标下、位置 = `站高 × 0.5` 的身体中心（实测局部 y=1.330）、
水平居中且在竖直轴线上、世界高度落在躯干范围、是白色、**已关闭深度测试**（否则被躯干挡死）、
加法混合 + 不受光照、场景里**同时只有一个**（防"每帧重造"）、解除锁定与目标销毁两条路径都收干净。
