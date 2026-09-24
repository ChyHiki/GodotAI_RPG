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
@export var min_pitch: float = -0.30
## 俯仰角上限（弧度，约 60°，防止镜头高到"上帝视角"）
@export var max_pitch: float = 0.95
## 鼠标灵敏度（乘相对位移换算为弧度）
@export var mouse_sensitivity: float = 0.0025
## 垂直视角方向是否"正向"：
##   true  = 鼠标上移→视角向上看（主流操作习惯）
##   false = 鼠标上移→视角向下看（反转型）
@export var look_invert_y: bool = true
## 跟随平滑速度：越大贴得越紧，越小越"飘"
@export var follow_speed: float = 10.0
## 锁定敌人时，镜头绕到玩家背后、正对敌人的角速度（越大转得越快越"跟手"）
@export var lock_yaw_speed: float = 6.0

## —— 命中震动 ——
## 【作用】攻击打中敌人时，镜头抖一下 —— 这是"打实了"最直接的一层反馈
##   （另外两层是顿帧与音效，见 player.gd 的 _on_hit_landed）。
## 【怎么实现 / 为什么不去动 global_position】本节点每帧都会被 look_at 重新摆正，
##   直接挪 global_position 会在下一帧被覆盖（要么抖不动、要么跟平滑跟随打架变抖屏）。
##   所以把震动施加在**子节点 Camera3D 的局部偏移**上：父节点照常做跟随/注视，
##   子节点负责"在画面里晃"。__process 里的 look_at 动的是父节点，两者互不干扰。
@export var shake_speed: float = 38.0        # 抖动频率(弧度/秒)：越大抖得越快越"脆"
## 当前震动振幅(米)。0 = 没在抖。
var _shake_amount: float = 0.0
## 震动剩余时长 / 总时长(秒)：用 剩余/总 做衰减系数，让"抖完刚好回到 0"。
var _shake_left: float = 0.0
var _shake_duration: float = 0.16
## 抖动相位(累加时间×频率)，用 sin/cos 造出平滑的往复位移（比纯随机更像"震"而不是"雪花屏"）。
var _shake_phase: float = 0.0
## 真正的"眼睛"节点（_ready 里生成）。震动就加在它身上。
var _cam: Camera3D = null

## 相机默认视野(度)。★ 分镜导演(见 cinematic_director.gd)会在特写期间临时改动 _cam.fov，
##   交还控制权时必须复位回这个值 —— 否则处决结束后画面会一直停在那把"长焦特写"的视野上。
const DEFAULT_FOV: float = 70.0

## 特写接管开关：true = 暂停"追尾写位姿"，改由分镜导演逐帧写位姿。
## 【为什么用一位开关而不是 set_process(false)】本节点每帧还要跑 _apply_shake（命中震动）；
##   直接停掉 _process 会把震动的收尾一起冻住。这里只掐掉"追尾写位姿"这一段，
##   震动、鼠标输入各自另有关口（见 _apply_shake / _input）。
var driven: bool = false

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
	cam.fov = DEFAULT_FOV  # 视野角度（度），越大看得越广
	cam.near = 0.05        # 近裁剪面（防近处穿模）
	cam.far = 300.0        # 远裁剪面
	add_child(cam)
	cam.current = true     # 设为当前活动相机（有多个相机时以它为准）
	_cam = cam             # 存一份引用：命中震动要往它身上加偏移（见 shake）

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
	# ★ 特写接管期间不接受鼠标转镜头：导演正在逐帧写死位姿，玩家的鼠标输入会被下一帧覆盖，
	#   表现为"镜头没反应"或"乱抖"。这里直接屏蔽，交还后自动恢复。
	if driven:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# ★ 锁定中 yaw 交给自动跟随（见 _process），这里**不再接受鼠标左右输入**：
		#   否则"玩家想转"与"镜头要绕到敌人背后"会互相拉扯，镜头会左右抖。
		#   俯仰(pitch)仍然保留手动控制 —— 锁定后想抬高/压低视线是很常见的需求。
		if _lock_target() == null:
			yaw -= event.relative.x * mouse_sensitivity     # 左右 → 环绕(符合直觉)
		# 上下 → 俯仰。注意 InputEventMouseMotion.relative.y 的正方向是"向下"，
		# 而主流习惯是"鼠标上移 = 向上看"。pitch 越大相机越高、看得越低，
		# 因此鼠标上移(relative.y<0)要减小 pitch → 系数取 +1(look_invert_y)。
		# 想要"鼠标上移=往下看"的反向手感，把编辑器里的 look_invert_y 关掉即可。
		var y_dir := 1.0 if look_invert_y else -1.0
		pitch += y_dir * event.relative.y * mouse_sensitivity * 0.55
		pitch = clampf(pitch, min_pitch, max_pitch)          # 防止翻转


