# brute_01 —— 敌人「红甲守卫·壮汉」资产（Godot 侧）

> ⚠️ **模型源文件不在本目录**，也不在 Godot 项目里。所有 `.blend` 源文件、生成脚本与完整预览图在：
> `E:\blender\blenderproject\enemies\brute_01\`（唯一来源，见该目录下的 README.md）
> 这里只放**引擎需要的产物**，按类型分类存放。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `brute_rigged.glb` | 绑定好的模型：1 网格 + **21 根骨骼**（Skin）+ **6 段动画**，**不含武器** |
| `club_01.glb` | 大棒槌，**独立资产**（原点 = 握把中心，槌头沿自身局部 −Z） |
| `previews/` | 各动画代表帧（`stand_front.png`、`walk_13_contact_R.png`、`windup_13_raised.png`、`attack_07_strike.png`、`hit_04_recoil.png` 等） |

## 模型规格

- 尺寸：原始总高 **3.006 m**（脚底→角尖）；`enemy.gd` 会缩放到 `model_target_height = 2.66 m`
  （= 改造前程序化外观的总高，保证换模型后体型观感不变），缩放系数 **0.8849**
- 朝向：模型 **−Z 为前向**（Blender +Y → 导出 yup → Godot −Z），与 `enemy.gd` 的 `_face_point` 一致
- 脚底已在 Blender 里精确踩 `z = 0`，导入后 `y = 0.0000`，脚不穿地也不悬空
- 材质：6 个纯色 Principled 材质（无贴图），低多边形方块风；前 4 个色值与
  `enemy.gd` 的 `_make_mat(...)` **刻意完全一致**
- 骨骼（21）：`root → hips → spine → chest → neck → head`；
  `chest → shoulder.L/R → upperarm.L/R → forearm.L/R → hand.L/R →（hand.R → weapon.R）`；
  `hips → thigh.L/R → shin.L/R → foot.L/R`
- 蒙皮方式：刚性蒙皮（每个部件 100% 绑定 1 根骨骼，权重 = 1.0）

## 动画（Blender 24 fps；Godot 导入按 `animation/fps=30` 重采样）

| 动画名 | 帧 | 内容时长 | 循环 | 对应 `enemy.gd` 状态 |
| --- | --- | --- | --- | --- |
| `Idle` | 1–49 | 2.000 s | ✅ | IDLE / RECOVER |
| `Walk` | 1–25 | 1.000 s | ✅ | CHASE（移动中） |
| `AttackWindup` | 1–13 | 0.500 s | — | WINDUP（`windup_time`） |
| `Attack` | 1–7 | 0.250 s | — | STRIKE（`strike_time`） |
| `Hit` | 1–11 | 0.417 s | — | STAGGER（`_stagger_time`：普通受击 0.4 s / 被完美格挡 **0.8 s**）；**BROKEN（失衡）**时按 0.6 s 播一遍后冻在末帧 |
| `Death` | 1–31 | 1.250 s | — | DEAD（单次，播完**冻末帧**不复位）。塌倒：站立 → 双腿一软 → 向后坐倒 → **仰面塌地**；整段逐帧贴地（见源 README） |

### 被玩家"完美格挡"弹开：`deflect(duration, from_pos)`

玩家在完美格挡窗口内挡下这一棒时，会调用敌人的 `deflect()`（**不是** `take_damage()`）：

| | `take_damage(amount, from_pos)` | `deflect(duration, from_pos)` |
| --- | --- | --- |
| 掉血 | 掉 `amount` | **一点不掉** |
| 硬直 | `stagger_time` = 0.4 s | 由调用方传（玩家侧 `block_parry_stagger`，默认 **0.8 s**） |
| 击退 | `knockback_strength` = 7.0 | × `parry_knockback_scale` = **1.4** |
| 闪光 | 1.0 | **1.5**（更亮，提示"被弹开"） |
| 攻击冷却 | 不变 | `max(_attack_cd, duration)`，硬直后不会立刻又抡过来 |
| **失衡值** | **不加** | **+`parry_poise_percent`（默认 34% → 3 次失衡）** |

- 【为什么单独开一个方法】`take_damage` 的语义是"造成伤害"，传 0 会白广播一次血量变化信号，
  而且 `Health` 处于无敌时会返回 `false` 导致硬直也进不去。弹反 = "被挡开"，与血量无关。
- 【为什么要传 duration】反击窗口长短属于**玩家格挡手感**，数值放在 `player.gd` 统一调；
  敌人只负责"进入硬直 X 秒"。
- `Hit` 动画会被 `_play_once(_hit_anim, _stagger_time)` 按 0.8 s 拉伸 → 0.52 倍速慢放，
  大块头被打得踉跄后退，正好读得出"被弹开"的感觉。
- ⚠️ **已经 BROKEN（失衡）时再次被完美格挡 → 保持 BROKEN**，只给击退+闪光、不再加失衡值。
  否则玩家在失衡窗口里"多弹一下"会把处决窗口取消掉（表现为"处决突然没反应"）。

### 失衡（`BROKEN` 状态）与处决

本敌人挂了 `Poise` 组件（`scripts/components/poise.gd`），场景里与 `Health` 平级的 `Poise` 子节点：

```
EnemyBrute(CharacterBody3D)
  ├─ CollisionShape3D
  ├─ Health     max_hp = 100
  └─ Poise      max_poise = 100, break_time = 3.0
