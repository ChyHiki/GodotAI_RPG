extends CharacterBody3D
class_name EnemyBrute
## ============================================================
## 敌人"红甲守卫"：简易 AI 状态机 + 骨骼动画外观
## ============================================================
## 【这个脚本做了什么】
##   一个会主动攻击玩家的红色壮汉怪：
##     - 平时在出生点附近待机(IDLE)，玩家进入仇恨范围(11m)后追击(CHASE)
##     - 靠近后开始"蓄力"(WINDUP，0.5s 高举棒槌=预警窗口，玩家趁机躲/打)
##     - 蓄力完挥出带判定的一棒(STRIKE)，命中玩家扣 15 血
##     - 挥完要休息(RECOVER)，玩家可以趁这时反击
##     - 被玩家打中会硬直+击退(STAGGER)；血空倒地消失(DEAD)
##     - 攻击被玩家"完美格挡"弹开 → 走 deflect() 进入更长的硬直(默认 0.8s)，
##       且**不掉血** —— 这是格挡成功给玩家的反击窗口
##
## 【状态机流转】
##   IDLE --玩家靠近--> CHASE --进入攻击距离且冷却好--> WINDUP
##   WINDUP --0.5s--> STRIKE --0.22s--> RECOVER --0.9s--> CHASE
##   (任意非死亡状态) --被击中--> STAGGER --0.4s--> CHASE
##   (任意非死亡状态) --被完美格挡--> STAGGER --0.8s--> CHASE
##   (任意非失衡状态) --失衡值涨满--> BROKEN --break_time--> CHASE(失衡值清空)
##   (任意状态) --血量归零--> DEAD(倒地消失+发 died 信号，主场景负责重生)
##
## 【BROKEN(失衡) 是什么】
##   玩家每成功"完美格挡"一次，就往本敌人的失衡条(Poise 组件)里顶一截。
##   顶满 → 进入 BROKEN：站都站不稳、命中盒关闭、**不能再出招**，
##   这段时间里玩家走进来按左键就能触发**处决**(超高伤害)。
##   break_time 秒内没被处决就自动恢复，失衡条清空重攒。
##
## 【外观：模型优先，程序化兜底】
##   优先加载 Blender 出的骨骼动画模型 assets/enemies/brute_01/brute_rigged.glb，
##   按状态机播放它自带的 5 段动画（Idle/Walk/AttackWindup/Attack/Hit）；
##   模型加载失败（文件缺失/空网格）时自动回退到原来那套**程序化原语外观**，
##   也就是本文件下半部分的 _build_procedural_body / _animate_procedural。
##   两套外观的状态机逻辑完全一致，只是"怎么动"的实现不同。
##
## 【设计要点】
##   - 蓄力期可被玩家打断(被打就 STAGGER 取消出招)→ 鼓励玩家主动进攻
##   - 攻击有明确"预警→出手"节奏，让翻滚躲招成为可能
## ============================================================

## 信号：本敌人死亡（主场景监听后提示并计时重生）
signal died

## 状态枚举（流转关系见文件头）
enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, BROKEN, DEAD }


# ------------------------------------------------------------------
# AI 参数（@export → 选中敌人节点可在编辑器实时调整难度）
# ------------------------------------------------------------------

## 敌人**类型**标识：任务系统靠它匹配"击杀某类怪"的目标（EventBus.enemy_died 的参数）。
## ⚠️ 填的是"类型"不是"实例"—— 同一种怪的所有实例填同一个值，任务只关心杀了几只。
@export var enemy_id: String = "brute"
@export var move_speed: float = 2.8          # 追击速度(米/秒) —— 玩家 6.2，留出空间感
@export var accel: float = 10.0              # 速度变化平滑度
@export var aggro_range: float = 11.0        # 仇恨半径：玩家进入此距离才开始追
@export var attack_range: float = 2.3        # 发动攻击的距离(近到能挥中)
@export var attack_damage: int = 15          # 挥击伤害（玩家100血 → 7棒倒）
@export var windup_time: float = 0.5         # 蓄力预警时长(越大越容易躲)
@export var strike_time: float = 0.22        # 挥击判定持续时长
@export var recover_time: float = 0.9        # 挥完的硬直(反击窗口)
@export var attack_interval: float = 1.6     # 两次攻击最小间隔(冷却)
@export var knockback_strength: float = 7.0  # 被击退的初速度
@export var stagger_time: float = 0.4        # 普通受击的硬直时长(秒)
## 完美格挡的击退力度倍率：被弹开时比普通受击推得更远一点，体现"格挡反震"。
@export var parry_knockback_scale: float = 1.4

## ★ 每次被完美格挡时，往失衡条里顶的**百分比**（相对 Poise.max_poise）。
## 【这就是"各类敌人增加的百分比不同"的实现处】
##   一次顶多少 = 100 ÷ "期望几次完美格挡打失衡"：
##     小怪/杂兵  50 → 2 次     精英/守卫  34 → 3 次（brute_01 就是这个档）
##     重甲/大型  25 → 4 次     Boss      20 → 5 次
##   数值只写在这里，玩家侧完全不关心 —— 敌人换皮/换难度只改这个字段。
@export_range(5.0, 100.0, 1.0) var parry_poise_percent: float = 34.0

## 处决伤害倍率：玩家处决时实际造成的伤害 = 本敌人的"处决基础伤害" × 这个倍率。
## 【为什么放在敌人身上】大块头理应更抗处决、小怪应该一刀秒，
##   差异归敌人自己管；玩家侧只负责"我发动了处决"。
@export var execute_damage_scale: float = 1.0

## ★ 调试开关：AI 是否接管这只怪。
##   true  = 自己追着玩家打（正常游戏行为）
##   false = 由外部（角色切换器）喂指令 —— 把这只怪当成"可操作角色"来测试
## 【为什么默认 true】关掉它就等于这只怪不发呆，正常跑游戏时行为与改造前完全一致。
@export var ai_enabled: bool = true

## 【手动操控】外部每帧写入的"想要的移动方向"（世界系水平向量，长度 0~1）。
## 只有 ai_enabled=false 时才被读取；留 ZERO 表示原地站住。
var manual_wish_dir: Vector3 = Vector3.ZERO

## 【手动操控】转身速率(度/秒级别，与玩家的 turn_speed 同量纲)：
## 太小会觉得"转不动"，太大又像抽搐。12 比玩家(14)略钝，体现大块头的笨重。
@export var manual_turn_speed: float = 12.0

## —— 近战朝向修正（出招"软锁定"，与玩家侧同一套设计）——
## 手动操控这只怪时，出招瞬间会把朝向吸到附近的玩家身上，免得"贴脸一棒抡空"。
## 以**自身正面**为锥形基准（这只怪不读镜头，它自己的朝向就是"它正在打哪"的意图）。
## 【AI 模式不需要它】AI 本来就全程锁定着玩家追，朝向永远是对的。
@export var soft_lock_range: float = 3.0     # 搜索半径(米)
@export var soft_lock_angle: float = 70.0    # 相对自身正面的最大偏角(度)

