extends CharacterBody3D
class_name PlayerCharacter
## ============================================================
## 玩家角色：状态机 + 外观（支持外部模型 / 原语兜底）
## ============================================================
## 【这个脚本做了什么】
##   第三人称动作游戏的主角控制：
##     - 移动：WASD 相对镜头方向平移（视角朝向哪，W 就往哪走）
##     - 翻滚：Shift，带位移与全程无敌帧（用来躲敌人攻击）
##     - 攻击：鼠标左键挥剑，命中面前敌人造成伤害
##     - 受击/死亡：被打会硬直+击退+闪白；血空倒地死亡
##
## 【外观两种形态】
##   1) 外部模型（默认）：加载 assets/characters/player_knight/player_knight.glb，
##      自动测量模型高度缩放到 1.8m 并落到脚底 y=0。
##      该 GLB 是"带 21 根骨骼的绑定模型"，内含 5 段骨骼动画（按名字自动识别）：
##        Walk       1.00s  循环  行走（原地，位移由本脚本负责）
##        RollLeap   0.417s 单次  跃起前滚翻（原地翻一圈，不含前移）
##        Slash      0.50s  单次  举剑过顶→前下劈（0.13~0.30s 为剑刃最快段）
##        JumpStart  0.333s 单次  蹲身→蹬地→踮脚离地（起跳瞬间播）
##        JumpAir    0.50s  循环  空中收腿+展臂平衡（离地后循环播）
##      识别到的动画会在对应状态自动播放；缺失的动画仍由本脚本做"整体姿态"
##      （奔跑起伏/攻击前倾/受击后仰/死亡倒地）与受击闪光兜底。
##   2) 原语兜底：找不到模型时用胶囊/球/方块拼装的"小蓝人"，
##      支持更细的肢体动画（摆腿/挥剑），逻辑保持不变。
##
## 【状态机设计（核心）】
##   state 变量保存当前状态，_physics_process 里按状态算速度，
##   _process 里按状态摆姿势(动画)。状态切换都是"改 state + 归零计时"：
##
##     MOVE(移动/待机) ──攻击键──▶ ATTACK(挥剑)
##     MOVE            ──翻滚键──▶ ROLL(无敌翻滚)
##     MOVE            ──跳跃键──▶ JUMP(起跳/滞空) ──落地──▶ MOVE
##     MOVE            ◀──超时── ATTACK / ROLL / HURT
##     HURT(受击硬直)  ──被打死──▶ DEAD(倒地)
##
## 【输入读取方式】
##   攻击/翻滚/跳跃在 _physics_process 里用 Input.is_action_just_pressed 轮询，
##   而不是靠 _unhandled_input 事件回调 —— 轮询不依赖事件是否被 UI 吃掉，
##   更稳定。镜头鼠标环绕在 camera 脚本里用 _input 读取。
##
## 【节点结构】
##   Player(CharacterBody3D，本脚本)
##   ├─ CollisionShape3D   胶囊碰撞(决定"身体"占多大)
##   ├─ Health             通用血量组件(scripts/components/health.gd)
##   └─ VisualPivot(代码生成) 外观根节点：只转它=转身，碰撞体不受影响
##       ├─ KnightModel 或 原语各部件
##       └─ AttackHitbox 攻击命中盒(Area3D)
## ============================================================

## 信号：玩家死亡（主场景收到后显示死亡遮罩）
signal player_died

## 状态枚举：一次只能处于一种状态（详见文件头状态机图）
enum State { MOVE, ROLL, ATTACK, HURT, JUMP_PREP, JUMP, DEAD }


# ------------------------------------------------------------------
# 手感参数（@export → 在编辑器选中 Player 节点即可实时调整试手感）
# ------------------------------------------------------------------

@export var move_speed: float = 6.2          # 走路/跑步最大速度(米/秒)
@export var accel: float = 22.0              # 加速度：越大起步/急停越快(更跟手)
@export var turn_speed: float = 14.0         # 转身速率：角色模型追移动方向的速度
@export var roll_speed: float = 4.0          # 翻滚位移速度(米/秒)；动画自带 1.0m 前跃由 _end_roll 过继给本体，两者相加约 2.2m
@export var roll_time: float = 0.42          # 翻滚持续时间(秒)，期间无敌
@export var attack_damage: int = 25          # 每次挥砍伤害（敌人100血→4刀）
@export var attack_cd: float = 0.42          # 攻击冷却：两次攻击的最小间隔
@export var attack_total: float = 0.5        # 一次攻击总时长(起手+挥砍+收招)
## 命中判定窗（判定帧期间攻击命中盒开启）。
## 【数值按动画实测】采样 Slash 动画里 hand.R/weapon.R 的角速度曲线：
##   举剑段 0~0.16s(≤90°/s) → 劈砍最快段 0.18~0.30s(峰值 496°/s @0.26s) → 收招段。
##   换算到游戏时间（动画 0.542s ÷ attack_total 0.5s ≈ 1.083 倍速）：
##   0.19s/1.083 ≈ 0.17、0.30s/1.083 ≈ 0.28。
## 所以取 0.17~0.28：只有"剑刃真正划过"时才判定，避免举剑阶段就打出伤害。
## 复现方式：godot --headless --path . --script res://tools/inspect_rig.gd -- <骑士glb> Slash
@export var attack_active_start: float = 0.17 # 判定帧开始(游戏时间，秒)
@export var attack_active_end: float = 0.28   # 判定帧结束(游戏时间，秒)
@export var knockback_strength: float = 9.0  # 受击时的击退初速度

## —— 跳跃手感（数值都在编辑器里可调）——
@export var jump_velocity: float = 7.4            # 起跳初速度(米/秒)；最高点 ≈ v²/(2g) ≈ 1.1m
@export var jump_cut_multiplier: float = 2.0      # 上升中松开跳跃键时的额外重力倍数 → 轻点=小跳
@export var fall_gravity_multiplier: float = 1.35 # 下落阶段的额外重力倍数 → 落地更干脆
@export var air_accel: float = 9.0                # 空中水平操控加速度(小于地面 accel → 跳跃有承诺感)
@export var coyote_time: float = 0.12             # 土狼时间：刚离开地面仍可起跳的宽限(秒)
@export var jump_buffer_time: float = 0.15        # 跳跃缓冲：落地前提前按跳跃也算数(秒)
@export var land_squash_time: float = 0.18        # 落地压缩(视觉)持续时间(秒)
## 起跳蓄力(预备)时长(秒)：按跳跃键后**先在地面**播完 JumpStart 的蹬地段，才真正离地。
## 【为什么需要】JumpStart 是"蹲身→蹬地→踮脚离地"的地面动作；若一按就立刻给向上速度，
##   人已经飞到空中了还在播蹬地动画（动画与位移不同步）。
## 取值权衡：越大越"有重量感"但起跳越迟钝；0.15~0.22 比较跟手，0 = 立即起跳(无蓄力)。
@export var jump_prep_time: float = 0.18

## —— 行走动画对齐 ——
## Walk 动画的"自然前进速度"(米/秒) = 一个周期的步幅 ÷ 周期时长。
## 本模型 Walk：0.5m × 2 步 ÷ 1.0s ≈ 1.0 m/s。
## 播放倍速 = 当前移动速度 ÷ 这个值（这样脚步与地面基本同步、不打滑）。
@export var walk_natural_speed: float = 1.0
## 行走动画的播放倍速上限。move_speed(6.2) 远高于自然步速(1.0)，
## 不设上限腿会快成"电风扇"；设上限的代价是跑动时仍有轻微滑步。
## 想彻底消除滑步，需要美术侧再出一段 Run（步幅更大的循环动画）。
@export var walk_max_speed_scale: float = 2.0

