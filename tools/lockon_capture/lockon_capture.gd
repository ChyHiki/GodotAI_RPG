extends Node
## 开发辅助：自动演示"点一次鼠标中键锁定敌人 → 面朝敌人 → A/S/D 侧移/后撤 → 整体降速"，
## 用于抓帧肉眼确认观感。（中键是"点击切换"：点一次锁定、再点一次解除。）
##
## 用法（和 tools/life_capture、tools/fx_capture 同一套路）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     --resolution 960x540 --write-movie D:\GodotProject\first-game\.tmp_lockon\frame.png \
##     res://tools/lockon_capture/lockon_capture.tscn
## 产物 frame00000000.png…，**序号 == Engine.get_frames_drawn()** → 脚本打印的帧号可直接定位。
##
## ⚠ 抓帧不能加 --headless：headless 用空渲染驱动，出不来图（会短暂弹窗口，可接受）。
## ---------------------------------------------------------------------------

## 逐帧打印用：当前是第几帧（--write-movie 下每帧都会渲染，序号可直接对应 PNG 文件名）
func _frame() -> int:
	return Engine.get_frames_drawn()


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player = get_tree().get_first_node_in_group("player")
	var enemy = get_tree().get_first_node_in_group("enemy")
	if player == null:
		print("CAPTURE: 找不到玩家")
		get_tree().quit(1)
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(" ", 0.01)      # 清掉开场大字，否则盖住画面中央

	# 把敌人变成被动木桩，并**摆到玩家正前方 4m**：这样"锁定后镜头绕到背后、
	# 玩家正对敌人"才看得出来（如果敌人在侧面，玩家会先转身、镜头再绕过去，不好读）。
	var home: Vector3 = player.global_position
	if enemy != null:
		enemy.aggro_range = 0.0
		enemy.attack_range = 0.0
		enemy.move_speed = 0.0
		enemy.global_position = home + Vector3(0, 0, -4.0)

	# 取景：默认 distance 5.5 在 960×540 里偏小；稍微拉近、压低，让横移的脚看得清。
	var cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
	if cam != null:
		cam.distance = 4.6
		cam.pitch = 0.30

	print("CAPTURE: 起点帧 %d（未锁定，动画=%s，速度倍率=1.0）" % [_frame(), _anim_name(player)])

	# ① 未锁定：给一段横移输入，此时身体会**扭向移动方向**、播 Walk
	_reset_pose(player, home)
	Input.action_press("move_left")
	await get_tree().create_timer(0.7).timeout
	print("CAPTURE: 未锁定横移 @ 帧 %d（动画=%s，身体朝移动方向）"
		% [_frame(), _anim_name(player)])
	Input.action_release("move_left")
	await get_tree().create_timer(0.4).timeout

	# ② 点一次中键 → 锁定：镜头开始绕到玩家背后、玩家转身正对敌人
	_reset_pose(player, home)
	# ⚠ 中键改成"点击切换"后：按下 → 跨过物理帧（让 is_action_just_pressed 被读到）→ 松开。
	#   press 完立刻 release 且中间不 await 会漏读，点击被吞掉。
	Input.action_press("lock_on")
	await get_tree().physics_frame
	Input.action_release("lock_on")
	await get_tree().create_timer(0.35).timeout
	print("CAPTURE: 刚点击中键 @ 帧 %d（锁定=%s，镜头正在绕）"
		% [_frame(), player.is_locked_on()])
	await get_tree().create_timer(0.9).timeout
	print("CAPTURE: 锁定就位 @ 帧 %d（动画=%s，面朝敌人）"
		% [_frame(), _anim_name(player)])
	# 锁定标记：敌人身体中心的白色亮点（LockMarker）。这里把"它确实存在、确实在身体中心"
	# 一并打出来 —— 抓帧图只是佐证，节点事实仍要看日志（万一亮点被挡/过小，日志能分辨）。
	var marker = player._lock_marker
	if marker == null or not is_instance_valid(marker):
		print("CAPTURE: ⚠ 没有锁定标记")
	elif enemy != null:
		print("CAPTURE: 锁定标记 @ 帧 %d（挂在 %s 下，局部 y=%.2f，比敌人脚底高 %.2f m，目标=%s）"
			% [_frame(), marker.get_parent().name, marker.position.y,
				marker.global_position.y - enemy.global_position.y,
				marker.get_target().name])

	# ③ A = 向左侧移（身体保持朝前，脚步横着走）
	#   ⚠ 每段位移前把玩家摆回出发点：不摆回去的话，横移+后撤几秒就漂到场地边界，
	#     撞墙后速度归零、动画掉回 Idle（抓帧会看到"没动"，误判成功能坏了）。
	_reset_pose(player, home)
	Input.action_press("move_left")
	await get_tree().create_timer(0.35).timeout
	print("CAPTURE: 锁定 + 左移(A) @ 帧 %d（动画=%s）" % [_frame(), _anim_name(player)])
	await get_tree().create_timer(0.45).timeout
	print("CAPTURE: 左移半程 @ 帧 %d（速度 %.2f m/s）"
		% [_frame(), Vector2(player.velocity.x, player.velocity.z).length()])
	Input.action_release("move_left")
	await get_tree().create_timer(0.35).timeout

	# ④ S = 后撤（背朝敌人退开，但仍然面朝敌人）
	_reset_pose(player, home)
	Input.action_press("move_back")
	await get_tree().create_timer(0.35).timeout
	print("CAPTURE: 锁定 + 后撤(S) @ 帧 %d（动画=%s）" % [_frame(), _anim_name(player)])
	await get_tree().create_timer(0.45).timeout
	print("CAPTURE: 后撤半程 @ 帧 %d（动画=%s）" % [_frame(), _anim_name(player)])
	Input.action_release("move_back")
	await get_tree().create_timer(0.35).timeout

	# ⑤ D = 向右侧移
	_reset_pose(player, home)
	Input.action_press("move_right")
	await get_tree().create_timer(0.35).timeout
	print("CAPTURE: 锁定 + 右移(D) @ 帧 %d（动画=%s）" % [_frame(), _anim_name(player)])
	await get_tree().create_timer(0.45).timeout
	print("CAPTURE: 右移半程 @ 帧 %d（速度 %.2f m/s）"
		% [_frame(), Vector2(player.velocity.x, player.velocity.z).length()])
	Input.action_release("move_right")
	await get_tree().create_timer(0.4).timeout

	# ⑥ 再点一次中键 → 解除锁定（镜头留在原地，不再自动跟随），身体中心的亮点同时消失
	Input.action_press("lock_on")
	await get_tree().physics_frame
	Input.action_release("lock_on")
	await get_tree().create_timer(0.5).timeout
	print("CAPTURE: 再点一次中键 @ 帧 %d（锁定=%s，标记已收掉=%s）"
		% [_frame(), player.is_locked_on(),
			player._lock_marker == null or not is_instance_valid(player._lock_marker)])
	print("CAPTURE: 结束帧 %d" % _frame())
	get_tree().quit(0)


func _anim_name(player) -> String:
	if player._anim_player == null:
		return "<无>"
	return String(player._anim_player.current_animation)


## 把玩家摆回出发点并清零速度/朝向 —— 每段位移演示前调用，避免几段累加漂到场地边界。
func _reset_pose(player, home: Vector3) -> void:
	player.global_position = home
	player.velocity = Vector3.ZERO
	player._wish_dir = Vector3.ZERO
	player._pivot.rotation.y = 0.0
