extends Node
## 开发辅助：自动演示"完美格挡 → 失衡 → 处决"全流程，用于抓帧肉眼确认特效与 HUD。
##
## 用法（和 tools/anim_capture/roll_capture.tscn 同一套路）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     res://tools/fx_capture/fx_capture.tscn --write-movie D:\GodotProject\first-game\.tmp_fx\frame.png
## 输出的 frame0000.png / frame0001.png … 是逐帧图；脚本会在关键帧打印序号，方便直接跳过去看。
##
## 【为什么要写这个工具】特效与 HUD 的"好不好看"没法用断言验证（自动测试只能验
##   "节点生成了、在放大、会自毁"）。抓帧是唯一能肉眼确认观感的手段。
## ---------------------------------------------------------------------------

## 逐帧打印用：当前是第几帧（--write-movie 下每帧都会渲染，序号可直接对应 PNG 文件名）
func _frame() -> int:
	return Engine.get_frames_drawn()


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	# 抓帧期间把鼠标设为可见：否则真实鼠标移动会带动镜头，污染画面
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player = get_tree().get_first_node_in_group("player")
	var enemy = get_tree().get_first_node_in_group("enemy")
	if player == null or enemy == null:
		print("CAPTURE: 找不到玩家/敌人")
		get_tree().quit(1)
		return
	# 把敌人变成被动木桩：不追、不打，保证抓帧节奏只由本脚本控制
	enemy.aggro_range = 0.0
	enemy.attack_range = 0.0
	enemy.move_speed = 0.0
	# 清掉开场操作提示：否则大字会盖住画面中央的特效（只为出图好看，不影响游戏）
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(" ", 0.01)
	# 抓帧用取景：默认第三人称镜头(distance 5.5、正后方)在 960×540 里人物很小，
	# 而且"前刺→上划"是**朝画面深处**做的，从正后方几乎看不出动作。
	# 这里绕到侧后方 + 拉近，让处决的剪影横着铺开。只改镜头，不动任何游戏逻辑。
	var cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
	if cam != null:
		cam.distance = 3.6
		cam.yaw = deg_to_rad(-68.0)   # 0 = 正后方 → -68° 绕到右侧后方（贴侧面）
		cam.pitch = 0.24
	print("CAPTURE: 起点帧 %d" % _frame())

	# ① 完美格挡 ×3 → 失衡值 34% / 68% / 100%(BROKEN)
	#    每次都要重新贴到身前：完美格挡的击退是 ×1.4 的，会把怪推出处决距离
	# ① 完美格挡 ×3 → 失衡值 34% / 68% / 100%(BROKEN)
	#    每次都要重新贴到身前：完美格挡的击退是 ×1.4 的，会把怪推出处决距离
	for i in 3:
		Input.action_release("block")
		await get_tree().create_timer(0.18).timeout
		_place_in_front(enemy, player, 1.3)
		Input.action_press("block")
		player._try_start_block()
		await get_tree().create_timer(0.05).timeout   # 让"举剑"动作演一下（纯视觉）
		# ⚠️ 兜底：BLOCK 的存续由"右键是否按住"决定，而模拟按键在无焦点窗口下可能被引擎清掉，
		#    导致 _update_state 提前收招。这里若发现已经不在格挡，就重新起手一次
		#    （_try_start_block 会把 _state_time 归零 → 完美窗口必然还在）。
		if player.state != PlayerCharacter.State.BLOCK:
			player._try_start_block()
		player.take_damage(15, enemy.global_position)
		print("CAPTURE: 第 %d 次完美格挡 @ 帧 %d（失衡值 %.0f / 玩家HP %d）" % [
			i + 1, _frame(), enemy.poise.current_poise, player.health.current_hp])
		await get_tree().create_timer(0.45).timeout   # 让黄光演完 + HUD 黄条走完
	print("CAPTURE: 敌人已失衡(BROKEN=%s) @ 帧 %d" % [enemy.poise.is_broken(), _frame()])

	# ② 处决：走近失衡的敌人按左键 → EXECUTE（起手金光 + 命中金爆闪）
	Input.action_release("block")
	await get_tree().create_timer(0.2).timeout
	# 兜底：处决只能从 MOVE 起手；若上一步的格挡没收干净就手动收掉
	if player.state != PlayerCharacter.State.MOVE:
		player._end_block()
	_place_in_front(enemy, player, 1.3)
	player._attack_cooldown = 0.0
	player._try_start_attack()
	print("CAPTURE: 处决起手 @ 帧 %d（状态 %d / 无敌 %s / 动画 %s）" % [
		_frame(), player.state, player.health.invincible,
		player._anim_player.current_animation if player._anim_player != null else "<无>"])
	# 等到"前刺命中"那一刻（判定帧 = execute_hit_time，对应 Execute 动画第 9 帧）
	await get_tree().create_timer(player.execute_hit_time + 0.08).timeout
	print("CAPTURE: 处决命中 @ 帧 %d（敌人存活=%s / 剩余 %d 血 / 动画 %s）" % [
		_frame(), enemy.is_alive(), enemy.health.current_hp,
		player._anim_player.current_animation if player._anim_player != null else "<无>"])
	await get_tree().create_timer(player.execute_time * 0.6).timeout
	print("CAPTURE: 处决收招 @ 帧 %d（玩家状态 %d / 敌人失衡 %s）" % [
		_frame(), player.state, enemy.poise.is_broken()])
	await get_tree().create_timer(0.6).timeout
	print("CAPTURE: 结束帧 %d" % _frame())
	get_tree().quit(0)


## 把目标摆到玩家正前方 dist 米处（玩家默认朝 -Z）。
func _place_in_front(target: Node3D, player: Node3D, dist: float) -> void:
	target.global_position = player.global_position + Vector3(0, 0, -1) * dist
	target.velocity = Vector3.ZERO
