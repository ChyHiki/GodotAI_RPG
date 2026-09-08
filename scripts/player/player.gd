extends CharacterBody3D
class_name PlayerCharacter
## M1 玩家控制：第三人称移动、翻滚(无敌帧)、近战攻击、受击/死亡。
## 视觉为运行时用原语网格拼装的"小蓝人"角色（无美术依赖，后续可整替换）。

signal player_died

enum State { MOVE, ROLL, ATTACK, HURT, DEAD }

# ---- 手感参数（在编辑器里可直接调整）----
@export var move_speed: float = 6.2
@export var accel: float = 22.0
@export var turn_speed: float = 14.0
@export var roll_speed: float = 9.5
@export var roll_time: float = 0.42
@export var attack_damage: int = 25
@export var attack_cd: float = 0.42
@export var attack_total: float = 0.5
@export var attack_active_start: float = 0.13
@export var attack_active_end: float = 0.3
@export var knockback_strength: float = 9.0

const GRAVITY := 24.0

var state: State = State.MOVE
var _state_time: float = 0.0
var _attack_cooldown: float = 0.0
var _iframes: float = 0.0
var _dead: bool = false

# 程序化视觉引用
var _pivot: Node3D
var _shoulder_r: Node3D
var _shoulder_l: Node3D
var _leg_r: Node3D
var _leg_l: Node3D
var _hitbox: Area3D
var _hit_targets: Array = []
var _mats: Array[StandardMaterial3D] = []

# 运动缓冲
var _wish_dir: Vector3 = Vector3.ZERO
var _facing_dir: Vector3 = Vector3.FORWARD # 局部 -Z 为默认朝向
var _roll_dir: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
var _hurt_from: Vector3 = Vector3.ZERO

@onready var health: Health = $Health


func _ready() -> void:
    add_to_group("player")
    _build_body()
    _connect_hitbox_signals()
    health.died.connect(_on_health_died)


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("attack"):
        _try_start_attack()
    elif event.is_action_pressed("roll"):
        _try_start_roll()


func is_alive() -> bool:
    return not _dead


func _physics_process(delta: float) -> void:
    _state_time += delta
    _attack_cooldown = maxf(0.0, _attack_cooldown - delta)
    _iframes = maxf(0.0, _iframes - delta)
    _update_wish_dir()
    _update_velocity(delta)
    move_and_slide()
    _update_state(delta)


# ------------------------------------------------------------------ 输入与状态

func _update_wish_dir() -> void:
    if _dead or state == State.DEAD:
        _wish_dir = Vector3.ZERO
        return
    if state == State.ROLL:
        return
    var fwd_in := Input.get_axis("move_back", "move_forward")
    var side_in := Input.get_axis("move_left", "move_right")
    var cam := _get_camera()
    var f := Vector3.ZERO
    var r := Vector3.RIGHT
    if cam != null:
        f = -cam.global_basis.z
        r = cam.global_basis.x
    f.y = 0.0
    r.y = 0.0
    f = f.normalized()
    r = r.normalized()
    _wish_dir = (f * fwd_in + r * side_in)
    if _wish_dir.length() > 1.0:
        _wish_dir = _wish_dir.normalized()


func _try_start_attack() -> void:
    if state != State.MOVE or _attack_cooldown > 0.0 or _dead:
        return
    state = State.ATTACK
    _state_time = 0.0
    _hit_targets.clear()
    # 若无移动输入则朝镜头方向攻击
    var aim := _wish_dir if _wish_dir.length() > 0.1 else _get_camera_forward()
    if aim.length() > 0.1:
        _face_instant(aim)
        _facing_dir = aim
    _set_hitbox_active(false)


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


func _update_state(_delta: float) -> void:
    match state:
        State.MOVE:
            _face_towards(_wish_dir, _delta)
            if _wish_dir.length() > 0.1:
                _bob_phase += _delta * 10.0
        State.ROLL:
            if _state_time >= roll_time:
                _end_roll()
        State.ATTACK:
            if _state_time >= attack_total:
                state = State.MOVE
                _state_time = 0.0
                _attack_cooldown = attack_cd
                _set_hitbox_active(false)
        State.HURT:
            if _state_time >= 0.32:
                state = State.MOVE
                _state_time = 0.0
        State.DEAD:
            pass


func _end_roll() -> void:
    health.invincible = false
    state = State.MOVE
    _state_time = 0.0
    _attack_cooldown = maxf(_attack_cooldown, 0.15)
    _pivot.rotation.x = 0.0


# ------------------------------------------------------------------ 物理速度