## 重力(米/秒²)，与玩家一致
const GRAVITY := 24.0


# ------------------------------------------------------------------
# 外观资产（模型 + 武器）
#
# 模型资产按类型分类存放：assets/enemies/brute_01/
#   ├─ brute_rigged.glb  （模型+骨骼+5 段动画，**不含武器**）
#   └─ club_01.glb       （大棒槌，独立资产）
# 源文件（.blend）在 E:\blender\blenderproject\enemies\brute_01\，不在 Godot 项目内。
#
# 模型缺失/加载失败时会自动回退到程序化原语外观（见 _build_procedural_body），
# 所以删掉 glb 也不会让游戏崩，只是回到旧观感。
# ------------------------------------------------------------------

## 敌人外观模型（.glb）。带骨骼动画的模型会自动识别并播放其中的动作。
const ENEMY_MODEL := preload("res://assets/enemies/brute_01/brute_rigged.glb")

## 武器资产：与角色**分离**存放 —— 换武器只换这个文件，角色与全部动画都不用动。
## 资产约定：原点 = 握把中心，槌头沿自身局部 **-Z**（实测包围盒 z 从 +0.33 到 −1.43）。
const ENEMY_WEAPON := preload("res://assets/enemies/brute_01/club_01.glb")

## 武器挂点骨骼名（模型里的空骨骼，位于右手手心）。
const ENEMY_WEAPON_SOCKET := "weapon.R"

## 挂点对齐变换（设在武器子节点上，见 _attach_weapon）：
## 把"槌头沿 -Z"扳到"槌头沿挂点骨骼 +Y" —— 绕 X 轴 +90° 即可（-Z → +Y）。
## 挂点骨骼本身的骨长方向在模型里已经做成"斜向前下方"，所以对齐后
## 大棒自然垂在身前下方，不需要额外的角度。
const ENEMY_WEAPON_ALIGN_LOCAL := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)

## 模型应缩放到的"总高"(米，脚底→角尖)。
## 【为什么是 2.66】改造前的程序化外观总高就是 2.66m（脚底 0 → 角尖 2.66），
## 取同一个值 = 换模型后体型观感不变。模型实测总高 3.006m → 缩放 0.885 倍。
## 注意这不是碰撞体高度：碰撞胶囊是 2.1m，角/头顶高出胶囊属正常（角不是碰撞体）。
@export var model_target_height: float = 2.66

## 行走动画的"自然前进速度"(米/秒) = 一个周期的步幅 ÷ 周期时长。
## 实测（tools 侧用 probe_stride.py）：单步 0.8288m × 2 步 ÷ 1.0s = 1.66 m/s。
## 播放倍速 = 当前移动速度 ÷ 这个值（这样脚步与地面基本同步、不打滑）。
@export var walk_natural_speed: float = 1.66

## 行走动画的播放倍速上限。move_speed(2.8) / 1.66 ≈ 1.69，留一点余量取 2.0。
## 设上限的代价是移动极快时仍有轻微滑步；想彻底消除需要美术侧再出一段 Run。
@export var walk_max_speed_scale: float = 2.0

## 动画之间的过渡混合时长(秒)。
## 【为什么需要】挥击动画收势停在"棒砸到身前地面"，而 Idle 起手是"棒垂在体侧"，
## 不对齐直接切会"啪"地闪一下。0.12s 的交叉淡入足够抹平，又不至于拖慢出招节奏。
## 设为 0 = 硬切。
@export var anim_blend_time: float = 0.12


# ------------------------------------------------------------------
# 运行时状态变量
# ------------------------------------------------------------------

var state: State = State.IDLE    # 当前 AI 状态
var _state_time: float = 0.0     # 当前状态已持续时长(秒)
var _attack_cd: float = 0.0      # 攻击冷却倒计时
var _dead: bool = false          # 是否已死亡
var _lunge_dir: Vector3 = Vector3.ZERO  # 挥击时的前冲方向（出手瞬间朝玩家锁定）
## 本次硬直的**总时长**(秒)。
## 【为什么要有这个变量】硬直有两种来源，时长不一样：
##   普通受击 = stagger_time(0.4s)；被完美格挡弹开 = 玩家传进来的 block_parry_stagger(0.8s)。
##   状态机只认 _stagger_time，判断逻辑因此不用改。
var _stagger_time: float = 0.4


# ------------------------------------------------------------------
# 外观引用
# ------------------------------------------------------------------

var _pivot: Node3D               # VisualPivot：外观根，旋转=面向玩家
var _arm_r: Node3D               # 【仅程序化外观用】右手臂关节(棒槌挂在下面，挥棒靠转它)
var _mats: Array[StandardMaterial3D] = []  # 部件材质(受击闪红白用)
var _flash_power: float = 0.0    # 当前受击闪光强度(逐步衰减到0)

## 是否正在使用外部模型（true=模型；false=程序化原语外观兜底）
var _use_model: bool = false
## 模型自带的动画播放器（GLB 内嵌动画时存在；静态模型则为 null）
var _anim_player: AnimationPlayer = null
## 模型的骨骼节点：用于"没有对应动画时"把骨骼复位成绑定姿势（见 _anim_to_rest）
var _skeleton: Skeleton3D = null
## 按名字识别到的 5 段动画（空字符串 = 该动作没有动画资源，走脚本姿态兜底）
var _idle_anim: String = ""
var _walk_anim: String = ""
var _windup_anim: String = ""
var _attack_anim: String = ""
var _hit_anim: String = ""
## 武器挂点（BoneAttachment3D，挂在模型的 weapon.R 骨骼上）
var _weapon_socket: BoneAttachment3D = null
## 当前装备的武器节点（徒手时为 null）
var _weapon: Node3D = null

## Health 组件引用
@onready var health: Health = $Health
## Poise(失衡)组件引用 —— 与 Health 平级挂在同一个 CharacterBody3D 下。
## 注意它可能不存在（例如某个临时测试场景只挂了 Health），所以下面所有
## 访问都做了 null 判断：没有失衡条时，敌人就退化成"没有失衡机制"的普通怪。
@onready var poise: Poise = get_node_or_null("Poise") as Poise


# ------------------------------------------------------------------
# 引擎回调与对外查询
# ------------------------------------------------------------------

## 进入场景：注册到 "enemy" 组(玩家命中盒/镜头靠组识别它)、拼外观、监听血量归零。
func _ready() -> void:
	add_to_group("enemy")
	_build_body()
	health.died.connect(_on_health_died)
	# 失衡条涨满 → 立刻切 BROKEN（放在这里而不是到处调，保证只有一条入口）
	if poise != null:
		poise.broken_started.connect(_on_poise_broken)


