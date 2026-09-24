extends Node
## ============================================================
## 开发辅助：处决"命中近景"取景候选 sweep（临时对比工具）
## ============================================================
## 【为什么要有它 / 背景】
##   处决第 2 刀（"命中近景"）在成片里**完全不可读**：画面被大块纯色多边形糊满
##   （玩家蓝、敌人橙、命中黄闪），看不到剑、看不到斩击、看不到敌人反应 ——
##   而这一刀占了整段约 30%，偏偏是最重要的"命中"镜头。
##   自动断言永远抓不到这种"骨架对、画面丑"的问题（fov 变了、相机 driven 了、
##   遮幅 > 0 —— 全绿），所以必须靠**出片目视**。
##
## 【为什么先 sweep 再改参数】重抓全片要 200+ 帧、好几分钟；盲改一组参数很可能再来一轮。
##   这里把"6 组候选取景"在同一现场、同一姿势下各渲十几帧，一次出片就能横向对比，
##   选定后再回去改 EXECUTE_SHOTS、重抓全片。
##
## 【现场还原】加载**真实主场景**，玩家站在敌人身前约 1.5m、双方面对面；
##   把玩家**摆到"命中那一拍"的姿势**（播 Execute 动画 → seek 到命中点 → 暂停），
##   然后**冻结双方**（停 _process/_physics_process）—— 这样 6 个候选之间
##   除了"机位"以外**一切完全相同**，对比才干净。
##   ⚠ 刻意**不跑**处决状态机：也就不会有 HitFlash 黄闪糊屏（那正是"糊"的元凶之一），
##     于是这一步测的是**纯几何构图**。改完参数后的全片重抓会再带上黄闪，届时另做判断。
##
## 【取景公式与导演完全一致】_compute_pose() 是 cinematic_director.gd::_compute_shot_pose()
##   的逐行照抄（axis=玩家→敌人水平轴；back=-axis；绕 Y 旋 azimuth；绕 dir_h×UP 抬 elev；
##   cam=pivot+dir×dist；look=pivot）。**务必保持一致** —— 否则 sweep 里好看的机位
##   搬回分镜表就不一样了。
##
## 【用法】⚠ **不要加 --headless**（headless 用空渲染驱动出不来图；见 combo_capture.gd 同注）：
##   mkdir -p .tmp_sweep
##   Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --resolution 800x450 \
##     --write-movie .tmp_sweep/frame.png res://tools/anim_capture/cine_frame_sweep.tscn
##   ★ --write-movie 的输出目录**必须先建好**（Godot 不会 mkdir，缺失时静默不出图）
##
## 【帧号】--write-movie 每帧写 frame%08d.png，序号 == Engine.get_frames_drawn()。
##   每个候选渲 FRAMES_PER_CAND 帧、**静止不变**，所以该窗口里任意一帧都代表该候选；
##   脚本打印每个候选窗口的**末帧号**作代表帧，拿号取图即可（见日志 rep_frame=）。
## ============================================================

## 看门狗：帧号停滞超过这么久（真实时间）→ 判定卡死，退出。
const STALL_MS := 30000
## 兜底总上限（真实时间）：极宽松，正常一次 sweep 远用不到。
const HARD_LIMIT_MS := 600000

## 每个候选渲染的帧数。候选机位是静止的 → 窗口内所有帧相同，任一帧可作代表。
const FRAMES_PER_CAND := 12

## ★★ 六个候选取景（A = 现状对照）。字段与 EXECUTE_SHOTS 完全同义：
##   pivot: player/enemy/mid ｜ azimuth: 度(0=玩家背后) ｜ elev: 度(正=俯) ｜ dist: 米 ｜ fov: 度
const CANDIDATES: Array = [
	{"id": "A", "pivot": "enemy", "azimuth": 30.0, "elev":  -7.0, "dist": 1.9, "fov": 36.0},
	{"id": "B", "pivot": "enemy", "azimuth": 30.0, "elev":  -7.0, "dist": 3.2, "fov": 46.0},
	{"id": "C", "pivot": "mid",   "azimuth": 78.0, "elev":   6.0, "dist": 3.0, "fov": 44.0},
	{"id": "D", "pivot": "mid",   "azimuth": 82.0, "elev":  10.0, "dist": 2.4, "fov": 40.0},
	{"id": "E", "pivot": "enemy", "azimuth": 18.0, "elev":   8.0, "dist": 3.6, "fov": 50.0},
	{"id": "F", "pivot": "enemy", "azimuth": 70.0, "elev": -14.0, "dist": 2.8, "fov": 44.0},
]

