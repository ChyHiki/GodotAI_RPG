extends SceneTree
## 验证敌人模型资产：骨骼/挂点/缩放/动画名/武器对齐，一次全查。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       --script res://tools/verify_enemy_model.gd
##
## 断言不通过会打印 ✗ 并以 exit=1 退出，可以直接用在 CI / 提交前自检。
##
## ⚠️ 帧偏移约定（玩家模型 player_knight.glb 同样如此，属管线固有行为，不是缺陷）
##   1) Blender 的 glTF 导出器把关键帧时间写成 frame/fps；而 Action 的帧范围是 1..N，
##      于是源动画的时间轴是 0.0417 .. N/24，整条相对原点平移了 1 帧。
##   2) Godot 导入时把它整体平移到从 t=0 开始，并重采样到 30 fps 网格；
##      但 Animation.length 保留的是【源末帧的绝对时刻】N/24。
##   结论：   Godot length = 设计内容时长 + 1/24 s
##   例：Idle 帧 1..49（48 帧 = 2.000s）→ Godot length = 49/24 = 2.0417s。
##   所以不要拿 length 直接和设计时长比 —— 本脚本断言的是 length − 1/24 = 设计时长，
##   并额外确认首帧已平移到 0、末帧时刻等于 length（即尾部没有一段"空播"）。