## 供玩家命中盒/处决判定查询：现在是不是"可以处决"？（失衡中且还活着）
func is_broken() -> bool:
	return not _dead and poise != null and poise.is_broken()


## ★ 处决入口（玩家在 EXECUTE 状态里调用）。
##
## 【和 take_damage 的区别】处决是"失衡期间的高伤害重击"（**默认打不死**，
##   见 player.gd 的 execute_damage 注释），语义上仍是伤害，所以复用 health.damage()；
##   但它有两点特殊：
##     1. 伤害乘上本敌人的 execute_damage_scale（大块头更抗处决）；
##     2. **不打断 BROKEN 状态** —— 处决演出需要敌人一直保持"站不稳"的姿势，
##        所以这里不走 take_damage 那套"转 STAGGER"的逻辑，而是手动扣血。
##   另外顺手 refresh_break()：把失衡倒计时顶回满，
##   免得处决演到一半敌人自己站起来打断演出。
##   → 演出结束后由玩家调 end_break_after_execution() 收掉失衡（见该函数注释）。
##
## @param amount 玩家侧的处决基础伤害
## @param from_pos 玩家位置（用于击退方向/闪白）
## @return 是否真的扣到血（false = 已死 或 血量组件在无敌）
func execute(amount: int, from_pos: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	var dmg := int(round(float(amount) * maxf(0.0, execute_damage_scale)))
	if not health.damage(dmg):
		return false
	# 演出期间续上失衡计时（敌人不会中途站起来）
	if poise != null:
		poise.refresh_break()
	if health.current_hp <= 0:
		_die()
		return true
	# 还活着：保持 BROKEN 姿势，只做一次强闪光 + 小击退
	_flash(2.0)
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	velocity.x = away.x * knockback_strength * 0.5
	velocity.z = away.z * knockback_strength * 0.5
	return true


## 供玩家命中盒查询：还活着吗？
func is_alive() -> bool:
	return not _dead


## ★ 处决演出结束时由玩家调用（见 player.gd::_end_execute）。
##
## 【作用】扛住处决还活着的敌人，这时才"爬起来" —— 主动结束自己的失衡。
##
## 【为什么必须有这个入口】处决伤害是**大量但非致命**的（默认 75 vs 满血 100），
##   所以敌人常常是"挨完还站着"。如果一直保持 BROKEN：
##     1. 玩家可以原地连按左键**无限连处决**（每次还都带全程无敌）→
##        处决从"3 次完美格挡换来的高光"退化成"刷伤害的循环"，普通挥剑被架空；
##     2. 敌人永远不起来，战斗无法进入"干掉它"的收尾阶段。
##   所以处决 = **消耗掉一次失衡**：换一大管血，代价是反击窗口就此关闭。
##
## 【为什么不能写在 execute() 里】那里演出才刚开始，敌人当场站直会变成
##   "在处决动画里复活"。必须等玩家的 EXECUTE 状态演完（_end_execute）才收。
func end_break_after_execution() -> void:
	if _dead or poise == null:
		return
	poise.end_break()      # 广播 break_ended；BROKEN 分支下一帧轮询到就转 CHASE
	_state_time = 0.0


## 找当前要攻击的目标：场景里第一个"活着的玩家"。死了/不在场返回 null。
func get_target() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and p.has_method("is_alive") and p.is_alive():
		return p
	return null


# ------------------------------------------------------------------
# 主循环：AI 状态机（每物理帧执行一次）
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	_attack_cd = maxf(0.0, _attack_cd - delta)   # 冷却递减
	if not is_on_floor():
		velocity.y -= GRAVITY * delta            # 重力

	var target := get_target()                   # 当前目标(可能为 null)

	match state:
		State.IDLE:
			# ★ 手动操控：不吃 AI，改听外部指令（见 _manual_drive 的注释）
			if not ai_enabled:
				_manual_drive(delta)
			elif target != null and global_position.distance_to(target.global_position) <= aggro_range:
				# 待机：玩家进入仇恨范围 → 切换追击
				state = State.CHASE
				_state_time = 0.0
				_damp_move(delta)
			else:
				_damp_move(delta)                    # 原地停住
		State.CHASE:
			# 追击：面朝玩家逼近；够近且冷却好 → 蓄力
			if not ai_enabled:
				_manual_drive(delta)
			elif target == null:                 # 玩家死了/消失了 → 回待机
				state = State.IDLE
				_state_time = 0.0
				_damp_move(delta)
				return
			else:
				var to_target := target.global_position - global_position
				var dist := Vector2(to_target.x, to_target.z).length()  # 水平距离
				_face_point(target.global_position, delta, 6.0)
				if dist <= attack_range and _attack_cd <= 0.0:
					state = State.WINDUP
					_state_time = 0.0
					_velocity_towards(target, 0.0, delta)   # 停下蓄力
					return
				_velocity_towards(target, move_speed, delta)
		State.WINDUP:
			# 蓄力预警：原地不动保持面向(只转不挪)，时间到就出手。
			# ★ 手动操控时不自动转向玩家 —— 朝哪打由操作者决定。
			if ai_enabled and target != null:
				_face_point(target.global_position, delta, 8.0)
			_damp_move(delta)
			if _state_time >= windup_time:
				_begin_strike(target)
		State.STRIKE:
			# 挥击：朝锁定方向小段前冲(带打击感)；判定结束后进入恢复
			if _state_time >= strike_time:
				_end_strike()
			else:
				var k := 1.0 - _state_time / strike_time   # 前冲随挥击衰减
				velocity.x = _lunge_dir.x * 8.0 * k
				velocity.z = _lunge_dir.z * 8.0 * k
		State.RECOVER:
			# 恢复(破绽期)：玩家该趁这时候输出
			_damp_move(delta)
			if _state_time >= recover_time:
				state = State.CHASE
				_state_time = 0.0
		State.STAGGER:
			# 被击硬直：顿一下回追击。时长用 _stagger_time
			# （普通受击 0.4s / 被完美格挡弹开 0.8s，见 deflect()）
			_damp_move(delta)
			if _state_time >= _stagger_time:
				state = State.CHASE
				_state_time = 0.0
		State.BROKEN:
			# 失衡：站不稳、原地打晃、完全不出手（命中盒也关着）。
			# 退出的唯一条件是"失衡计时走完"——计时归 Poise 组件管，
			# 它结束时会把 broken 置回 false，这里轮询到就恢复追击。
			# 处决成功会 refresh_break() 把计时顶满，所以演出不会被中途打断。
			_damp_move(delta)
			if poise == null or not poise.is_broken():
				state = State.CHASE
				_state_time = 0.0
		State.DEAD:
			_damp_move(delta)    # 尸体滑行减速

	move_and_slide()             # 真正的物理移动


# ------------------------------------------------------------------
# 状态切换辅助
# ------------------------------------------------------------------

## 进入挥击：锁定前冲方向、记攻击冷却、打开命中盒。
## 命中盒开着时若玩家在面前 → 命中回调触发伤害。
func _begin_strike(target: Node3D) -> void:
	state = State.STRIKE
	_state_time = 0.0
	_attack_cd = attack_interval     # 从现在起冷却 1.6s，防止连挥
	# ★ 手动操控时不再"自动瞄准玩家"：前冲方向取自己当前的正面，
	#   否则会出现"我明明面朝空地挥棒，怪却自己转向砸中了玩家"的假手感。
	if not ai_enabled or target == null:
		_lunge_dir = _get_facing_flat()
	else:
		_lunge_dir = (target.global_position - global_position)
		_lunge_dir.y = 0.0
		_lunge_dir = _lunge_dir.normalized()   # 锁定出手瞬间玩家的方位
	_set_hitbox_active(true)


## 挥击结束：关命中盒 → 恢复状态。
func _end_strike() -> void:
	_set_hitbox_active(false)
	state = State.RECOVER
	_state_time = 0.0


## 朝目标移动：把速度平滑插值到"指向目标×speed"。
func _velocity_towards(target: Node3D, speed: float, delta: float) -> void:
	var to_target := target.global_position - global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	flat = flat.normalized()
	var want := flat * speed
	var t := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, want.x, t)
	velocity.z = lerpf(velocity.z, want.z, t)


