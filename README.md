# FirstGame — 第三人称 3D 动作游戏（M1 垂直切片）

用 Godot 4.7 开发的第三人称动作游戏。当前为 **M1 可玩垂直切片**：移动 / **前冲·后撤闪避(无敌 + 完美闪避)** / 近战攻击 / **格挡(减伤 + 完美格挡)** / **失衡条与处决** / 跳跃 / 受击死亡的手感验证阶段。
角色与敌人已换装 Blender 低模骨骼动画（源文件在 `E:\blender\blenderproject\`），场景仍为引擎原语占位；打击闪光特效（完美格挡 / 处决的黄光）为引擎内实时生成的纯原语特效。

运行效果预览（都在 `docs/`）：
- `preview_m1.png` —— M1 整体画面（蓝色小机器人=玩家，红色壮汉=敌人，屏幕中央小白点=准星）
- `preview_parry_flash_1.png` / `preview_parry_flash_2.png` —— **完美格挡的黄光特效**（亮核 → 扩散金环 + 地面被照亮），右上角可见黄条已涨一截
- `preview_poise_broken.png` —— **失衡成立**：敌人血条下方黄条变亮金并拉满，提示"走近按【左键】处决"
- `preview_execute_1_windup.png` / `preview_execute_2_impact.png` / `preview_execute_3_slash.png`
  —— **处决**三拍：举剑蓄力金光 → 前刺命中金爆闪 → 上划撩开
- `preview_execute_anim_1_raise.png` / `_2_thrust.png` / `_3_slash.png` —— 处决动画本体的三段姿势原稿（Blender 侧渲染，全身剪影更清楚）
- `preview_anim_idle.png` / `preview_anim_hurt.png` —— **待机**呼吸峰值、**受击**后仰峰值（引擎内实拍）
- `preview_anim_death_1_fall.png` / `preview_anim_death_2_landed.png` —— **倒地**：前扑中（root 前倾约 45°）→ 躺平定住（尸体不复位）
- `preview_combo_poses.png` —— **三段连击九宫姿势条**（三段各取 起手/挥出/收招）：1 段举剑过顶→横扫至腰、2 段右手横斩、3 段回旋后过顶下劈，一眼看出三段**剪影互不相同**
- `preview_combo_chain.gif` —— **整套三段连击动图**（引擎内实拍）：能直接看出"第 2/3 段是在前一段后摇里被掐出来接上的"、以及命中那一下的**顿帧定格**（横条看不出节奏，所以补了动图）
- `preview_jump_instant.gif` —— **跳跃（起跳动画已取消后）**：按一下立即离地、直接进滞空循环。这一版专门用来确认"从站立直接切到 `JumpAir` 不会硬切"——实测 `JumpAir` 起始几帧贴近站立姿势，收腿是随后 1~2 帧演进去的
- `preview_execute_cine.gif` —— **处决特写分镜动图**（引擎内实拍一次真实处决）：演员一动机位就跟着走（**相对取景**），三刀之间是**硬切** —— 0.00 全景交代 → 0.32 命中（过肩近景 + 慢动作）→ 0.62 拉回收招，全程上下**遮幅黑边**。★ "切镜"这件事只存在于帧与帧之间，静态图上根本读不出来，所以给了 GIF
- `preview_execute_cine_poses.png` —— **分镜三刀代表帧横条**：用来确认三刀的**取景互不相同**、且第 2 刀近景能读出"剑砍进敌人"（GIF 看**切镜节奏**、横条看**逐刀取景**）
- `lockon_04_marker_body_center.png` / `lockon_05_marker_zoom.png`（在 `assets/characters/player_knight/previews/`）
  —— **锁定标记**：点一次中键锁定后敌人**身体中心**出现一颗白色亮点（右图为同一帧放大；近白像素实测 20×20 px、再点一次解除后 0 个）
- `preview_wolf_walk.gif` —— **狼的步态动图**（引擎内实拍）：站立 → 中速 trot（**2.5 m/s**）→ 全速 trot（**4.2 m/s**），正侧视看四足**对角步态**、以及"全速下步子够不够大"。★ 步态是"帧与帧之间"的东西，静态图上根本读不出来，所以用 GIF
  - ⚠️ **这张 GIF 已过时（2026-09-25）**：它是在 **方案 β 之前**抓的，而那正是 `_play_loop` 两层相乘的坑最显形的时候 —— 图上"全速"那一档的**实际步频是随机打折的**（同二进制量到过 1.0155 / 0.5704 / 2.4668 / 1.4096 等值），所以它**不能**用来论证"全速下步子够不够大"。β 之后 `get_playing_speed() ≡ speed_scale`，且狼 `move_speed` 已 4.2 → **3.4**，重跑一遍才有意义（`tools/anim_capture/wolf_capture.tscn`）
- `preview_wolf_combat.gif` —— **狼的招式动图**（引擎内实拍）：`AttackWindup→Attack`（下蹲蓄力 → 前扑咬合，斜前 45°）→ `Hit` 受击 → `Death` 塌倒后**尸体停留约 1.29s 再消失**

> 前几张贴图由 `tools/fx_capture/fx_capture.tscn` 逐帧抓出来的，改完特效可以重跑一遍对比；
> 生活三张由 `tools/life_capture/life_capture.tscn` 抓（演"待机 → 挨打 → 阵亡"）。
> 锁定/侧移/标记由 `tools/lockon_capture/lockon_capture.tscn` 抓（演"未锁定横移 → 点一次中键 → A/S/D → 再点一次中键"）。
> 连击两张由 `tools/anim_capture/combo_capture.tscn` 抓（第一幕逐段采姿势 → 用 `tools/img_probe/grid.py`
> 拼成 `preview_combo_poses.png`；第二幕真一整套连击 → 用 `tools/img_probe/make_gif.py` 拼成 `preview_combo_chain.gif`）。
> 跳跃那张由 `tools/anim_capture/jump_capture.tscn` 抓 → `preview_jump_instant.gif`。
> 处决特写两张由 `tools/anim_capture/execute_cine_capture.tscn` 抓（真跑一次处决、让分镜导演驱动相机）→ 取关键帧用 `grid.py` 拼成 `preview_execute_cine_poses.png`、用 `make_gif.py` 拼成 `preview_execute_cine.gif`。
> 狼两张由 `tools/anim_capture/wolf_capture.tscn` 抓（真跑 `wolf.tscn`、相机每帧跟住狼、`--fixed-fps 30` 固定步长）→ `make_gif.py` 合成。
> ⚠️ 清单里所有 `docs/preview*` 预览图**已在 `.gitignore` 里忽略**（连同 `assets/**/previews/`）—— 仅为控制仓库体积：本地保留、仓库不带图，clone 下来看不到图时跑对应工具重出即可。

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
| 左键 | **三段连击**：点一下 = 第 1 段，在**后摇取消点之后**再点 = 接第 2 段（`Slash2` 横斩）、再点 = 第 3 段（`Slash3` 回旋收尾，**不可取消**）。**取消点之前**按的那一下会被**输入缓冲**记住、到点自动兑现；**面前有失衡的敌人时 = 处决**；每一段起手都会**自动朝向附近(3.5m / 正面 70°)的敌人**（近战修正，见下）；命中时触发**顿帧 + 镜头震动 + 打击音效**（见「三段连击」一节） |
| **右键（按住）** | **格挡**（减伤 70%、不硬直；按下的前 **0.45s** 挡下 = 完美格挡：0 伤害 + 黄光 + 敌人 0.8s 硬直 + 敌人失衡值 +34%） |
| **中键（点击切换）** | **锁定敌人**：身体始终面朝敌人，A/S/D 变成相对敌人的**侧移/后撤**（专用动画），镜头绕到背后正对敌人，**敌人身体中心出现一颗白色亮点**，移速 ×0.6。**点一次锁定、再点一次解除** |
| **Shift + 任意方向键** | **前闪**（0.375s / ≈**4.0m**，全程无敌）：身体**先转向**按键指向的方向再冲出去。W/A/S/D 分别朝前/左/后/右前闪 —— 不用先转镜头。**锁定时也照转**，闪避结束后自动转回敌人 |
| **Shift（单按，不按方向键）** | **后闪**（0.458s / ≈**3.0m**，全程无敌）：朝身体**正后方**跳开，且不改朝向 |
| *闪避无敌帧里被敌人挥击判定盒扫中* | = **完美闪避**：0 伤害 + 青蓝闪光 + 身后拖出 3 道角色残影 + **子弹时间**（全局 **0.45** 倍速 **0.25s** 后回升）+ HUD 青蓝闪屏。一次闪避只认一次完美判定 |
| 空格 | 跳跃（**按一下立即离地**，按住跳更高 ≈1.2m，轻点小跳 ≈0.6m） |
| **Tab / F（调试）** | **切换操控的角色**：玩家 ⇄ 红甲守卫循环。被操控者听你的键鼠（守卫：WASD 移动 + 左键挥棒，含 0.5s 蓄力），另一个原地站桩当陪练；镜头与 HUD 两条血条跟着换（详见 `scripts/debug/character_switcher.gd`） |
| Esc | 释放/捕获鼠标 |
| R | 重新开始（死亡后也可用） |

## M1 包含

- ✅ 第三人称自由追尾镜头（鼠标环绕、平滑跟随、墙体避让）
- ✅ 角色状态机：移动 / **闪避(无敌 + 完美闪避)** / 攻击 / **格挡(减伤 + 完美格挡)** / **处决** / 受击硬直 / 跳跃 / 死亡
- ✅ 跳跃：**按一下立即离地（起跳动画已取消，见下）**、可变跳跃高度、土狼时间(0.12s)、跳跃缓冲(0.15s)、空中操控、落地压缩反馈
- ✅ 敌人"红甲守卫"AI：索敌 → 追击 → 蓄力预警 → 挥击 → 恢复（可打断）
- ✅ **失衡条与处决**：完美格挡攒失衡（守卫 3 次）→ 敌人 BROKEN 站不稳 → 走近按左键处决（专属三段动画 + 全程无敌 + 大量但**不致命**的伤害 → 敌人爬起来，补一刀收尾）
- ✅ 战斗循环：攻击判定、受击闪白、击退硬直、击杀
- ✅ 打击闪光特效：完美格挡迸黄光、处决金爆闪（纯原语：亮球 + 扩散光环 + 点光源，播完自毁）
- ✅ **处决特写分镜**（镜头导演层）：处决命中那一刻镜头自动切至特写 —— 相对取景分镜表 + 三刀**硬切** + 上下**遮幅黑边** + 慢动作/震屏，演完**无缝交还**追尾（见「处决特写分镜」一节）
- ✅ **锁定标记**：锁定期间在敌人**身体中心**放一颗白色亮点（纯原语发光球，关深度测试所以透得过躯干；随敌人移动、脉动、解除即收）
- ✅ 有边界竞技场（围墙 + 立柱）、天空光照
- ✅ HUD：玩家血条、敌人血条 + **黄色失衡条**、准星、提示消息、完美格挡全屏金光、死亡遮罩
- ✅ 【调试】**角色切换器**：Tab/F 把操控权在"玩家 ⇄ 守卫"之间切换，可以直接用守卫的手感去撞判定（复用守卫自己的状态机/命中盒，测出来的就是它 AI 时的真实行为）
- ✅ **近战朝向修正（软锁定）**：攻击起手瞬间自动朝向附近最近的敌人（3.5m 内、镜头**或身体**前方 70° 锥；敌人在任一朝向的锥内即算 nearby），远距离与背后的敌人不抢朝向
- ✅ 敌人 3 秒重生、玩家 R 重开

## 目录结构

```
project.godot            # 引擎配置（3D 渲染 / Jolt 物理 / 主场景 / autoload）
scenes/
  main/main.tscn         # 主场景（程序化构建环境 + 生成管理）
  player/player.tscn     # 玩家（胶囊碰撞 + Health）
  enemy/enemy.tscn       # 红甲守卫（两足 + 武器）
  enemy/wolf.tscn        # 狼（四足、徒手；与守卫共用 scripts/enemy/enemy.gd）
  camera/camera.tscn     # 追尾镜头
  ui/hud.tscn            # HUD
