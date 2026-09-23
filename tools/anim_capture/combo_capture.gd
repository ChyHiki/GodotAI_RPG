extends Node
## 开发辅助：演示"三段连击（Slash → Slash2 → Slash3）"，并在关键时刻打印帧号，
## 便于抓帧后拼成对比条（tools/img_probe/montage.py）。
##
## 用法（⚠ **不要加 --headless**，headless 用空渲染驱动出不来图）：
##   mkdir -p .tmp_combo
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 960x540 \
##     --write-movie .tmp_combo/frame.png res://tools/anim_capture/combo_capture.tscn
##   ★ --write-movie 的输出目录**必须先建好**（Godot 不会 mkdir，缺失时静默不出图）
##   ★ 抓一次约半分钟起 → 用后台任务跑，别在前台等
##
## 【为什么要让脚本自己报帧号】--write-movie 每渲染一帧写一张 frame%08d.png，
##   序号正好等于 Engine.get_frames_drawn()。而连击里每一次命中都会触发**顿帧**
##   （全局时间被压慢）→ 同一段动作跨的帧数变多，任何"秒数 × 帧率"的心算都会错位。
##   所以这里在每段的关键姿势时刻直接打印帧号，拿号去取图即可。
##
## 【分两幕】第一幕逐段单独播（每段采 3 个姿势，用来拼姿势对比条）；
##   第二幕才是真正一整套连击（带后摇取消 + 输入缓冲），用来验证"真的能连起来"。
##   不把两件事混在一起，是因为"采样时刻"和"取消点"会打架 —— 第 1 段的取消点(0.30s)
##   在第 1 段总时长(0.50s)的 60% 处，想采到 70% 的收招姿势就**必然**已经接上了下一段。

## 第一幕的采样时刻（占该段总时长的比例）：起手、挥出（判定窗内）、收招。
const SEG_SAMPLES: Array[float] = [0.25, 0.55, 0.80]

## 看门狗：**帧号不再前进**超过这么久（真实时间）就强制退出。
##
## 【为什么盯"帧号停滞"而不是"总耗时"】抓帧是"无人值守"的长任务（Movie Maker 逐帧渲染，
##   一次几百帧）。最初这里写的是"总耗时上限 45s"，结果**它会把正常的一次抓帧自己掐死**：
##   逐帧渲染的耗时 ∝ 帧数 × 单帧渲染时间，跟机器快慢强相关 —— 实测本机 189 帧就吃掉约 45s，
##   而一整套连击（含顿帧，顿帧会让同一秒内渲染的帧数变多）轻松超过 500 帧。
##   按总耗时设限，要么把小机器上的正常任务杀掉，要么把上限抬到很大、真卡住时又要干等。
##
##   而"卡住"的本质特征其实是 **Engine.get_frames_drawn() 不再增长**（脚本空转，
##   一张新图都不出；本次真踩过：后台跑了 6 分钟、`ls` 出来的还是上一轮的 189 张图）。
##   盯这个信号 + 30s 宽限，就与"这台机器渲染快不快""这一趟要跑多少帧"全部无关。
const STALL_MS := 30000

## 兜底总上限（真实时间）：万一帧号一直在涨但永远跑不完（逻辑死循环里还在渲染），
##   也得有个尽头，别把整轮工作无限堵住。给得很宽松，正常一次抓帧远远用不到。
const HARD_LIMIT_MS := 600000