## 速度衰减到 0（待机/蓄力/恢复时原地停住）。
func _damp_move(delta: float) -> void:
	var t := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, 0.0, t)
	velocity.z = lerpf(velocity.z, 0.0, t)


# ------------------------------------------------------------------
# 手动操控（调试：把这只怪当成"可操作角色"）
#
# 【为什么不复制一套玩家控制器】玩家那套 WASD→状态机→15 段动画的逻辑是和
#   PlayerCharacter 深度耦合的，搬过来等于再养一份双胞胎代码。这里的做法是
#   **最小接口**：外部只喂"想往哪走"和"要不要出招"两条指令，
#   剩下的蓄力/挥击/硬直/动画/命中盒**全部复用本文件原有的状态机** ——
#   于是"操控敌人打玩家"打出来的手感，与"敌人 AI 打玩家"是同一套代码，测出来的结论才可信。
# ------------------------------------------------------------------

## 每帧把 manual_wish_dir 换算成速度与朝向（ai_enabled=false 时由 IDLE/CHASE 分支调用）。
## 实现与 AI 追击一致（同样的 move_speed / accel），只是"目标点"换成输入方向，
##   这样手动操控时的移动手感（起步、急停、撞墙）与 AI 追击完全相同。
func _manual_drive(delta: float) -> void:
	var wish := manual_wish_dir
	wish.y = 0.0
	if wish.length() > 0.01:
		if wish.length() > 1.0:
			wish = wish.normalized()
		var want := wish * move_speed
		var t := 1.0 - exp(-accel * delta)
		velocity.x = lerpf(velocity.x, want.x, t)
		velocity.z = lerpf(velocity.z, want.z, t)
		# 朝移动方向转身（和玩家"朝移动方向转身"的规则一致）
		_face_point(global_position + wish, delta, manual_turn_speed)
	else:
		_damp_move(delta)


## ★ 手动出招：请求挥一棒（走与 AI 完全相同的 WINDUP→STRIKE 流程，含 0.5s 蓄力预警）。
## 【为什么要走完整蓄力】蓄力是这只怪的"招式本体"，跳过它直接 STRIKE 的话，
##   测到的就不是真实节奏 —— 而且 warning 动画与命中盒开启时机是绑定的。
##
## @param face_dir 出手朝向（世界系水平向量）；传 ZERO 表示保持当前朝向不变
## @return true=已抬手进入蓄力；false=冷却中/正在出招/已死
func request_attack(face_dir: Vector3 = Vector3.ZERO) -> bool:
	if _dead or (state != State.IDLE and state != State.CHASE):
		return false
	if _attack_cd > 0.0:
		return false
	# 近战修正优先：附近站着玩家就朝玩家（见 _find_soft_lock_dir）。
	# 传进来的 face_dir 只在"附近没人"时才生效 —— 这样"我朝空地挥一棒"依然做得到。
	var soft := _find_soft_lock_dir()
	if soft.length_squared() > 0.0001:
		_face_instant_dir(soft)         # 出手瞬间对齐朝向（攻击要跟手，不能慢慢转）
	elif face_dir.length_squared() > 0.0001:
		_face_instant_dir(face_dir)
	state = State.WINDUP
	_state_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	return true


## 找"近战修正"要吸附的玩家：自身正面锥形内、**水平距离最近的**活着的玩家。
## @return 指向他的水平单位向量；没有合适目标时返回零向量。
## 【为什么锥内取"最近"】和玩家侧同一个道理：贴身那个才是这一棒真正该砸的，
##   按"最对准正面"取会出现"贴脸的人偏 20°、3 米外的人正对着，结果一棒甩向远处"。
func _find_soft_lock_dir() -> Vector3:
	if soft_lock_range <= 0.0:
		return Vector3.ZERO
	var facing := _get_facing_flat()
	var cos_limit := cos(deg_to_rad(soft_lock_angle))
	var best: Node3D = null
	var best_dist := soft_lock_range
	for p in get_tree().get_nodes_in_group("player"):
		var target := p as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("is_alive") and not target.is_alive():
			continue
		var to_t := target.global_position - global_position
		to_t.y = 0.0
		var dist := to_t.length()
		if dist > best_dist or dist < 0.05:          # 太远 / 几乎重合 → 跳过
			continue
		if to_t.normalized().dot(facing) < cos_limit:  # 不在正面锥形内 → 跳过
			continue
		best_dist = dist
		best = target
	if best == null:
		return Vector3.ZERO
	var to_best := best.global_position - global_position
	to_best.y = 0.0
	return to_best.normalized()


## 立即把外观转到 dir 指的方向（与玩家 _face_instant 同一套 atan2 换算）。
func _face_instant_dir(dir: Vector3) -> void:
	var flat := dir
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_pivot.rotation.y = atan2(-flat.x, -flat.z)


## 当前"正面"的水平单位向量（模型正面 = 局部 -Z）。
func _get_facing_flat() -> Vector3:
	var f := -_pivot.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.BACK


## 让 VisualPivot 平滑转向 point（与玩家脚本同样的 atan2 换算）。
func _face_point(point: Vector3, delta: float, speed: float) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-speed * delta))


# ------------------------------------------------------------------
# 受击与死亡
# ------------------------------------------------------------------

