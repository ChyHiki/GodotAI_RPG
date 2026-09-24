extends Node
## ============================================================
## 开发辅助：抓"处决电影化特写分镜"的真实成片帧
## ============================================================
## 【为什么必须真跑一遍抓帧】这次改的是**纯观感**——运镜角度、切镜时机、遮幅比例。
##   自动化断言只能证明"骨架正确"（fov 变了、相机 driven 了、遮幅高度 > 0），
##   **证明不了"好不好看"**：分镜角度不对 / 切点太早太晚 / 遮幅比例不对，测试全绿画面依然难看。
##   所以本脚本加载**真实主场景**、**真的触发一次处决**，让**分镜导演自己驱动相机**，
##   把玩家实际会看到的那一路镜头逐帧落盘成 PNG 序列 —— 抓的就是"玩家眼里那个特写"，
##   而不是另摆一个旁视角。
##
## 【用法】⚠ **不要加 --headless**（headless 用空渲染驱动出不来图；见 combo_capture.gd / jump_capture.gd 同注）：
##   mkdir -p .tmp_cine
##   Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 \
##     --write-movie .tmp_cine/frame.png res://tools/anim_capture/execute_cine_capture.tscn
##   ★ --write-movie 的输出目录**必须先建好**（Godot 不会 mkdir，缺失时静默不出图）
##   ★ 抓帧很慢（逐帧渲染，几百帧要几十秒到几分钟）→ 用后台任务跑，别在前台等
##   ★ PNG 张数 ≠ Godot 结尾自报的引擎帧数；**以落盘文件为准**（自己数 .tmp_cine/*.png）
##
## 【为什么要让脚本自己报帧号】--write-movie 每渲染一帧写 frame%08d.png，
##   序号 == Engine.get_frames_drawn()。处决带**慢动作**（time_scale 掉到 0.35 再回升），
##   同一段动作会被"摊开"成比常速更多的帧 —— 任何"秒数 × 60"的心算都会错位。
##   所以在每个关键时刻直接打印帧号，拿号去取图即可。
##
## 【看门狗盯"帧号是否仍在推进"，不盯"总耗时"】见 combo_capture.gd 的长注释：
##   逐帧渲染耗时 ∝ 帧数 × 单帧耗时，与机器快慢强相关；按总耗时设限会误杀/漏杀。
##   真正代表"卡死"的信号是 Engine.get_frames_drawn() 不再增长。
## ============================================================

## 看门狗：帧号停滞超过这么久（真实时间）→ 判定卡死，退出。
const STALL_MS := 30000
## 兜底总上限（真实时间）：极宽松，正常一次抓帧远用不到。
const HARD_LIMIT_MS := 600000