```

| 项 | 值 | 说明 |
| --- | --- | --- |
| `parry_poise_percent` | **34.0** | 每次完美格挡加上限的 34% → **3 次顶满**。小怪 50(2 次) / 重甲 25(4 次) / Boss 20(5 次) |
| `execute_damage_scale` | 1.0 | 处决伤害倍率。普通守卫 1.0（玩家处决 75 → 100 血剩 25，**不秒杀**，补一刀收尾）；精英/Boss 调低即可让它更抗处决 |
| `max_poise` | 100.0 | 失衡条上限（组件参数） |
| `break_time` | 3.0 | 失衡持续时长(秒)（组件参数） |
| `break_keep_ratio` | 0.0 | 失衡结束后清空重攒（0.5 = 保留一半，难度旋钮） |

进入 `BROKEN` 后（`_on_poise_broken()`）：

- 命中盒**关闭** → 这段时间绝对打不到玩家
- 播 `Hit`（0.6 s 常速）后**冻在末帧**（垂头半跪），再叠加 `rotation.z` 左右打晃 + 重心下沉 0.12 m
- 每物理帧检查 `poise.is_broken()`，倒计时归零 → 自动回 `CHASE`
- 玩家在 2.6 m 内按左键 → `player.gd` 的 `EXECUTE` 状态 → 调用本脚本的 **`execute(amount, from_pos)`**：
  - 伤害 = `amount × execute_damage_scale`，走 `health.damage()`
  - **不打断 BROKEN**（处决演出要敌人一直站不稳），并 `poise.refresh_break()` 把倒计时顶回满
  - 血量没归零 → 保持 BROKEN 姿势 + 强闪光 + 半力击退

**★ 挨完处决还活着时，敌人会"爬起来" —— `end_break_after_execution()`**（2026-09-20 新增）

玩家的处决伤害是**大量但不致命**的（默认 75 → 满血 100 剩 25），所以敌人常常扛得住。
这时**由玩家侧在收招那一刻**（`player.gd::_end_execute`）调用这个入口，主动收掉 BROKEN：

- **为什么必须收**：不收的话敌人永远站不稳，玩家能原地连按左键**无限连处决**（还全程无敌），
  处决就从"3 次完美格挡换来的高光"退化成"刷伤害的循环"，普通挥砍被架空；
  而且敌人永远不起来，战斗进不了收尾阶段
- **为什么不写在 `execute()` 里**：那一刻演出才刚开始，敌人当场站直会变成"在处决动画里复活"。
  必须等玩家把 `Execute` 演完
- 收掉后 BROKEN 分支下一物理帧轮询到 `poise.is_broken() == false` → 自动转 `CHASE`
- 于是处决的完整节奏是：**处决重创（75）→ 敌人爬起来 → 补一刀（25）击杀**

> `execute()` 与 `take_damage()` 的差别：后者会把状态打成 `STAGGER`，
> 而处决要求敌人**保持 BROKEN**，所以单独开一个入口。
> 另注：`take_damage()` 也做了保护 —— 已在 BROKEN 时**不变状态**，
> 免得被普通攻击蹭一下就把失衡提前结束。

### ⚠️ 帧偏移约定：`Godot length = 内容时长 + 1/24`（不是 bug）

Blender 的 glTF 导出器把关键帧时间写成 `frame/fps`，而 Action 帧范围是 `1..N`，
所以 GLB 里的时间轴是 `0.0417 .. N/24`，**首帧不在 0**。
Godot 导入时会把时间轴平移到从 `t = 0` 开始，但 **`Animation.length` 保留的是源末帧的绝对时刻 `N/24`**：

| 动画 | 内容时长 | Godot `length` |
| --- | --- | --- |
| `Idle` | 2.0000 | **2.0417** |
| `Walk` | 1.0000 | **1.0417** |
| `AttackWindup` | 0.5000 | **0.5417** |
| `Attack` | 0.2500 | **0.2917** |
| `Hit` | 0.4167 | **0.4583** |
| `Death` | 1.2500 | **1.2917** |

- **玩家模型 `player_knight.glb` 同样如此**，属管线固有行为，两边保持一致。
- 循环段（Idle / Walk）源动画**首尾帧姿势完全相同**，所以 wrap 回 0 时姿势连续、
  循环本身无缝，只是周期比标称长 1 帧。
- `enemy.gd` 的 `_play_once(anim, duration)` 是按 `length / duration` **现算倍速**的，
  会把多出的 1 帧一起压缩进 `duration`，所以状态机时长不受影响。
- **别为了消掉这 1 帧去改 BLENDER 的帧区间** —— 那会连带改变 `length`，
  直接打破 `tools/autotest/m1_autotest.tscn` 里已固化的断言（如"翻滚动画倍速有效: 1.091"）。

## 位移约定（接入代码时必须知道）

- **动画不含净水平位移**：前进/前冲由 `enemy.gd` 的速度逻辑负责，避免播完残留偏移。
- `Walk` 的"自然前进速度" = 单步 0.8288 m × 2 步 ÷ 1.0 s = **1.66 m/s**
  （由 `probe_stride.py` 实测得出，对应 `enemy.gd` 的 `walk_natural_speed`）。
  播放倍速 = 当前移动速度 ÷ 1.66（上限 2.0），这样脚步与地面基本同步、不打滑。
- 动画只驱动骨骼姿势，切换动画不会改变角色位置。

## 武器挂载（与角色分离）

- `club_01.glb` 的原点在**握把中心**，槌头沿自身局部 **−Z**（实测包围盒 z 从 +0.33 到 −1.43）。
- 角色里只留**挂点骨骼 `weapon.R`**（位于右手手心）。
- `enemy.gd` 用 `BoneAttachment3D`（`bone_name = "weapon.R"`）挂载，
  对齐偏移 `ENEMY_WEAPON_ALIGN_LOCAL = Transform3D(Basis(Vector3(1,0,0), PI/2), ZERO)`
  （绕 X +90°，把 −Z 扳到挂点 +Y）。
- ⚠️ **对齐偏移必须设在"武器的子节点"上**：`BoneAttachment3D` 自身的 transform
  每帧都会被骨骼姿势覆盖，设在它上面等于没设。
- 换武器只换这个文件，**角色与全部动画都不用动**。

> 💡 本模型 `weapon.R` 的骨轴是**斜向前下方**（不是骑士那样的水平前方）——
> 因为静止姿势是双臂自然下垂，挂点若指水平前方，大棒会像长矛一样横举在胯高。

## 在 Godot 里怎么用

`enemy.gd` 已改为**模型优先、程序化兜底**，通常你不需要手动操作 —— 挂上 `EnemyBrute` 场景即可：

```gdscript
# 外观在 _build_body() 里自动完成：
#   优先 _setup_model()  →  识别 6 段动画、缩放对齐、挂武器
#   失败则 _build_procedural_body()  →  回到旧的原语外观（删掉 glb 也不会崩）
```

按状态手动播动画（当你不想要自动状态机时）：

```gdscript
@onready var anim: AnimationPlayer = $VisualPivot/BruteModel/AnimationPlayer