scripts/
  autoload/input_setup.gd      # 运行时输入映射（WASD/攻击/闪避/锁定…）
  components/health.gd         # 通用生命值组件
  components/poise.gd          # 通用失衡值组件（黄色失衡条，完美格挡加值）
  effects/hit_flash.gd         # 打击闪光特效（完美格挡黄光 / 处决金爆闪 / 完美闪避青蓝光）
  effects/ghost_trail.gd       # 完美闪避的角色残影（复制当前姿势 + 叠加混合 + 淡出自毁）
  effects/lock_marker.gd       # 锁定标记（敌人身体中心的白色亮点）
  player/player.gd             # 玩家状态机 + 锁定模式 + 程序化原语角色
  enemy/enemy.gd               # 敌人 AI 状态机（含 BROKEN 失衡）
  camera/third_person_camera.gd# 镜头（含锁定自动绕背）
  camera/cinematic_director.gd # 处决特写分镜导演（接管相机 + 相对取景分镜表 + 遮幅黑边）
  ui/hud.gd                    # HUD 构建与更新
  main/main.gd                 # 主场景逻辑
assets/                    # 美术资产（源工程在 E:\blender\blenderproject\，不在本仓库）
  enemies/wolf_01/       # 狼：wolf_rigged.glb（22 骨 / 6 段动画）
  enemies/brute_01/      # 红甲守卫：brute_rigged.glb + club_01.glb
  characters/ weapons/   # 玩家骑士 / 武器（见 docs/GAME_DESIGN.md「美术资产管线」）
maps/
  wolf_test.tscn         # 狼试玩地图（把 enemy_scene 覆盖成狼；另有 forest_clearing.tscn）
tools/…                    # 校验/抓帧工具（见下方「动画 QA 工具」）
docs/GAME_DESIGN.md       # 设计文档与后续方向
```

## 已知限制（M1 有意为之）

- 角色视觉在运行时用原语网格拼装（编辑器场景预览看不到模型，运行即可见）
- 输入动作用代码注册（Input Map 面板不可见），M2 迁移为正式项目配置以支持改键
- 无音效 / 顿帧(hitstop) / 屏幕震动 / 连击——属于 M2 打磨内容（**锁定敌人已做**；打击闪光特效已有：见 `scripts/effects/hit_flash.gd`）
- 处决**不秒杀**是刻意的（75 伤害 / 满血 100，剩 25 正好一刀补掉）；失衡敌人不会瞬移贴身，玩家需自己走近
- **挨打不改面朝向**（只被击退）：HURT 全程不写 `_pivot.rotation.y`。好处是"位置变了、朝哪没变"，
  正面顶怪时被侧后杂兵擦一下不会突然扭头、丢掉主目标；代价是**看不出攻击来自哪个方向**，
  需要靠受击闪白和击退方向自行判断（若以后要加"受击转向提示"，这是明确要动的一处）

## 验证方式（命令行）

### ⚡ 一条命令跑全部探针（推荐）

```powershell
.\tools\run_probes.ps1              # 全跑：4 套探针（m1 339 + quest 113 + lock 62 + possess 36 = 550 断言）+ 5 个资产验证器
.\tools\run_probes.ps1 -Only m1     # 只跑一套探针（m1 / quest / lock / possess）
.\tools\run_probes.ps1 -Verify      # 只跑 5 个资产验证器（跳过 4 套探针）
```

脚本会逐套打印 `断言 通过数/基准数`，并在断言数与基准不符时**黄色告警**（防止断言被悄悄增删）；
资产验证器**按退出码**判过（逐条打印 `[OK]/[FAIL] 名称 exit=N`）。任一项失败总 `exit=1`，全过 `exit=0`。

> **⚠️ 绝不要用 `--script` 跑探针**，也别在编辑器里对探针的 `.gd` 点「运行」。
> 探针是 `extends Node`，**必须**作为 `.tscn` 启动。用错命令会得到两种**完全不提正确做法**的报错：
> 1. `Can't load the script "…" as it doesn't inherit from SceneTree or MainLoop.`
>    （`--script` 只接受 `extends SceneTree/MainLoop` 的脚本）
> 2. `Identifier not found: EventBus` —— autoload 在 `--script` 下**不注册**，且这是**编译期**失败，
>    会连锁拖垮所有依赖它的脚本（报错点甚至落在你没改过的 `enemy.gd`）。
> 看着像"代码被改坏了"，实际只是命令用错。项目备忘 `.workbuddy/memory/MEMORY-godot-ops.md`
> 里记了完整的排查顺序（**报错落在没改过的文件 → 先查调用方式，再查代码**）。

下面是每一套的**原始命令**（脚本内部用的就是它们，需要在 CI 里单独调时可直接抄）：

冒烟测试（加载主场景跑 240 帧）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game --quit-after 240
# exit=0 且无 SCRIPT ERROR 即通过
```