var _last_frames: int = -1
var _last_progress_ms: int = 0
var _started_ms: int = 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _started_ms > 0 and now - _started_ms > HARD_LIMIT_MS:
		print("CAPTURE: ⚠ 兜底总上限 %d ms 到，强制退出（已渲 %d 帧）"
			% [HARD_LIMIT_MS, Engine.get_frames_drawn()])
		get_tree().quit(0)
		return
	var drawn := Engine.get_frames_drawn()
	if drawn != _last_frames:                 # 有新帧 → 刷新"最后一次推进"的时刻
		_last_frames = drawn
		_last_progress_ms = now
	elif _last_progress_ms > 0 and now - _last_progress_ms > STALL_MS:
		print("CAPTURE: ⚠ 帧号停滞 %d ms（末帧=%d）→ 判定卡死，强制退出"
			% [STALL_MS, drawn])
		get_tree().quit(0)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_last_progress_ms = _started_ms
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 抓帧期间鼠标必须可见，否则真鼠标会带镜头

	var player = get_tree().get_first_node_in_group("player")
	var hud = get_tree().get_first_node_in_group("hud")
	if player == null:
		print("CAPTURE: 找不到玩家")
		get_tree().quit(1)
		return
	if hud != null:
		hud.show_message(" ", 0.01)                   # 清掉开场大字，别盖住画面中央
	print("CAPTURE: 三段动画 = %s / %s / %s ｜ 取消点 = %.2f / %.2f ｜ 第3段取消点 = %.2f(不可取消)" % [
		player._slash_anim, player._slash2_anim, player._slash3_anim,
		player._combo_cancel_at(0), player._combo_cancel_at(1), player._combo_cancel_at(2)])

	# ── 取景：侧前方约 40°，让"由右向左横扫"的剑轨在画面里展开（正后方看只有纵深，读不出动作）──
	var cam = get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.distance = 4.8
		cam.yaw = deg_to_rad(-40.0)
		cam.pitch = 0.34
		cam._snap_to_target()

	# ── 靶子：另造一只**被动木桩**（不追、不打、不掉到会死的血量），别用主场景那只真怪 ──
	var target = load("res://scenes/enemy/enemy.tscn").instantiate()
	main.add_child(target)
	target.aggro_range = 0.0
	target.attack_range = 0.0
	target.move_speed = 0.0
	# 把主怪临时移出 enemy 组：软锁定取"范围内最近的敌人"，留着它可能抢走朝向
	var real_enemy = get_tree().get_first_node_in_group("enemy")
	if real_enemy != null and real_enemy != target:
		real_enemy.remove_from_group("enemy")

	player.global_position = Vector3(0.0, player.global_position.y, 9.0)
	player.velocity = Vector3.ZERO
	player._face_instant(Vector3(0, 0, -1))
	player._facing_dir = Vector3(0, 0, -1)
	_place_target(target, player)
	await _wait(0.4)

	# ================= 第一幕：逐段单独播，采姿势 =================
	print("CAPTURE: ══ 第一幕：三段各自的姿势（帧号 = Engine.get_frames_drawn()）══")
	for step in range(3):
		player._attack_cooldown = 0.0
		target.health.reset()
		_place_target(target, player)
		await _wait(0.2)
		player._start_combo_step(step)                # 直接指定段号起手（跳过连击链，纯看姿势）
		print("CAPTURE: 第 %d 段 起手  %s  时长 %.3fs  判定窗 %.2f~%.2fs  伤害 %d" % [
			step + 1, player._combo_anim(step), player._combo_total(step),
			player._combo_active_start(step), player._combo_active_end(step),
			player._combo_damage(step)])
		# 按真实段号采样：切段后 _state_time 会归零，所以只能"进一段、采一段"
		var sampled: Array[float] = []
		var guard := 0
		while player.is_attacking() and guard < 4000:
			# 等这一段真的开始了（_start_combo_step 是下一物理帧才生效）
			if int(player.get_combo_step()) == step:
				for frac in SEG_SAMPLES:
					if not sampled.has(frac) and float(player._state_time) >= player._combo_total(step) * frac:
						sampled.append(frac)
						print("CAPTURE: 第 %d 段 @%2.0f%%  t=%.3f  帧=%d  动画=%s" % [
							step + 1, frac * 100.0, player._state_time,
							Engine.get_frames_drawn(), player._anim_player.current_animation])
			guard += 1
			await get_tree().physics_frame

	# ================= 第二幕：真正一整套连击（后摇取消 + 输入缓冲）=================
	print("CAPTURE: ══ 第二幕：一整套连击（在取消点之前按下 → 走输入缓冲自动接续）══")
	player._attack_cooldown = 0.0
	target.health.reset()
	_place_target(target, player)
	await _wait(0.2)
	var hp_before: int = target.health.current_hp
	player._try_start_attack()
	print("CAPTURE: 起手第 1 段  帧=%d  动画=%s" % [
		Engine.get_frames_drawn(), player._anim_player.current_animation])
	var pressed: Array[int] = []
	var last_step: int = 0
	var chain_guard := 0
	while player.is_attacking() and chain_guard < 6000:
		var st: int = int(player.get_combo_step())
		# 段号一变就报一次：这一帧就是"掐掉剩余收招、接上下一段"的那一刻
		if st != last_step:
			last_step = st
			print("CAPTURE: ★ 接上第 %d 段  帧=%d  动画=%s  缓冲已清空=%s" % [
				st + 1, Engine.get_frames_drawn(),
				player._anim_player.current_animation, not player.is_combo_queued()])
		# 在取消点之前一点点按下（这一次会被缓冲，到取消点才兑现）
		if st < 2 and not pressed.has(st) \
				and float(player._state_time) >= maxf(0.05, player._combo_cancel_at(st) - 0.10):
			pressed.append(st)
			_place_target(target, player)             # 前一段把它打退了，摆回身前
			player._try_start_attack()
			print("CAPTURE: 第 %d 段后摇里按下 → 缓冲=%s  帧=%d（还没到取消点，绝不立刻断招）" % [
				st + 1, player.is_combo_queued(), Engine.get_frames_drawn()])
		chain_guard += 1
		await get_tree().physics_frame
	print("CAPTURE: 连击结束  帧=%d  段号=%d  冷却=%.2f（=combo_finish_cd %.2f）敌人血量 %d → %d" % [
		Engine.get_frames_drawn(), player.get_combo_step(), player._attack_cooldown,
		player.combo_finish_cd, hp_before, target.health.current_hp])
	# 第 3 段不可取消：这里按一下应该**毫无反应**（连缓冲都不记）
	player._start_combo_step(2)
	await _wait_frames(3)
	player._try_start_attack()
	print("CAPTURE: 第 3 段中途按下 → 缓冲=%s（应为 false：收尾重击不可取消）"
		% player.is_combo_queued())
	await _wait_attack_over(player)
	await _wait(0.3)
	get_tree().quit(0)


# ------------------------------------------------------------------ 工具

## 把靶子摆到玩家身前（跟随玩家当前朝向，而不是死板的 -Z）。
func _place_target(target, player) -> void:
	var fwd: Vector3 = player._get_facing_flat()
	target.global_position = player.global_position + fwd * 1.5
	target.velocity = Vector3.ZERO


## 等当前这段攻击演完（离开 ATTACK），或超时返回。
func _wait_attack_over(player) -> void:
	var guard := 0
	while player.is_attacking() and guard < 4000:
		await get_tree().physics_frame
		guard += 1


## 按**真实时间**等待（不受顿帧/子弹时间影响）—— 抓帧时的"停一下"用它才准。
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## 等 N 个渲染帧（用来让"刚好按下"的那一下被引擎读进去）。
func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