## 重力加速度(米/秒²)。动作游戏常用比现实重力略大，手感更"沉"
const GRAVITY := 24.0


# ------------------------------------------------------------------
# 玩家模型（可选）。要换角色模型时，替换这里的路径即可
# 模型资产按类型分类存放：assets/characters/player_knight/
#   ├─ player_knight.glb   （模型+骨骼+5 段动画）
#   ├─ animations/         （从 GLB 抽出的独立动画 .tres，由 tools/split_player_animations.gd 生成）
#   └─ previews/           （各动画代表帧，仅供参考）
# 源文件（.blend）在 E:\blender\blenderproject\player_knight\，不在 Godot 项目内
# ------------------------------------------------------------------

## 玩家外观模型（.glb/.tscn 均可）。带骨骼动画的模型会自动识别并播放其中的动作。
const PLAYER_MODEL := preload("res://assets/characters/player_knight/player_knight.glb")
## 模型应缩放到的"站高"(米)。碰撞胶囊高 1.8，默认让模型与之匹配
const MODEL_TARGET_HEIGHT := 1.8

## 武器资产：与角色**分离**存放 —— 换武器只换这个文件，角色与全部动画都不用动。
## 资产约定（本资产实测）：原点 = 握把中心；刀身沿局部 **-Z**（护手 z≈±0.14、刀身 z -0.145~-1.0）
const PLAYER_WEAPON := preload("res://assets/weapons/sword_01/sword_01.glb")
## 武器挂点骨骼名（角色模型里的空骨骼）。换手/背挂只需改这里，或再建挂点骨骼。
const WEAPON_SOCKET := "weapon.R"
## 挂点对齐变换（相对挂点骨骼）：让**握柄停在骨骼原点(拳心)、刀身沿骨骼 +Y 朝向身前**。
## 【为什么沿 +Y】挂点骨骼 weapon.R 的静止基实测为：
##   +Y ≈ 模型前方(-Z)、+Z ≈ 模型上方、+X ≈ 模型右侧 —— 骨骼本身就是"沿 +Y 指向前方"的持械轴。
##   而武器刀身沿自身 -Z，所以绕骨骼 X 轴 +90°（-Z → +Y）即可把刀身扳到身前。
## 【为什么不沿用旧位置】武器分离前旧模型里剑是**竖直朝上**贴在手臂外侧的，
##   照抄那个位置会让刀身陷在手臂网格里（实测剑与手臂包围盒重叠），视觉上像"嵌在手臂中"。
##   朝前握持才是正常姿态。
## 【怎么验证】tools/check_weapon.tscn 会打印"握柄到拳心距离"和"刀身指向与模型前方的夹角"；
##   自动测试也有对应断言（握柄≈拳心、刀身朝前、挥砍时跟随手臂）。
const WEAPON_ALIGN_LOCAL := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)

## 是否正在使用外部模型（true=用模型；false=用原语小蓝人兜底）
var _use_model: bool = false
## 模型自带的动画播放器（GLB 内嵌动画时存在；静态模型则为 null）
var _anim_player: AnimationPlayer = null
## 识别到的"翻滚动画"名（按名字含 roll 自动识别；没有则空字符串=走兜底动画）
var _roll_anim: String = ""
## 翻滚动画播放倍速：让动画恰好铺满 roll_time 秒，与位移/无敌帧同步
var _roll_anim_speed: float = 1.0
## 翻滚动画里"被位移驱动"的节点（本项目为 EMT-KnightRoot/EMT-RollPivot）
var _roll_pivot: Node3D = null
## 该节点的静止姿势（翻滚结束时用它把模型复位，见 _end_roll）
var _roll_pivot_rest_pos: Vector3 = Vector3.ZERO
var _roll_pivot_rest_rot: Vector3 = Vector3.ZERO
## 其余识别到的骨骼动画名（空字符串 = 该动作没有动画资源，走脚本姿态兜底）
var _walk_anim: String = ""
var _slash_anim: String = ""
var _jump_start_anim: String = ""
var _jump_air_anim: String = ""
## 武器挂点（BoneAttachment3D，挂在模型的 weapon.R 骨骼上）
var _weapon_socket: BoneAttachment3D = null
## 当前装备的武器节点（徒手时为 null）
var _weapon: Node3D = null
## 武器相对挂点的对齐偏移（= WEAPON_ALIGN_LOCAL，设在武器子节点上，见 _attach_weapon）
var _weapon_align_local: Transform3D = Transform3D.IDENTITY
## 模型的骨骼节点：用于"没有动画时"把骨骼复位成绑定姿势（见 _anim_to_rest）。
## 为什么需要：骨骼动画一停播，骨骼会冻在停播那一帧的姿势上。
var _skeleton: Skeleton3D = null


# ------------------------------------------------------------------
# 运行时状态变量
# ------------------------------------------------------------------

var state: State = State.MOVE      # 当前状态（见 State 枚举）
var _state_time: float = 0.0       # 当前状态已持续的时间(秒)，用于判定"该切换到下一个状态了"
var _attack_cooldown: float = 0.0  # 攻击冷却倒计时(秒)，>0 时不能攻击
var _iframes: float = 0.0          # 受击后的短暂无敌倒计时(秒)，>0 时伤害无效
var _dead: bool = false            # 是否已死亡（死亡后忽略一切输入/伤害）


# ------------------------------------------------------------------
# 外观引用
# ------------------------------------------------------------------

var _pivot: Node3D                 # VisualPivot：外观根节点，旋转=转身
## —— 仅"原语小蓝人"模式用 ——
var _shoulder_r: Node3D            # 右肩节点（剑挂在它下面，挥剑=转它）
var _shoulder_l: Node3D            # 左肩节点
var _leg_r: Node3D                 # 右腿节点（走路时摆腿）
var _leg_l: Node3D                 # 左腿节点
## —— 通用 ——
var _hitbox: Area3D                # 攻击命中盒（面前的长方体感应区）
var _hit_targets: Array = []       # 本刀已经打中的敌人（防止一刀多次伤害）
var _mats: Array[StandardMaterial3D] = []  # 外观材质（受击闪白要批量改它们）


# ------------------------------------------------------------------
# 运动缓冲变量
# ------------------------------------------------------------------

var _wish_dir: Vector3 = Vector3.ZERO  # 本帧"想要的移动方向"(由输入+镜头换算)
var _facing_dir: Vector3 = Vector3.FORWARD  # 朝攻击/翻滚方向（默认朝 -Z）
var _roll_dir: Vector3 = Vector3.ZERO   # 翻滚的方向（进入 ROLL 时锁定）
var _bob_phase: float = 0.0            # 跑步摆腿/起伏的相位(累加时间产生循环)
var _hurt_from: Vector3 = Vector3.ZERO # 受击来源位置（决定击退方向）
var _coyote: float = 0.0               # 土狼时间剩余(秒)：离地后仍允许起跳的宽限
var _jump_buffer: float = 0.0          # 跳跃缓冲剩余(秒)：落地前提前按也算数
var _squash: float = 0.0               # 落地压缩计时(秒，纯视觉)