## 每帧：平滑地把镜头推向期望位置，并始终注视玩家。
func _process(delta: float) -> void:
	_apply_shake(delta)              # 先处理震动偏移（与 target 无关，放在 early-return 之前）
	# ★ 特写接管：震动处理完之后再交权。震动加在子节点 _cam 的局部偏移上、导演写父节点位姿，
	#   两者作用于不同层级、天然互不干扰 —— 于是"处决命中那一下的镜头震动"照常生效。
	if driven:
		return
	if target == null:
		return
	# 锁定中：先把 yaw 平滑转到"玩家 → 敌人"的方位，镜头就自动绕到玩家背后、正对敌人。
	# 公式与玩家的 _face_towards 一致（模型/镜头的正面都是 -Z）：yaw = atan2(-x, -z)。
	# 【为什么用 lerp_angle 而不是直接赋值】直接赋值会让镜头"啪"地跳到背后；
	#   平滑跟踪还能顺带处理"敌人在绕圈"的情况，镜头会跟过去而不是呆住。
	var lt := _lock_target()
	if lt != null:
		var to_t := lt.global_position - target.global_position
		to_t.y = 0.0
		if to_t.length() > 0.05:
			yaw = lerp_angle(yaw, atan2(-to_t.x, -to_t.z), 1.0 - exp(-lock_yaw_speed * delta))
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


## 请求一次镜头震动。由玩家脚本在"攻击命中"时调用（见 player.gd::_on_hit_landed）。
## @param amount   振幅(米)：屏幕上的晃动量级，0.03≈轻击、0.09≈收尾重击
## @param duration 持续时长(秒)
## 【为什么取 max 而不是叠加】一刀扫中两个敌人会连着调两次；若累加振幅，画面会直接甩飞。
##   取"更狠的那一次"既保证了反馈强度，又不会因为命中数量而失控。
func shake(amount: float, duration: float) -> void:
	if amount <= 0.0 or duration <= 0.0:
		return
	_shake_amount = maxf(_shake_amount, amount)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_left = maxf(_shake_left, duration)


## 对外查询：当前震动振幅（0 = 没在抖）。自动测试据此断言"命中真的震了镜头"。
func get_shake_amount() -> float:
	return _shake_amount if _shake_left > 0.0 else 0.0


## 对外查询：当前子相机的视野角度。分镜导演进场时用它记基准、退场时复位。
func get_fov() -> float:
	return _cam.fov if _cam != null else DEFAULT_FOV


# ------------------------------------------------------------------
# 特写接管（由分镜导演调用，见 cinematic_director.gd）
# ------------------------------------------------------------------

## 外部（分镜导演）逐帧写入位姿与 fov。
## 【为什么要把 _current_pos / _current_look 一起同步】它们本是"追尾平滑缓冲"：
##   交还控制权后 _process 会从这两个缓冲继续向期望位置缓动。若不在这里同步成"导演当前的位姿"，
##   交还瞬间缓冲里还留着"特写之前的旧值" → 镜头会猛地弹回旧位置（这就是"弹回"）。
## @param pos     相机世界坐标
## @param look    注视点世界坐标
## @param fov_deg 视野角度(度)
func apply_driven_pose(pos: Vector3, look: Vector3, fov_deg: float) -> void:
	driven = true
	global_position = pos
	_current_pos = pos
	_current_look = look
	if _cam != null:
		_cam.fov = fov_deg
	# 注视点与相机重合时 look_at 会报错，做个最小距离保护（同 _process 里的写法）。
	if pos.distance_to(look) > 0.05:
		look_at(look, Vector3.UP)