## 玩家攻击命中盒调用的伤害入口：
##   扣血成功 → 若血量归零则死亡；否则进入硬直(STAGGER)并朝伤害来源反方向击退。
##   被打会打断蓄力/挥击(取消出招)→ 玩家主动进攻的奖励。
func take_damage(amount: int, from_pos: Vector3) -> void:
	if _dead:
		return
	if not health.damage(amount):
		return
	if health.current_hp <= 0:
		_die()
		return
	# 硬直 + 取消进行中的攻击 + 关闭命中盒
	# 【例外】已在 BROKEN(失衡) 时就保持原状态：失衡本身比硬直更"软"，
	# 被普通攻击打一下不该让它"提前站起来"，否则玩家会舍不得打。
	if state != State.DEAD and state != State.BROKEN:
		state = State.STAGGER
		_state_time = 0.0
		_stagger_time = stagger_time      # 普通受击用常规硬直时长（不是被格挡的 0.8s）
		_set_hitbox_active(false)
	# 击退方向 = 远离攻击来源
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.BACK        # 兜底方向
	away = away.normalized()
	velocity.x = away.x * knockback_strength
	velocity.z = away.z * knockback_strength
	_flash(1.0)                    # 受击闪红白


## ★ 完美格挡的反弹入口（玩家脚本在"完美格挡"成立时调用）。
##
## 【和 take_damage 的区别】take_damage 的语义是"造成伤害"，会走 health.damage()；
##   完美格挡是"被弹开"——**一点血都不掉**，只改状态机 + 把怪推开。
##   所以单独开一个方法，而不是 take_damage(0)：后者会白广播一次血量变化信号，
##   而且 health 处于无敌时会直接返回 false，导致硬直也进不去。
##
## 【为什么时长由调用方传】反击窗口的长短是"玩家格挡手感"的一部分，
##   数值放在 player.gd 的 block_parry_stagger 里统一调；
##   敌人只负责"进入硬直 X 秒"。默认 0.8 与玩家侧默认值一致。
##
## @param duration 硬直时长(秒)，默认 0.8（是普通受击 0.4 的两倍 → 明显的反击窗口）
## @param from_pos 攻击者(玩家)的位置：用来决定把这个怪朝哪个方向弹开
func deflect(duration: float = 0.8, from_pos: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	# ★ 已经处于 BROKEN(失衡) 时被再次完美格挡：**必须保持 BROKEN**。
	#   BROKEN 才是玩家能处决的状态。若这里照旧把 state 覆盖成 STAGGER，
	#   玩家在失衡窗口里"多弹一下"就会把窗口取消掉（表现为"处决突然没反应了"）。
	#   所以这一支只给击退+闪光，不碰状态机；失衡值也不再累加
	#   （Poise.add 自带 broken 保护，加了也是空转）。
	var broken_now: bool = poise != null and poise.is_broken()
	if not broken_now:
		state = State.STAGGER
		_state_time = 0.0
		_stagger_time = maxf(0.05, duration)
		_attack_cd = maxf(_attack_cd, _stagger_time)   # 硬直结束后也别立刻又抡过来
		_set_hitbox_active(false)                      # 出招被打断 → 关掉判定盒
	# 弹开方向 = 远离攻击者；推力比普通受击更强一点，读得出"格挡反震"
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	velocity.x = away.x * knockback_strength * parry_knockback_scale
	velocity.z = away.z * knockback_strength * parry_knockback_scale
	_flash(1.0 if broken_now else 1.5)   # 普通受击闪得更亮，提示"这一下是被弹开的"
	# ★ 失衡值累积的唯一入口：只在这里加，就不会有"某条分支漏加"的 bug。
	#   加满时 Poise 会广播 broken_started → _on_poise_broken() 把状态切成 BROKEN。
	if not broken_now and poise != null:
		poise.percent(parry_poise_percent)


## 失衡值涨满的回调 → 进入 BROKEN（打断当前一切动作）。
func _on_poise_broken() -> void:
	if _dead:
		return
	state = State.BROKEN
	_state_time = 0.0
	_attack_cd = maxf(_attack_cd, _stagger_time)   # 恢复后别立刻抡过来
	_set_hitbox_active(false)                      # 关判定盒：失衡期间绝不打人
	_flash(2.0)
	velocity.x = 0.0
	velocity.z = 0.0


## Health 血量归零回调 → 死亡（防重复）
func _on_health_died() -> void:
	if _dead:
		return
	_die()


## 进入死亡：取消碰撞与命中盒、闪强光、广播 died、1.2s 后自动销毁自己。
## (销毁是为了让"倒地消失动画"播完再清场；重生由主场景另计时生成新实例)
func _die() -> void:
	if _dead:
		return
	_dead = true
	state = State.DEAD
	_state_time = 0.0
	collision_layer = 0            # 关碰撞：别人(玩家/镜头)不再被尸体挡住
	collision_mask = 0
	_set_hitbox_active(false)
	_flash(2.0)
	died.emit()                    # 通知主场景开始重生计时
	# 广播给全局事件总线：任务系统/成就/统计都靠这一行知道"某类怪死了一只"。
	# 【为什么有了 died 还要多发一条】died 是**本实例**的局部信号，主场景用它排重生计时；
	#   任务关心的是"某种怪死了一只"这个跨系统的世界事实 —— 两者语义不同、生命周期不同。
	#   分开之后，任务系统不用去认识 EnemyBrute 这个类，以后加成就/掉落也不用再改这里。
	EventBus.enemy_died.emit(enemy_id)
	# 【临时占位掉落】项目还没有掉落表 / 拾取物系统，这里让守卫固定掉一枚徽记，
	#   目的是把 "COLLECT 类任务目标" 这条链路先打通（示例任务 q_guards 要 3 枚）。
	#   ⚠️ 等真正的掉落系统落地后删掉这一行，改由掉落物实体在"玩家拾取"时 emit ——
	#      那时"击杀"与"获得物品"才会真正分成两个独立事件。
	EventBus.item_collected.emit("guard_insignia", 1)
	get_tree().create_timer(1.2).timeout.connect(queue_free)


# ------------------------------------------------------------------
# 命中盒（挥击时开启，检测面前玩家）
# ------------------------------------------------------------------

## 开关命中盒（set_deferred 安全延迟到物理步后生效）。
func _set_hitbox_active(active: bool) -> void:
	if _hitbox == null:
		return
	_hitbox.set_deferred("monitoring", active)


## 命中回调(撞到身体)：只在挥击判定期生效，只打组别 "player" 且会接伤害的单位。
func _on_hitbox_body_entered(body: Node3D) -> void:
	if state != State.STRIKE:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)