anim.play("Walk")            # 循环动画，enemy.gd 的 _set_loop 已置 LOOP_LINEAR
anim.play("AttackWindup")    # 蓄力（windup_time = 0.5，与动画内容时长对齐）
anim.play("Attack")          # 下劈（strike_time = 0.22）
anim.play("Hit")             # 受击硬直（倍速铺满 _stagger_time：普通 0.4s / 被完美格挡 0.8s）
```

## 验证与重新生成

```bash
# 资产自检（21 骨骼 / 挂点 / 缩放 / 6 动画时长 / 武器对齐；exit=0 即全过）
D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe --headless \
  --path D:\GodotProject\first-game --script res://tools/verify_enemy_model.gd

# 解析 GLB 时间轴（纯 Python，不需要 Godot）
python E:\blender\blenderproject\enemies\brute_01\scripts\probe_glb_times.py \
  D:\GodotProject\first-game\assets\enemies\brute_01\brute_rigged.glb
```

重新生成 GLB：在 `E:\blender\blenderproject\enemies\brute_01\` 下
用 `scripts/build_brute.py -- all` 重建，再 `scripts/export_glb.py` 导出，
最后把 `export/` 下的两个 `.glb` 覆盖到本目录（详见该目录 README.md）。

> ⚠️ **改完模型记得回来跑一次自检脚本** —— 尤其是"动画时长"和"武器对齐"两项，
> 改了 Blender 的帧区间或挂点轴向，很容易在 Godot 侧悄悄错位。
>
> ⚠️ **覆盖 .glb 后若自检报"动画段数少了"，先清导入缓存再重导**：Godot 4.7.2 的
> `--import` 偶尔会"更新了 `.godot/imported/<name>-*.md5` 却没换掉 `-*.scn`"，
> 之后两次 `--import` 都会认为"已最新"而跳过，于是永远用旧的 `.scn`。
> 处置：删掉该资产的 `-*.md5` / `-*.scn`（含残留 `*.tmp`）后重跑 `--import`，
> 再用本自检脚本回读动画名确认（本项目 T04 真踩过：GLB 已是 6 段、Godot 只报 5 段）。