## 交还控制权（处决结束 / 目标失效 / 导演被销毁时调用）。★ 必须随时可安全调用。
## 【为什么要反推 yaw / pitch】追尾 rig 的期望位置由 (yaw, pitch) 球坐标算出
##   （见 _wanted_position）。特写期间相机被导演搬到了一个 yaw/pitch 表达不了的位姿，
##   若直接交还、不更新这两个角，下一帧追尾会按"特写之前的旧角度"重算期望位置 →
##   镜头在特写结束瞬间大幅摆回去。从**当前实际位姿**反推 yaw/pitch，追尾就能从当前位置无缝续上。
##   推导：_wanted_position 中 off = raw - look = UP*(d·sin p) - fwd*(d·cos p)，
##   而 fwd = (-sin yaw, 0, -cos yaw) → off 的水平分量 = (d·cos p)·(sin yaw, 0, cos yaw)。
func release_driven() -> void:
	driven = false
	# ★ 把 fov 复位回默认：导演可能在特写里用了 36° 长焦，交还后必须回到 70°。
	if _cam != null:
		_cam.fov = DEFAULT_FOV
	if not is_instance_valid(target):
		return
	var look := target.global_position + Vector3.UP * look_height
	var off := global_position - look
	var off_h := Vector3(off.x, 0.0, off.z)
	# atan2(x, z) 与 _wanted_position 的 fwd=(-sin,0,-cos) 约定一致（推导见上方注释）。
	yaw = atan2(off_h.x, off_h.z)
	pitch = clampf(atan2(off.y, off_h.length()), min_pitch, max_pitch)
	# 同步平滑缓冲 → 追尾从"现在这个位姿"无缝续上，而不是从特写前的旧值弹回。
	_current_pos = global_position
	_current_look = look


## 把震动施加到子节点相机的**局部偏移**上（原因见 _shake_amount 的声明注释）。
## 【衰减形状】振幅 ∝ (剩余/总)²，而不是线性 —— 线性衰减在结尾会"抖到一半突然停"，
##   平方衰减则越抖越小、最后自然收住，读起来像"余震"。
## 【为什么用 sin/cos 而不是每帧随机】随机是白噪声，在高帧率下会糊成"画面重影"；
##   三条不同频率的正弦（横/纵/滚转）能造出有方向感的往复晃动，更像"被震了一下"。
func _apply_shake(delta: float) -> void:
	if _cam == null:
		return
	if _shake_left <= 0.0:
		# 收尾时把偏移擦干净 —— 否则最后一次写入的偏移值会永久留在相机上（画面一直斜着）
		if _shake_amount != 0.0:
			_shake_amount = 0.0
			_cam.h_offset = 0.0
			_cam.v_offset = 0.0
			_cam.rotation.z = 0.0
		return
	# ⚠ 这里用的是**被 time_scale 缩放过的 delta**（不是真实时间），这是刻意的：
	#   顿帧期间时间几乎停住 → 震动也跟着"冻在最大振幅上"，画面定格+镜头在抖，
	#   "这一刀很重"的感觉最强烈；顿帧一结束，震动才继续衰减。若改用真实时间，
	#   震动会在顿帧里悄悄抖完，玩家什么都看不到。
	_shake_left = maxf(0.0, _shake_left - delta)
	_shake_phase += delta * shake_speed
	var k := _shake_left / maxf(0.0001, _shake_duration)   # 1 → 0
	var a := _shake_amount * k * k
	_cam.h_offset = sin(_shake_phase) * a
	_cam.v_offset = cos(_shake_phase * 1.37) * a * 0.8   # ×1.37：与横向不同频，避免走出斜直线
	_cam.rotation.z = sin(_shake_phase * 0.83) * a * 0.30 # 轻微滚转：眼睛最容易被这一下带动


## 玩家当前的锁定目标（没锁定就返回 null）。
## 【为什么反向问玩家】锁定规则的细节（点击中键切换、范围内最近、目标死了重找）
##   全部属于玩家脚本；镜头只需要知道"现在该对着谁"。这样换锁定策略不用动镜头。
func _lock_target() -> Node3D:
	if target == null or not target.has_method("get_lock_target"):
		return null
	return target.get_lock_target() as Node3D


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