## Health 组件的引用（场景里的子节点，onready=子节点就绪后自动取）
@onready var health: Health = $Health


# ------------------------------------------------------------------
# 引擎回调
# ------------------------------------------------------------------

## 进入场景：注册组、拼装外观、接通命中盒信号、监听血量归零。
func _ready() -> void:
	add_to_group("player")         # 让敌人AI/镜头/主场景能按组找到玩家
	_build_body()                  # 优先用骑士模型，失败则回退原语小蓝人
	_connect_hitbox_signals()      # 命中盒的"有东西进入"信号接好
	health.died.connect(_on_health_died)


## 供外部(AI/主场景)查询：还活着吗？
func is_alive() -> bool:
	return not _dead


## 物理帧主循环：推进计时 → 轮询攻击/翻滚/跳跃键 → 更新方向/速度 → 移动 → 检查状态切换
func _physics_process(delta: float) -> void:
	_state_time += delta                           # 状态计时
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_iframes = maxf(0.0, _iframes - delta)         # 无敌倒计时递减
	_coyote = maxf(0.0, _coyote - delta)           # 土狼时间递减
	_jump_buffer = maxf(0.0, _jump_buffer - delta) # 跳跃缓冲递减
	_squash = maxf(0.0, _squash - delta)           # 落地压缩递减
	if is_on_floor():
		_coyote = coyote_time                      # 站在地面上就刷新土狼时间
	# ★ 攻击/翻滚/跳跃都用"轮询"读取：不依赖事件是否被 UI 吞掉，稳定可靠
	if Input.is_action_just_pressed("attack"):
		_try_start_attack()
	if Input.is_action_just_pressed("roll"):
		_try_start_roll()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time            # 先记进缓冲，落地瞬间会自动补跳
	if _jump_buffer > 0.0:
		_try_start_jump()                          # 不满足条件时(如已在空中)会被函数自己拒绝
	_update_wish_dir()                             # 读输入算出移动意图
	_update_velocity(delta)                        # 按状态给 velocity 赋值
	move_and_slide()                               # 让引擎真正移动+碰撞+落地
	_update_state(delta)                           # 状态超时→切换


# ------------------------------------------------------------------
# 输入 → 移动意图 / 状态启动
# ------------------------------------------------------------------

## 把 WASD + 镜头朝向换算成世界系移动方向(_wish_dir)。
## 实现：镜头"前进方向"和"右方向"做基向量，W=前进、D=右移，
##       组合后若长度>1(斜向)则归一化，保证斜走不比直走快。
func _update_wish_dir() -> void:
	if _dead or state == State.DEAD:
		_wish_dir = Vector3.ZERO
		return
	if state == State.ROLL:          # 翻滚期间不接受方向输入(方向已锁定)
		return
	var fwd_in := Input.get_axis("move_back", "move_forward")  # W→+1, S→-1
	var side_in := Input.get_axis("move_left", "move_right")   # D→+1, A→-1
	var cam := _get_camera()
	var f := Vector3.ZERO
	var r := Vector3.RIGHT
	if cam != null:
		f = -cam.global_basis.z      # 镜头局部 -Z = 它看向的方向
		r = cam.global_basis.x       # 镜头局部 X = 它的右边
	f.y = 0.0                        # 只看水平分量(角色不会飞)
	r.y = 0.0
	f = f.normalized()
	r = r.normalized()
	_wish_dir = (f * fwd_in + r * side_in)
	if _wish_dir.length() > 1.0:
		_wish_dir = _wish_dir.normalized()


## 尝试开始攻击（只有站立/移动状态且冷却结束才允许）。
## 一进入就把命中盒关闭；真正能打人的时刻由 _process 按时间窗开启。
func _try_start_attack() -> void:
	if state != State.MOVE or _attack_cooldown > 0.0 or _dead:
		return
	state = State.ATTACK
	_state_time = 0.0
	_hit_targets.clear()             # 新的一刀，清空"已命中"记录
	# 朝哪打：有移动输入就朝移动方向，否则朝镜头方向
	var aim := _wish_dir if _wish_dir.length() > 0.1 else _get_camera_forward()
	if aim.length() > 0.1:
		_face_instant(aim)           # 瞬间转身(攻击要跟手，不能慢慢转)
		_facing_dir = aim
	_set_hitbox_active(false)
	# 挥砍动画：按"动画时长 ÷ attack_total"换算播放倍速，让收招与状态切换对齐
	# （本模型 Slash 0.5s、attack_total 0.5s → 倍速 1.0；判定窗 0.13~0.30s 正好是剑刃最快段）
	if _anim_player != null and _slash_anim != "":
		var a := _anim_player.get_animation(_slash_anim)
		var spd := 1.0
		if a != null and a.length > 0.01:
			spd = a.length / maxf(0.05, attack_total)
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_slash_anim, -1.0, spd)


## 尝试开始翻滚（只有站立状态允许）。
## 翻滚方向=当前移动方向；没按方向就朝脸朝向滚。
## 关键：health.invincible=true → 翻滚全程免疫伤害（无敌帧）。
func _try_start_roll() -> void:
	if state != State.MOVE or _dead:
		return
	state = State.ROLL
	_state_time = 0.0
	health.invincible = true
	if _wish_dir.length() > 0.1:
		_roll_dir = _wish_dir.normalized()
	else:
		_roll_dir = _get_facing_flat()
	# 让"身体朝向"立刻对齐翻滚方向：模型动画是朝身体正前方(-Z)前跃的，
	# 不转身的话侧向翻滚会出现"人往前跃、实际往侧面飘"的错位。
	_face_instant(_roll_dir)
	# 模型自带翻滚动画(如 RollLeap)时播放它；stop() 先归零，避免残留上次进度。
	if _anim_player != null and _roll_anim != "":
		_anim_player.stop()
		_anim_player.play(_roll_anim, -1.0, _roll_anim_speed)


## 尝试起跳（由物理帧里的"跳跃缓冲"驱动调用）。
## 可以被接受的情况：
##   ① 正站在地面上；② 刚离开地面不久（还在 coyote_time 土狼时间内）。
## 会被拒绝的情况：翻滚/攻击/受击硬直中、已经在跳跃流程里（不做二段跳）、已死亡。
## 【两段式起跳】站在地面且有 JumpStart 动画时，先进入 JUMP_PREP 蓄力段
##   （原地播完蹬地动作，**仍在地面**），蓄力结束才由 _launch_jump() 真正给向上速度；
##   若人已在空中（走下平台的土狼跳），则跳过蓄力直接进入 JUMP。
func _try_start_jump() -> void:
	if _dead or state == State.ROLL or state == State.ATTACK or state == State.HURT:
		return
	if state == State.JUMP or state == State.JUMP_PREP:
		return                                      # 已在跳跃流程中 → 不可二段跳
	if not is_on_floor() and _coyote <= 0.0:
		return                                      # 既不在地面、也不在土狼时间内
	_jump_buffer = 0.0
	_coyote = 0.0
	if is_on_floor() and _anim_player != null and _jump_start_anim != "" and jump_prep_time > 0.01:
		# —— 蓄力段：留在地面，播放蹬地预备动作（按 jump_prep_time 换算倍速）——
		state = State.JUMP_PREP
		_state_time = 0.0
		var a := _anim_player.get_animation(_jump_start_anim)
		var spd := 1.0
		if a != null and a.length > 0.01:
			spd = a.length / jump_prep_time          # 0.375s ÷ 0.18s ≈ 2.08 倍速
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_jump_start_anim, -1.0, spd)
	else:
		_launch_jump(true)


