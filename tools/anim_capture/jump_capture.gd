extends Node
## 开发辅助：演示"**跳跃**"这一下，用来肉眼确认「按一下立即离地」的观感。
##
## 【为什么专门为跳跃做一个抓帧】2026-09-21 取消了"起跳蓄力段"（及起跳动画 JumpStart）：
##   原本按下跳跃键会**先在地面播 0.18s 的蹲身→蹬地**，再离地；
##   现在一按就给向上速度、直接进 `JUMP` 播滞空循环 `JumpAir`。
##   这是一处**纯粹影响观感/手感**的改动 —— 断言只能证明"状态对了、动画对了"，
##   证明不了"好不好看"。要去确认的正是那个最可疑的点：
##   **从站立的 Idle 直接切到 JumpAir 的第 0 帧，会不会"啪"地硬切**（滞空动画起始就是收腿姿势）。
##
## 用法（⚠ **不要加 --headless**，headless 用空渲染驱动出不来图）：
##   mkdir -p .tmp_jump
##   Godot_v4.7.2-stable_win64_console.exe --path . --write-movie .tmp_jump/frame.png \
##     res://tools/anim_capture/jump_capture.tscn
##   ★ --write-movie 的输出目录**必须先建好**（Godot 不会 mkdir，缺失时静默不出图）
##   ★ 抓一次约半分钟起 → 用后台任务跑，别在前台等
##
## 【为什么要让脚本自己报帧号】--write-movie 每渲染一帧写一张 frame%08d.png，
##   序号正好等于 Engine.get_frames_drawn()，拿打印出来的号去取图即可。

## 看门狗：**帧号停滞**超过这么久（真实时间）就强制退出。
## ⚠️ 盯"帧号不再增长"而不是"总耗时"：逐帧渲染的耗时与机器快慢强相关，
##    按总耗时设限会在慢机器上把正常的一次抓帧自己掐死（详见 combo_capture.gd 的说明）。
const STALL_MS := 30000
const HARD_LIMIT_MS := 600000

var _last_frames: int = -1
var _last_progress_ms: int = 0
var _started_ms: int = 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _started_ms > 0 and now - _started_ms > HARD_LIMIT_MS:
		print("CAPTURE: ⚠ 兜底总上限到，强制退出（已渲 %d 帧）" % Engine.get_frames_drawn())
		get_tree().quit(0)
		return
	var drawn := Engine.get_frames_drawn()
	if drawn != _last_frames:
		_last_frames = drawn
		_last_progress_ms = now
	elif _last_progress_ms > 0 and now - _last_progress_ms > STALL_MS:
		print("CAPTURE: ⚠ 帧号停滞 %d ms（末帧=%d）→ 判定卡死，强制退出" % [STALL_MS, drawn])
		get_tree().quit(0)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_last_progress_ms = _started_ms
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 抓帧期间鼠标必须可见，否则真鼠标会带镜头

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		print("CAPTURE: 找不到玩家")
		get_tree().quit(1)
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(" ", 0.01)                   # 清掉开场大字，别盖住画面中央

	print("CAPTURE: 跳跃配置 = prep=%.2f（0=按一下立即离地）｜ 起跳动画=%s（应不再播放）｜ 滞空=%s" % [
		player.jump_prep_time, player._jump_start_anim, player._jump_air_anim])

	# ── 取景：侧前方约 55°，跳跃是"上下"运动，侧视才能读出离地高度与收腿 ──
	var cam = get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.distance = 4.6
		cam.yaw = deg_to_rad(-55.0)
		cam.pitch = 0.22
		cam._snap_to_target()

	# 把真怪赶远：它在仇恨半径内会一直追过来乱入，污染画面与镜头
	var real_enemy = get_tree().get_first_node_in_group("enemy")
	if real_enemy != null:
		real_enemy.global_position = player.global_position + Vector3(60, 0, 0)
		real_enemy.velocity = Vector3.ZERO
		real_enemy.remove_from_group("enemy")

	player.global_position = Vector3(0.0, player.global_position.y, 9.0)
	player.velocity = Vector3.ZERO
	player._face_instant(Vector3(0, 0, -1))
	player._facing_dir = Vector3(0, 0, -1)
	await _wait(0.5)

	# ================= 第一跳：按住（跳满 ≈1.2m）=================
	print("CAPTURE: ══ 第一跳：按住跳跃键（帧号 = Engine.get_frames_drawn()）══")
	print("CAPTURE: 起跳前（站立 Idle）帧=%d 动画=%s" % [
		Engine.get_frames_drawn(), player._anim_player.current_animation])
	var y0: float = player.global_position.y
	Input.action_press("jump")
	player._try_start_jump()
	# ★ 关键一帧：起跳后**马上**取，看 Idle → JumpAir 是不是硬切
	#   （状态枚举：MOVE=0 DODGE=1 ATTACK=2 HURT=3 JUMP_PREP=4 JUMP=5 BLOCK=6 EXECUTE=7 DEAD=8）
	print("CAPTURE: ★ 起跳瞬间 帧=%d 状态=%d（5=JUMP；**4=JUMP_PREP 说明蓄力段没关掉**）动画=%s vy=%.2f" % [
		Engine.get_frames_drawn(), player.state,
		player._anim_player.current_animation, player.velocity.y])
	var peak: float = y0
	var printed_rising := false
	for _i in 90:                                     # 约 1.5s
		await _wait(0.016)
		peak = maxf(peak, player.global_position.y)
		if not printed_rising and player.global_position.y > y0 + 0.25:
			printed_rising = true
			print("CAPTURE: 离地上升中 帧=%d 动画=%s y-y0=%.2f" % [
				Engine.get_frames_drawn(), player._anim_player.current_animation,
				player.global_position.y - y0])
		if player.is_on_floor() and player.global_position.y <= y0 + 0.05:
			break
	Input.action_release("jump")
	print("CAPTURE: 最高点 y-y0=%.2fm  落地帧=%d 动画=%s" % [
		peak - y0, Engine.get_frames_drawn(), player._anim_player.current_animation])
	await _wait(0.4)

	# ================= 第二跳：轻点（小跳），看起跳那一帧是否同样干脆 =================
	print("CAPTURE: ══ 第二跳：轻点（小跳，松开得早）══")
	print("CAPTURE: 起跳前 帧=%d 动画=%s" % [
		Engine.get_frames_drawn(), player._anim_player.current_animation])
	var y1: float = player.global_position.y
	Input.action_press("jump")
	player._try_start_jump()
	print("CAPTURE: ★ 起跳瞬间 帧=%d 动画=%s vy=%.2f" % [
		Engine.get_frames_drawn(), player._anim_player.current_animation, player.velocity.y])
	await _wait(0.10)
	Input.action_release("jump")                      # 早松 → 小跳
	var peak2: float = y1
	for _i in 90:
		await _wait(0.016)
		peak2 = maxf(peak2, player.global_position.y)
		if player.is_on_floor() and player.global_position.y <= y1 + 0.05:
			break
	print("CAPTURE: 轻点最高点 y-y0=%.2fm（应明显低于第一跳的 %.2fm）  落地帧=%d" % [
		peak2 - y1, peak - y0, Engine.get_frames_drawn()])
	await _wait(0.3)
	get_tree().quit(0)


# ------------------------------------------------------------------ 工具

## 按**真实时间**等待 —— 抓帧时的"停一下"用它才准（不受顿帧/子弹时间影响）。
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