const MODEL_PATH := "res://assets/enemies/brute_01/brute_rigged.glb"
const WEAPON_PATH := "res://assets/enemies/brute_01/club_01.glb"
const SOCKET := "weapon.R"
## 与 enemy.gd 的 model_target_height 保持一致
const TARGET_HEIGHT := 2.66
## 与 enemy.gd 的 ENEMY_WEAPON_ALIGN_LOCAL 保持一致（-Z 扳到挂点 +Y）
const ALIGN_LOCAL := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)
## 期望的动画名（enemy.gd 按关键字识别，这里核对实际导入名）
const EXPECT_ANIMS := ["Idle", "Walk", "AttackWindup", "Attack", "Hit"]

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _init() -> void:
	print("=== 敌人模型资产验证 ===")
	var model_scene := load(MODEL_PATH) as PackedScene
	var weapon_scene := load(WEAPON_PATH) as PackedScene
	if model_scene == null or weapon_scene == null:
		push_error("资产未导入：%s / %s" % [MODEL_PATH, WEAPON_PATH])
		quit(1)
		return

	var model := model_scene.instantiate() as Node3D

	# ---------- 1. 骨骼 ----------
	print("\n[1] 骨骼")
	var skel := _find_skeleton(model)
	if skel == null:
		push_error("模型里没有 Skeleton3D")
		quit(1)
		return
	_check(skel.get_bone_count() == 21, "骨骼数 = 21", "实际 %d" % skel.get_bone_count())

	# ---------- 2. 挂点 ----------
	print("\n[2] 武器挂点")
	var bone := skel.find_bone(SOCKET)
	_check(bone >= 0, "存在挂点骨骼 '%s'" % SOCKET, "索引 %d" % bone)
	if bone < 0:
		quit(1)
		return

	# ---------- 3. 缩放与脚底对齐（复刻 enemy.gd 的 _setup_model 逻辑）----------
	print("\n[3] 缩放与脚底对齐")
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for mi in _all_meshes(model):
		var aabb: AABB = mi.get_aabb()
		mn = mn.min(aabb.position)
		mx = mx.max(aabb.position + aabb.size)
	var raw_h := mx.y - mn.y
	var s := TARGET_HEIGHT / raw_h
	model.scale = Vector3.ONE * s
	model.position = Vector3(-(mn.x + mx.x) * 0.5 * s, -mn.y * s, -(mn.z + mx.z) * 0.5 * s)
	print("  原始总高 = %.4f m（脚底 y=%.4f, 角尖 y=%.4f）" % [raw_h, mn.y, mx.y])
	print("  缩放系数 = %.4f → 目标总高 %.2f m" % [s, TARGET_HEIGHT])
	print("  缩放后实际总高 = %.4f m" % (raw_h * s))
	_check(absf(raw_h * s - TARGET_HEIGHT) < 0.01, "缩放后总高 = 目标值", "%.4f" % (raw_h * s))
	_check(absf(mn.y) < 0.001, "模型脚底在 y=0 平面（可被 -mn.y*s 精确对齐）", "min.y=%.4f" % mn.y)

	# ---------- 4. 动画 ----------
	print("\n[4] 动画")
	var anim := _find_animation_player(model)
	if anim == null:
		_fail += 1
		print("  ✗ 没有 AnimationPlayer")
	else:
		var names := anim.get_animation_list()
		print("  导入的动画名 = %s" % str(names))
		for a in EXPECT_ANIMS:
			_check(names.has(a), "存在动画 %s" % a)
		# 时长（enemy.gd 的状态机参数要对得上）
		# 设计内容时长 = Blender 里 Action 帧区间的跨度（24 fps）
		var design_len := {"Idle": 2.000, "Walk": 1.000, "AttackWindup": 0.500,
			"Attack": 0.250, "Hit": 0.4167}
		# 见文件头"帧偏移约定"：Godot length = 源末帧绝对时刻 = 内容时长 + 1/24
		var frame_off := 1.0 / 24.0
		for a in EXPECT_ANIMS:
			if not names.has(a):
				continue
			var a_res := anim.get_animation(a)
			var want_len: float = design_len[a] + frame_off
			_check(absf(a_res.length - want_len) < 0.005,
				"%s length = %.4fs（内容 %.3fs + 1/24 帧偏移）" % [a, want_len, design_len[a]],
				"实际 %.4fs" % a_res.length)
			# 取所有轨道里最早 / 最晚的关键帧时刻
			var first_t := INF
			var last_t := -INF
			var min_gap := INF
			for ti in a_res.get_track_count():
				var kc := a_res.track_get_key_count(ti)
				if kc == 0:
					continue
				first_t = minf(first_t, a_res.track_get_key_time(ti, 0))
				last_t = maxf(last_t, a_res.track_get_key_time(ti, kc - 1))
				if kc >= 2:
					min_gap = minf(min_gap, a_res.track_get_key_time(ti, 1) - a_res.track_get_key_time(ti, 0))
			_check(absf(first_t) < 0.001, "%s 首帧已平移到 t=0" % a, "t=%.4f" % first_t)
			_check(absf(last_t - a_res.length) < 0.005,
				"%s 末帧时刻 = length（尾部没有空播段）" % a, "%.4fs vs %.4fs" % [last_t, a_res.length])
			if min_gap < INF:
				print("  · %s 最小关键帧间隔 = %.4fs（导入按 animation/fps=30 重采样，"
					% [a, min_gap]
					+ "再对恒定段做关键帧精简，所以部分轨道间隔更大）")
		# 循环标记（enemy.gd 会给 Idle/Walk 打开 LOOP）
		# 注：源动画首尾帧姿势完全一致（闭合循环），所以即使 length 多了 1/24，
		#     wrap 回 0 时姿势仍连续，循环本身无缝，只是周期比标称长 1 帧。
		for a in ["Idle", "Walk"]:
			if names.has(a):
				print("  · %s 导入时 loop_mode = %d（enemy.gd 的 _set_loop 会置为 LOOP_LINEAR=1）"
					% [a, anim.get_animation(a).loop_mode])

	# ---------- 5. 武器对齐 ----------
	print("\n[5] 武器对齐（与 enemy.gd 的 _attach_weapon 一致）")
	var socket := BoneAttachment3D.new()
	socket.name = "WeaponSocket"
	skel.add_child(socket)
	socket.bone_name = SOCKET
	var weapon := weapon_scene.instantiate() as Node3D
	weapon.transform = ALIGN_LOCAL
	socket.add_child(weapon)

	root.add_child(model)
	await process_frame
	await process_frame

	var palm := skel.global_transform * skel.get_bone_global_pose(bone).origin
	var grip := weapon.global_position
	var off := grip.distance_to(palm)
	print("  握柄原点(全局) = %s" % str(grip))
	print("  手心位置(全局) = %s" % str(palm))
	_check(off < 0.05, "握柄↔手心 偏差 < 0.05 m", "实际 %.4f m" % off)

	# 大棒槌头方向：资产里槌头沿局部 -Z
	var head_dir := (weapon.global_transform.basis * Vector3(0, 0, -1)).normalized()
	var body_fwd := (model.global_transform.basis * Vector3(0, 0, -1)).normalized()
	var ang_fwd := rad_to_deg(head_dir.angle_to(body_fwd))
	var down := Vector3(0, -1, 0)
	var ang_down := rad_to_deg(head_dir.angle_to(down))
	print("  槌头方向(世界) = (%.3f, %.3f, %.3f)" % [head_dir.x, head_dir.y, head_dir.z])
	print("  与身前夹角 = %.1f°   与正下方夹角 = %.1f°" % [ang_fwd, ang_down])
	_check(ang_fwd > 55.0 and ang_fwd < 80.0, "大棒垂在身前下方（与身前 55~80°）", "%.1f°" % ang_fwd)
	_check(ang_down > 10.0 and ang_down < 35.0, "大棒接近竖直下垂（与正下方 10~35°）", "%.1f°" % ang_down)

	var wmn := Vector3.INF
	var wmx := -Vector3.INF
	for mi in _all_meshes(weapon):
		var aabb: AABB = mi.get_aabb()
		wmn = wmn.min(aabb.position)
		wmx = wmx.max(aabb.position + aabb.size)
	print("  武器包围盒(局部) = %.3f × %.3f × %.3f m" % [wmx.x - wmn.x, wmx.y - wmn.y, wmx.z - wmn.z])

	# ---------- 结论 ----------
	print("")
	if _fail == 0:
		print("结论：全部通过 ✓")
		quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		quit(1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_all_meshes(child))
	return out