## 真正起跳：给向上初速度并进入空中状态（JUMP），切换为滞空循环动画。
## @param with_impulse true=给跳跃初速度(正常起跳)；false=不给冲量(蓄力途中掉下平台)
## 实现要点：竖直速度"直接赋值"而不是插值——起跳要脆、要立刻响应；
##           水平速度不重置，跑动中跳跃能保留冲量(跳跃距离自然更远)。
func _launch_jump(with_impulse: bool) -> void:
	if with_impulse:
		velocity.y = jump_velocity
	state = State.JUMP
	_state_time = 0.0
	if _anim_player != null and _jump_air_anim != "":
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_jump_air_anim, -1.0, 1.0)


## 状态超时检测：每个状态是否该结束/切换（被 _physics_process 每帧调用）。
func _update_state(_delta: float) -> void:
	match state:
		State.MOVE:
			_face_towards(_wish_dir, _delta)      # 走路时身体平滑转向移动方向
			if _wish_dir.length() > 0.1:
				_bob_phase += _delta * 10.0       # 在动才累计跑步相位
			# 走下台阶/跳下平台：过了土狼时间仍未落地 → 进入 JUMP(下落)状态
			if not is_on_floor() and _coyote <= 0.0:
				state = State.JUMP
				_state_time = 0.0
		State.ROLL:
			if _state_time >= roll_time:          # 翻滚时间到 → 结束
				_end_roll()
		State.ATTACK:
			if _state_time >= attack_total:       # 整段攻击(0.5s)放完 → 回移动
				state = State.MOVE
				_state_time = 0.0
				_attack_cooldown = attack_cd      # 并进入冷却
				_set_hitbox_active(false)
		State.HURT:
			if _state_time >= 0.32:               # 受击硬直 0.32s 后恢复行动
				state = State.MOVE
				_state_time = 0.0
		State.JUMP_PREP:
			# 蓄力段（仍在地面）：播蹬地预备动作；时间到 → 真正起跳。
			# 若中途掉下平台（不再是 on_floor 且过了土狼时间）→ 不给冲量直接进入空中。
			if not is_on_floor() and _coyote <= 0.0:
				_launch_jump(false)
			elif _state_time >= jump_prep_time:
				_launch_jump(true)
		State.JUMP:
			# 落地判定：踩到地面且竖直速度已非上升 → 回移动状态 + 落地压缩 + 收掉滞空动画。
			# （起跳的蹬地动画在 JUMP_PREP 的地面阶段就播完了，这里只需处理滞空循环）
			if is_on_floor() and velocity.y <= 0.01:
				state = State.MOVE
				_state_time = 0.0
				_squash = land_squash_time
				if _anim_player != null and _anim_player.is_playing():
					_anim_to_rest()
		State.DEAD:
			pass                                  # 死亡状态保持，等主场景重开


## 结束翻滚：解除无敌、回到移动状态、短暂冷却(防止立刻接攻击/翻滚连滚)。
func _end_roll() -> void:
	health.invincible = false
	# 动画驱动的翻滚：RollLeap 最后一帧停在"向前 1m"处（动画自带的根位移）。
	# 这里把它过继给角色本体（用 move_and_collide，撞墙会少走、不会穿墙），
	# 再把模型复位到站姿。两件事在同一帧内完成 → 模型在屏幕上的位置保持不变，
	# 不会出现"瞬移"或"模型永久领先碰撞体"的问题。
	if _anim_player != null and _roll_anim != "" and _roll_pivot != null:
		var fwd := _get_facing_flat()
		var offset := _roll_pivot.global_position - _pivot.global_position
		var dist := offset.dot(fwd)          # 动画位移在"面朝方向"上的投影
		if dist > 0.05:
			move_and_collide(fwd * dist)
		_roll_pivot.position = _roll_pivot_rest_pos
		_roll_pivot.rotation = _roll_pivot_rest_rot
	# 停掉翻滚动画并复位骨骼：骨骼版 RollLeap 的末帧就是站立姿势（转满 360°、无净前移），
	# 所以在这里收掉不会跳变；不收的话下一段动作会从它停下的位置混进来。
	if _anim_player != null and _roll_anim != "":
		_anim_to_rest()
	state = State.MOVE
	_state_time = 0.0
	_attack_cooldown = maxf(_attack_cooldown, 0.15)
	_pivot.rotation.x = 0.0          # 兜底模式(无动画)的整体旋转复位


# ------------------------------------------------------------------
# 速度计算（每个状态对 velocity 的不同处理）
# ------------------------------------------------------------------

## 按状态设置水平速度，并始终应用重力。
## 平滑手法：velocity 向目标值做帧率无关插值 lerp(x, target, 1-exp(-rate*dt))，
##           数字越大越"贴"，越小越"滑"。
func _update_velocity(delta: float) -> void:
	if not is_on_floor():
		# 重力分三段，做出"起跳跟手、下落利落"的手感：
		#   ① 上升中且按住跳跃键 → 常规重力(跳满高度)
		#   ② 上升中但松开了跳跃键 → 重力×jump_cut_multiplier(轻点=小跳)
		#   ③ 下落中 → 重力×fall_gravity_multiplier(落地更干脆，不飘)
		var g := GRAVITY
		if velocity.y > 0.0:
			if not Input.is_action_pressed("jump"):
				g *= jump_cut_multiplier
		else:
			g *= fall_gravity_multiplier
		velocity.y -= g * delta
	match state:
		State.MOVE:
			var target := _wish_dir * move_speed
			var t := 1.0 - exp(-accel * delta)   # accel 越大越跟手
			velocity.x = lerpf(velocity.x, target.x, t)
			velocity.z = lerpf(velocity.z, target.z, t)
		State.ROLL:
			# 翻滚速度：开头快、随时间衰减到 45%
			var t := clampf(1.0 - _state_time / roll_time, 0.0, 1.0)
			var spd := roll_speed * lerpf(0.45, 1.0, t)
			velocity.x = _roll_dir.x * spd
			velocity.z = _roll_dir.z * spd
		State.ATTACK, State.HURT:
			# 攻击/受击硬直时快速刹停（不能一边走一边挥）
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-12.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-12.0 * delta))
		State.JUMP_PREP, State.JUMP:
			# 蓄力段与空中都用较小的水平加速度：保留起跳冲量，但很难在空中大幅变向
			var target := _wish_dir * move_speed
			var t := 1.0 - exp(-air_accel * delta)
			velocity.x = lerpf(velocity.x, target.x, t)
			velocity.z = lerpf(velocity.z, target.z, t)
		State.DEAD:
			# 死亡后慢慢停住（尸体不滑走）
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-8.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-8.0 * delta))


# ------------------------------------------------------------------
# 受击与死亡
# ------------------------------------------------------------------

## 对外伤害入口（敌人命中盒调用）。
## 顺序：死亡/翻滚/短暂无敌 → 忽略；否则扣血；血空→死亡；否则→受击硬直。
func take_damage(amount: int, from_pos: Vector3) -> void:
	if _dead or state == State.ROLL or _iframes > 0.0:
		return
	if not health.damage(amount):                # Health 组件自身也会挡无敌
		return
	if health.current_hp <= 0:
		_die()
		return
	_enter_hurt(from_pos)


