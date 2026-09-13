# player_knight —— 玩家角色资产（Godot 侧）

> ⚠️ **模型源文件不在本目录**，也不在 Godot 项目里。所有 `.blend` 源文件与完整预览图在：
> `E:\blender\blenderproject\player_knight\`（唯一来源，见该目录下的 README.md）
> 这里只放**引擎需要的产物**，按类型分类存放。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `player_knight.glb` | 绑定好的模型：6 个网格 + 21 根骨骼（Skin）+ **5 段动画** |
| `animations/` | 从 GLB 抽出的独立动画资源（`*.tres`），便于预览/复用（由 `tools/split_player_animations.gd` 生成） |
| `previews/` | 各动画代表帧。**行走含左右两步 + 侧视**：`walk_side_01_contact_R.png`（右步触地）、`walk_side_07_passing_R.png`、`walk_side_13_contact_L.png`（左步触地）、`walk_side_19_passing_L.png`，另有斜视 `walk_01_contact_R.png` / `walk_13_contact_L.png` |

## 模型规格

- 尺寸：身高 **1.87 m**，脚底在原点平面（Y=0），朝向 **-Z**（Godot 默认前向）
- 网格：`GEO-knight_body`、`GEO-leg_L/R`、`GEO-arm_L/R`、`GEO-sword_01`（剑，独立武器网格）
- 材质：7 个纯色 Principled 材质（无贴图），低多边形方块风
- 骨骼（21）：`root → hips → spine → chest → neck → head`；`chest → shoulder.L/R → upperarm.L/R → forearm.L/R → hand.L/R →（hand.R → weapon.R）`；`hips → thigh.L/R → shin.L/R → foot.L/R`
- 蒙皮方式：刚性蒙皮（每个部件 100% 绑定 1 根骨骼）

## 动画（24 fps）

| 动画名 | 帧 | 时长 | 循环 | 说明 |
| --- | --- | --- | --- | --- |
| `Walk` | 1–25 | 1.000 s | ✅ 循环 | **完整两步循环**：右脚支撑 f3–f13、左脚支撑 f14–f2（各半周期）；接触帧双脚同时着地（0.005 / 0.035），摆动腿抬起 7.8 cm，身体起伏 4.4 cm；首尾帧完全一致 |
| `RollLeap` | 1–11 | 0.417 s | 单次 | 原地腾空前滚翻（0.22 m 腾空弧 + 全身 −360°） |
| `Slash` | 1–13 | 0.500 s | 单次 | 举剑过顶 → 前下劈；命中窗 0.13–0.30 s 即剑刃最快段 |
| `JumpStart` | 1–9 | 0.333 s | 单次 | 起跳：蹲身（root 自动降到 −0.17 m）→ 爆发 → 踮脚离地 |
| `JumpAir` | 1–13 | 0.500 s | ✅ 循环 | 悬空：收腿 + 双臂外展平衡；首尾帧完全一致 |

### 位移约定（接入代码时必须知道）
- **动画不含净水平位移**：前进/冲刺/跳跃弧线由 `player.gd` 的速度逻辑负责，避免播放结束后角色残留偏移。
- `JumpStart` 的 root 高度是"双脚贴地"约束自动反解出来的（脚不穿地也不悬空）；`Walk` 的 root 起伏同样由地面接触约束生成。
- 动画只驱动骨骼姿势，切换动画不会改变角色位置。

## 在 Godot 里怎么用

```gdscript
# 模型挂到 Player 下后（导入场景内含 AnimationPlayer）
@onready var anim: AnimationPlayer = $PlayerKnight/AnimationPlayer

# 行走（循环）：速度 > 阈值时播放；注意 Walk 为原地动画，位移由代码给
anim.play("Walk")

# 翻滚 / 攻击
anim.play("RollLeap")   # 与 player.gd 的 roll_time = 0.42 对齐
anim.play("Slash")      # 命中窗 0.13–0.30s，与 attack_active_start/end 对齐

# 跳跃：起跳瞬间 → 离地后循环悬空 → 落地回 Idle/Walk
anim.play("JumpStart")
anim.queue("JumpAir")
```

## 重新生成

- `animations/*.tres`：在项目根目录运行
  `Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tools/split_player_animations.gd`
- `player_knight.glb`：在 Blender 打开 `E:\blender\blenderproject\player_knight\knight-player.blend`
  → File → Export → glTF 2.0 (.glb，勾选 Animation) → 覆盖本目录同名文件