战斗闭环自动化测试（含玩家模型/**闪避与完美闪避**/跳跃/**起跳动画已取消**/格挡/失衡/处决/**待机受击死亡**/**锁定侧移**/**锁定点击切换**/**锁定标记**/**近战朝向修正**/**三段连击与命中反馈**/**处决特写分镜**全链路等 **339 项断言**，exit=0 即全过）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game 'res://tools/autotest/m1_autotest.tscn'
```

锁定输入边沿对抗性探针（**独立于主测试**，共 **62 条断言**；与主测试分工：主测试跑**业务闭环**，本探针专打**输入边沿语义**的边界 —— 长按中键 2s 只翻转一次、仅松手不解锁、连续点击奇偶翻转、范围外点击不自锁且无残留标记、锁定中目标 `queue_free` / 死亡两条退化路径、目标 A 死亡时当场改锁目标 B、全程不碰中键不得自锁、锁定态不变量采样 30 帧、死亡后点按不得锁定）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game 'res://tools/autotest/lock_toggle_probe.tscn'
# exit=0 = 62 条断言全过
```

"敌人也能操作"的对抗性探针（切换操控 / AI 真的关掉 / 手动出招走原 WINDUP→STRIKE 链路 / 镜头与血条跟人 / 操控中死亡自动交还操控权，**36 条断言**，exit=0 即全过）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game 'res://tools/autotest/possess_probe.tscn'
# exit=0 = 36 条断言全过
```

⚠️ **换过 `assets/**/*.glb` 之后要先强制重新导入**，否则引擎还在用 `.godot/imported/` 里的旧缓存，
表现为"新动画一个都认不出来"（headless 运行不会自动重新导入）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game --import
```

## 动画 QA 工具（tools/）

| 工具 | 用途 |
|---|---|
| **`tools/run_probes.ps1`** | ⚡ **跑全部回归探针 + 资产验证器**：4 套探针（m1/quest/lock/possess，共 **550 条断言**）+ 5 个资产验证器（`verify_enemy_model` / `verify_enemy_wolf` / `verify_wolf_hitbox` / `verify_wolf_death` / `verify_brute_death`）。`.\tools\run_probes.ps1`，可加 `-Only m1` 只跑一套、`-Verify` 只跑验证器。探针逐套打印通过数并与基准比对（数字不符会告警）；验证器**按退出码**判过、逐条打印 `[OK]/[FAIL] 名称 exit=N`。**改完代码优先跑这个** |
| `tools/inspect_model.gd` | 打印 GLB 的节点树/骨骼/动画列表与时长 |
| `tools/inspect_anim.gd` | 打印某条动画的每条轨道与关键帧数值（看清位移/旋转幅度） |
| `tools/anim_capture/dodge_capture.tscn` | 自动演示 **行走 → 挥砍 → 跳跃 → 前冲 → 后撤**，配合 `--write-movie` 抓帧 |
| `tools/anim_diff.gd` | 逐帧比较抓帧的"运动量"曲线，判断动画是否真的在播 |
| `tools/fx_capture/fx_capture.tscn` | 自动演示 **完美格挡 → 失衡 → 处决** 全流程并逐帧出图，用于肉眼确认黄光特效与 HUD 失衡条（见下方命令） |
| `tools/life_capture/life_capture.tscn` | 自动演示 **待机 → 挨打 → 阵亡** 三段并逐帧出图，用于肉眼确认 Idle 呼吸 / 受击后仰 / 倒地不复位 |
| `tools/lockon_capture/lockon_capture.tscn` | 自动演示 **未锁定横移 → 点一次中键锁定（镜头绕到背后 + 身体中心亮点出现）→ A/S/D 侧移后撤 → 再点一次中键（亮点收掉）** 并逐帧出图，用于肉眼确认"身体保持朝前、脚步横着走、亮点在躯干中心" |
| `tools/anim_capture/combo_capture.tscn` | 自动演示 **三段连击**：第一幕逐段单独播并各采 3 个姿势帧、第二幕才是真正一整套连击（带后摇取消 + 输入缓冲），脚本自己打印**关键帧号**供取图。用于肉眼确认三段的剪影确实不同、以及"接段不跳位置" |
| `tools/anim_capture/jump_capture.tscn` | 自动演示 **按住跳（≈1.2m）→ 落地 → 轻点小跳**，并打印"起跳前 / ★起跳瞬间 / 上升中 / 最高点 / 落地"的帧号。用于确认「按一下立即离地」的观感（起跳动画取消后新增，2026-09-21） |
| `tools/anim_capture/execute_cine_capture.tscn` | 加载**真实主场景**、真的触发一次**处决**、让**分镜导演自己驱动相机**，把玩家**实际看到的那一路镜头**逐帧落盘（含慢动作摊帧），脚本打印"特写接管 / 遮幅到位 / ★★命中切点 / 拉回收招 / 慢动作谷底与回升 / 相机交还"的帧号。⚠ 不加 `--headless`；⚠ 落盘 PNG 序号 = `Engine.get_frames_drawn() − 1`（差 1 帧）；⚠ 关键帧判定用 **fov 门限**（`FOV_NEAR_CUT` 54 / `FOV_PULL_BACK` 55），**改分镜 fov 就要同步改** |
| `tools/anim_capture/cine_frame_sweep.tscn` | 处决第 2 刀**取景候选 sweep**（临时对比工具）：把玩家摆到"命中那一拍"的姿势、冻结双方，在一次现场里渲 6 组候选取景（A 为旧值）→ 用 `grid.py` 拼图横向对比。用来自查"断言证明不了好看"的构图问题（见下方「处决特写分镜」一节） |
| `tools/anim_capture/wolf_capture.tscn` | 引擎内实拍**狼的 6 段表现**（idle → 中速/全速 trot → `AttackWindup→Attack` → `Hit` → `Death`），相机**每帧跟住狼**、步态段正侧视、招式段斜前 45°，脚本打印各片段的 `CAPTURE_SEG <名> frame=N` 帧号。⚠ 不加 `--headless`；用 `--fixed-fps 30` 固定步长抓帧。出片 → `docs/preview_wolf_walk.gif` / `preview_wolf_combat.gif` |
| `tools/gen_sfx.py` | **程序化合成音效**（纯 Python 无第三方依赖）：`python tools/gen_sfx.py assets/audio/sfx` 重新生成轻挥/重挥/命中三个 wav。内置"滤波器发散"质量护栏 |
| `tools/glb_anim_probe.py` | 直接解析 GLB 的 JSON chunk 打印**动画名 / 网格名清单**（**不经过 Godot**，一秒出结果）。覆盖 `assets/` 之前先用它确认"新 GLB 里到底有没有我要的动画" |
| `tools/autotest/lock_toggle_probe.tscn` | **锁定输入边沿对抗性探针**（62 条断言，headless 即可跑）：专打"按住 → 点击切换"的边界 —— 长按中键 2s 只翻转一次、仅松手不解锁、连续点击奇偶翻转、范围外点击不自锁且无残留标记、锁定中目标销毁 / 死亡两条退化路径、目标 A 死亡当场改锁 B、不碰中键不得自锁。与主测试分工：主测试测**业务闭环**，本探针测**输入边沿语义**。运行命令见上方「验证方式（命令行）」 |
| `tools/fx_capture/dodge_fx_capture.tscn` | 自动演示 **普通后撤 → 完美后撤**（青蓝闪光 + 角色虚影拖尾 + 子弹时间）并逐帧出图。侧面机位，专看「拖影往哪拖、虚影是不是 T-pose、是不是跟着本体跑」 |
| `tools/img_probe/find_marker.py` | **数像素**验证"某个视觉到底画出来没有"：统计抓帧图里的近白像素（数量/包围盒/质心）+ 裁块放大。用于点亮类特效（如锁定标记）；有/无两帧对比可给出确定结论（实测 288 px vs 0 px）。⚠️ 需 Pillow，见文件头注释里的隔离 venv 建法 |
| `tools/img_probe/montage.py` | 把一串抓帧 PNG **横向拼成一条静态对比条**（`--label` 逐格贴标签）——张数少（3~4 张）时最直接 |
| `tools/img_probe/grid.py` | 把一串抓帧 PNG **拼成网格**（`grid.py <out.png> <每行张数> <图...>`）。⚠️ 张数一多横排会变成 10000px+ 的细长条、被压到看不清，这时用网格版；`montage.py` 与它功能相近，**拼多张一律用 `grid.py`** |
| `tools/img_probe/make_gif.py` | 把一串抓帧 PNG 合成 **GIF 动图**（`--fps` / `--every` / `--width` / `--loop`）。★ 与上面两个**互补**：静态条看**姿势**，GIF 看**节奏**（连击接段、顿帧定格这类"帧与帧之间"的东西，静态图上根本看不出来）。⚠️ 需 Pillow |
| `tools/verify_enemy_model.gd` | **资产验证器**（`--script` 类）：核对守卫模型 —— 骨骼数 / **6 段**动画名与时长（含 glTF 1 帧偏移）/ 武器挂点对齐 / `export` 数值。exit=0 即通过 |
| `tools/verify_enemy_wolf.gd` | **资产验证器**（`--script` 类）：核对狼模型 —— 骨骼 **22** / 无 `weapon.R` / 6 段动画名与时长 / 缩放与脚底对齐 / `enemy_weapon_path` 空串**静默跳过** / `export` 数值 / `wolf_test.tscn` 地图接线 |
| `tools/verify_wolf_hitbox.tscn` | **资产验证器**（`.tscn` 类）：把玩家摆在狼正前 1.3m、让狼真跑一遍 `WINDUP→STRIKE`，断言玩家**真的掉血 12**（实机物理帧跑出来的，不是算坐标） |
| `tools/verify_wolf_death.tscn` | **资产验证器**（`.tscn` 类）：狼死亡观感 —— 尸体 `scale` 恒 1、不叠加程序化栽倒（`\|rot.x\|≈0`）、在 `Death` 长度 + 0.25s 后清场 |
| `tools/verify_brute_death.tscn` | **资产验证器**（`.tscn` 类）：守卫 `Death` 观感 —— 尸体不缩小、不栽倒、**末帧骨骼不复位**（root 保持 Death 末帧 92° 大角度）、在 `max(1.2, Death 长度 + 0.25)` 后清场 |