## 进入受击状态：硬直 + 击退 + 0.6s 无敌(防连击) + 闪白 + 面朝伤害来源。
func _enter_hurt(from_pos: Vector3) -> void:
	state = State.HURT
	_state_time = 0.0
	_iframes = 0.6
	_hurt_from = from_pos
	var away := global_position - from_pos       # 远离伤害来源的方向=击退方向
	away.y = 0.0
	if away.length() < 0.01:
		away = -_get_camera_forward()            # 兜底：来源正下方时朝镜头反向飞
	away = away.normalized()
	velocity.x = away.x * knockback_strength
	velocity.z = away.z * knockback_strength
	_flash(0.7)                                  # 白闪一下提示"被打到了"
	_face_instant(away)


## Health 组件血量归零信号的回调 → 进入死亡（与 take_damage 里的路径去重）
func _on_health_died() -> void:
	if _dead:
		return
	_die()


## 进入死亡：锁死一切行动、广播 player_died（主场景弹遮罩）。
func _die() -> void:
	if _dead:            # 防重复触发（damage 内部信号与外部调用可能双到）
		return
	_dead = true
	state = State.DEAD
	_state_time = 0.0
	health.invincible = true    # 死后不再受伤害(尸体不被打)
	_set_hitbox_active(false)
	player_died.emit()


# ------------------------------------------------------------------
# 朝向（转向）工具 —— 都基于"模型的 -Z 是正面"这个约定
# ------------------------------------------------------------------

## 平滑转向：让 VisualPivot 的 Y 轴旋转逐渐对准 dir。
## 公式 rotation.y = atan2(-dir.x, -dir.z) 是因为：绕 Y 转 θ 后，
## 模型正面(-Z)指向 (-sinθ, 0, -cosθ)，反解出 θ。
func _face_towards(dir: Vector3, delta: float, speed: float = -1.0) -> void:
	var flat := dir
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	var rate: float = turn_speed if speed < 0.0 else speed
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-rate * delta))


## 瞬间转身（攻击起手用，保证出手方向跟手）。
func _face_instant(dir: Vector3) -> void:
	var flat := dir
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_pivot.rotation.y = atan2(-flat.x, -flat.z)


## 当前模型朝向的水平单位向量（翻滚无输入时用它定方向）。
func _get_facing_flat() -> Vector3:
	var f := -_pivot.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


## 镜头看向的水平单位向量（静止攻击时朝屏幕中心打）。
func _get_camera_forward() -> Vector3:
	var cam := _get_camera()
	if cam == null:
		return _get_facing_flat()
	var f := -cam.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


## 按组名查找镜头（镜头的 ThirdPersonCamera 脚本把自己加进了 "camera" 组）
func _get_camera() -> Node3D:
	return get_tree().get_first_node_in_group("camera") as Node3D


# ------------------------------------------------------------------
# 攻击命中（Area3D 命中盒）
# ------------------------------------------------------------------

## 连接命中盒信号。Area3D 的 body_entered(撞进身体) / area_entered(撞进区域)
## 信号，在监控打开且目标重叠时触发。
func _connect_hitbox_signals() -> void:
	if _hitbox == null:
		return
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_hitbox.area_entered.connect(_on_hitbox_area_entered)


func _on_hitbox_body_entered(body: Node3D) -> void:
	_on_hitbox_target(body)


## 敌人是 CharacterBody3D(身体)，通常 body_entered 就够；
## 这条兜底处理"目标是个 Area(区域)"的情况，取它的父亲当目标。
func _on_hitbox_area_entered(area: Area3D) -> void:
	var hit_owner := area.get_parent()
	if hit_owner != null and hit_owner != self:
		_on_hitbox_target(hit_owner)


## 命中判定统一出口：
##   只在自己处于 ATTACK 且判定帧内生效；同一次挥砍对同一敌人只打一次
##   (_hit_targets 记录)；只打组别为 "enemy" 且有 take_damage 的活目标。
func _on_hitbox_target(node: Node) -> void:
	if state != State.ATTACK:
		return
	if node == null or _hit_targets.has(node):
		return
	if not node.is_in_group("enemy") or not node.has_method("take_damage"):
		return
	if not node.is_alive():
		return
	_hit_targets.append(node)
	node.take_damage(attack_damage, global_position)


## 开关命中盒：set_deferred 让修改在"安全时机"(物理步结束后)生效，
## 避免在物理回调里直接改监控状态导致报错。
func _set_hitbox_active(active: bool) -> void:
	if _hitbox != null:
		_hitbox.set_deferred("monitoring", active)


# ------------------------------------------------------------------
# 外观构建入口
# ------------------------------------------------------------------

## 搭外观：先尝试加载外部模型(PLAYER_MODEL)；失败则用原语小蓝人兜底。
## 无论哪种，都会创建攻击命中盒挂在 VisualPivot 下(随朝向转动)。
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "VisualPivot"
	add_child(_pivot)

	if PLAYER_MODEL != null:
		_use_model = _setup_model()      # 尝试把骑士模型装进 VisualPivot
	if not _use_model:
		_build_robot_visuals()           # 兜底：原语小蓝人
	_create_attack_hitbox()              # 共用命中盒


## 加载并安置外部模型。
## 实现三步：
##   1. 实例化 GLB；
##   2. 递归收集每个网格部件，用它们的包围盒+节点变换算出模型总包围盒；
##   3. 按 MODEL_TARGET_HEIGHT 统一缩放，并平移到脚底 y=0、水平居中。
## 同时把部件材质登记进 _mats（受击闪光用）。
func _setup_model() -> bool:
	var model := PLAYER_MODEL.instantiate() as Node3D
	_pivot.add_child(model)
	model.name = "KnightModel"

	# 递归收集所有 MeshInstance3D 及其"相对模型根"的变换
	var meshes: Array = []   # 每个元素 { "node": MeshInstance3D, "xform": Transform3D }
	_collect_meshes(model, Transform3D.IDENTITY, meshes)
	if meshes.is_empty():
		model.queue_free()   # 空模型 → 放弃使用
		return false

	# 计算总包围盒(模型局部坐标，未缩放)
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for info in meshes:
		var mi: MeshInstance3D = info["node"]
		var aabb: AABB = mi.get_aabb()
		for corner in _aabb_corners(aabb):
			var p := (info["xform"] as Transform3D) * corner
			mn = mn.min(p)
			mx = mx.max(p)
	if mx.y - mn.y <= 0.001:
		model.queue_free()
		return false

	# 统一缩放到目标身高，并让脚底对齐 y=0、水平居中
	var s := MODEL_TARGET_HEIGHT / (mx.y - mn.y)
	model.scale = Vector3.ONE * s
	model.position = Vector3(
		-(mn.x + mx.x) * 0.5 * s,
		-mn.y * s,
		-(mn.z + mx.z) * 0.5 * s
	)

	# 登记材质：GLTF 导入后通常是每个面一个 StandardMaterial3D
	for info in meshes:
		var mi: MeshInstance3D = info["node"]
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mi.get_active_material(surface)
			if mat is StandardMaterial3D and not _mats.has(mat):
				_mats.append(mat)
	# 识别模型自带动画（Walk/RollLeap/Slash/JumpStart/JumpAir）
	_setup_animations(model)
	# 把独立武器资产挂到骨骼挂点上（武器与角色分离 → 换武器不用改角色和动画）
	_attach_weapon(model)
	return true


