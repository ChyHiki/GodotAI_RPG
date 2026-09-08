extends CharacterBody3D
class_name EnemyBrute
## M1 敌人"红甲守卫"：索敌 → 追击 → 蓄力(预警) → 挥击 → 恢复 的简单状态机。
## 被击中会闪白 + 硬直 + 击退；血量为 0 时倒地消失并发出 died 信号（由主场景负责重生）。

signal died

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

# ---- 参数 ----
@export var move_speed: float = 2.8
@export var accel: float = 10.0
@export var aggro_range: float = 11.0
@export var attack_range: float = 2.3
@export var attack_damage: int = 15
@export var windup_time: float = 0.5
@export var strike_time: float = 0.22
@export var recover_time: float = 0.9
@export var attack_interval: float = 1.6   # 两次攻击的最小间隔
@export var knockback_strength: float = 7.0

const GRAVITY := 24.0

var state: State = State.IDLE
var _state_time: float = 0.0
var _attack_cd: float = 0.0
var _dead: bool = false
var _lunge_dir: Vector3 = Vector3.ZERO

# 程序化视觉引用
var _pivot: Node3D
var _arm_r: Node3D
var _mats: Array[StandardMaterial3D] = []
var _flash_power: float = 0.0

@onready var health: Health = $Health


func _ready() -> void:
    add_to_group("enemy")
    _build_body()
    health.died.connect(_on_health_died)


func is_alive() -> bool:
    return not _dead


func get_target() -> Node3D:
    var p := get_tree().get_first_node_in_group("player") as Node3D
    if p != null and p.has_method("is_alive") and p.is_alive():
        return p
    return null


func _physics_process(delta: float) -> void:
    _state_time += delta
    _attack_cd = maxf(0.0, _attack_cd - delta)
    if not is_on_floor():
        velocity.y -= GRAVITY * delta

    var target := get_target()

    match state:
        State.IDLE:
            if target != null and global_position.distance_to(target.global_position) <= aggro_range:
                state = State.CHASE
                _state_time = 0.0
            _damp_move(delta)
        State.CHASE:
            if target == null:
                state = State.IDLE
                _state_time = 0.0
                _damp_move(delta)
                return
            var to_target := target.global_position - global_position
            var dist := Vector2(to_target.x, to_target.z).length()
            _face_point(target.global_position, delta, 6.0)
            if dist <= attack_range and _attack_cd <= 0.0:
                state = State.WINDUP
                _state_time = 0.0
                _velocity_towards(target, 0.0, delta)
                return
            _velocity_towards(target, move_speed, delta)
        State.WINDUP:
            # 蓄力预警：原地不动，仅面向目标
            if target != null:
                _face_point(target.global_position, delta, 8.0)
            _damp_move(delta)
            if _state_time >= windup_time:
                _begin_strike(target)
        State.STRIKE:
            if _state_time >= strike_time:
                _end_strike()
            else:
                var k := 1.0 - _state_time / strike_time
                velocity.x = _lunge_dir.x * 8.0 * k
                velocity.z = _lunge_dir.z * 8.0 * k
        State.RECOVER:
            _damp_move(delta)
            if _state_time >= recover_time:
                state = State.CHASE
                _state_time = 0.0
        State.STAGGER:
            _damp_move(delta)
            if _state_time >= 0.4:
                state = State.CHASE
                _state_time = 0.0
        State.DEAD:
            _damp_move(delta)

    move_and_slide()


func _begin_strike(target: Node3D) -> void:
    state = State.STRIKE
    _state_time = 0.0
    _attack_cd = attack_interval
    _lunge_dir = Vector3.ZERO
    if target != null:
        _lunge_dir = (target.global_position - global_position)
        _lunge_dir.y = 0.0
        _lunge_dir = _lunge_dir.normalized()
    _set_hitbox_active(true)


func _end_strike() -> void:
    _set_hitbox_active(false)
    state = State.RECOVER
    _state_time = 0.0


func _velocity_towards(target: Node3D, speed: float, delta: float) -> void:
    var to_target := target.global_position - global_position
    var flat := Vector3(to_target.x, 0.0, to_target.z)
    flat = flat.normalized()
    var want := flat * speed
    var t := 1.0 - exp(-accel * delta)
    velocity.x = lerpf(velocity.x, want.x, t)
    velocity.z = lerpf(velocity.z, want.z, t)