## 兜底：如果目标是 Area(区域)，取其父节点当作受害者再判断。
func _on_hitbox_area_entered(area: Area3D) -> void:
	if state != State.STRIKE:
		return
	var hit_owner := area.get_parent()
	if hit_owner != null and hit_owner.is_in_group("player") and hit_owner.has_method("take_damage"):
		hit_owner.take_damage(attack_damage, global_position)


# ------------------------------------------------------------------
# 外观：模型优先，程序化原语兜底
# ------------------------------------------------------------------

var _hitbox: Area3D   # 攻击命中盒(见 _build_hitbox)


## 搭外观：先尝试加载外部模型(ENEMY_MODEL)；失败则用程序化原语兜底。
## 无论哪种，都会创建攻击命中盒挂在 VisualPivot 下(随朝向转动)。
## 结构与 player.gd 的 _build_body 保持一致，便于两边对照维护。
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "VisualPivot"
	add_child(_pivot)

	if ENEMY_MODEL != null:
		_use_model = _setup_model()
	if not _use_model:
		_build_procedural_body()
	_build_hitbox()


# ------------------------------------------------------------------
# 模型外观（brute_rigged.glb，21 骨骼 / 5 动画）
# ------------------------------------------------------------------

## 加载并安置外部骨骼模型。实现三步：
##   1. 实例化 GLB，递归收集所有网格，用它们的包围盒+节点变换算出模型总包围盒；
##   2. 按 model_target_height 统一缩放，并平移到脚底 y=0、水平居中；
##   3. 登记材质（受击闪光用）→ 识别动画 → 把武器挂到骨骼挂点上。
func _setup_model() -> bool:
	var model := ENEMY_MODEL.instantiate() as Node3D
	_pivot.add_child(model)
	model.name = "BruteModel"

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

	# 统一缩放到目标总高，并让脚底对齐 y=0、水平居中
	# （模型在 Blender 里脚底已踩 z=0，所以这一步基本是恒等；留着是为了
	#   以后改模型尺寸时不用动代码，和 player.gd 的处理方式一致）
	var s := model_target_height / (mx.y - mn.y)
	model.scale = Vector3.ONE * s
	model.position = Vector3(
		-(mn.x + mx.x) * 0.5 * s,
		-mn.y * s,
		-(mn.z + mx.z) * 0.5 * s
	)

	_register_mesh_materials(model)   # 登记材质（受击闪光用）
	_setup_animations(model)          # 识别 5 段动画
	_attach_weapon(model)             # 把独立武器资产挂到骨骼挂点
	return true


## 递归收集模型下所有网格部件和它们相对根节点的累计变换。
## 注意：只递归 Node3D 子节点——模型里可能混有非 Node3D 的节点
## （例如 AnimationPlayer），强转型会报空引用。
func _collect_meshes(node: Node3D, parent_xform: Transform3D, out: Array) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D:
		out.append({ "node": node, "xform": xform })
	for child in node.get_children():
		if child is Node3D:
			_collect_meshes(child as Node3D, xform, out)


## 把 root 下所有网格的材质**复制成私有副本**并登记进 _mats（受击闪光用）。
##
## 【为什么要 duplicate】GLB 导入的材质是引擎资源缓存里**共享**的对象，
## 直接改它的 emission 会波及其他使用者。现在场上一只怪看不出问题，
## 但以后一波刷多只时就会"打一只、亮一片"。复制成实例私有再登记最稳。
func _register_mesh_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(surface)
				if mat is StandardMaterial3D:
					var owned := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(surface, owned)
					if not _mats.has(owned):
						_mats.append(owned)
	for child in root.get_children():
		_register_mesh_materials(child)


## 扫描模型自带的动画资源：找到 AnimationPlayer，并按名字识别 5 段动作。
## 识别规则（大小写无关、忽略下划线）：
##   含 windup                → 蓄力预警（AttackWindup）
##   含 attack / slash        → 挥击（Attack）
##   含 walk                  → 行走（循环）
##   含 idle                  → 待机（循环）
##   含 hit / hurt            → 受击硬直（Hit）
## 【判断顺序很重要】"AttackWindup" 里也含 "attack"，
## 必须**先判 windup 再判 attack**；否则蓄力动画会被识别成挥击动画，
## 表现为"举着棒子不动就突然打完了"。改动画名时留意这一点。
func _setup_animations(model: Node3D) -> void:
	_anim_player = _find_animation_player(model)
	if _anim_player == null:
		push_warning("敌人模型里没有 AnimationPlayer，将不做骨骼动画")
		return
	_skeleton = _find_skeleton(model)
	for anim_name in _anim_player.get_animation_list():
		var key := String(anim_name).to_lower().replace("_", "")
		if key.contains("windup"):
			_windup_anim = String(anim_name)
		elif key.contains("attack") or key.contains("slash"):
			_attack_anim = String(anim_name)
		elif key.contains("walk"):
			_walk_anim = String(anim_name)
			_set_loop(_walk_anim)
		elif key.contains("idle"):
			_idle_anim = String(anim_name)
			_set_loop(_idle_anim)
		elif key.contains("hit") or key.contains("hurt"):
			_hit_anim = String(anim_name)


## 给"循环类"动画打开循环播放。
## 为什么需要：glTF 本身没有循环标记，导入后的 Animation 默认 LOOP_NONE，
## 不打开的话待机/行走只会播一次就定住。
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


## 递归查找第一个 AnimationPlayer。模型层级里可能有空节点，所以要递归。
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


## 把武器资产挂到模型骨骼的挂点上（BoneAttachment3D 挂在 Skeleton3D 下）。
## 之后蓄力/挥击等动画驱动手臂 → 武器自动跟随，无需为每把武器重做动画。
func _attach_weapon(model: Node3D) -> void:
	if _skeleton == null or ENEMY_WEAPON == null:
		return
	var bone_idx := _skeleton.find_bone(ENEMY_WEAPON_SOCKET)
	if bone_idx < 0:
		push_warning("敌人模型里没有挂点骨骼 %s，武器未装备" % ENEMY_WEAPON_SOCKET)
		return
	_weapon_socket = BoneAttachment3D.new()
	_weapon_socket.name = "WeaponSocket"
	_skeleton.add_child(_weapon_socket)
	_weapon_socket.bone_name = ENEMY_WEAPON_SOCKET
	# 注意：BoneAttachment3D 自己的 transform 每帧都会被"骨骼姿势"覆盖（引擎行为），
	# 所以对齐偏移不能设在挂点上，而要设在**武器子节点**上。
	_weapon = ENEMY_WEAPON.instantiate() as Node3D
	_weapon.transform = ENEMY_WEAPON_ALIGN_LOCAL
	_weapon_socket.add_child(_weapon)
	_register_mesh_materials(_weapon)   # 武器也跟着一起闪光


