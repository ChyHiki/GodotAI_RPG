extends SceneTree
## ============================================================
## 验证狼敌人资产与场景接线：骨骼 / 动画名与时长 / 缩放 / 无武器 / export 数值。
## ============================================================
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       --script res://tools/verify_enemy_wolf.gd
##
## 断言不通过会打印 ✗ 并以 exit=1 退出，可直接用在 CI / 提交前自检。
##
## ⚠️ 帧偏移约定（与 verify_enemy_model.gd 完全一致，属管线固有行为，不是缺陷）
##   Blender glTF 导出器把关键帧时间写成 frame/fps，Action 帧区间是 1..N →
##   源时间轴是 0.0417 .. N/24（整条相对原点平移了一帧）。Godot 导入时整体平移到 t=0，
##   但 Animation.length 保留【源末帧绝对时刻】N/24。
##   结论： Godot length = 设计内容时长 + 1/24 s。故本脚本断言 length − 1/24 = 设计时长，
##   并额外确认首帧已平移到 0、末帧时刻 = length（尾部没有"空播"）。
##
## 【与 verify_enemy_model.gd 的区别】狼**没有武器**，故删掉了守卫版里的
##   [2] 武器挂点 与 [5] 武器对齐 两节（照抄会让狼在"没有 weapon.R"上假失败）；
##   改为断言 enemy_weapon_path=="" 时**静默跳过**、不生成 WeaponSocket。
##   ⚠️ 本脚本只验证狼；守卫版 verify_enemy_model.gd 已在 T04 同步升级为 6 段（含 Death）。
## ============================================================

const MODEL_PATH := "res://assets/enemies/wolf_01/wolf_rigged.glb"
const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
## 与 enemy.gd 的 model_target_height 一致（狼 1.20m）
const TARGET_HEIGHT := 1.20
## 期望的动画名（enemy.gd 按关键字识别，这里核对实际导入名 + 精确名字集）
const EXPECT_ANIMS := ["Idle", "Walk", "AttackWindup", "Attack", "Hit", "Death"]
## 狼 6 段动画的设计内容时长（Blender 里 Action 帧区间的跨度，24 fps）
const DESIGN_LEN := {
	"Idle": 2.000, "Walk": 1.000, "AttackWindup": 0.500,
	"Attack": 0.250, "Hit": 0.4167, "Death": 1.000,
}

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


## 把可能为 null 的数值安全转成 float（断言失败时给出哨兵值而不是崩掉）。
func _f(v: Variant) -> float:
	return float(v) if v != null else -99999.0