var _last_frames: int = -1
var _last_progress_ms: int = 0
var _started_ms: int = 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _started_ms > 0 and now - _started_ms > HARD_LIMIT_MS:
		print("CAPTURE: WARN hard-limit %d ms hit, force quit (drew %d frames)"
			% [HARD_LIMIT_MS, Engine.get_frames_drawn()])
		get_tree().quit(0)
		return
	var drawn := Engine.get_frames_drawn()
	if drawn != _last_frames:                 # 有新帧 → 刷新"最后一次推进"的时刻
		_last_frames = drawn
		_last_progress_ms = now
	elif _last_progress_ms > 0 and now - _last_progress_ms > STALL_MS:
		print("CAPTURE: WARN frame counter stalled %d ms (last=%d), force quit"
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
	var director = get_tree().get_first_node_in_group("cinematic")
	var cam = get_tree().get_first_node_in_group("camera")
	var cam3d: Camera3D = (cam.get("_cam") as Camera3D) if cam != null else null
	if player == null or cam == null or cam3d == null:
		print("CAPTURE: FATAL missing player/cam (player=%s cam=%s cam3d=%s)"
			% [player, cam, cam3d])
		get_tree().quit(1)
		return
	if hud != null:
		hud.show_message(" ", 0.01)                   # 清掉开场大字，别盖住画面中央

	# ── 靶子：另造一只**被动木桩**（不追、不打、不移动）──
	var target = load("res://scenes/enemy/enemy.tscn").instantiate()
	main.add_child(target)
	target.aggro_range = 0.0
	target.attack_range = 0.0
	target.move_speed = 0.0
	# 主场景那只真怪移出 enemy 组并赶远：它在仇恨半径内会追过来乱入
	var real_enemy = get_tree().get_first_node_in_group("enemy")
	if real_enemy != null and real_enemy != target:
		real_enemy.global_position = player.global_position + Vector3(200, 0, 0)
		real_enemy.velocity = Vector3.ZERO
		real_enemy.remove_from_group("enemy")

	# ── ★ 先冻结双方，再摆位 ──
	#   为什么必须先冻结：玩家/敌人都是 CharacterBody3D，每物理帧跑 move_and_slide()。
	#   处决时双方贴得很近（约 1.5m），两个碰撞胶囊会**互相重叠** → 分离求解把玩家推走：
	#   实测摆了 1.5m、跑 0.3s 后水平间距被撑到 **2.16m** 且朝向轴也歪了。
	#   先停掉 _process/_physics_process，move_and_slide 不再执行，摆好的 1.5m 现场
	#   **一个字节都不会动**，6 个候选才真正"除机位以外完全相同"，对比才干净。
	player.set_process(false)
	player.set_physics_process(false)
	target.set_process(false)
	target.set_physics_process(false)

	# ── 摆位：玩家站定朝 -Z，靶子放正前方 1.5m，且靶子转身面对玩家 ──
	var gy: float = player.global_position.y            # 落地后的地面高度
	player.global_position = Vector3(0.0, gy, 0.0)
	player.velocity = Vector3.ZERO
	player._face_instant(Vector3(0, 0, -1))
	player._facing_dir = Vector3(0, 0, -1)
	# 冻结后没人再跑 _apply_land_squash，落地压缩若残留会把模型压扁 → 显式复位。
	if player.get("_pivot") != null:
		player._pivot.scale = Vector3.ONE
	target.global_position = player.global_position + Vector3(0, 0, -1.5)
	target.velocity = Vector3.ZERO
	# 与玩家同一套朝向约定（forward = VisualPivot 的 -Z）：让敌人转头"看着玩家"
	if target.has_method("_face_instant_dir"):
		target._face_instant_dir(player.global_position - target.global_position)

	# ── 把玩家摆到"命中那一拍"的姿势 ──
	var pose_desc: String = _apply_player_hit_pose(player)

	# ── 遮幅黑边：照原样显示（复用主场景里那个导演自建的 overlay，比例/层级与产品一致）──
	if director != null:
		if director.get("_bar_top") != null:
			director._bar_top.visible = true
		if director.get("_bar_bottom") != null:
			director._bar_bottom.visible = true
		if director.has_method("_set_bar_k"):
			director._set_bar_k(1.0)

	# ── 两个锚点（胸口），与导演 PIVOT_HEIGHT 一致 ──
	var a_chest: Vector3 = player.global_position \
		+ Vector3.UP * float(CinematicDirector.PIVOT_HEIGHT["player"])
	var b_chest: Vector3 = target.global_position \
		+ Vector3.UP * float(CinematicDirector.PIVOT_HEIGHT["enemy"])

	print("CAPTURE: hit-pose = %s" % pose_desc)
	print("CAPTURE: player_chest=(%.2f,%.2f,%.2f) enemy_chest=(%.2f,%.2f,%.2f) horiz_gap=%.2fm"
		% [a_chest.x, a_chest.y, a_chest.z, b_chest.x, b_chest.y, b_chest.z,
			Vector2(a_chest.x - b_chest.x, a_chest.z - b_chest.z).length()])

	var reps: Array[int] = []
	var labels: Array[String] = []
	for ci in range(CANDIDATES.size()):
		var shot: Dictionary = CANDIDATES[ci]
		var pose: Dictionary = _compute_pose(shot, a_chest, b_chest)
		cam.apply_driven_pose(pose["pos"], pose["look"], float(pose["fov"]))
		# ★ 记录"该候选实际占用的帧窗口"。--write-movie 写 PNG 与 Engine.get_frames_drawn()
		#   之间会有一帧级的偏差（实测内容窗口 ≈ [施加帧, 施加帧+N-1]），窗口正中一定属于本候选，
		#   取正中当代表帧可躲开边界 off-by-one（不然会取到下一候选的第一帧）。
		var f_start: int = Engine.get_frames_drawn()
		var f_end: int = f_start
		for _f in range(FRAMES_PER_CAND):
			await get_tree().process_frame
			f_end = Engine.get_frames_drawn()
		var rep: int = (f_start + f_end) / 2
		var cp: Vector3 = pose["pos"]
		var ap: Vector3 = cam.global_position
		print("CAPTURE: CAND %s pivot=%s az=%.0f elev=%.0f dist=%.1f fov=%.0f  rep_frame=%d window=[%d,%d]  want_cam=(%.2f,%.2f,%.2f)  actual_cam=(%.2f,%.2f,%.2f) driven=%s act_fov=%.1f"
			% [shot["id"], shot["pivot"], shot["azimuth"], shot["elev"],
				shot["dist"], shot["fov"], rep, f_start, f_end, cp.x, cp.y, cp.z,
				ap.x, ap.y, ap.z, cam.driven, cam3d.fov])
		reps.append(rep)
		labels.append("%s  fov%d d%.1f %.0f/%.0f" % [
			shot["id"], int(shot["fov"]), float(shot["dist"]),
			float(shot["azimuth"]), float(shot["elev"])])

	print("CAPTURE: rep_frames = %s" % [reps])
	print("CAPTURE: labels = %s" % [labels])
	print("CAPTURE: === END ===")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)