## 关键帧判定用的 fov 门限：第 1 刀 fov=62、第 2 刀 fov=50、第 3 刀 fov=58。
##   < 54 即判定"已硬切到近景刀"；> 55（且已切过近景）即判定"已切到拉回收招刀"。
##   （54 落在 62 与 50 之间；55 落在 50 与 58 之间，且硬切当帧 fov=50 > 55 为假 → 不会在切点误报"拉回"。）
const FOV_NEAR_CUT := 54.0
const FOV_PULL_BACK := 55.0
## 慢动作最低倍率附近的门限（cinematic_slowmo_scale = 0.35）。
const SLOWMO_PLATEAU := 0.351

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
	if drawn != _last_frames:                 # 有新帧 → 刷新"最后一次推进"的时刻
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
	var director = get_tree().get_first_node_in_group("cinematic")
	var cam = get_tree().get_first_node_in_group("camera")
	var cam3d: Camera3D = (cam.get("_cam") as Camera3D) if cam != null else null
	if director == null or cam == null or cam3d == null:
		print("CAPTURE: 找不到分镜导演或相机(director=%s cam=%s cam3d=%s)" % [director, cam, cam3d])
		get_tree().quit(1)
		return

	# ── 靶子：另造一只**被动木桩**（照抄 m1_autotest 的处决小节）──
	#    不追、不打、不移动；否则它会冲上来搅乱取景与镜头。
	var target = load("res://scenes/enemy/enemy.tscn").instantiate()
	main.add_child(target)
	target.aggro_range = 0.0
	target.attack_range = 0.0
	target.move_speed = 0.0
	# 主场景那只真怪移出 enemy 组并赶远：它在仇恨半径内会追过来乱入
	var real_enemy = get_tree().get_first_node_in_group("enemy")
	if real_enemy != null and real_enemy != target:
		real_enemy.global_position = player.global_position + Vector3(80, 0, 0)
		real_enemy.velocity = Vector3.ZERO
		real_enemy.remove_from_group("enemy")

	# ── 摆位：玩家站定朝 -Z，靶子放正前方 ──
	player.global_position = Vector3(0.0, player.global_position.y, 9.0)
	player.velocity = Vector3.ZERO
	player._face_instant(Vector3(0, 0, -1))
	player._facing_dir = Vector3(0, 0, -1)
	target.global_position = player.global_position + Vector3(0, 0, -1.3)
	target.velocity = Vector3.ZERO
	# 让追尾镜头先摆到玩家后方（处决前是正常的第三人称视角）
	cam.set_target(player)
	cam._snap_to_target()
	await get_tree().create_timer(0.4).timeout

	# ── 把靶子顶进失衡(BROKEN)：一次完美格挡直接顶满（照抄 m1_autotest）──
	target.poise.reset()
	target.parry_poise_percent = 100.0
	target.deflect(0.2, target.global_position + Vector3(0, 0, 1.0))
	target.health.reset()
	player.health.reset()
	player.health.invincible = false
	player._attack_cooldown = 0.0
	await get_tree().create_timer(0.2).timeout

	print("CAPTURE: 分镜表 = %s" % [CinematicDirector.EXECUTE_SHOTS])
	print("CAPTURE: ══ 处决前（站立，导演未接管）帧=%d  状态=%d  fov=%.1f  driven=%s  active=%s  相机距玩家=%.1fm ══" % [
		Engine.get_frames_drawn(), player.state, cam3d.fov,
		cam.driven, director.is_active(), cam.distance])

	# ★ prev_active 必须在**触发之前**取初始值：play() 会让 is_active() 立刻变 true，
	#   若在触发之后再取，就永远看不到 false→true 的那次跳变，"特写接管"帧会漏报。
	# ⚠️ 这里必须显式标注 `: bool` —— director 是无类型句柄，其方法返回 Variant，
	#    用 `:=` 推断会报 "Cannot infer the type of ... because the value doesn't have a set type"。
	var prev_active: bool = director.is_active()

	# ── 真的触发一次处决（自动贴近 + 专属 Execute 动画 + 分镜导演接管相机）──
	player._try_start_execute(target)
	print("CAPTURE: ★ 处决触发 帧=%d  状态=%d（7=EXECUTE）导演 active=%s" % [
		Engine.get_frames_drawn(), player.state, director.is_active()])

	var printed_in := false
	var printed_cut := false
	var printed_pullback := false
	var printed_slow_plateau := false
	var printed_slow_rise := false
	var released_at_frame := -1
	var guard := 0

	while guard < 9000:
		var ts := Engine.time_scale
		var frm := Engine.get_frames_drawn()

		# ① 特写接管
		if not prev_active and director.is_active():
			prev_active = true
			print("CAPTURE: ★ 特写接管（导演 is_active→true）帧=%d  driven=%s  fov=%.1f" % [
				frm, cam.driven, cam3d.fov])

		# ② 遮幅滑入到位（bar_k 到 1.0）
		if not printed_in and float(director.get("_bar_k")) >= 0.99:
			printed_in = true
			print("CAPTURE: 遮幅滑入到位（bar_k=%.2f）帧=%d" % [
				float(director.get("_bar_k")), frm])

		# ③ ★★ 命中切点：硬切近景（fov 62 → 50，第 2 刀定稿值）
		if not printed_cut and cam3d.fov < FOV_NEAR_CUT:
			printed_cut = true
			print("CAPTURE: ★★ 命中切点·硬切近景（fov 62→%.1f）帧=%d  time_scale=%.2f" % [
				cam3d.fov, frm, ts])

		# ④ 拉回收招刀（fov 由 50 回到 58）
		if printed_cut and not printed_pullback and cam3d.fov > FOV_PULL_BACK:
			printed_pullback = true
			print("CAPTURE: 切到拉回收招刀（fov→%.1f）帧=%d" % [cam3d.fov, frm])

		# ⑤ 慢动作进入最深（落到最低倍率那一刻）
		if not printed_slow_plateau and ts <= SLOWMO_PLATEAU:
			printed_slow_plateau = true
			print("CAPTURE: ★ 慢动作进入最深（time_scale=%.2f）帧=%d" % [ts, frm])

		# ⑥ 慢动作开始回升（离谷底）
		if printed_slow_plateau and not printed_slow_rise and ts > SLOWMO_PLATEAU + 0.001 and ts < 0.999:
			printed_slow_rise = true
			print("CAPTURE: 慢动作开始回升（time_scale=%.3f）帧=%d" % [ts, frm])

		# ⑦ ★ 相机交还（导演 is_active→false；遮幅此刻开始滑出、追尾从当前位姿续上）
		if prev_active and not director.is_active():
			prev_active = false
			released_at_frame = frm
			print("CAPTURE: ★ 相机交还（导演 is_active→false，遮幅开始滑出）帧=%d  driven=%s  fov=%.1f  状态=%d" % [
				frm, cam.driven, cam3d.fov, player.state])

		guard += 1
		await get_tree().process_frame

		# 交还后再抓约 1.1 游戏秒（≈66 帧 @60fps），把"追尾回位"演完
		if released_at_frame >= 0 and (Engine.get_frames_drawn() - released_at_frame) >= 66:
			break

	if released_at_frame < 0:
		print("CAPTURE: ⚠ 未观测到'相机交还'（导演可能没接管/没启动）")

	print("CAPTURE: ══ 结束（回到追尾）帧=%d  driven=%s  active=%s  fov=%.1f  状态=%d ══" % [
		Engine.get_frames_drawn(), cam.driven, director.is_active(), cam3d.fov, player.state])
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)
