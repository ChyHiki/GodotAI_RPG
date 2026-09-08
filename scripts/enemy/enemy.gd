extends CharacterBody3D
class_name EnemyBrute
## ============================================================
## 敌人"红甲守卫"：简易 AI 状态机 + 程序化外观
## ============================================================
## 【这个脚本做了什么】
##   一个会主动攻击玩家的红色壮汉怪：
##     - 平时在出生点附近待机(IDLE)，玩家进入仇恨范围(11m)后追击(CHASE)
##     - 靠近后开始"蓄力"(WINDUP，0.5s 高举棒槌=预警窗口，玩家趁机躲/打)
##     - 蓄力完挥出带判定的一棒(STRIKE)，命中玩家扣 15 血
##     - 挥完要休息(RECOVER)，玩家可以趁这时反击
##     - 被玩家打中会硬直+击退(STAGGER)；血空倒地消失(DEAD)
##
## 【状态机流转】
##   IDLE --玩家靠近--> CHASE --进入攻击距离且冷却好--> WINDUP
##   WINDUP --0.5s--> STRIKE --0.22s--> RECOVER --0.9s--> CHASE
##   (任意非死亡状态) --被击中--> STAGGER --0.4s--> CHASE
##   (任意状态) --血量归零--> DEAD(倒地消失+发 died 信号，主场景负责重生)
##
## 【设计要点】
##   - 蓄力期可被玩家打断(被打就 STAGGER 取消出招)→ 鼓励玩家主动进攻
##   - 攻击有明确"预警→出手"节奏，让翻滚躲招成为可能
## ============================================================

## 信号：本敌人死亡（主场景监听后提示并计时重生）
signal died

## 状态枚举（流转关系见文件头）
enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }


# ------------------------------------------------------------------
# AI 参数（@export → 选中敌人节点可在编辑器实时调整难度）
# ------------------------------------------------------------------

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

## 重力(米/秒²)，与玩家一致
const GRAVITY := 24.0


# ------------------------------------------------------------------
# 运行时状态变量
# ------------------------------------------------------------------

var state: State = State.IDLE    # 当前 AI 状态
var _state_time: float = 0.0     # 当前状态已持续时长(秒)
var _attack_cd: float = 0.0      # 攻击冷却倒计时
var _dead: bool = false          # 是否已死亡
var _lunge_dir: Vector3 = Vector3.ZERO  # 挥击时的前冲方向（出手瞬间朝玩家锁定）


# ------------------------------------------------------------------
# 程序化外观引用
# ------------------------------------------------------------------

var _pivot: Node3D               # VisualPivot：外观根，旋转=面向玩家
var _arm_r: Node3D               # 右手臂关节(棒槌挂在下面，挥棒靠转它)
var _mats: Array[StandardMaterial3D] = []  # 部件材质(受击闪红白用)
var _flash_power: float = 0.0    # 当前受击闪光强度(逐步衰减到0)

## Health 组件引用
@onready var health: Health = $Health


# ------------------------------------------------------------------
# 引擎回调与对外查询
# ------------------------------------------------------------------

## 进入场景：注册到 "enemy" 组(玩家命中盒/镜头靠组识别它)、拼外观、监听血量归零。
func _ready() -> void:
	add_to_group("enemy")
	_build_body()
	health.died.connect(_on_health_died)


## 供玩家命中盒查询：还活着吗？
func is_alive() -> bool:
	return not _dead


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
			# 待机：玩家进入仇恨范围 → 切换追击
			if target != null and global_position.distance_to(target.global_position) <= aggro_range:
				state = State.CHASE
				_state_time = 0.0
			_damp_move(delta)                    # 原地停住
		State.CHASE:
			# 追击：面朝玩家逼近；够近且冷却好 → 蓄力
			if target == null:                   # 玩家死了/消失了 → 回待机
				state = State.IDLE
				_state_time = 0.0
				_damp_move(delta)
				return
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
			# 蓄力预警：原地不动保持面向(只转不挪)，时间到就出手
			if target != null:
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
			# 被击硬直：顿一下回追击
			_damp_move(delta)
			if _state_time >= 0.4:
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
	_lunge_dir = Vector3.ZERO
	if target != null:
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
	if state != State.DEAD:
		state = State.STAGGER
		_state_time = 0.0
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
# 程序化外观（红甲守卫 = 壮汉：红躯干/双角/大棒槌）
# ------------------------------------------------------------------

var _hitbox: Area3D   # 攻击命中盒(见下方 _build_body)


## 拼接身体。结构同玩家：肢体是"关节节点"、网格挂其下做偏移，
## 旋转关节(尤其 _arm_r)即可做出举棒/挥棒动画。
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "VisualPivot"
	add_child(_pivot)

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
	_add_box_mesh(_arm_r, Vector3(0.0, -0.95, 0.0), Vector3(0.2, 1.0, 0.2), club_mat)
	_add_box_mesh(_arm_r, Vector3(0.0, -1.45, 0.0), Vector3(0.34, 0.4, 0.34), club_mat)

	# ---- 攻击命中盒：面前 2.2 米的大长方体感应区(平时关闭) ----
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
# 程序化姿态动画（按 AI 状态摆姿势）
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_decay_flash(delta)
	if _pivot == null:
		return
	var t := Time.get_ticks_msec() * 0.001      # 秒为单位的时间(驱动循环摆动)
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
			var raise := lerpf(0.0, -2.4, k)
			_arm_r.rotation.x = raise
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
		State.DEAD:
			# 死亡：0.45s 内栽倒(-90°)，同时缩小并下沉(像被击碎消失)
			_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.45, 0.0, 1.0)
			_pivot.scale = _pivot.scale.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * delta))
			_pivot.position.y = lerpf(_pivot.position.y, -0.6, 1.0 - exp(-2.0 * delta))