## 停掉当前动画，并把所有骨骼复位到"绑定姿势"(rest pose)。
## 【为什么必须做】骨骼动画一旦停播，骨骼会**冻结在停播那一帧的姿势**。
## 本模型没有"死亡动画"，所以死亡时统一复位到 rest pose，再由脚本叠加整体倒地。
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


## 攻击命中盒：面前 2.2 米的大长方体感应区(平时关闭)。
## 挂在 _pivot 下 → 随朝向转动，天然对齐"面前"。
## 高度取 1.15m / 纵深 1.7m，与改造前完全一致（数值是按体验调过的，别乱动）。
func _build_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_pivot.add_child(_hitbox)
	var shape := CollisionShape3D.new()
	shape.name = "HitboxShape"
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.5, 1.5)          # 宽2.2 高1.5 纵深1.5米(挥棒覆盖范围)
	shape.shape = box
	shape.position = Vector3(0.0, 1.15, -1.7)  # 面前1.7米、胸口高度
	_hitbox.add_child(shape)
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_hitbox.area_entered.connect(_on_hitbox_area_entered)


# ------------------------------------------------------------------
# 程序化原语外观（模型加载失败时的兜底方案）
# ------------------------------------------------------------------

## 拼接身体。结构同玩家：肢体是"关节节点"、网格挂其下做偏移，
## 旋转关节(尤其 _arm_r)即可做出举棒/挥棒动画。
## 这套配色与尺寸刻意与 assets/enemies/brute_01 的材质色值一致，
## 所以"换模型 / 回退"两种情况的观感是连贯的。
func _build_procedural_body() -> void:
	# 四种材质
	var armor_mat := _make_mat(Color(0.62, 0.16, 0.14), 0.35, 0.6)  # 红甲
	var dark_mat := _make_mat(Color(0.25, 0.1, 0.09), 0.4, 0.6)     # 暗红(腿/脸罩)
	var bone_mat := _make_mat(Color(0.86, 0.8, 0.68), 0.05, 0.7)    # 骨白(角)
	var club_mat := _make_mat(Color(0.42, 0.3, 0.18), 0.1, 0.75)    # 木棒

	# ---- 腿（两根粗胶囊）----
	_add_capsule_mesh(_pivot, Vector3(0.26, 0.55, 0.0), 0.16, 1.1, dark_mat)
	_add_capsule_mesh(_pivot, Vector3(-0.26, 0.55, 0.0), 0.16, 1.1, dark_mat)

	# ---- 躯干（厚实的大号红色胶囊，比玩家粗壮一圈）----
	_add_capsule_mesh(_pivot, Vector3(0.0, 1.3, 0.0), 0.52, 1.05, armor_mat)

	# ---- 头 + 深色脸罩 + 两只向两侧翘的骨角 ----
	var head := _add_box_mesh(_pivot, Vector3(0.0, 2.12, 0.0), Vector3(0.62, 0.5, 0.58), armor_mat)
	_add_box_mesh(head, Vector3(0.0, 0.16, -0.29), Vector3(0.2, 0.16, 0.1), dark_mat)  # 脸罩
	var horn_l := _add_box_mesh(head, Vector3(-0.26, 0.34, 0.02), Vector3(0.1, 0.4, 0.1), bone_mat)
	horn_l.rotation.z = 0.5    # 左角外翘
	var horn_r := _add_box_mesh(head, Vector3(0.26, 0.34, 0.02), Vector3(0.1, 0.4, 0.1), bone_mat)
	horn_r.rotation.z = -0.5   # 右角外翘

	# ---- 手臂（肩关节；右手=持棒手，动画主操作 _arm_r）----
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.68, 1.7, 0.0)
	_pivot.add_child(_arm_r)
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-0.68, 1.7, 0.0)
	_pivot.add_child(arm_l)
	_add_capsule_mesh(_arm_r, Vector3(0.0, -0.42, 0.0), 0.15, 0.84, armor_mat)
	_add_capsule_mesh(arm_l, Vector3(0.0, -0.42, 0.0), 0.15, 0.84, armor_mat)
	_add_sphere_mesh(_arm_r, Vector3(0.0, -0.42, 0.0), 0.19, dark_mat)  # 拳头
	_add_sphere_mesh(arm_l, Vector3(0.0, -0.42, 0.0), 0.19, dark_mat)

	# ---- 右手的大棒槌（棍身 + 加粗棒头）----
	# 注意：这是**程序化兜底**才需要的大棒。用模型时武器是独立资产 club_01.glb，
	# 由 _attach_weapon() 挂到 weapon.R 骨骼上，不走这里。
	_add_box_mesh(_arm_r, Vector3(0.0, -0.95, 0.0), Vector3(0.2, 1.0, 0.2), club_mat)
	_add_box_mesh(_arm_r, Vector3(0.0, -1.45, 0.0), Vector3(0.34, 0.4, 0.34), club_mat)

	# 命中盒不在这里建，统一由 _build_hitbox() 负责（两种外观共用同一个）


## 建材质并登记（受击闪光要统一改它们）。
func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	_mats.append(mat)
	return mat


## 在 parent 下造胶囊网格。
func _add_capsule_mesh(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 5
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造球网格。
func _add_sphere_mesh(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 10
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造长方体网格。
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
# 受击闪光（自发光红色闪光，逐步衰减）
# ------------------------------------------------------------------

## 开启受击闪光：_flash_power 取较大值，并把所有材质自发光设为红橙色。
func _flash(power: float) -> void:
	_flash_power = maxf(_flash_power, power)
	for mat in _mats:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.3)
		mat.emission_energy_multiplier = _flash_power


## 每帧衰减闪光强度，低到阈值后关闭。
func _decay_flash(delta: float) -> void:
	if _flash_power <= 0.02:
		return
	_flash_power = lerpf(_flash_power, 0.0, 1.0 - exp(-16.0 * delta))
	for mat in _mats:
		mat.emission_energy_multiplier = _flash_power
	if _flash_power <= 0.02:
		for mat in _mats:
			mat.emission_enabled = false


# ------------------------------------------------------------------
# 姿态动画（按 AI 状态驱动）
#
# 两套实现，状态机逻辑完全一致，只是"怎么动"不同：
#   _animate_model      —— 模型外观：播 glTF 自带的骨骼动画
#   _animate_procedural —— 程序化外观：脚本直接转关节节点
# 死亡状态两者共用 _animate_death（模型没有死亡动画，都是整体栽倒 + 缩小消失）
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_decay_flash(delta)
	if _pivot == null:
		return
	if state == State.DEAD:
		_animate_death(delta)
	elif _use_model:
		_animate_model(delta)
	else:
		_animate_procedural(delta)


## 死亡：0.45s 内栽倒(-90°)，同时缩小并下沉(像被击碎消失)。两种外观共用。
func _animate_death(delta: float) -> void:
	if _use_model and _anim_player != null and _anim_player.is_playing():
		_anim_to_rest()   # 模型没有死亡动画 → 先复位骨骼（复位后 is_playing 为假，只做一次）
	_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.45, 0.0, 1.0)
	_pivot.scale = _pivot.scale.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * delta))
	_pivot.position.y = lerpf(_pivot.position.y, -0.6, 1.0 - exp(-2.0 * delta))