## 递归收集模型下所有网格部件和它们相对根节点的累计变换。
## 注意：只递归 Node3D 子节点——模型里可能混有非 Node3D 的节点
## （例如 AnimationPlayer），强转会导致空引用报错。
func _collect_meshes(node: Node3D, parent_xform: Transform3D, out: Array) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D:
		out.append({ "node": node, "xform": xform })
	for child in node.get_children():
		if child is Node3D:
			_collect_meshes(child as Node3D, xform, out)


## 扫描模型自带的动画资源：找到 AnimationPlayer，并按名字识别 5 段动作。
## 识别规则（大小写无关、忽略下划线）：
##   含 roll            → 翻滚（RollLeap），并计算播放倍速让动画铺满 roll_time
##   含 walk            → 行走（循环）
##   含 slash / attack  → 挥砍
##   含 jumpstart/jumpup→ 起跳
##   含 jumpair/air/fall→ 滞空（循环）
## 没识别到的动作，脚本会用"整体姿态"兜底（见 _animate_model）。
func _setup_animations(model: Node3D) -> void:
	_anim_player = _find_animation_player(model)
	if _anim_player == null:
		return
	_skeleton = _find_skeleton(model)      # 蒙皮骨骼（复位姿势时要用）
	for anim_name in _anim_player.get_animation_list():
		var key := String(anim_name).to_lower().replace("_", "")
		if key.contains("roll"):
			_roll_anim = String(anim_name)
			var a := _anim_player.get_animation(anim_name)
			if a != null and a.length > 0.01:
				_roll_anim_speed = a.length / maxf(0.05, roll_time)
			_setup_roll_root_motion(model, a)
		elif key.contains("walk"):
			_walk_anim = String(anim_name)
			_set_loop(_walk_anim)
		elif key.contains("slash") or key.contains("attack"):
			_slash_anim = String(anim_name)
		elif key.contains("jumpstart") or key.contains("jumpup"):
			_jump_start_anim = String(anim_name)
		elif key.contains("jumpair") or key.contains("air") or key.contains("fall"):
			_jump_air_anim = String(anim_name)
			_set_loop(_jump_air_anim)


## 给"循环类"动画打开循环播放。
## 为什么需要：glTF 本身没有循环标记，导入后的 Animation 默认 LOOP_NONE，
## 不打开的话行走/滞空只会播一次就定住。
func _set_loop(anim_name: String) -> void:
	var a := _anim_player.get_animation(anim_name)
	if a != null and a.loop_mode == Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_LINEAR


## 递归查找模型里的 Skeleton3D（蒙皮网格的骨骼）。
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## 把武器资产挂到角色骨骼的挂点上（BoneAttachment3D 挂在 Skeleton3D 下）。
## 挂点自身带一个固定的对齐变换（WEAPON_ALIGN_MODEL），
## 让"武器资产约定(原点=握把中心、刀身 -Z)"落到"手握持、刀身朝上"的正确姿态；
## 之后挥砍/翻滚等动画驱动手臂 → 武器自动跟随，无需为每把武器重做动画。
func _attach_weapon(model: Node3D) -> void:
	if _skeleton == null or PLAYER_WEAPON == null:
		return
	var bone_idx := _skeleton.find_bone(WEAPON_SOCKET)
	if bone_idx < 0:
		push_warning("模型里没有挂点骨骼 %s，武器未装备" % WEAPON_SOCKET)
		return
	_weapon_socket = BoneAttachment3D.new()
	_weapon_socket.name = "WeaponSocket"
	_skeleton.add_child(_weapon_socket)
	_weapon_socket.bone_name = WEAPON_SOCKET
	# 注意：BoneAttachment3D 自己的 transform 每帧都会被"骨骼姿势"覆盖（引擎行为），
	# 所以对齐偏移不能设在挂点上，而要设在**武器子节点**上（见 equip_weapon）。
	_weapon_align_local = WEAPON_ALIGN_LOCAL
	equip_weapon(PLAYER_WEAPON)


## 换武器：传入武器场景（.glb/.tscn）即可；传 null = 徒手（收刀）。
## 约定：武器资产原点 = 握把中心、刀身沿局部 -Z（与 sword_01 一致），
##       对齐由挂点自带的 WEAPON_ALIGN_MODEL 负责，换武器不需要改角色或动画。
func equip_weapon(weapon_scene: PackedScene) -> void:
	if _weapon_socket == null:
		return
	for child in _weapon_socket.get_children():
		child.queue_free()
	_weapon = null
	if weapon_scene == null:
		return
	_weapon = weapon_scene.instantiate() as Node3D
	_weapon.transform = _weapon_align_local    # 对齐偏移（见 _attach_weapon 的说明）
	_weapon_socket.add_child(_weapon)


## 停掉当前动画，并把所有骨骼复位到"绑定姿势"(rest pose)。
## 【为什么必须做】骨骼动画一旦停播，骨骼会**冻结在停播那一帧的姿势**：
##   - 走到一半停下 → 僵在迈步中途（双腿分开）
##   - 落地时收掉 JumpAir → 僵在蜷腿姿势
##   - 受击/死亡时 → 还保留着上一段动作的姿势
## 模型目前没有 Idle / 受击 / 死亡动画，所以这些情况统一复位到 rest pose，
## 再由脚本叠加整体姿态（后仰、倒地、落地压缩等）。
func _anim_to_rest() -> void:
	if _anim_player != null and _anim_player.is_playing():
		_anim_player.stop()
		_anim_player.speed_scale = 1.0
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		var rest: Transform3D = _skeleton.get_bone_rest(i)
		_skeleton.set_bone_pose_position(i, rest.origin)
		_skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		_skeleton.set_bone_pose_scale(i, rest.basis.get_scale())


## 找出翻滚动画里被"位置轨道"驱动的节点（本模型是 EMT-KnightRoot/EMT-RollPivot），
## 并记录它的静止姿势。
## 为什么需要：RollLeap 的最后一帧停在"向前 1m"处（这是动画自带的根位移），
## 翻滚结束时要把它过继给角色本体、并把该节点复位，
## 否则模型会一直比碰撞体靠前 1 米（看着像"人飘在身体前面"）。
func _setup_roll_root_motion(model: Node3D, anim: Animation) -> void:
	if anim == null:
		return
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := anim.track_get_path(i)
		# 轨道路径相对 AnimationPlayer 的 root_node（通常就是模型根）解析
		var node := model.get_node_or_null(path)
		if node == null:
			node = _anim_player.get_node_or_null(path)
		if node is Node3D:
			_roll_pivot = node as Node3D
			_roll_pivot_rest_pos = _roll_pivot.position
			_roll_pivot_rest_rot = _roll_pivot.rotation
			break


## 递归查找第一个 AnimationPlayer。
## 模型层级可能有空节点（如 EMT-KnightRoot → EMT-RollPivot），所以要递归。
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## 返回 AABB 的 8 个角点（显式类型，供循环直接推断）。
func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	var out: Array[Vector3] = [
		p, p + Vector3(s.x, 0, 0), p + Vector3(0, s.y, 0), p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, s.y, s.z),
		p + s
	]
	return out


# ------------------------------------------------------------------
# 原语小蓝人外观（兜底方案）
# ------------------------------------------------------------------

