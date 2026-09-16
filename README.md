# FirstGame — 第三人称 3D 动作游戏（M1 垂直切片）

用 Godot 4.7 开发的第三人称动作游戏。当前为 **M1 可玩垂直切片**：移动/翻滚/近战攻击手感验证阶段，全部美术为引擎原语占位。

运行效果预览：`docs/preview_m1.png`（蓝色小机器人=玩家，红色壮汉=敌人，屏幕中央小白点=准星）

## 环境

- Godot **4.7.2 stable**：`D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
  （编辑器也可直接双击 `Godot.lnk` 或用该 exe 打开本目录的 `project.godot`）
- Blender 5.2.1 LTS（`E:\blender\blender.exe`）：预留的建模管线，M2 起用于正式角色/场景

## 如何运行

1. 用 Godot 打开 `D:\GodotProject\first-game\project.godot`
2. 打开场景 `scenes/main/main.tscn`（或直接按 **F6** 运行当前工程的主场景）
3. 试玩

### 操作

| 输入 | 动作 |
|---|---|
| WASD / 方向键 | 移动（相对镜头方向） |
| 鼠标 | 环绕视角（点击窗口可重新捕获鼠标） |
| 左键 | 近战挥砍 |
| Shift | 翻滚（全程无敌帧） |
| 空格 | 跳跃（按住跳更高 ≈1.2m，轻点小跳 ≈0.6m） |
| Esc | 释放/捕获鼠标 |
| R | 重新开始（死亡后也可用） |

## M1 包含

- ✅ 第三人称自由追尾镜头（鼠标环绕、平滑跟随、墙体避让）
- ✅ 角色状态机：移动 / 翻滚(无敌) / 攻击 / 受击硬直 / 跳跃 / 死亡
- ✅ 跳跃：可变跳跃高度、土狼时间(0.12s)、跳跃缓冲(0.15s)、空中操控、落地压缩反馈
- ✅ 敌人"红甲守卫"AI：索敌 → 追击 → 蓄力预警 → 挥击 → 恢复（可打断）
- ✅ 战斗循环：攻击判定、受击闪白、击退硬直、击杀
- ✅ 有边界竞技场（围墙 + 立柱）、天空光照
- ✅ HUD：玩家血条、敌人血条、准星、提示消息、死亡遮罩
- ✅ 敌人 3 秒重生、玩家 R 重开

## 目录结构

```
project.godot            # 引擎配置（3D 渲染 / Jolt 物理 / 主场景 / autoload）
scenes/
  main/main.tscn         # 主场景（程序化构建环境 + 生成管理）
  player/player.tscn     # 玩家（胶囊碰撞 + Health）
  enemy/enemy.tscn       # 红甲守卫
  camera/camera.tscn     # 追尾镜头
  ui/hud.tscn            # HUD
scripts/
  autoload/input_setup.gd      # 运行时输入映射（WASD/攻击/翻滚…）
  components/health.gd         # 通用生命值组件
  player/player.gd             # 玩家状态机 + 程序化原语角色
  enemy/enemy.gd               # 敌人 AI 状态机
  camera/third_person_camera.gd# 镜头
  ui/hud.gd                    # HUD 构建与更新
  main/main.gd                 # 主场景逻辑
docs/GAME_DESIGN.md       # 设计文档与后续方向
```

## 已知限制（M1 有意为之）

- 角色视觉在运行时用原语网格拼装（编辑器场景预览看不到模型，运行即可见）
- 输入动作用代码注册（Input Map 面板不可见），M2 迁移为正式项目配置以支持改键
- 无音效 / 打击特效 / 锁定 / 连击——属于 M2 打磨内容

## 验证方式（命令行）

冒烟测试（加载主场景跑 240 帧）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game --quit-after 240
# exit=0 且无 SCRIPT ERROR 即通过
```