func _update_velocity(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    match state:
        State.MOVE:
            var target := _wish_dir * move_speed
            var t := 1.0 - exp(-accel * delta)
            velocity.x = lerpf(velocity.x, target.x, t)
            velocity.z = lerpf(velocity.z, target.z, t)
        State.ROLL:
            var t := clampf(1.0 - _state_time / roll_time, 0.0, 1.0)
            var spd := roll_speed * lerpf(0.45, 1.0, t)
            velocity.x = _roll_dir.x * spd
            velocity.z = _roll_dir.z * spd
        State.ATTACK, State.HURT:
            velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-12.0 * delta))
            velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-12.0 * delta))
        State.DEAD:
            velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-8.0 * delta))
            velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-8.0 * delta))


# ------------------------------------------------------------------ 受击/死亡

func take_damage(amount: int, from_pos: Vector3) -> void:
    if _dead or state == State.ROLL or _iframes > 0.0:
        return
    if not health.damage(amount):
        return
    if health.current_hp <= 0:
        _die()
        return
    _enter_hurt(from_pos)


func _enter_hurt(from_pos: Vector3) -> void:
    state = State.HURT
    _state_time = 0.0
    _iframes = 0.6
    _hurt_from = from_pos
    var away := global_position - from_pos
    away.y = 0.0
    if away.length() < 0.01:
        away = -_get_camera_forward()
    away = away.normalized()
    velocity.x = away.x * knockback_strength
    velocity.z = away.z * knockback_strength
    _flash(0.7)
    _face_instant(away)


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
    health.invincible = true
    _set_hitbox_active(false)
    player_died.emit()


# ------------------------------------------------------------------ 朝向工具

func _face_towards(dir: Vector3, delta: float, speed: float = -1.0) -> void:
    var flat := dir
    flat.y = 0.0
    if flat.length_squared() < 0.0001:
        return
    var target_yaw := atan2(-flat.x, -flat.z)
    var rate: float = turn_speed if speed < 0.0 else speed
    _pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-rate * delta))


func _face_instant(dir: Vector3) -> void:
    var flat := dir
    flat.y = 0.0
    if flat.length_squared() < 0.0001:
        return
    _pivot.rotation.y = atan2(-flat.x, -flat.z)


func _get_facing_flat() -> Vector3:
    var f := -_pivot.global_basis.z
    f.y = 0.0
    return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


func _get_camera_forward() -> Vector3:
    var cam := _get_camera()
    if cam == null:
        return _get_facing_flat()
    var f := -cam.global_basis.z
    f.y = 0.0
    return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


func _get_camera() -> Node3D:
    return get_tree().get_first_node_in_group("camera") as Node3D


# ------------------------------------------------------------------ 攻击命中

func _connect_hitbox_signals() -> void:
    if _hitbox == null:
        return
    _hitbox.body_entered.connect(_on_hitbox_body_entered)
    _hitbox.area_entered.connect(_on_hitbox_area_entered)


func _on_hitbox_body_entered(body: Node3D) -> void:
    _on_hitbox_target(body)


func _on_hitbox_area_entered(area: Area3D) -> void:
    var owner := area.get_parent()
    if owner != null and owner != self:
        _on_hitbox_target(owner)


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


func _set_hitbox_active(active: bool) -> void:
    if _hitbox != null:
        _hitbox.set_deferred("monitoring", active)


# ------------------------------------------------------------------ 程序化视觉

func _build_body() -> void:
    _pivot = Node3D.new()
    _pivot.name = "VisualPivot"
    add_child(_pivot)

    # 腿
    var leg_mat := _make_mat(Color(0.16, 0.36, 0.68), 0.35, 0.55)
    _leg_r = _limb(Vector3(0.17, 0.62, 0.0))
    _leg_l = _limb(Vector3(-0.17, 0.62, 0.0))
    _pivot.add_child(_leg_r)
    _pivot.add_child(_leg_l)
    _add_capsule_mesh(_leg_r, Vector3(0.0, -0.31, 0.0), 0.11, 0.62, leg_mat)

    # 躯干
    var torso_mat := _make_mat(Color(0.24, 0.53, 0.92), 0.5, 0.45)
    _add_capsule_mesh(_pivot, Vector3(0.0, 0.98, 0.0), 0.34, 0.85, torso_mat)

    # 头
    var head_mat := _make_mat(Color(0.86, 0.89, 0.93), 0.15, 0.5)
    var head := _add_sphere_mesh(_pivot, Vector3(0.0, 1.56, 0.0), 0.24, head_mat)
    var visor_mat := _make_mat(Color(0.05, 0.1, 0.16), 0.0, 0.2)
    _add_box_mesh(head, Vector3(0.0, 0.02, -0.12), Vector3(0.3, 0.09, 0.08), visor_mat)

    # 手臂（肩节点，便于摆动作）
    var arm_mat := _make_mat(Color(0.30, 0.58, 0.95), 0.45, 0.5)
    _shoulder_r = _limb(Vector3(0.42, 1.34, 0.0))
    _shoulder_l = _limb(Vector3(-0.42, 1.34, 0.0))
    _pivot.add_child(_shoulder_r)
    _pivot.add_child(_shoulder_l)
    _add_capsule_mesh(_shoulder_r, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)
    _add_capsule_mesh(_shoulder_l, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)

    # 武器（剑，挂在右手肩节点下）
    var sword_mat := _make_mat(Color(0.85, 0.87, 0.92), 0.9, 0.22)
    var grip_mat := _make_mat(Color(0.45, 0.3, 0.18), 0.1, 0.7)
    _add_box_mesh(_shoulder_r, Vector3(0.03, -0.66, 0.02), Vector3(0.07, 0.5, 0.04), sword_mat)
    _add_box_mesh(_shoulder_r, Vector3(0.03, -0.28, 0.02), Vector3(0.09, 0.16, 0.07), grip_mat)

    # 攻击命中盒（位于 VisualPivot 前方，随朝向转动）
    _hitbox = Area3D.new()
    _hitbox.name = "AttackHitbox"
    _hitbox.monitoring = false
    _hitbox.monitorable = false
    _pivot.add_child(_hitbox)
    var shape := CollisionShape3D.new()
    shape.name = "HitboxShape"
    var box := BoxShape3D.new()
    box.size = Vector3(1.2, 1.0, 1.8)
    shape.shape = box
    shape.position = Vector3(0.0, 1.05, -1.25)
    _hitbox.add_child(shape)


