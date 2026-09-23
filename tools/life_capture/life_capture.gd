extends Node
## 开发辅助：自动演示"站立待机(Idle) → 挨打(Hurt) → 倒地(Death)"三段生活动画，
## 用于抓帧肉眼确认观感。
##
## 用法（和 tools/fx_capture/fx_capture.tscn 同一套路）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     --resolution 960x540 --write-movie D:\GodotProject\first-game\.tmp_life\frame.png \
##     res://tools/life_capture/life_capture.tscn
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
	if enemy != null:
		# 把敌人变成被动木桩：不追、不打，保证抓帧节奏只由本脚本控制
		enemy.aggro_range = 0.0
		enemy.attack_range = 0.0
		enemy.move_speed = 0.0
		enemy.global_position = player.global_position + Vector3(6, 0, 0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(" ", 0.01)      # 清掉开场大字，否则盖住画面中央
	# 取景：默认第三人称(distance 5.5、正后方)在 960×540 里人物太小；
	# 而且倒地是**朝画面纵深**趴下去的，从正后方看不出剪影 → 绕到侧面并拉近。
	var cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
	if cam != null:
		cam.distance = 3.9
		cam.yaw = deg_to_rad(-72.0)      # 0 = 正后方 → -72° 贴到右侧
		cam.pitch = 0.20
	print("CAPTURE: 起点帧 %d（Idle，动画=%s）" % [_frame(), _anim_name(player)])

	# ① Idle：站住不动，呼吸循环 2.0s。取吸气峰值与呼气谷值两个时刻。
	await get_tree().create_timer(0.55).timeout
	print("CAPTURE: Idle 吸气峰值 @ 帧 %d" % _frame())
	await get_tree().create_timer(1.0).timeout
	print("CAPTURE: Idle 呼气谷值 @ 帧 %d" % _frame())
	await get_tree().create_timer(0.45).timeout

	# ② Hurt：0.333s 的挨打一甩（后仰到位 → 缓回来）
	player.health.reset()
	player._iframes = 0.0
	player._enter_hurt(player.global_position + Vector3(0, 0, -1.5))
	await get_tree().create_timer(0.09).timeout
	print("CAPTURE: Hurt 后仰峰值 @ 帧 %d（动画=%s，实际倍速 %.3f）"
		% [_frame(), _anim_name(player), player._anim_player.get_playing_speed()])
	await get_tree().create_timer(0.34).timeout
	print("CAPTURE: Hurt 结束 @ 帧 %d（状态 %d，动画=%s）"
		% [_frame(), player.state, _anim_name(player)])

	# ③ Death：挨满 1000 伤害 → 前扑倒地（1.06 倍速播 0.542s 的内容）
	player.health.reset()
	await get_tree().create_timer(0.25).timeout
	player.take_damage(1000, player.global_position + Vector3(0, 0, -1.5))
	# 抓帧用：死亡遮罩是全屏红色 vignette，会把尸体整个染红、看不清姿势。
	# 这里只把它藏起来（纯出图需要，不改游戏行为）。
	await get_tree().create_timer(0.03).timeout
	var overlay = hud.get("_death_overlay") if hud != null else null
	if overlay != null:
		overlay.visible = false
	await get_tree().create_timer(0.17).timeout
	print("CAPTURE: Death 膝盖发软 @ 帧 %d（动画=%s）" % [_frame(), _anim_name(player)])
	await get_tree().create_timer(0.20).timeout
	print("CAPTURE: Death 前扑中 @ 帧 %d" % _frame())
	await get_tree().create_timer(0.25).timeout
	print("CAPTURE: Death 落地 @ 帧 %d（动画在播=%s）"
		% [_frame(), player._anim_player.is_playing() if player._anim_player != null else false])
	await get_tree().create_timer(0.5).timeout
	print("CAPTURE: Death 定住 @ 帧 %d（尸体未复位=%s）"
		% [_frame(), not _bones_at_rest(player)])
	print("CAPTURE: 结束帧 %d" % _frame())
	get_tree().quit(0)


func _anim_name(player) -> String:
	if player._anim_player == null:
		return "<无>"
	return String(player._anim_player.current_animation)


## 所有骨骼是否回到绑定姿势（用来证明倒地后**没有**被复位）
func _bones_at_rest(player) -> bool:
	var skel = player._skeleton
	if skel == null:
		return false
	for i in skel.get_bone_count():
		var rest: Transform3D = skel.get_bone_rest(i)
		var q_rest: Quaternion = rest.basis.get_rotation_quaternion()
		if absf(skel.get_bone_pose_rotation(i).angle_to(q_rest)) > 0.08:
			return false
	return true