## 拼接身体：腰以下部件都挂在 VisualPivot 下；
## 手臂/腿是"关节节点"，网格作为其子节点偏移，这样旋转关节=摆肢体。
func _build_robot_visuals() -> void:
	# ---- 腿（两根胶囊，挂在髋部高度）----
	var leg_mat := _make_mat(Color(0.16, 0.36, 0.68), 0.35, 0.55)  # 深蓝
	_leg_r = _limb(Vector3(0.17, 0.62, 0.0))    # 右腿关节
	_leg_l = _limb(Vector3(-0.17, 0.62, 0.0))   # 左腿关节
	_pivot.add_child(_leg_r)
	_pivot.add_child(_leg_l)
	_add_capsule_mesh(_leg_r, Vector3(0.0, -0.31, 0.0), 0.11, 0.62, leg_mat)

	# ---- 躯干（主色胶囊）----
	var torso_mat := _make_mat(Color(0.24, 0.53, 0.92), 0.5, 0.45)  # 亮蓝
	_add_capsule_mesh(_pivot, Vector3(0.0, 0.98, 0.0), 0.34, 0.85, torso_mat)

	# ---- 头 + 深色面罩 ----
	var head_mat := _make_mat(Color(0.86, 0.89, 0.93), 0.15, 0.5)   # 浅灰(像头盔)
	var head := _add_sphere_mesh(_pivot, Vector3(0.0, 1.56, 0.0), 0.24, head_mat)
	var visor_mat := _make_mat(Color(0.05, 0.1, 0.16), 0.0, 0.2)    # 近黑
	_add_box_mesh(head, Vector3(0.0, 0.02, -0.12), Vector3(0.3, 0.09, 0.08), visor_mat)  # 面罩在脸前

	# ---- 手臂（肩关节节点，动画靠转它们）----
	var arm_mat := _make_mat(Color(0.30, 0.58, 0.95), 0.45, 0.5)    # 中蓝
	_shoulder_r = _limb(Vector3(0.42, 1.34, 0.0))
	_shoulder_l = _limb(Vector3(-0.42, 1.34, 0.0))
	_pivot.add_child(_shoulder_r)
	_pivot.add_child(_shoulder_l)
	_add_capsule_mesh(_shoulder_r, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)
	_add_capsule_mesh(_shoulder_l, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)

	# ---- 武器：剑（挂在右肩下，挥剑=甩动右肩）----
	var sword_mat := _make_mat(Color(0.85, 0.87, 0.92), 0.9, 0.22)  # 银白金属
	var grip_mat := _make_mat(Color(0.45, 0.3, 0.18), 0.1, 0.7)     # 棕色握柄
	_add_box_mesh(_shoulder_r, Vector3(0.03, -0.66, 0.02), Vector3(0.07, 0.5, 0.04), sword_mat)
	_add_box_mesh(_shoulder_r, Vector3(0.03, -0.28, 0.02), Vector3(0.09, 0.16, 0.07), grip_mat)


## 攻击命中盒：面前的长方体感应区(平时关闭，判定帧才开)。两种外观共用。
func _create_attack_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.monitoring = false   # 默认不检测
	_hitbox.monitorable = false  # 也不让别人检测到自己
	_pivot.add_child(_hitbox)
	var shape := CollisionShape3D.new()
	shape.name = "HitboxShape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.8)            # 宽1.2 高1.0 纵深1.8米
	shape.shape = box
	shape.position = Vector3(0.0, 1.05, -1.25)   # 放在胸口高度、面前1.25米
	_hitbox.add_child(shape)


## 造一个"关节节点"：只是带位置的 Node3D。
func _limb(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	return n


## 建材质并登记到 _mats（闪白时统一处理）。metallic=金属感 0~1，roughness=粗糙度 0~1。
func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	_mats.append(mat)
	return mat


## 在 parent 下造一根胶囊网格（radius=半径，height=总高）。
func _add_capsule_mesh(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16   # 圆周分段数（越大越圆，越小越省）
	mesh.rings = 6              # 纵向分段数
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造一个球网格。
func _add_sphere_mesh(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造一个长方体网格。
func _add_box_mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------
# 受击闪白（自发光代替换色，简单有效）
# ------------------------------------------------------------------

## 把所有部件材质打开自发光并设强度 → 角色瞬间发白（受击反馈）。
## 对外部模型同样生效（GLB 材质也登记进了 _mats）。
func _flash(intensity: float) -> void:
	for mat in _mats:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 1.0)
		mat.emission_energy_multiplier = intensity


## 每帧衰减自发光强度，归零后关掉（实现"闪一下"的效果）。
func _decay_flash(delta: float) -> void:
	var alive := false
	for mat in _mats:
		if mat.emission_energy_multiplier > 0.02:
			mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, 0.0, 1.0 - exp(-14.0 * delta))
			alive = true
	if not alive:
		for mat in _mats:
			mat.emission_enabled = false


# ------------------------------------------------------------------
# 姿态动画（_process 每帧按状态摆姿势）
# 原理：旋转各"关节节点"或用正弦波做循环动作；所有 lerp 都带
# 1-exp(-k*dt) 平滑，切换自然不跳变。
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_decay_flash(delta)
	if _pivot == null:
		return
	if _use_model:
		_animate_model(delta)      # 骑士模型：整体姿态
	else:
		_animate_robot(delta)      # 原语小蓝人：肢体级动画
	_apply_land_squash()           # 落地压缩统一在这里生效(避免各状态残留缩放)


## 落地压缩（纯视觉）：落地后 0.18s 内把模型压扁一点（x/z 略宽、y 略矮），
## 让"落地"这一下有重量感。每帧统一设置 scale，所以不会有残留。
## 注：命中盒是 VisualPivot 的子节点，缩放会带来 ±10% 的判定盒变化(0.18s 内，可忽略)。
func _apply_land_squash() -> void:
	if _squash > 0.0:
		var k := _squash / maxf(0.01, land_squash_time)      # 1 → 0
		_pivot.scale = Vector3(1.0 + 0.10 * k, 1.0 - 0.16 * k, 1.0 + 0.10 * k)
	else:
		_pivot.scale = Vector3.ONE


## 原语小蓝人的肢体动画（甩腿/挥剑/收臂等，见状态枚举）。
func _animate_robot(delta: float) -> void:
	match state:
		State.MOVE:
			# 走路/待机：腿摆动 + 身体起伏 + 手臂闲逛轻摆
			var spd := Vector2(velocity.x, velocity.z).length()  # 水平速度大小
			var moving := spd > 0.5
			var t := clampf(spd / move_speed, 0.0, 1.0)          # 0(站)~1(全速)
			var swing := sin(_bob_phase) * 0.7 * t if moving else 0.0  # 摆腿幅度
			if _leg_r != null:
				_leg_r.rotation.x = swing
				_leg_l.rotation.x = -swing                        # 两腿反相
			var bob := sin(_bob_phase * 2.0) * 0.03 * t if moving else 0.0  # 跑步起伏
			_pivot.position.y = bob
			var sway := sin(Time.get_ticks_msec() * 0.003) * 0.08  # 手臂缓慢摇摆
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.15 + sway, 1.0 - exp(-12.0 * delta))
				_shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, -0.08, 1.0 - exp(-12.0 * delta))
			if _shoulder_l != null:
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.15 - sway, 1.0 - exp(-12.0 * delta))
				_shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, 0.08, 1.0 - exp(-12.0 * delta))
		State.ROLL:
			# 翻滚：整个模型绕局部 X 轴转一圈(前滚翻)，同时收臂护身
			var p := clampf(_state_time / roll_time, 0.0, 1.0)    # 翻滚进度 0~1
			_pivot.rotation.x = -TAU * p                          # -TAU=-360°
			_pivot.position.y = 0.0
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.4, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.4, 1.0 - exp(-14.0 * delta))
		State.ATTACK:
			# 挥剑三段式(与判定窗对应)：举剑(0~0.13s)→劈下(0.13~0.3s，开判定)→收招(0.3~0.5s)
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			var windup := attack_active_start   # =0.13 举剑结束时刻
			var slash := attack_active_end      # =0.3  判定结束时刻
			if _state_time < windup:
				# ① 举剑过顶(右肩向后上方转) —— 起手让玩家看清
				var k := _state_time / windup
				_shoulder_r.rotation.x = lerpf(-0.15, 1.9, k * k)   # 缓入(k²)
			elif _state_time < slash:
				# ② 向前下方劈砍 —— 判定帧开启，命中盒工作
				var k := (_state_time - windup) / (slash - windup)
				_set_hitbox_active(true)
				_shoulder_r.rotation.x = lerpf(1.9, 0.85, sqrt(k))  # 快劈(sqrt 先快后慢)
			else:
				# ③ 收招回位
				_set_hitbox_active(false)
				var k := (_state_time - slash) / maxf(0.01, attack_total - slash)
				_shoulder_r.rotation.x = lerpf(0.85, -0.15, k * k)
			_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.5, 1.0 - exp(-12.0 * delta))  # 左手护身
		State.HURT:
			# 受击：身体站直复位、双手向后张开(挨打姿势)
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
			_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
		State.JUMP_PREP:
			# 原语小蓝人：蓄力段下蹲(整体压低 + 屈腿)
			_pivot.position.y = lerpf(_pivot.position.y, -0.16, 1.0 - exp(-14.0 * delta))
			if _leg_r != null:
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.7, 1.0 - exp(-14.0 * delta))
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.7, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, 0.5, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, 0.5, 1.0 - exp(-14.0 * delta))
		State.JUMP:
			# 原语小蓝人：起跳屈腿收臂，下落时伸腿准备着地
			var rising := velocity.y > 0.0
			var leg_tuck := 0.9 if rising else 0.25
			if _leg_r != null:
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, leg_tuck, 1.0 - exp(-14.0 * delta))
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, leg_tuck, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				var arm := -0.6 if rising else -0.2
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, arm, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, arm, 1.0 - exp(-14.0 * delta))
			_pivot.position.y = 0.0
		State.DEAD:
			# 死亡：0.55 秒内向前栽倒(-90°)，略微抬离地面避免插进地板
			_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.55, 0.0, 1.0)
			_pivot.position.y = lerpf(_pivot.position.y, 0.08, 1.0 - exp(-6.0 * delta))