func _limb(at: Vector3) -> Node3D:
    var n := Node3D.new()
    n.position = at
    return n


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
    mesh.radial_segments = 16
    mesh.rings = 6
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
    mesh.radial_segments = 20
    mesh.rings = 12
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


func _flash(intensity: float) -> void:
    for mat in _mats:
        mat.emission_enabled = true
        mat.emission = Color(1.0, 1.0, 1.0)
        mat.emission_energy_multiplier = intensity


func _decay_flash(delta: float) -> void:
    var alive := false
    for mat in _mats:
        if mat.emission_energy_multiplier > 0.02:
            mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, 0.0, 1.0 - exp(-14.0 * delta))
            alive = true
    if not alive:
        for mat in _mats:
            mat.emission_enabled = false


# ------------------------------------------------------------------ 姿态动画（process 中驱动，简单程序化）

func _process(delta: float) -> void:
    _decay_flash(delta)
    if _pivot == null:
        return
    match state:
        State.MOVE:
            var spd := Vector2(velocity.x, velocity.z).length()
            var moving := spd > 0.5
            var t := clampf(spd / move_speed, 0.0, 1.0)
            # 腿摆动
            var swing := sin(_bob_phase) * 0.7 * t if moving else 0.0
            if _leg_r != null:
                _leg_r.rotation.x = swing
                _leg_l.rotation.x = -swing
            # 身体上下浮动
            var bob := sin(_bob_phase * 2.0) * 0.03 * t if moving else 0.0
            _pivot.position.y = bob
            # 手臂闲逛摆动
            var sway := sin(Time.get_ticks_msec() * 0.003) * 0.08
            if _shoulder_r != null:
                _shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.15 + sway, 1.0 - exp(-12.0 * delta))
                _shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, -0.08, 1.0 - exp(-12.0 * delta))
            if _shoulder_l != null:
                _shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.15 - sway, 1.0 - exp(-12.0 * delta))
                _shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, 0.08, 1.0 - exp(-12.0 * delta))
        State.ROLL:
            var p := clampf(_state_time / roll_time, 0.0, 1.0)
            _pivot.rotation.x = -TAU * p
            _pivot.position.y = 0.0
            if _shoulder_r != null:
                _shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.4, 1.0 - exp(-14.0 * delta))
                _shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.4, 1.0 - exp(-14.0 * delta))
        State.ATTACK:
            _pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
            var windup := attack_active_start
            var slash := attack_active_end
            if _state_time < windup:
                var k := _state_time / windup
                _shoulder_r.rotation.x = lerpf(-0.15, 1.9, k * k)
            elif _state_time < slash:
                var k := (_state_time - windup) / (slash - windup)
                _set_hitbox_active(true)
                _shoulder_r.rotation.x = lerpf(1.9, 0.85, sqrt(k))
            else:
                _set_hitbox_active(false)
                var k := (_state_time - slash) / maxf(0.01, attack_total - slash)
                _shoulder_r.rotation.x = lerpf(0.85, -0.15, k * k)
            _shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.5, 1.0 - exp(-12.0 * delta))
        State.HURT:
            _pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
            _shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
            _shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
        State.DEAD:
            _pivot.rotation.x = -PI / 2.0 * clampf(_state_time / 0.55, 0.0, 1.0)
            _pivot.position.y = lerpf(_pivot.position.y, 0.08, 1.0 - exp(-6.0 * delta))