# ==================================================================
# 取景公式（逐行照抄 cinematic_director.gd::_compute_shot_pose，务必保持一致）
# ==================================================================

## 计算某候选的相机位姿（相对取景）。返回 {"pos","look","fov"}。
func _compute_pose(shot: Dictionary, a_chest: Vector3, b_chest: Vector3) -> Dictionary:
	# 基准轴：玩家 → 敌人（水平）。相机方位角以它为 0 度基准。
	var axis := b_chest - a_chest
	axis.y = 0.0
	if axis.length() > 0.01:
		axis = axis.normalized()
	else:
		axis = Vector3(0.0, 0.0, -1.0)
	var back := -axis                                  # azimuth = 0 时相机在这个方向（玩家背后）

	# 注视点（pivot）
	var pivot: Vector3
	match String(shot["pivot"]):
		"player":
			pivot = a_chest
		"enemy":
			pivot = b_chest
		_:
			pivot = (a_chest + b_chest) * 0.5          # "mid"

	# 水平方向绕 Y 旋转 azimuth（正角 = 往角色右侧绕）
	var dir_h := back.rotated(Vector3.UP, deg_to_rad(float(shot["azimuth"])))
	# 再绕"水平且垂直于它"的轴抬起 elev（正角 = 相机更高 = 俯视，与分镜表语义一致）
	var elev_axis := dir_h.cross(Vector3.UP)
	elev_axis = elev_axis.normalized() if elev_axis.length() > 0.001 else Vector3.RIGHT
	var dir := dir_h.rotated(elev_axis, deg_to_rad(float(shot["elev"])))

	var pos := pivot + dir * float(shot["dist"])
	return {"pos": pos, "look": pivot, "fov": float(shot["fov"])}


# ==================================================================
# 姿势：把玩家摆到"命中那一拍"
# ==================================================================

## 播 Execute 动画 → seek 到"命中点"（execute_hit_time 相对整段的进度换算成动画秒）→ 暂停，
## 让剑停在最像"刺中"的那一帧。返回一段可读的描述（失败也不中断 sweep）。
## ★ 动画名从 player._execute_anim 取（空则退化 _slash_anim），**不硬编码**。
func _apply_player_hit_pose(player) -> String:
	var anim: AnimationPlayer = player._anim_player
	if anim == null:
		return "(no AnimationPlayer -> pose not applied)"
	var clip: String = String(player._execute_anim)
	if clip == "":
		clip = String(player._slash_anim)
	if clip == "":
		return "(no Execute/Slash clip -> pose not applied)"
	var a: Animation = anim.get_animation(clip)
	if a == null:
		return "(missing anim resource: %s)" % clip
	# 命中点在"整段时长"里的比例 = execute_hit_time / execute_time；换到动画本地时间 = 比例 × 动画长度。
	var frac: float = float(player.execute_hit_time) / maxf(0.0001, float(player.execute_time))
	var t: float = frac * a.length
	anim.speed_scale = 1.0
	anim.stop()
	anim.play(clip, -1.0, 1.0)
	anim.seek(t, true)                                 # 摆到命中那一拍
	anim.pause()                                       # 冻住，别继续往下演
	return "%s (len=%.3fs, seek=%.3fs = hit %.2f)" % [clip, a.length, t, frac]