战斗闭环自动化测试（含玩家模型/翻滚动画/翻滚位移等 22 项断言，exit=0 即全过）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game 'res://tools/autotest/m1_autotest.tscn'
```

## 动画 QA 工具（tools/）

| 工具 | 用途 |
|---|---|
| `tools/inspect_model.gd` | 打印 GLB 的节点树/骨骼/动画列表与时长 |
| `tools/inspect_anim.gd` | 打印某条动画的每条轨道与关键帧数值（看清位移/旋转幅度） |
| `tools/anim_capture/roll_capture.tscn` | 自动触发一次翻滚，配合 `--write-movie` 抓帧 |
| `tools/anim_diff.gd` | 逐帧比较抓帧的"运动量"曲线，判断动画是否真的在播 |

抓帧示例：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path D:\GodotProject\first-game 'res://tools/anim_capture/roll_capture.tscn' --write-movie D:\GodotProject\first-game\.tmp_anim\frame.png
# 再分析： --headless --script res://tools/anim_diff.gd -- .tmp_anim
```

## 玩家模型与动画

- 模型：`assets/characters/player_knight/player_knight.glb`（**21 根骨骼的蒙皮模型**，5 段动画；Blender 源文件在 `E:\blender\blenderproject\player_knight\`）
- 资产说明见 `assets/characters/player_knight/README.md`；独立动画资源在 `animations/*.tres`

| 动画 | 时长 | 循环 | 触发时机 | 播放倍速 |
|---|---|---|---|---|
| `Walk` | 1.04s | ✅ | 移动中（站住即停） | 当前速度 ÷ `walk_natural_speed`，上限 `walk_max_speed_scale` |
| `RollLeap` | 0.458s | 单次 | Shift 翻滚 | 动画时长 ÷ `roll_time` |
| `Slash` | 0.542s | 单次 | 左键攻击（判定窗 `0.17~0.28s` = 实测剑刃最快段） | 动画时长 ÷ `attack_total` |
| `JumpStart` | 0.375s | 单次 | **起跳蓄力段（仍在地面）**，播完才真正离地 | 动画时长 ÷ `jump_prep_time` |
| `JumpAir` | 0.542s | ✅ | 离地后直到落地 | 1.0 |

动画状态机要点（都在 `scripts/player/player.gd`）：
- 动画名按"小写 + 忽略下划线"匹配（`roll` / `walk` / `slash|attack` / `jumpstart|jumpup` / `jumpair|air|fall`），换模型/改动画名后无需改代码
- **循环必须显式打开**：glTF 没有循环标记，代码会把 Walk / JumpAir 设为 `LOOP_LINEAR`，否则只播一次就定住
- **骨骼复位**：骨骼动画一停播，骨骼会冻在停播那一帧（走到一半停下→僵在迈步中途；落地→僵在蜷腿姿势）。所以"没有对应动画"的状态（待机 / 受击 / 死亡 / 落地后）统一调用 `_anim_to_rest()` 把骨骼复位到绑定姿势，再由脚本叠加整体姿态与落地压缩
- **两段式起跳**：`JUMP_PREP`（地面蓄力，播 JumpStart）→ 蓄力结束才 `_launch_jump()` 给向上速度并切 `JUMP`（播 JumpAir）。这样蹬地动画不会在已经飞起来之后还在播
- 这套动画**不含净水平位移**（前进量由速度逻辑负责），所以翻滚不再需要"根位移过继"
- 骨架动画目前没有 Idle / 受击 / 死亡片段：待机用绑定姿势、受击用后仰、死亡用整体倒地；补上动画后可自动接入

## 武器（与角色分离）

- 武器资产：`assets/weapons/sword_01/sword_01.glb`（原点 = 握把中心、**刀身沿局部 -Z**）
- 挂载方式：`BoneAttachment3D` 挂在角色骨骼 `weapon.R` 上；换武器只需 `player.equip_weapon(场景)`，**角色模型与全部动画都不用动**
- 对齐规则：**握柄停在骨骼原点（拳心）、刀身沿骨骼 +Y（= 模型前方 / 身前）**
  - 实测 `weapon.R` 静止基：+Y ≈ 模型 −Z（前方）、+Z ≈ 模型 +Y（上方）、+X ≈ 模型 +X（右侧）——
    骨骼本身就是"沿 +Y 指向前方"的持械轴
  - 武器刀身沿自身 −Z，所以对齐 = 绕骨骼 X 轴 +90°（`WEAPON_ALIGN_LOCAL`），**实测结果：握柄偏差 0.000m、刀身与身前夹角 8°**
- ⚠️ 两个踩过的坑：
  1. **不能单位变换直挂**：那样刀身会沿骨骼 −Z 朝**下**（实测整把剑掉到 y≈−0.4）
  2. **不能照抄"武器分离前"的旧位置**：旧模型里剑是竖直朝上贴着**手臂**的，照抄会让刀身陷在手臂网格里（看起来像"嵌在手臂中"）
- 对齐偏移必须设在**武器子节点**上：`BoneAttachment3D` 自己的 transform 每帧会被引擎用骨骼姿态覆盖，设在挂点上无效
- 想换成"刃朝上/刃朝下"等其它握法：只改 `WEAPON_ALIGN_LOCAL` 一个常量即可（绕 X 轴 ±90° / 改 roll）
- 回归验证：`tools/check_weapon.tscn`（打印握柄↔拳心距离、刀身↔身前夹角、剑与手臂的包围盒）；自动测试含 6 项武器断言

## 命中判定窗是怎么定的

`attack_active_start/end` 不是拍脑袋写的：`tools/inspect_rig.gd` 会采样 Slash 动画里
`hand.R` / `weapon.R` 的角速度曲线，实测结果——

| 动画时间 | 段 | 角速度 |
|---|---|---|
| 0.00–0.16s | 举剑 | ≤ 90°/s |
| **0.18–0.30s** | **劈砍（判定窗）** | 峰值 **496°/s** @0.26s |
| 0.32–0.54s | 收招 | ≤ 375°/s |

换算到游戏时间（动画 0.542s ÷ `attack_total` 0.5s ≈ 1.083 倍速）即 **0.17~0.28s**。
复现命令：`godot --headless --path . --script res://tools/inspect_rig.gd -- <骑士glb> Slash`

## 跳跃手感参数（`scripts/player/player.gd` 顶部 @export）

| 参数 | 默认 | 作用 |
|---|---|---|
| `jump_velocity` | 7.4 | 起跳初速度；最高点 ≈ v²/(2g) |
| `jump_prep_time` | 0.18 | **地面蓄力时长**：先在地面播完 JumpStart 蹬地动作才离地；0 = 立即起跳(无蓄力) |
| `jump_cut_multiplier` | 2.0 | 上升中松开跳跃键的重力倍数 → 轻点=小跳 |
| `fall_gravity_multiplier` | 1.35 | 下落重力倍数 → 落地干净不飘 |
| `air_accel` | 9.0 | 空中水平操控（小于地面 accel → 跳跃有承诺感） |
| `coyote_time` | 0.12 | 土狼时间：刚离开地面仍可起跳 |
| `jump_buffer_time` | 0.15 | 跳跃缓冲：落地前提前按也算数 |
| `land_squash_time` | 0.18 | 落地压缩(视觉)时长 |
| `walk_natural_speed` | 1.0 | Walk 动画的自然步速(米/秒)，用于算播放倍速 |
| `walk_max_speed_scale` | 2.0 | Walk 播放倍速上限（见下方"已知取舍"） |

跳跃相关的设计取舍：
- 跳跃**不能取消**攻击/翻滚，攻击/翻滚/受击硬直中按跳跃无效（动作要有承诺感）
- 空中不能二段跳；空中也不能攻击、不能翻滚（M2 可扩展为空战）
- **起跳是两段式**：按下 → `JUMP_PREP` 地面蓄力 0.18s（播 JumpStart 蹬地）→ 真正离地进入 `JUMP`（播 JumpAir）。
  好处是蹬地动画与"离地"这一事件对齐；代价是起跳有 0.18s 预备。想更跟手就把 `jump_prep_time` 调小（0.10~0.15），
  想更有重量感就调大（0.20~0.28）；设为 0 则恢复"一按即起跳"（此时蹬地动画会来不及播完）。

## 已知取舍（动画相关）

- **滑步**：`move_speed = 6.2 m/s` 远高于 Walk 动画的自然步速（约 1.0 m/s），
  倍速上限 2.0 意味着跑动时腿部动作与地面仍有滑步。要彻底消除需要美术侧再出一段
  **Run**（步幅更大的循环），或把 `move_speed` 降到 3~4 更接近"重甲骑士"的感觉。
- 没有 Idle 动画：站住时是绑定姿势（静止站姿），看起来会有点"呆"。
