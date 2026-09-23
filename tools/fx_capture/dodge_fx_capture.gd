extends Node
## 开发辅助：抓帧确认"完美闪避"的三样表现 —— 青蓝闪光 / 角色虚影 / 子弹时间。
##
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     res://tools/fx_capture/dodge_fx_capture.tscn --write-movie D:\GodotProject\first-game\.tmp_dodgefx\frame.png
##
## 【为什么必须肉眼确认一次】完美闪避的三样表现**全是视觉的**，断言只能证明
##   "节点存在、时间倍率变了、会自动销毁"，证明不了"屏幕上看得见"：
##     · 虚影最容易出的是"骨架复制出来是 T-pose"（姿势没搬过去）和
##       "虚影跟着本体跑"（忘了 top_level）—— 两者节点数、材质、生命周期断言全绿，
##       但一个看着像"另一个人"，一个看着像"本体重影"。
##     · 子弹时间慢不慢，只能看动作节奏。
##   所以这里专门摆一个**侧面机位**：闪避是纯前后向的动作，侧面才能一眼看出拖影是往哪拖的。
## ---------------------------------------------------------------------------

func _frame() -> int:
	return Engine.get_frames_drawn()


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player = get_tree().get_first_node_in_group("player")
	var enemy = get_tree().get_first_node_in_group("enemy")
	if player == null or enemy == null:
		print("CAPTURE: 找不到玩家/敌人")
		get_tree().quit(1)
		return
	# 敌人变被动木桩：抓帧节奏只由本脚本控制（完美闪避也不会被它补刀打断）
	enemy.aggro_range = 0.0
	enemy.attack_range = 0.0
	enemy.move_speed = 0.0
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(" ", 0.01)

	# ★ 侧面机位（yaw = -90° → 相机绕到角色右侧正对，前后向动作铺满画面宽度）
	var cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
	if cam != null:
		cam.distance = 4.2
		cam.yaw = deg_to_rad(-90.0)
		cam.pitch = 0.12
	print("CAPTURE: 起点帧 %d" % _frame())

	# ── ① 普通后撤（不按方向键）：先录一遍"没有完美判定"的原样，作为对照 ──
	player._try_start_dodge()
	print("CAPTURE: 普通后撤起手 @ 帧 %d（状态 %d / 动画 %s / 时间倍率 %.2f）" % [
		_frame(), player.state, player._anim_player.current_animation, Engine.time_scale])
	await get_tree().create_timer(0.6).timeout
	print("CAPTURE: 普通后撤收招 @ 帧 %d（时间倍率 %.2f，应仍为 1.00）" % [_frame(), Engine.time_scale])

	# ── ② 完美后撤：闪避刚起手就"被敌人判定盒扫到"（等价于敌人这一下本来会打中）──
	await get_tree().create_timer(0.5).timeout            # 等 _iframes 耗干，否则会被提前 return
	player._try_start_dodge()
	await get_tree().create_timer(0.06).timeout
	player.take_damage(15, player.global_position + Vector3(0, 0, 1.5))
	print("CAPTURE: 完美闪避触发 @ 帧 %d（HP %d 未变 / 时间倍率 %.2f / 虚影 %d 个 / 动画 %s）" % [
		_frame(), player.health.current_hp, Engine.time_scale,
		_count_ghost(player), player._anim_player.current_animation])
	# 虚影生命周期只有零点几秒，密集打点把淡出过程也录下来
	for i in 4:
		await get_tree().create_timer(0.12).timeout
		print("CAPTURE:   +%.2fs 帧 %d（时间倍率 %.2f / 虚影 %d 个）" % [
			(i + 1) * 0.12, _frame(), Engine.time_scale, _count_ghost(player)])
	await get_tree().create_timer(1.4).timeout
	print("CAPTURE: 结束帧 %d（时间倍率 %.2f，应已回到 1.00 / 虚影 %d 个，应已清零）" % [
		_frame(), Engine.time_scale, _count_ghost(player)])
	get_tree().quit(0)


## 递归数当前活着的虚影（同自动测试里的做法：挂载点不固定，只能整棵树数）
func _count_ghost(node: Node) -> int:
	var n := 0
	if node is GhostTrail:
		n += 1
	for c in node.get_children():
		n += _count_ghost(c)
	return n