抓帧示例：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path D:\GodotProject\first-game 'res://tools/anim_capture/dodge_capture.tscn' --write-movie D:\GodotProject\first-game\.tmp_anim\frame.png
# 再分析： --headless --script res://tools/anim_diff.gd -- .tmp_anim
```

特效/失衡抓帧示例（输出 `.tmp_fx\frame00000000.png` …，脚本会打印各关键时刻的帧号）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path D:\GodotProject\first-game --resolution 960x540 'res://tools/fx_capture/fx_capture.tscn' --write-movie D:\GodotProject\first-game\.tmp_fx\frame.png
```

锁定/侧移抓帧示例（同样的套路，脚本会打印各关键时刻的帧号与当时播的动画名）：

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path D:\GodotProject\first-game --resolution 960x540 'res://tools/lockon_capture/lockon_capture.tscn' --write-movie D:\GodotProject\first-game\.tmp_lockon\frame.png
```

> ⚠️ 抓帧**不能加 `--headless`**（headless 用空渲染驱动，出不来图），所以会短暂弹出游戏窗口。
> `.tmp_*` 目录已在 `.gitignore` 里忽略，出图后挑需要的帧拷进 `docs/` 即可。

## 玩家模型与动画

- 模型：`assets/characters/player_knight/player_knight.glb`（**21 根骨骼的蒙皮模型**，19 段动画；Blender 源文件在 `E:\blender\blenderproject\player_knight\`）
- 资产说明见 `assets/characters/player_knight/README.md`；独立动画资源在 `animations/*.tres`

| 动画 | 时长 | 循环 | 触发时机 | 播放倍速 |
|---|---|---|---|---|
| `Walk` | 1.04s | ✅ | 移动中（站住即停） | 当前速度 ÷ `walk_natural_speed`，上限 `walk_max_speed_scale` |
| `WalkStrafeLeft` | 1.04s | ✅ | **锁定中**按 A（相对敌人向左横移） | 当前速度 ÷ `strafe_natural_speed` |
| `WalkStrafeRight` | 1.04s | ✅ | **锁定中**按 D（向右横移） | 同上 |
| `WalkBack` | 1.04s | ✅ | **锁定中**按 S（后撤） | 同上 |
| `Idle` | 2.042s | ✅ | 站住不动（速度 ≤ 0.5） | 1.0（= 动画内容时长 2.0s） |
| `DodgeForward` | 0.417s | 单次 | **前闪**：Shift + **任意**方向键（W/A/S/D 分别朝前/左/后/右；身体先转向该方向） | 动画时长 ÷ `dodge_forward_time` |
| `DodgeBack` | 0.500s | 单次 | **后闪**：**单按** Shift（不按方向键），朝身体正后方、不转身 | 动画时长 ÷ `dodge_back_time` |
| `RollLeap` | 0.458s | 单次 | *（已停用）* 旧的「Shift 翻滚」 | — |
| `Slash` | 0.542s | 单次 | 左键**第 1 段**（判定窗 `0.17~0.28s` = 实测剑刃最快段） | 动画时长 ÷ `attack_total` |
| `Slash2` | 0.458s | 单次 | 左键**第 2 段**（第 1 段取消点 0.30s 后接上；判定窗 `0.12~0.30s`） | 动画时长 ÷ `combo2_total` |
| `Slash3` | 0.625s | 单次 | 左键**第 3 段 · 收尾重击**（不可取消；判定窗 `0.16~0.42s`，转体一圈 + 过顶下劈） | 动画时长 ÷ `combo3_total` |
| `Hurt` | 0.375s | 单次 | 受击硬直 | 动画时长 ÷ `hurt_time` |
| `JumpStart` | 0.375s | 单次 | *（已停用）* 起跳蓄力段（蹲身→蹬地）；**2026-09-21 起跳动画已取消 → 不再播放**，资产与识别保留（`jump_prep_time` 调回 >0 即恢复） | — |
| `JumpAir` | 0.542s | ✅ | 离地后直到落地 | 1.0 |
| `Block` | 0.292s | 单次 | 按下右键（格挡起手），播完自动切 `BlockHold` | `block_anim_speed` |
| `BlockHold` | 1.042s | ✅ | 按住右键持续格挡 | `block_anim_speed` |
| `BlockImpact` | 0.375s | 单次 | 挡下攻击瞬间插播顿挫（占 `block_impact_hold` 0.22s） | `block_anim_speed` |
| `Execute` | 1.042s | 单次 | 处决（举剑→前刺→上划→收招）；命中帧 = 动画第 9 帧 | 动画时长 ÷ `execute_time`（=1.0 倍速） |
| `Death` | 0.583s | 单次 | 死亡（膝盖发软→前扑→躺平）；末帧定住不复位 | 动画时长 ÷ `death_time` |

> 表里的时长是模型内 `Animation.length` = 源末帧绝对时刻 `N/24`（本工程约定，见 `docs/GAME_DESIGN.md`）。
> 例：`Execute` 关键帧 1..25 @24fps → **内容时长 1.0s**，而 `length` = 25/24 = **1.042s**；
> 那多出来的 1/24 是约定不是 bug，别去"修"它（会连带打掉自动测试里已固化的倍速断言）。

动画状态机要点（都在 `scripts/player/player.gd`）：
- 动画名按"小写 + 忽略下划线"匹配（`exec` / `dodgeforward` / `dodgeback` / `walkstrafeleft` / `walkstraferight` / `walkback` / `walk` / `slash2|attack2|combo2` / `slash3|attack3|combo3` / `slash|attack` / `jumpstart|jumpup` / `jumpair|air|fall` / `blockhold` / `blockimpact` / `block|guard` / `idle` / `hurt|damage` / `death|die`），换模型/改动画名后无需改代码
- ⚠️ **识别顺序敏感（三处坑，都靠断言钉住）**：
  ① `BlockHold` / `BlockImpact` 的名字里都含 `block`，必须**先判 hold / impact 再判裸 block**，否则两段都会被吃成"格挡起手"（敌人脚本的 `AttackWindup` / `Attack` 是同一个坑）；
  ② `WalkStrafeLeft` / `WalkStrafeRight` / `WalkBack` 都含 `walk`，必须**排在裸 `walk` 之前**，顺序写反 `_walk_anim` 会被后出现的名字覆盖掉；
  ③ `Slash2` / `Slash3` 都含 `slash`，必须**排在裸 `slash` 之前** —— 同样的覆盖陷阱，症状是"三段连击全长一个样"且第 1 段播的是第 3 段的动画（`m1_autotest` 有一条"三段必须是三段不同动画"的外层防线专盯它）
- **循环必须显式打开**：glTF 没有循环标记，代码会把 Walk / **侧移三段** / Idle / JumpAir / BlockHold 设为 `LOOP_LINEAR`，否则只播一次就定住
- **骨骼复位**：骨骼动画一停播，骨骼会冻在停播那一帧（走到一半停下→僵在迈步中途；落地→僵在蜷腿姿势）。所以"没有对应动画"的状态（落地后等）统一调用 `_anim_to_rest()` 把骨骼复位到绑定姿势，再由脚本叠加整体姿态与落地压缩。**但死亡是例外**：`Death` 播完**故意不复位**，尸体定格在躺平那帧
- **跳跃：按一下立即离地**（`jump_prep_time = 0`）。原本是"两段式起跳"——按下后先进 `JUMP_PREP` 在地面播 `JumpStart` 蹬地动作、0.18s 蓄力结束才由 `_launch_jump()` 给向上速度并切 `JUMP`（播 `JumpAir`），好处是蹬地动画与"离地"这个事件对齐。
  **2026-09-21 取消起跳动画**：既然连那段动画本身都不要了，"动画与位移对齐"的前提也就不存在 → 直接瞬间起跳，少了 0.18s"按了没反应"的迟钝。
  ★ `JUMP_PREP` 那套代码**没有被删**（默认进不去）：`jump_prep_time` 就是开关，**调回 0.18 即可恢复两段式起跳**；自动测试里有一条"调回 0.18 蓄力段必须复活"的断言守着这个可逆性
- 这套动画**不含净水平位移**（前进量由速度逻辑负责），所以闪避不需要"根位移过继"（只有老翻滚才需要 —— RollLeap 末帧停在身前 1m，要过继给碰撞体）
- **`EXECUTE`(处决) 有专属动画 `Execute`**：举剑 → 前刺（命中帧）→ 上划 → 收招，整段 1.0s。
  倍速按"动画时长 ÷ `execute_time`"自动换算（默认 1.0 倍速，不慢放也不加速）；
  万一模型里缺这段，会自动退回"慢放 `Slash`"，再退到全身姿态三段式兜底 —— 所以换模型也不会没有处决演出
- **`IDLE` / `HURT` / `DEAD` 各有专属动画**（2026-09-20 补齐，由 `life_anim.py` 生成）：
  `Idle` 呼吸循环（站住时播，带细微起伏，不再僵在绑定姿势）、`Hurt` 被打后仰（倍速 = 动画时长 ÷ `hurt_time`）、
  `Death` 膝盖发软→前扑→躺平（倍速 = 动画时长 ÷ `death_time`）。
  三段都是"模型里有就播，没有就退回脚本整体姿态兜底"，所以删掉 GLB 里的动画也不会崩
- **锁定侧移三段 `WalkStrafeLeft` / `WalkStrafeRight` / `WalkBack`**（2026-09-20，由 `strafe_anim.py` 生成）。
  ⚠️ **侧移是"横向开合"、不是"前后迈步"**，这是整段读不读得对的关键，也是唯一踩过的坑：
  只屈膝不补髋，脚会被甩到**身后**（屈膝 36° → 脚后退 0.23m，而抬脚才 0.12m），渲出来是弓步劈叉而不是侧移。
  修法是 `planted_hip()`：**髋角 = −0.494 × 屈膝角**（比例由骨架实测大小腿长推出），让摆动腿"原地抬膝"。
  判据别靠肉眼，直接量 —— `probe_foot_travel.py` 打印两只脚的 X/Y 行程比：
  侧移 `Y/X ≈ 0.1`（左右为主）、Walk `Y/X ≈ 8`（前后为主）、WalkBack `Y/X ≈ 12.8`。**右移由左移镜像生成**（`mirror_pose()`），不手写第二份表

## 三段连击（左键）与命中反馈

左键点一下 = 第 1 段；**在后摇取消点之后再点** = 掐掉剩余收招、接下一段。三段各有专属动画与独立参数：

| 段 | 动画 | 时长 | 判定窗 | 后摇取消点 | 伤害 |
|---|---|---|---|---|---|
| ① 挥砍 | `Slash` | 0.500s | 0.17–0.28s | `combo_cancel_1` = **0.30s** | 25 |
| ② 横斩 | `Slash2` | 0.417s | 0.12–0.30s | `combo_cancel_2` = **0.28s** | 30 |
| ③ 回旋收尾 | `Slash3` | 0.583s | 0.16–0.42s | **无 → 不可取消** | 40 |

- **输入缓冲** `combo_buffer_time` 0.30s：在取消点**之前**按的那一下不会被丢掉，会记进缓冲、到点自动兑现。
  没有缓冲就必须掐帧去按（"早了无效、晚了断链"），手感立刻变硬；但缓冲会过期，避免"很久以前随手按的一下"突然替你接一段
- ★ **第 3 段刻意不可取消**：必须站着把 0.583s 的长后摇演完 —— **这段被对手惩罚的窗口就是连击的代价**。
  若三段都能取消，连击就是"只有收益没有风险"，玩家会无脑连点
- ★ **三段总伤害 25+30+40 = 95 < 满血 100**：一次完整连击打不死任何敌人，最后仍要补一刀；
  与"处决 75 之后留恰好一刀的量"是同一条设计原则。第 1 段伤害仍是 25（老参数 `attack_damage` 未变）
- 冷却分两档：普通收招 `attack_cd` 0.42，**第 3 段收尾** `combo_finish_cd` 0.62（收尾的"重量"也体现在多站一会儿）
- 每一段起手都重新跑一次**近战朝向修正**（见下一节）—— 敌人被前一段打退了，第 2/3 段必须跟着转，否则会"对着空气连挥三刀"

**命中反馈三件套**（每次命中同时触发，`_on_hit_landed()`）：

| 反馈 | 参数 | 说明 |
|---|---|---|
| 顿帧 hitstop | `hitstop_normal` 0.055s / `hitstop_finisher` 0.11s，期间 `time_scale` → **0.05** | 把全局时间几乎冻住，"这一刀吃进去了"的重量感。收尾重击给双倍时长 |
| 镜头震动 | `shake_normal` 0.035 / `shake_finisher` 0.085，`shake_time` 0.16s | ★ 施加在**子节点 Camera3D 的局部偏移**（`h_offset`/`v_offset` + 轻微滚转）—— 直接挪 `global_position` 会被下一帧的 `look_at` 覆盖，跟平滑跟随打架会变成抖屏 |
| 音效 | `swing_light` / `swing_heavy` / `hit_impact`（`AudioStreamPlayer3D`） | 起手播破空声（第 3 段更沉），命中播打击声。3D 播放器 → 有距离衰减与方位感，是以后"听声辨位"的基础 |

- ★★ **顿帧与子弹时间是两个独立因子，最终取更慢者**：`Engine.time_scale = min(_bt_factor, _hs_factor)`。
  两者都会压慢全局时间，但用途/时长/深度完全不同。若共用一个变量，后写的一方会盖掉对方，
  且先前那个补间到点还会把对方的减速一起拉回 1.0（画面会突然"抽一下"）。
  拆开后"完美闪避里打中敌人"也表现正常，互不干扰（自动测试有 3 条专门钉这个）
- 音效是**程序化合成**的（`tools/gen_sfx.py`，纯 Python）：挥砍 = 带通噪声 + 时变共振峰（"嗖"的本质就是噪声的共振峰在移动），
  命中 = 瞬态噪声（"啪"）+ 85→46Hz 扫频正弦（"砰"）+ 中频填充。改音色就改脚本参数重跑，见 `assets/audio/sfx/README.md`

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

## 近战朝向修正（攻击软锁定）

攻击**起手的那一瞬间**，如果附近有敌人，角色会自动朝向它 —— 这是动作游戏标配的"软锁定"，解决的是第三人称近战最典型的手感问题：**明明贴脸站着，一刀却砍在空气里**。

| 参数 | 默认 | 说明 |
|---|---|---|
| `soft_lock_enabled` | `true` | 总开关（想体验完全手动瞄准就关掉） |
| `soft_lock_range` | `3.5` | 搜索半径(米)：水平距离超出这个值的敌人**不参与**修正 |
| `soft_lock_angle` | `70` | 相对**镜头或身体正前方**的最大偏角(度)：敌人在两个朝向的锥外(比如背后)才不抢朝向 |

朝向的优先级：**锁定目标 > 附近敌人(软锁定) > 移动输入方向 > 镜头正前方**。

- **锁定目标排第一**：那是玩家显式按中键指定的，任何自动修正都不能盖掉它
- **软锁定压过移动输入**：这是本次修正的核心 —— 边按 S 后退边挥砍时，"我手指正按着后退"不代表"我想朝背后砍"
- 敌人（守卫）侧同一套规则，基准换成**它自己的正面**（怪不读镜头），只在**手动操控**时生效（AI 本来就全程锁着玩家追）。敌人侧的吸附行为由 `tools/autotest/possess_probe.tscn` 的 **T5b** 章节覆盖（侧前方 60°/2.2m 出招 → 朝向吸附偏差 0.0° 并砸中玩家；`soft_lock_range=0` 时朝镜头正前方挥空）

两条防"帮倒忙"的边界：**超出半径不修正**（远处的怪不许抢朝向）、**背后的敌人绝不修正**（把每一刀掰到身后是最难受的手感）。

> 和"锁定"的区别：锁定是玩家显式按键、全程生效、还改镜头与位移动画；近战修正是**自动的**、只在攻击起手那一瞬生效，其余一切照旧。

## 锁定敌人（点击鼠标中键切换）

**点一次中键 = 锁定范围内最近的敌人；再点一次中键 = 解除**（**切换型**输入，读法和"按住型"的格挡不同：只在中键上花一瞬，不必一直按着）。

**为什么从"按住"改成"切换"？玩家又靠什么知道当前锁没锁？** 按住型会把手指一直钉在中键上，长时间按着累、也腾不出手做别的；改成"点一次开 / 再点一次关"后手是自由的。至于"我到底锁没锁"，不靠手指记忆 —— 靠敌人**身体中心那颗白色亮点**（锁定期间一直在、解除立刻收掉），所见即所得。所以本项目不再拿"按住 = 状态与手指一一对应、不会有暗开关"当理由。

锁定同时改五件事，缺一件都会别扭：

| 改什么 | 怎么改 | 为什么 |
|---|---|---|
| **面相** | 身体**始终朝敌人**，移动方向不再参与转身 | 这是"侧移"能成立的前提：不锁住朝向，身体会扭向移动方向，侧移动画就白做了 |
| **位移段** | 按 A/S/D 播 `WalkStrafeLeft` / `WalkBack` / `WalkStrafeRight`（W 仍是 `Walk`） | 复用在自由模式下会打架：`Walk` 是"朝移动方向走"，而锁定要求"身体朝前、脚步横着走" |
| **镜头** | 自动绕到玩家背后、正对敌人（`lock_yaw_speed` 平滑跟随） | 看得见敌人才谈得上"锁定"；同时**忽略鼠标左右环绕**，否则自动跟随和玩家手动会互相拉扯、镜头抖（俯仰仍可手动） |
| **移速** | ×`lock_move_scale`（0.6） | 横移的脚是横着走的，全速跑会显得"飘"；降速也更容易看清敌人起手 |
| **标记** | 敌人**身体中心**出现一颗白色亮点（`LockMarker`，随敌人移动、轻微脉动，解除即收） | 锁定会同时改面相/动画/镜头，但画面上**没有东西指出"锁的是哪一只"**；怪一多、或目标被自动重找换了人，玩家只能靠镜头角度去猜 |

几条设计取舍：

- **锁定是"模式"不是"状态"**：不新增 `State`，只在 `MOVE`/`BLOCK` 里加一层朝向与选段的优先判断 —— 新状态要改 4 处 `match state:` 分支、还会和闪避/攻击/格挡的状态机互相打断
- **哪一段动画**：把移动方向**投影到角色自身的两个水平轴**上（前轴 = 模型 −Z、右轴 = `basis.x`），左右分量占优就播侧移、否则前进/后撤。**不能用 A/S/D 输入轴直接判**，因为 `_wish_dir` 是镜头相对算出来的，只有投到自身轴才和"角色此刻朝哪"一致
- **标记挂在敌人根节点上、并关闭深度测试**：亮点在身体**内部**，不关深度测试会被躯干网格挡死（等于什么都没看见）；挂点用根节点而不是会摇晃的 `VisualPivot`，否则敌人挨打/失衡时标记会跟着抖。高度 = `敌人站高 × lock_marker_body_ratio(0.5)`，不同身材的敌人自动落在胸口
- **目标死了就当场重找**：锁定的意图是"我要一直盯着打"，而不是"锁定这一只直到它死"；找不到（或敌人出圈）就退化成未锁定
- **解除后镜头停在原地**：yaw 不会弹回锁定前 —— 和真实第三人称一致，玩家自己用鼠标找回手感

## 格挡（`BLOCK` 状态）

按**鼠标右键**进入格挡，松开立刻收招。设计目标是"按住 = 稳住，时机准 = 反打"：

| 情形 | 效果 |
|---|---|
| 按住右键，攻击落在**正面 120° 锥形**内 | **减伤 70%**（只吃 30%，且至少 1 点 —— 不是无敌）、**不硬直、不击退**，可边挡边小碎步挪（移速 ×0.3） |
| 按下的**前 0.45s** 内挡下 | **完美格挡**：0 伤害 + **黄光特效** + 攻击者被弹进 **0.8s** 长硬直（普通受击只有 0.4s）→ 反击窗口；同时**敌人失衡值 +34%** |
| 攻击来自**背后 / 侧后** | 挡不住，吃满伤害并硬直（逼玩家把敌人留在视野里） |
| 格挡中按左键 / Shift / 空格 | 一律无效（不能边挡边输出，也不能举着剑闪避/跳） |
| 被打进硬直时右键还按着 | 硬直结束**自动重新举剑**（不白送完美窗口，`_perfect_parried` 保持 true） |

- 一次**按住**只给一次完美判定：窗口过了继续按住只是普通格挡，避免"长按白嫖"
- 完美格挡靠玩家的 `_stagger_attacker()` → 敌人的 `deflect(duration, from_pos)`（`scripts/enemy/enemy.gd`）：
  **不掉血**，只改状态机 + 把怪推开（推力 ×1.4，闪得更亮）+ **给敌人的失衡条加一截**
- 三段动画由 `_block_play()` 调度：`Block`(起手 0.25s) → `BlockHold`(循环) → 挡下时插播 `BlockImpact`
- 完美格挡会同时迸一个 `HitFlash` 黄光（格挡点前方），并把 HUD 整屏泛一下金光

格挡参数（`scripts/player/player.gd` 顶部 `@export`）：

| 参数 | 默认 | 作用 |
|---|---|---|
| `block_damage_reduction` | 0.7 | 普通格挡减伤比例 |
| `perfect_parry_window` | **0.45** | 完美格挡窗口(秒)；沿革 0.15 → 0.22 → 0.45。放宽是安全的：**一次按住只给一次完美判定**，不会退化成"按住就无敌" |
| `block_guard_angle` | 120.0 | 正面格挡锥形张角(度) |
| `block_move_scale` | 0.3 | 格挡时移速倍率 |
| `block_parry_stagger` | 0.8 | 完美格挡让敌人硬直的时长(秒) |
| `block_anim_speed` | 1.0 | 格挡三段动画播放倍速 |
| `block_impact_hold` | 0.22 | 挡下顿挫占用的时长(秒) |

## 失衡条与处决

**一句话**：完美格挡不只是一次硬直，它还在给敌人攒一条**黄色失衡条**；攒满 → 敌人 **BROKEN** → 走近按左键**处决**。

```
完美格挡 ──▶ 敌人 STAGGER 0.8s + 失衡 +34% ──3 次──▶ 失衡条满
                                                        │
                                                        ▼
                              敌人 BROKEN（3.0s：不出手、命中盒关闭、站不稳打晃）
                                                        │
                玩家在 2.6m 内按左键 ──▶ EXECUTE：全程无敌 + 自动贴近 + 金爆闪
                                                        │
                Execute 动画第 9 帧(前刺) ──▶ enemy.execute(75) → 金爆闪
                                                        │   · 守卫满血 100 → 剩 25，**打不死**
                                                        │   · 保持 BROKEN 把演出演完（不会中途站起来）
                         收招瞬间 ──▶ 敌人爬起来（失衡被消耗）──▶ 玩家补一刀(25) 击杀
                                                        │
                        3.0s 内没被处决 ──▶ 自动恢复追击，失衡值清空重攒
```

| 情形 | 效果 |
|---|---|
| 失衡值怎么涨 | **只有完美格挡**会涨（普通格挡/普通攻击都不涨）—— 它是"弹反奖励的进度条" |
| 每次涨多少 | 敌人自己的 `parry_poise_percent`（**上限的百分比**）。守卫 **34% → 3 次**；小怪 50(2 次) / 重甲 25(4 次) / Boss 20(5 次) |
| 涨满后 | 敌人进入 **BROKEN**：不能出手、命中盒关闭、播受击姿势并保持 + 左右打晃，持续 `break_time` 3.0s |
| 处决怎么触发 | 走近（2.6m 内）**按左键**。没失衡敌人时左键仍是普通挥剑 |
| 处决演出 | 专属动画 `Execute`：**举剑 → 前刺（命中帧）→ 上划 → 收招**，整段 1.0s |
| 处决伤害 | **大量但刻意不致命**：`execute_damage` **75**（守卫 100 → 剩 25）。留的量 = 正好一刀 `attack_damage`(25) → **处决重创 + 补刀收尾** |
| 为什么不做成秒杀 | 一击必杀会让最优解退化成"格挡→秒杀→格挡→秒杀"，普通挥砍被架空；处决还自带全程无敌，能秒杀就等于"无敌+秒杀"，强度失控 |
| 处决为什么无敌 | 处决动作比普通挥砍长（1.0s vs 直 0.5s），不能被打断才"值得用"；代价是收招长，怪堆里无脑处决会挨打 |
| 处决会不会被打断 | 不会：处决时把敌人的失衡倒计时**顶回满**（`poise.refresh_break()`），敌人不会演到一半站起来 |
| 敌人挨完还活着怎么办 | 玩家**收招那一刻**才调 `end_break_after_execution()` 收掉失衡 → 敌人爬起来。因此**不能原地连按左键无限连处决**（那会让处决退化成刷伤害循环） |
| 失衡期再被弹反 | 保持 BROKEN（不会被多余的格挡取消处决窗口），也不再累加失衡值 |
| HUD | 敌人血条下方一条细黄条（常驻显示进度）；失衡时变亮金 + 标题改成"已失衡！按左键处决" + 顶部弹提示 |

主要参数：

| 参数 | 位置 | 默认 | 作用 |
|---|---|---|---|
| `parry_poise_percent` | `enemy.gd` | 34.0 | 每次完美格挡加多少 %（**各类敌人差异就在这一项**） |
| `execute_damage_scale` | `enemy.gd` | 1.0 | 处决伤害倍率（大块头调低即可让它更抗处决） |
| `max_poise` | `poise.gd` | 100.0 | 失衡条上限 |
| `break_time` | `poise.gd` | 3.0 | 失衡持续时长(秒) |
| `break_keep_ratio` | `poise.gd` | 0.0 | 失衡结束后的残留比例（0=清空重攒，0.5=更难被连续弹到失衡） |
| `decay_rate` | `poise.gd` | 0.0 | 自然回落速度（默认关闭 → "只涨不落"，节奏确定） |
| `execute_damage` | `player.gd` | 75 | 处决基础伤害（大量但**不秒杀**：满血 100 的守卫剩 25 = 一刀补掉） |
| `execute_range` | `player.gd` | 2.6 | 触发处决的距离(米) |
| `execute_time` | `player.gd` | 1.0 | 处决整段时长(秒) = `Execute` 动画的内容时长 |
| `execute_hit_time` | `player.gd` | 0.32 | 处决判定时刻(秒) = `0.32 × execute_time`（对齐动画第 9 帧前刺，**改动画命中帧要同步改**） |
| `execute_anim_speed` | `player.gd` | 0.0 | 处决动画倍速：**0 = 自动**（动画时长 ÷ `execute_time`），>0 = 手动固定 |

组件复用：`Poise`（`scripts/components/poise.gd`）和 `Health` 一样是"挂在战斗单位下的子节点"，
所以以后给玩家/精英/Boss 加失衡条只需加一个节点 + 配 `parry_poise_percent`，逻辑零改动。

## 打击闪光特效（`scripts/effects/hit_flash.gd`）

完美格挡与处决会调用 `HitFlash.spawn(父节点, 世界坐标, 颜色, 半径, 时长, 光强)` 生成一次性闪光：

- 三件套叠在一起、0.3~0.45s 内放大淡出后**自毁**：`Core` 亮球（放大）+ `Ring` 扩散光环（冲击波感）+ `Light` 点光源（把周围照亮）
- 材质是 `UNSHADED` + `BLEND_MODE_ADD` + 双面，所以不依赖场景光照就能"发亮"
- 节点 `top_level = true`（不跟随父节点的旋转与落地压缩），所以调用方直接传**世界坐标**
- 纯原语、零美术资源，与项目整体低模风格一致。以后要换正式特效（GPUParticles3D + 贴图）
  只需替换 `HitFlash` 内部实现，**调用方接口不用改**
- ⚠️ 这类"跟着游戏事件实时触发"的光效**必须**在引擎内做（云侧的 3D/视频生成只能产出离线素材，无法实时响应游戏事件）

## 处决特写分镜（镜头导演层）

处决不只是一段动画 —— 命中那一刻镜头会**自己切上去**：拉起上下遮幅黑边、按一张"分镜表"逐刀**硬切**机位、命中刀压上慢动作与震屏，演完再把相机交还追尾。实现是一个**自包含**节点 `CinematicDirector`（`scripts/camera/cinematic_director.gd`），塞进主场景即生效。逐刀取景的调参说明与设计取舍见 **`docs/CINEMATIC_CAMERA_GUIDE.md`**。

三条机制（都在 `cinematic_director.gd`）：

- **导演接管相机**：处决起手时 `player.gd` 调 `director.play(EXECUTE_SHOTS, execute_time, self, target)`，导演从 `"camera"` 组找到追尾相机、置 `driven = true`，此后每帧用 `ThirdPersonCamera.apply_driven_pose(pos, look, fov)` 写位姿与 fov（追尾的 `_process`/`_input` 在 `driven` 期间直接 `return`）；收招时 `director.stop()` → `release_driven()` 从当前位姿**反推 yaw/pitch** 交还，镜头**不弹回**。
- **相对取景（每帧重采样锚点）**：取景轴 = 玩家胸口 → 敌人胸口（水平）；机位 = 锚点 + 由 `azimuth`/`elev`/`dist` 描述的方向 × 距离，`fov` 单独给。所以"从玩家侧后方 4.2m、抬高 22° 俯视"这句话**不管演员怎么动都成立** —— 机位跟着人走（绝对坐标机位会因为击退/前冲而失焦）。
- **归一化时间 + 硬切**：分镜表的 `t` 是 0..1 的**比例**（相对 `execute_time`），改时长时分镜自动等比伸缩、命中切镜也不会落后于动画；三刀之间**硬切（不插值）**，只在进场（`INTRO_TIME` 0.15s）与交还两端平滑。时间轴用**被 `time_scale` 缩放过的 delta** 推进，慢动作时机位与画面天然同步。

分镜表 `EXECUTE_SHOTS`（三刀，切点对齐 `execute_hit_time`）：

| t | pivot | azimuth | elev | dist | fov | 意图 |
|---|---|---|---|---|---|---|
| 0.00 | `mid` | 58° | 22° | 4.2m | 62° | 全景交代（看清"在处决谁"） |
| 0.32 | `enemy` | 18° | 8° | 3.6m | 50° | **命中近景**（= `execute_hit_time`，硬切过肩） |
| 0.62 | `player` | 18° | 20° | 4.6m | 58° | 拉回收招 |

- **遮幅黑边**：导演自建 `CanvasLayer(layer = 0)` + 上下两条 `ColorRect`，各占视口高 `LETTERBOX_RATIO` **0.12**（有效画面 ≈ 76%，接近 2.35:1 的电影感）；滑入/滑出 **0.15 真实秒**（`set_ignore_time_scale` → 慢动作不会把遮幅也拖慢）。HUD 是 `layer = 10`，所以遮幅压在 **3D 之上、HUD 之下**（不挡血条）。
- **处决命中反馈**（`player.gd` 顶部 `@export`）：命中刀同时压 **慢动作** `cinematic_slowmo_scale` **0.35** / 保持 **0.28s** / 回升 **0.40s**（复用子弹时间那套 `_start_bullet_time`）、**震屏** `execute_shake` **0.085** / 0.16s（加在相机**子节点**偏移上，与导演写父节点位姿互不干扰 → 特写期间照样看得见）、**金爆闪**收敛到半径 **0.95** / 时长 **0.30** / 光强 **7.5**（近景特写下原 1.4/0.45/9.0 会糊屏）；可选顿帧 `execute_hitstop` 默认 **0**（关）。
- **优雅降级**：`"cinematic"` 组里没有导演时（自动测试 / 裸场景），`play()`/`stop()` 调用处**静默跳过**，处决照常跑完；目标在演出中途失效 → 导演 `_process` 检测到锚点失效即 `stop()` 安全退出、相机交还。
- **测试与出片**：`m1_autotest` 1f-2 节覆盖"导演接管 / fov 改动 / 遮幅纯黑且 `layer == 0` / 命中后机位改变 / 慢动作自行回升 / 震屏 / 交还后 yaw·pitch 反推一致（**不弹回**）/ 目标失效安全退出 / 无导演降级 / fov 复位 70"；真成片用 `tools/anim_capture/execute_cine_capture.tscn` 抓帧（⚠ **不加 `--headless`**）。
- ⚠️ **两个抓帧坑**：① `--write-movie` 落盘的 PNG 序号 = `Engine.get_frames_drawn() − 1`（差 1 帧，取关键帧要据此修正）；② 抓帧脚本的关键帧判定用 **fov 门限**（`FOV_NEAR_CUT` 54 / `FOV_PULL_BACK` 55），**改了分镜表里任一刀的 fov 就要同步改门限**，否则对应字幕行会静默消失（本工程真踩过：第 2 刀 fov 从 36 改成 50 后，旧门限 49 永远不触发）。
- ⚠️ **断言证明不了"好看"**：第 2 刀最初取景 `enemy / 1.9m / fov 36` 时**四套测试全绿**（fov 变了、机位变了），可真成片里是**一整屏蓝橙色平面多边形、完全读不出斩击** —— 机位离敌人太近直接穿进了玩家身体。最后是靠 `tools/anim_capture/cine_frame_sweep.tscn` 扫 6 组候选、目视对比才定成现在的过肩机位。**这一层改了必须真跑一遍抓帧、肉眼复核**。

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
| `jump_prep_time` | **0.0** | **起跳蓄力时长 —— 起跳动画已取消 → 默认 0 = 按一下立即离地**（见下方取舍）。调回 0.15~0.22 即恢复"先在地面播完 JumpStart 蹬地再离地"的两段式起跳 |
| `jump_cut_multiplier` | 2.0 | 上升中松开跳跃键的重力倍数 → 轻点=小跳 |
| `fall_gravity_multiplier` | 1.35 | 下落重力倍数 → 落地干净不飘 |
| `air_accel` | 9.0 | 空中水平操控（小于地面 accel → 跳跃有承诺感） |
| `coyote_time` | 0.12 | 土狼时间：刚离开地面仍可起跳 |
| `jump_buffer_time` | 0.15 | 跳跃缓冲：落地前提前按也算数 |
| `land_squash_time` | 0.18 | 落地压缩(视觉)时长 |
| `walk_natural_speed` | 1.0 | Walk 动画的自然步速(米/秒)，用于算播放倍速 |
| `walk_max_speed_scale` | 2.0 | Walk 播放倍速上限（见下方"已知取舍"） |

跳跃相关的设计取舍：
- 跳跃**不能取消**攻击/闪避，攻击/闪避/受击硬直中按跳跃无效（动作要有承诺感）
- 空中不能二段跳；空中也不能攻击、不能闪避（M2 可扩展为空战）
- **起跳是"一按即离地"**（`jump_prep_time = 0`，2026-09-21 起跳动画取消）。
  原来是两段式：按下 → `JUMP_PREP` 地面蓄力 0.18s（播 JumpStart 蹬地）→ 真正离地进入 `JUMP`（播 JumpAir），
  目的是让蹬地动画与"离地"这一事件对齐。**现在这段动画不用了，对齐的前提也就不存在** → 直接瞬间起跳。
  ★ 想要回重量感/预备感：把 `jump_prep_time` 调回 0.15~0.22（`JUMP_PREP` 那套代码与 JumpStart 动画都还在）。

## 已知取舍（动画相关）

- **滑步**：`move_speed = 6.2 m/s` 远高于 Walk 动画的自然步速（约 1.0 m/s），
  倍速上限 2.0 意味着跑动时腿部动作与地面仍有滑步。要彻底消除需要美术侧再出一段
  **Run**（步幅更大的循环），或把 `move_speed` 降到 3~4 更接近"重甲骑士"的感觉。
- **处决/受击缺少"受方"专属动画**：处决时敌人播的仍是受击姿势，还没有专属的"被处决"演出；
  敌人侧也还没有死亡动画（`enemy.gd` 用整体倒地兜底）。玩家侧 Idle / 受击 / 死亡已在 2026-09-20 补齐。