func _damp_move(delta: float) -> void:
    var t := 1.0 - exp(-accel * delta)
    velocity.x = lerpf(velocity.x, 0.0, t)
    velocity.z = lerpf(velocity.z, 0.0, t)


func _face_point(point: Vector3, delta: float, speed: float) -> void:
    var flat := point - global_position
    flat.y = 0.0
    if flat.length_squared() < 0.0001:
        return
    var target_yaw := atan2(-flat.x, -flat.z)
    _pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-speed * delta))


# ------------------------------------------------------------------ 受击/死亡

func take_damage(amount: int, from_pos: Vector3) -> void:
    if _dead:
        return
    if not health.damage(amount):
        return
    if health.current_hp <= 0:
        _die()
        return
    # 硬直 + 击退
    if state != State.DEAD:
        state = State.STAGGER
        _state_time = 0.0
        _set_hitbox_active(false)
    var away := global_position - from_pos
    away.y = 0.0
    if away.length() < 0.01:
        away = Vector3.BACK
    away = away.normalized()
    velocity.x = away.x * knockback_strength
    velocity.z = away.z * knockback_strength
    _flash(1.0)


func _on_health_died() -> void:
    if _dead:
        return
    _die()


func _die() -> void:
    if _dead:
        return
    _dead = true
    state = State.DEAD
    _state_time = 0.0
    collision_layer = 0
    collision_mask = 0
    _set_hitbox_active(false)
    _flash(2.0)
    died.emit()
    get_tree().create_timer(1.2).timeout.connect(queue_free)


# ------------------------------------------------------------------ 命中盒

func _set_hitbox_active(active: bool) -> void:
    if _hitbox == null:
        return
    _hitbox.set_deferred("monitoring", active)


func _on_hitbox_body_entered(body: Node3D) -> void:
    if state != State.STRIKE:
        return
    if body.is_in_group("player") and body.has_method("take_damage"):
        body.take_damage(attack_damage, global_position)


func _on_hitbox_area_entered(area: Area3D) -> void:
    if state != State.STRIKE:
        return
    var owner := area.get_parent()
    if owner != null and owner.is_in_group("player") and owner.has_method("take_damage"):
        owner.take_damage(attack_damage, global_position)


# ------------------------------------------------------------------ 程序化视觉

var _hitbox: Area3D


func _build_body() -> void:
    _pivot = Node3D.new()
    _pivot.name = "VisualPivot"
    add_child(_pivot)

    var armor_mat := _make_mat(Color(0.62, 0.16, 0.14), 0.35, 0.6)
    var dark_mat := _make_mat(Color(0.25, 0.1, 0.09), 0.4, 0.6)
    var bone_mat := _make_mat(Color(0.86, 0.8, 0.68), 0.05, 0.7)
    var club_mat := _make_mat(Color(0.42, 0.3, 0.18), 0.1, 0.75)

    # 腿
    _add_capsule_mesh(_pivot, Vector3(0.26, 0.55, 0.0), 0.16, 1.1, dark_mat)
    _add_capsule_mesh(_pivot, Vector3(-0.26, 0.55, 0.0), 0.16, 1.1, dark_mat)

    # 躯干（厚实）
    _add_capsule_mesh(_pivot, Vector3(0.0, 1.3, 0.0), 0.52, 1.05, armor_mat)

    # 头 + 角
    var head := _add_box_mesh(_pivot, Vector3(0.0, 2.12, 0.0), Vector3(0.62, 0.5, 0.58), armor_mat)
    _add_box_mesh(head, Vector3(0.0, 0.16, -0.29), Vector3(0.2, 0.16, 0.1), dark_mat)
    var horn_l := _add_box_mesh(head, Vector3(-0.26, 0.34, 0.02), Vector3(0.1, 0.4, 0.1), bone_mat)
    horn_l.rotation.z = 0.5
    var horn_r := _add_box_mesh(head, Vector3(0.26, 0.34, 0.02), Vector3(0.1, 0.4, 0.1), bone_mat)
    horn_r.rotation.z = -0.5

    # 手臂（肩节点）
    _arm_r = Node3D.new()
    _arm_r.position = Vector3(0.68, 1.7, 0.0)
    _pivot.add_child(_arm_r)
    var arm_l := Node3D.new()
    arm_l.position = Vector3(-0.68, 1.7, 0.0)
    _pivot.add_child(arm_l)
    _add_capsule_mesh(_arm_r, Vector3(0.0, -0.42, 0.0), 0.15, 0.84, armor_mat)
    _add_capsule_mesh(arm_l, Vector3(0.0, -0.42, 0.0), 0.15, 0.84, armor_mat)
    _add_sphere_mesh(_arm_r, Vector3(0.0, -0.42, 0.0), 0.19, dark_mat)
    _add_sphere_mesh(arm_l, Vector3(0.0, -0.42, 0.0), 0.19, dark_mat)

    # 大棒槌（右手）
    _add_box_mesh(_arm_r, Vector3(0.0, -0.95, 0.0), Vector3(0.2, 1.0, 0.2), club_mat)
    _add_box_mesh(_arm_r, Vector3(0.0, -1.45, 0.0), Vector3(0.34, 0.4, 0.34), club_mat)

    # 攻击命中盒（跟随朝向）
    _hitbox = Area3D.new()
    _hitbox.name = "AttackHitbox"
    _hitbox.monitoring = false
    _hitbox.monitorable = false
    _pivot.add_child(_hitbox)
    var shape := CollisionShape3D.new()
    shape.name = "HitboxShape"
    var box := BoxShape3D.new()
    box.size = Vector3(2.2, 1.5, 1.5)
    shape.shape = box
    shape.position = Vector3(0.0, 1.15, -1.7)
    _hitbox.add_child(shape)
    _hitbox.body_entered.connect(_on_hitbox_body_entered)
    _hitbox.area_entered.connect(_on_hitbox_area_entered)