## 循环播放某段动画（同名则不重启，避免每帧重播卡在第一帧）。
func _play_loop(anim_name: String, speed: float = 1.0) -> void:
	if _anim_player == null or anim_name == "":
		return
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name, anim_blend_time, speed)
	else:
		_anim_player.speed_scale = speed


## 单次播放某段动画，并把它拉伸/压缩到 duration 秒播完。
## 【为什么按 duration 现算倍速】动画时长和状态机时长本来是成对设计的
## （AttackWindup 0.5s ↔ windup_time 0.5），但两个值都能在编辑器里改。
## 用"动画长度 ÷ 目标时长"实时换算，改任何一个都不会出现
## "动画播完了状态还没结束"或"状态结束了动画还在挥"。
func _play_once(anim_name: String, duration: float) -> void:
	if _anim_player == null or anim_name == "":
		return
	var a := _anim_player.get_animation(anim_name)
	if a == null:
		return
	var spd := a.length / maxf(0.05, duration)
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name, anim_blend_time, spd)
	else:
		_anim_player.speed_scale = spd


## 模型外观：按 AI 状态播对应的骨骼动画。
func _animate_model(delta: float) -> void:
	# 骨骼动画已经在动，整体节点不要再叠加起伏/前倾（会与动画打架）
	_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-10.0 * delta))
	_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
	# 侧倾统一在这里回正；BROKEN 分支会在下面重新写它（打晃效果）
	_pivot.rotation.z = lerp_angle(_pivot.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))

	match state:
		State.IDLE:
			# 待机：呼吸起伏循环
			_play_loop(_idle_anim)
		State.CHASE:
			# 追击：走起来播 Walk（按"速度 ÷ 自然步速"调倍速，避免脚底打滑）；
			# 站住（够近了/被挡住）回待机。
			var spd := Vector2(velocity.x, velocity.z).length()
			if spd > 0.4 and _walk_anim != "":
				var want := clampf(spd / maxf(0.2, walk_natural_speed), 0.4, walk_max_speed_scale)
				_play_loop(_walk_anim, want)
			else:
				_play_loop(_idle_anim)
		State.WINDUP:
			# 蓄力：举棒动画 + 整体轻微脉动（"绷紧"预警，纯视觉不影响判定）
			_play_once(_windup_anim, windup_time)
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.001 * 30.0) * 0.03
			_pivot.scale = Vector3.ONE * pulse
		State.STRIKE:
			# 挥击：下劈动画，倍速铺满 strike_time（与命中盒开启时长同步）
			_pivot.scale = Vector3.ONE
			_play_once(_attack_anim, strike_time)
		State.RECOVER:
			# 收招：回待机站姿（anim_blend_time 会把它从收势姿势平滑过渡过来）
			_pivot.scale = Vector3.ONE
			_play_loop(_idle_anim)
		State.STAGGER:
			# 受击硬直：受击动画，倍速铺满 _stagger_time（与状态机里的硬直时长同步）。
			# 被完美格挡时 _stagger_time = 0.8（普通受击的 2 倍），Hit 动画会被拉成
			# 0.52 倍速慢放 —— 一只大块头被打得踉跄后退，正好读得出"被弹开"的感觉。
			_pivot.scale = Vector3.ONE
			_play_once(_hit_anim, _stagger_time)
		State.BROKEN:
			# 失衡：先正常速度播一遍受击动画（0.6s），**播完就冻在末帧**
			# —— 大块头垂着头半跪着站不稳，一眼就看出"这只现在能处决"。
			# （_play_once 同名动画不会重播，所以末帧会一直保持）
			_pivot.scale = Vector3.ONE
			_play_once(_hit_anim, 0.6)
			# 叠加一点左右打晃，避免站着像定格；幅度小，不影响观感
			_pivot.rotation.z = sin(Time.get_ticks_msec() * 0.001 * 3.0) * 0.05
			_pivot.position.y = -0.12      # 重心下沉一点


## 程序化原语外观：按 AI 状态转关节节点（模型加载失败时的兜底）。
func _animate_procedural(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001      # 秒为单位的时间(驱动循环摆动)
	# 侧倾统一回正；BROKEN 分支会在下面重新写它（打晃效果）
	_pivot.rotation.z = lerp_angle(_pivot.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))
	match state:
		State.IDLE, State.CHASE:
			# 待机/追击：慢晃手臂 + 身体轻微起伏；在走时摆幅加大
			var spd := Vector2(velocity.x, velocity.z).length()
			var moving := spd > 0.4
			if _arm_r != null:
				var swing := sin(t * 4.0) * (0.35 if moving else 0.08)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing, 1.0 - exp(-10.0 * delta))
			var bob := sin(t * 3.0) * (0.05 if moving else 0.02)
			_pivot.position.y = bob
		State.WINDUP:
			# 蓄力：棒槌举到身后上方(rotation.x 转成负 = 向后上抬)，并快速小幅抖动预警
			var k := _state_time / windup_time
			_arm_r.rotation.x = lerpf(0.0, -2.4, k)
			var pulse := 1.0 + sin(t * 30.0) * 0.03    # 身体"绷紧"抖动
			_pivot.scale = Vector3.ONE * pulse
			_pivot.position.y = 0.0
		State.STRIKE:
			# 挥击：棒槌从身后上方甩到前下方（-2.4 → 0.6）
			var k := _state_time / strike_time
			_arm_r.rotation.x = lerpf(-2.4, 0.6, k)
			_pivot.scale = Vector3.ONE
			_pivot.position.y = 0.0
		State.RECOVER:
			# 恢复：棒槌缓缓垂回体侧
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 1.0 - exp(-8.0 * delta))
			_pivot.scale = Vector3.ONE
			_pivot.position.y = 0.0
		State.STAGGER:
			# 被击：双臂后仰(挨打姿势)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.2, 1.0 - exp(-10.0 * delta))
			_pivot.scale = Vector3.ONE
			_pivot.position.y = 0.0
		State.BROKEN:
			# 失衡：棒槌垂到身前地上、身体重心下沉 + 左右打晃（"站都站不稳"）。
			# 与模型外观的 BROKEN 保持同一个观感语义：垂头、下沉、打晃。
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.9, 1.0 - exp(-6.0 * delta))
			_pivot.rotation.z = sin(t * 3.0) * 0.06
			_pivot.scale = Vector3.ONE
			_pivot.position.y = -0.12