## 骑士模型的姿态动画。
## 优先用模型自带的骨骼动画（Walk/RollLeap/Slash/JumpStart/JumpAir）；
## 没有对应动画的动作，才退回"整体姿态"（起伏/前倾/后仰/倒地）。
func _animate_model(delta: float) -> void:
	match state:
		State.MOVE:
			if _anim_player != null and _walk_anim != "":
				# 有行走动画（原地循环）：按"当前速度 ÷ 自然步速"调播放倍速，
				# 站住就复位骨骼（模型没有待机动画，用绑定姿势当待机）。
				var spd := Vector2(velocity.x, velocity.z).length()
				if spd > 0.5:
					var want := clampf(spd / maxf(0.2, walk_natural_speed), 0.5, walk_max_speed_scale)
					if _anim_player.current_animation != _walk_anim:
						_anim_player.stop()
						_anim_player.play(_walk_anim, -1.0, want)
					else:
						_anim_player.speed_scale = want
				elif _anim_player.is_playing():
					_anim_to_rest()      # 停下：收掉行走动画并复位骨骼(否则僵在迈步中途)
				# 骨骼动画已经在动，整体节点不要再叠加起伏/前倾（会与动画打架）
				_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-10.0 * delta))
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
			else:
				var spd_f := Vector2(velocity.x, velocity.z).length()
				var t := clampf(spd_f / move_speed, 0.0, 1.0)
				# 跑步起伏
				_pivot.position.y = sin(_bob_phase * 2.0) * 0.04 * t
				# 跑步前倾(rotation.x 转负 = 顶部朝前压)；静止回正
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.12 * t, 1.0 - exp(-8.0 * delta))
		State.ROLL:
			# 模型自带翻滚动画时：翻滚完全交给动画（骨骼转 360°，原地无前移），
			# 这里只把兜底用的整体旋转缓慢归零，避免两者叠加成"转两圈"。
			if _roll_anim != "":
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-20.0 * delta))
				_pivot.position.y = 0.0
			else:
				# 兜底(静态模型)：整身前滚翻一圈
				var p := clampf(_state_time / roll_time, 0.0, 1.0)
				_pivot.rotation.x = -TAU * p
				_pivot.position.y = 0.0
		State.ATTACK:
			# 命中盒时间窗与"有没有动画"无关，每帧都要更新（判定帧 0.13~0.30s）
			var windup := attack_active_start
			var slash_end := attack_active_end
			_set_hitbox_active(_state_time >= windup and _state_time < slash_end)
			if _anim_player != null and _slash_anim != "":
				# 有挥砍动画：姿态交给动画，只把兜底用的整体前倾归零
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			else:
				# 兜底：整体突刺表达挥砍（起手后仰 → 判定帧前倾刺出 → 收招回正）
				if _state_time < windup:
					var k := _state_time / windup
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.18, k * k)
				elif _state_time < slash_end:
					var k := (_state_time - windup) / (slash_end - windup)
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.5, sqrt(k))
				else:
					var k := (_state_time - slash_end) / maxf(0.01, attack_total - slash_end)
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, k * k)
			_pivot.position.y = 0.0
		State.JUMP_PREP:
			# 蓄力段：姿态完全交给 JumpStart 动画（蹲身→蹬地），整体节点不要再叠加姿态
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			_pivot.position.y = 0.0
		State.JUMP:
			if _anim_player != null and _jump_air_anim != "":
				# 离地即播滞空循环（蹬地动画已在地面蓄力段播完，这里不再回头播 JumpStart）
				if _anim_player.current_animation != _jump_air_anim:
					_anim_player.speed_scale = 1.0
					_anim_player.play(_jump_air_anim, -1.0, 1.0)
				# 有跳跃动画时不再叠加整体前倾/后仰
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
				_pivot.position.y = 0.0
			else:
				# 兜底(无跳跃动画)：上升身体前收、下落微后仰准备着地
				var lean := -0.20 if velocity.y > 0.0 else 0.12
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, lean, 1.0 - exp(-9.0 * delta))
				_pivot.position.y = 0.0
		State.HURT:
			# 受击后仰（模型没有受击动画 → 先收掉其它动画并复位骨骼，再叠加后仰）
			if _anim_player != null and _anim_player.is_playing():
				_anim_to_rest()
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.35, 1.0 - exp(-10.0 * delta))
			_pivot.position.y = 0.0
		State.DEAD:
			# 死亡前栽（模型没有死亡动画 → 先复位骨骼，再整体倒下）
			if _anim_player != null and _anim_player.is_playing():
				_anim_to_rest()
			_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.55, 0.0, 1.0)
			_pivot.position.y = lerpf(_pivot.position.y, 0.08, 1.0 - exp(-6.0 * delta))
