extends Node3D
class_name ThirdPersonCamera
## 自由追尾 + 环绕镜头。
## - 左键拖动期间/平时鼠标移动控制环绕（鼠标捕获时）
## - 镜头平滑跟随目标，并对墙体做射线避让（允许穿过角色）

@export var target: Node3D = null
@export var distance: float = 5.5          # 相机到目标的距离
@export var look_height: float = 1.25      # 注视点高度（目标脚下往上）
@export var min_pitch: float = 0.18        # 最低俯仰角（弧度，约 10°）
@export var max_pitch: float = 1.05        # 最高俯仰角（弧度，约 60°）
@export var mouse_sensitivity: float = 0.0032
@export var follow_speed: float = 10.0     # 位置/注视平滑速率

var yaw: float = 0.0
var pitch: float = 0.45
var _current_pos: Vector3 = Vector3.ZERO
var _current_look: Vector3 = Vector3.ZERO


func _ready() -> void:
    add_to_group("camera")
    if target:
        _snap_to_target()


func set_target(new_target: Node3D) -> void:
    target = new_target
    if is_inside_tree():
        _snap_to_target()


func _snap_to_target() -> void:
    if target == null:
        return
    var look := target.global_position + Vector3.UP * look_height
    var want := _wanted_position(look)
    global_position = want
    _current_pos = want
    _current_look = look
    look_at(look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
    if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if event is InputEventMouseMotion:
        yaw -= event.relative.x * mouse_sensitivity
        pitch -= event.relative.y * mouse_sensitivity * 0.55
        pitch = clampf(pitch, min_pitch, max_pitch)


func _process(delta: float) -> void:
    if target == null:
        return
    var look := target.global_position + Vector3.UP * look_height
    var want := _wanted_position(look)
    var t := 1.0 - exp(-follow_speed * delta)
    _current_pos = _current_pos.lerp(want, t)
    _current_look = _current_look.lerp(look, t)
    global_position = _current_pos
    if _current_pos.distance_to(_current_look) > 0.05:
        look_at(_current_look, Vector3.UP)


## 计算期望的相机世界坐标（含墙体避让）。
func _wanted_position(look_at_point: Vector3) -> Vector3:
    var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
    var raw := look_at_point \
        + Vector3.UP * (distance * sin(pitch)) \
        - fwd * (distance * cos(pitch))
    var params := PhysicsRayQueryParameters3D.create(look_at_point, raw)
    params.exclude = _character_rids()
    var hit := get_world_3d().direct_space_state.intersect_ray(params)
    if not hit.is_empty():
        var dir := (raw - look_at_point).normalized()
        return hit.position - dir * 0.25
    return raw


## 收集所有角色（玩家/敌人）的碰撞 RID，让镜头可以穿过角色但不能穿墙。
func _character_rids() -> Array[RID]:
    var rids: Array[RID] = []
    for group_name in ["player", "enemy"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if node is CollisionObject3D:
                rids.append(node.get_rid())
    return rids
