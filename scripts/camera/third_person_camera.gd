extends Node3D
class_name ThirdPersonCamera
## ============================================================
## 第三人称"自由追尾 + 环绕"镜头
## ============================================================
## 【作用】像黑魂/战神那样：镜头永远悬在角色侧后方上方，随鼠标环绕、
##   平滑跟随，撞墙时自动拉近（防穿墙），但可以穿过角色本身。
##
## 【工作方式】
##   1. 本节点是一个"镜头支架"（普通 Node3D），_ready() 里生成一个
##      Camera3D 子节点作为真正的"眼睛"。← 关键！没有 Camera3D 就看不到 3D 世界
##   2. 用两个角度描述镜头方向：
##        yaw   (偏航角)：绕 Y 轴转，鼠标左右移动改变 → 环绕
##        pitch (俯仰角)：镜头抬/降的角度，鼠标上下移动改变
##   3. 目标(玩家)位置 → 期望的镜头位置(球坐标换算) → 射线防穿墙修正
##      → 用指数平滑(lerp)缓动过去 → look_at 注视玩家
##   4. 使用"组(camera)"对外暴露：玩家脚本通过 get_tree().get_first_node_in_group("camera")
##      找到本节点，用它面向的方位换算 WASD 的移动方向。
##
## 【经验公式说明】1.0 - exp(-速度 * delta) 是帧率无关的"向目标逼近比例"，
##   比直接 lerp 固定系数更平滑且与帧率无关，本文件多处使用。
## ============================================================

## 跟随目标（玩家）。由主场景在生成玩家后调用 set_target() 传入。
@export var target: Node3D = null
## 相机到注视点的直线距离（米）
@export var distance: float = 5.5
## 注视点高度 = 目标脚下往上抬的高度（米），约在角色胸口
@export var look_height: float = 1.25
## 俯仰角下限（弧度，约 10°，防止镜头钻到脚下）
@export var min_pitch: float = 0.18
## 俯仰角上限（弧度，约 60°，防止镜头高到"上帝视角"）
@export var max_pitch: float = 1.05
## 鼠标灵敏度（乘相对位移换算为弧度）
@export var mouse_sensitivity: float = 0.0032
## 跟随平滑速度：越大贴得越紧，越小越"飘"
@export var follow_speed: float = 10.0

## 当前偏航角（绕 Y 轴），初始 0 = 镜头在角色正后方（角色默认朝 -Z）
var yaw: float = 0.0
## 当前俯仰角（弧度），初始约 26°
var pitch: float = 0.45
## 平滑缓冲：镜头实际坐标（每帧向期望位置靠近）
var _current_pos: Vector3 = Vector3.ZERO
## 平滑缓冲：镜头实际注视点
var _current_look: Vector3 = Vector3.ZERO


func _ready() -> void:
    # 把自己登记进 "camera" 组，方便玩家/主场景查找
    add_to_group("camera")

    # ★ 关键：生成真正的 Camera3D 作为子节点。
    #   如果场景中没有"当前活动相机"，Godot 完全不渲染 3D 世界，
    #   屏幕只剩 UI——这是 M1 早期"画面全空"bug 的根源。
    var cam := Camera3D.new()
    cam.name = "Camera"
    cam.fov = 70.0         # 视野角度（度），越大看得越广
    cam.near = 0.05        # 近裁剪面（防近处穿模）
    cam.far = 300.0        # 远裁剪面
    add_child(cam)
    cam.current = true     # 设为当前活动相机（有多个相机时以它为准）

    if target:
        _snap_to_target() # 初始瞬间直接跳到正确位置，避免开场抖动


## 由外部(主场景)设置跟随目标并立刻摆好镜头。
func set_target(new_target: Node3D) -> void:
    target = new_target
    if is_inside_tree():
        _snap_to_target()


## 不经过平滑、瞬间把镜头摆到目标后方正确位置（场景启动/重设目标时用）。
func _snap_to_target() -> void:
    if target == null:
        return
    var look := target.global_position + Vector3.UP * look_height
    var want := _wanted_position(look)   # 计算期望坐标（含防穿墙）
    global_position = want
    _current_pos = want                  # 同步缓冲，避免随后抖动
    _current_look = look
    look_at(look, Vector3.UP)            # 让 -Z 轴对准玩家


## 处理鼠标环绕输入。只有鼠标被捕获(游戏内)时才响应。
## 用 _input(而不是 _unhandled_input)：_input 对每个原始事件最先触发，
## 即使某个 UI 控件吃掉事件，环绕也不会失灵。
func _input(event: InputEvent) -> void:
    if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if event is InputEventMouseMotion:
        yaw -= event.relative.x * mouse_sensitivity          # 左右 → 环绕
        pitch -= event.relative.y * mouse_sensitivity * 0.55 # 上下 → 俯仰(0.55=垂直减速)
        pitch = clampf(pitch, min_pitch, max_pitch)          # 防止翻转


## 每帧：平滑地把镜头推向期望位置，并始终注视玩家。
func _process(delta: float) -> void:
    if target == null:
        return
    var look := target.global_position + Vector3.UP * look_height
    var want := _wanted_position(look)
    var t := 1.0 - exp(-follow_speed * delta)   # 帧率无关的逼近系数
    _current_pos = _current_pos.lerp(want, t)   # 位置缓动
    _current_look = _current_look.lerp(look, t) # 注视点缓动
    global_position = _current_pos
    # 注视点与镜头重合时会报错，做个最小距离保护
    if _current_pos.distance_to(_current_look) > 0.05:
        look_at(_current_look, Vector3.UP)


## 计算期望的相机世界坐标（球坐标 + 防穿墙）。
## @param look_at_point 注视点世界坐标
## 实现：
##   1. 由 yaw 得到水平朝向 fwd；由 pitch 把镜头抬高 distance*sin(pitch)
##      并后撤 distance*cos(pitch) → 期望位置 raw；
##   2. 从注视点向 raw 打一条物理射线，若中途撞墙(hit)，
##      就把镜头停在撞点前 0.25m，实现"贴墙自动拉近"。
func _wanted_position(look_at_point: Vector3) -> Vector3:
    # 水平朝向：yaw=0 时指向 -Z（角色背后方向的反向）
    var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
    var raw := look_at_point \
        + Vector3.UP * (distance * sin(pitch)) \
        - fwd * (distance * cos(pitch))
    # 射线参数：起点=注视点，终点=期望镜头位置，碰撞全部图层
    var params := PhysicsRayQueryParameters3D.create(look_at_point, raw)
    params.exclude = _character_rids()  # 允许穿过玩家/敌人，只挡墙
    var hit := get_world_3d().direct_space_state.intersect_ray(params)
    if not hit.is_empty():
        var dir := (raw - look_at_point).normalized()
        return hit.position - dir * 0.25
    return raw


## 收集所有角色(玩家/敌人)的物理体 RID。
## 实现：遍历 "player" 与 "enemy" 两个组里的 CollisionObject3D，
##       把它们的 RID 交给射线 exclude 参数，让镜头可以穿过角色本体。
func _character_rids() -> Array[RID]:
    var rids: Array[RID] = []
    for group_name in ["player", "enemy"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if node is CollisionObject3D:
                rids.append(node.get_rid())
    return rids