## 【为什么用 _initialize 而不是 _init】_init 在对象构造期执行，此时 autoload 尚未注册，
## 加载引用了 autoload（EventBus）的 enemy.gd 会编译失败；_initialize 在引擎主循环启动时执行，
## autoload 已就绪。同时这里还要 await 物理帧，必须等循环跑起来。
func _initialize() -> void:
	print("=== 狼敌人资产验证 ===")
	var model_scene := load(MODEL_PATH) as PackedScene
	if model_scene == null:
		push_error("资产未导入：%s" % MODEL_PATH)
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
	_check(skel.get_bone_count() == 22, "骨骼数 = 22", "实际 %d" % skel.get_bone_count())
	# 徒手物种：骨架里不该有 weapon.R（这正是 enemy.gd 需要"空串早退"的原因）
	_check(skel.find_bone("weapon.R") < 0, "骨架里没有 weapon.R（狼是徒手物种）")

	# ---------- 2. 缩放与脚底对齐（复刻 enemy.gd 的 _setup_model 逻辑）----------
	print("\n[2] 缩放与脚底对齐")
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for info in _collect_meshes(model, Transform3D.IDENTITY, []):
		var mi: MeshInstance3D = info["node"]
		var xform: Transform3D = info["xform"]
		for corner in _aabb_corners(mi.get_aabb()):
			var p: Vector3 = xform * corner
			mn = mn.min(p)
			mx = mx.max(p)
	var raw_h := mx.y - mn.y
	var s := TARGET_HEIGHT / raw_h
	print("  原始总高 = %.4f m（脚底 y=%.4f, 顶 y=%.4f）" % [raw_h, mn.y, mx.y])
	print("  缩放系数 = %.4f → 目标总高 %.2f m" % [s, TARGET_HEIGHT])
	print("  缩放后实际总高 = %.4f m" % (raw_h * s))
	_check(absf(raw_h * s - TARGET_HEIGHT) < 0.01, "缩放后总高 = 目标值 ±0.01", "%.4f" % (raw_h * s))
	_check(absf(mn.y) < 0.001, "模型脚底在 y=0 平面", "min.y=%.4f" % mn.y)

	# ---------- 3. 动画 ----------
	print("\n[3] 动画")
	var anim := _find_animation_player(model)
	if anim == null:
		_fail += 1
		print("  ✗ 没有 AnimationPlayer")
	else:
		var names := anim.get_animation_list()
		print("  导入的动画名 = %s" % str(names))
		# 精确名字集：既要求每个都在，也要求没有多余段
		for a in EXPECT_ANIMS:
			_check(names.has(a), "存在动画 %s" % a)
		_check(names.size() == EXPECT_ANIMS.size(),
			"动画段数 = 6（无多余段）", "实际 %d" % names.size())
		var frame_off := 1.0 / 24.0
		for a in EXPECT_ANIMS:
			if not names.has(a):
				continue
			var a_res := anim.get_animation(a)
			var want_len: float = DESIGN_LEN[a] + frame_off
			_check(absf(a_res.length - want_len) < 0.005,
				"%s length = %.4fs（内容 %.3fs + 1/24 帧偏移）" % [a, want_len, DESIGN_LEN[a]],
				"实际 %.4fs" % a_res.length)
			var first_t := INF
			var last_t := -INF
			for ti in a_res.get_track_count():
				var kc := a_res.track_get_key_count(ti)
				if kc == 0:
					continue
				first_t = minf(first_t, a_res.track_get_key_time(ti, 0))
				last_t = maxf(last_t, a_res.track_get_key_time(ti, kc - 1))
			_check(absf(first_t) < 0.001, "%s 首帧已平移到 t=0" % a, "t=%.4f" % first_t)
			_check(absf(last_t - a_res.length) < 0.005,
				"%s 末帧时刻 = length（尾部没有空播段）" % a, "%.4fs vs %.4fs" % [last_t, a_res.length])
		# 循环标记（enemy.gd 会给 Idle/Walk 打开 LOOP；Death 必须单次 → 不应是 LOOP）
		for a in ["Idle", "Walk"]:
			if names.has(a):
				print("  · %s 导入时 loop_mode = %d（enemy.gd 的 _set_loop 会置为 LOOP_LINEAR=1）"
					% [a, anim.get_animation(a).loop_mode])

	# ---------- 4. 场景 export + 无武器 + 命中盒 ----------
	print("\n[4] wolf.tscn export 与运行时装配")
	var wscn := load(WOLF_TSCN) as PackedScene
	if wscn == null:
		_fail += 1
		print("  ✗ 加载不到 %s（先生成场景）" % WOLF_TSCN)
	else:
		var wolf := wscn.instantiate()
		root.add_child(wolf)
		await process_frame
		await process_frame

		_check(wolf.get("enemy_id") == "wolf", "enemy_id == \"wolf\"",
			"实际 %s" % str(wolf.get("enemy_id")))
		_check(wolf.get("enemy_model_path") == MODEL_PATH,
			"enemy_model_path 指向狼 GLB", str(wolf.get("enemy_model_path")))
		_check(wolf.get("enemy_weapon_path") == "", "enemy_weapon_path == \"\"（空串=无武器）")
		_check(wolf.get("drop_item_id") == "", "drop_item_id == \"\"（不掉落）")
		_check(wolf.get("_use_model") == true, "成功使用模型外观（_use_model=true）")

		# ★ 无武器：空串 → 静默跳过、不生成 WeaponSocket；且骨架无 weapon.R 也没报警
		_check(wolf.get("_weapon_socket") == null, "无 WeaponSocket（空串武器路径 → 静默跳过）")
		_check(wolf.get("_weapon") == null, "无武器节点（_weapon == null）")
		if wolf.get("_weapon_socket") == null:
			var sk := _find_skeleton(wolf)
			_check(sk != null and sk.find_bone("weapon.R") < 0,
				"狼骨架无 weapon.R，且未触发挂点 warning")

		# 动画识别（enemy.gd 关键字匹配的结果）
		_check(wolf.get("_idle_anim") == "Idle", "识别 _idle_anim = Idle")
		_check(wolf.get("_walk_anim") == "Walk", "识别 _walk_anim = Walk")
		_check(wolf.get("_windup_anim") == "AttackWindup", "识别 _windup_anim = AttackWindup")
		_check(wolf.get("_attack_anim") == "Attack", "识别 _attack_anim = Attack")
		_check(wolf.get("_hit_anim") == "Hit", "识别 _hit_anim = Hit")
		_check(wolf.get("_death_anim") == "Death", "★ 新增：识别 _death_anim = Death")

		# 命中盒几何（@export 生效）
		var hb: Node = wolf.get("_hitbox")
		if hb == null:
			_fail += 1
			print("  ✗ 命中盒未创建")
		else:
			var shape_node: Node = hb.get_node_or_null("HitboxShape")
			_check(shape_node != null, "命中盒有 HitboxShape 子节点")
			if shape_node != null:
				var bs := shape_node.shape as BoxShape3D
				_check(bs != null and bs.size.is_equal_approx(Vector3(1.4, 1.1, 1.5)),
					"命中盒尺寸 = (1.4, 1.1, 1.5)", str(bs.size) if bs != null else "null")
				_check(shape_node.position.is_equal_approx(Vector3(0.0, 0.65, -1.2)),
					"命中盒偏移 = (0, 0.65, -1.2)", str(shape_node.position))

		# 组件数值
		var hp := wolf.get_node_or_null("Health")
		_check(hp != null and hp.max_hp == 70, "Health.max_hp == 70",
			"%d" % (hp.max_hp if hp != null else -1))
		var po := wolf.get_node_or_null("Poise")
		_check(po != null and absf(po.max_poise - 100.0) < 0.001, "Poise.max_poise == 100",
			"%.1f" % (po.max_poise if po != null else -1.0))

		# 数值参数
		_check(absf(_f(wolf.get("move_speed")) - 4.2) < 0.001, "move_speed == 4.2")
		_check(absf(_f(wolf.get("walk_natural_speed")) - 1.1724) < 0.0001, "walk_natural_speed == 1.1724")
		_check(absf(_f(wolf.get("walk_max_speed_scale")) - 3.8) < 0.001, "walk_max_speed_scale == 3.8")
		_check(absf(_f(wolf.get("model_target_height")) - 1.20) < 0.001, "model_target_height == 1.20")
		_check(int(_f(wolf.get("attack_damage"))) == 12, "attack_damage == 12")
		_check(absf(_f(wolf.get("parry_poise_percent")) - 50.0) < 0.001, "parry_poise_percent == 50")

		wolf.free()

	# ---------- 5. wolf_test.tscn 地图接线 ----------
	print("\n[5] wolf_test.tscn 地图接线")
	var map_scene := load("res://maps/wolf_test.tscn") as PackedScene
	if map_scene == null:
		_fail += 1
		print("  ✗ 加载不到 res://maps/wolf_test.tscn")
	else:
		var map := map_scene.instantiate()
		var es: Variant = map.get("enemy_scene")
		_check(es is PackedScene, "wolf_test.tscn 覆盖了 enemy_scene（不再用默认守卫）")
		if es is PackedScene:
			var espawn := (es as PackedScene).instantiate()
			_check(espawn.get("enemy_id") == "wolf", "地图的 enemy_scene 指向狼",
				str(espawn.get("enemy_id")))
			espawn.free()
		map.free()

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


## 递归收集所有网格部件 + "相对模型根"的累计变换（复刻 enemy.gd 的 _collect_meshes）。
func _collect_meshes(node: Node3D, parent_xform: Transform3D, out: Array) -> Array:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D:
		out.append({ "node": node, "xform": xform })
	for child in node.get_children():
		if child is Node3D:
			_collect_meshes(child as Node3D, xform, out)
	return out


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	var out: Array[Vector3] = [
		p, p + Vector3(s.x, 0, 0), p + Vector3(0, s.y, 0), p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, s.y, s.z),
		p + s
	]
	return out