func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    _mats.append(mat)
    return mat


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


func _add_box_mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.surface_set_material(0, mat)
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.position = pos
    parent.add_child(mi)
    return mi


func _flash(power: float) -> void:
    _flash_power = maxf(_flash_power, power)
    for mat in _mats:
        mat.emission_enabled = true
        mat.emission = Color(1.0, 0.5, 0.3)
        mat.emission_energy_multiplier = _flash_power


func _decay_flash(delta: float) -> void:
    if _flash_power <= 0.02:
        return
    _flash_power = lerpf(_flash_power, 0.0, 1.0 - exp(-16.0 * delta))
    for mat in _mats:
        mat.emission_energy_multiplier = _flash_power
    if _flash_power <= 0.02:
        for mat in _mats:
            mat.emission_enabled = false


# ------------------------------------------------------------------ 姿态动画

func _process(delta: float) -> void:
    _decay_flash(delta)
    if _pivot == null:
        return
    var t := Time.get_ticks_msec() * 0.001
    match state:
        State.IDLE, State.CHASE:
            var spd := Vector2(velocity.x, velocity.z).length()
            var moving := spd > 0.4
            if _arm_r != null:
                var swing := sin(t * 4.0) * (0.35 if moving else 0.08)
                _arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing, 1.0 - exp(-10.0 * delta))
            var bob := sin(t * 3.0) * (0.05 if moving else 0.02)
            _pivot.position.y = bob
        State.WINDUP:
            # 高举棒槌 + 抖动预警
            var k := _state_time / windup_time
            var raise := lerpf(0.0, -2.4, k)
            _arm_r.rotation.x = raise
            var pulse := 1.0 + sin(t * 30.0) * 0.03
            _pivot.scale = Vector3.ONE * pulse
            _pivot.position.y = 0.0
        State.STRIKE:
            var k := _state_time / strike_time
            _arm_r.rotation.x = lerpf(-2.4, 0.6, k)
            _pivot.scale = Vector3.ONE
            _pivot.position.y = 0.0
        State.RECOVER:
            _arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 1.0 - exp(-8.0 * delta))
            _pivot.scale = Vector3.ONE
            _pivot.position.y = 0.0
        State.STAGGER:
            _arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.2, 1.0 - exp(-10.0 * delta))
            _pivot.scale = Vector3.ONE
            _pivot.position.y = 0.0
        State.DEAD:
            _pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.45, 0.0, 1.0)
            _pivot.scale = _pivot.scale.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * delta))
            _pivot.position.y = lerpf(_pivot.position.y, -0.6, 1.0 - exp(-2.0 * delta))
