extends Node
## ============================================================
## 验证章鱼敌人：资产（骨骼/缩放/6 段动画）+ 场景接线（octopus.tscn / octopus_test.tscn）
##            + ★ 已知限制记录（arm1/arm4 支撑相起始前冲；见 octopus_01/DESIGN.md §3.5）
## ============================================================
## 运行（★ 必须跑场景，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_enemy_octopus.tscn
##
## 【为什么必须 .tscn】本探针要真实驱动物理帧 / `_process` → `_animate_model` 这条链路，
##   且 enemy.gd 以标识符方式引用 autoload `EventBus` —— `--script` 下 autoload 不注册，
##   会在**编译期**报 `Identifier not found: EventBus` 并连锁挂掉所有依赖脚本。
##
## 【帧偏移约定（管线固有，不是缺陷）】Blender glTF 导出把关键帧写成 frame/fps，
##   Action 帧区间 1..N → 源时间轴是 1/24..N/24；Godot 导入时整体平移到 t=0，
##   但 Animation.length 保留源末帧绝对时刻 N/24。故本脚本断言 length − 1/24 = 设计时长。
##
## 【本探针覆盖】
##   [1][2] 资产：19 骨 / 无 weapon.R / 缩放到 0.90 / 6 段动画名与时长 / 首末帧
##   [3]    octopus.tscn：enemy_id / 模型 / 无武器 / 动画识别（_run_anim 必须为空）/ 数值哨兵 /
##                       命中盒（最宽最矮）/ 组件（血量 80 / 失衡 25%→4 次）
##   [4]    octopus_test.tscn 地图接线
##   [5]    ★ 已知限制：Walk 支撑相 arm1/arm4 的前冲回弹（记录 + 受约束的边界断言）
## ============================================================

const MODEL_PATH := "res://assets/enemies/octopus_01/octopus_rigged.glb"
const OCTOPUS_TSCN := "res://scenes/enemy/octopus.tscn"
const OCTOPUS_TEST_TSCN := "res://maps/octopus_test.tscn"
## 与 enemy.gd 的 model_target_height 一致（章鱼 0.90m —— 全场最矮）
const TARGET_HEIGHT := 0.90
## 期望动画名（enemy.gd 按关键字识别；6 段，**无 Run** —— 章鱼 v1 没有奔跑段）
const EXPECT_ANIMS := ["Idle", "Walk", "AttackWindup", "Attack", "Hit", "Death"]
## 6 段动画的设计内容时长（Blender Action 帧区间跨度，24 fps，见 DESIGN §2.2）
## ★ DESIGN_LEN 的键必须与 EXPECT_ANIMS 完全同步，否则 DESIGN_LEN[a] 返回 null → 运行时类型错。
const DESIGN_LEN := {
	"Idle": 2.0000, "Walk": 0.5000, "AttackWindup": 0.5000,
	"Attack": 0.2500, "Hit": 0.4167, "Death": 1.0000,
}
## 章鱼实际骨架骨数 = 19（8 腕 × 2 段 + root/mantle/head）
const EXPECT_BONES := 19

## ---- 数值哨兵（octopus.tscn 被改坏 / 与 DESIGN §4 漂移 ⇒ 立刻变红）----
## 权威口径见 octopus_01/DESIGN.md：D3 表 + §3.2 实测 walk_natural_speed
const OCTO_MOVE_SPEED := 2.2
const OCTO_WALK_NATURAL := 1.68          # = 0.4200/(0.5×0.5)，probe_stance_stride.py 实测
const OCTO_WANT := 1.310                 # = 2.2/1.68，须落在自然重定时带 [1.20,1.45]
const OCTO_WALK_MAX := 2.0
const OCTO_DAMAGE := 14
const OCTO_INTERVAL := 2.0
const OCTO_RECOVER := 1.2
const OCTO_PARRY := 25.0
const OCTO_HP := 80
const OCTO_HITBOX := Vector3(2.6, 1.1, 2.2)
const OCTO_HITBOX_OFF := Vector3(0.0, 0.45, -1.1)

## ★ 已知限制（DESIGN §3.5）：arm1/arm4 支撑相起始"前冲回弹"的实测上界（米，模型内）
##   原始（Blender）≈ 0.047 m；Godot 缩放到 0.90/(原始总高 0.540) ≈ ×1.667 ⇒ ≈ 0.078 m。
##   这里给一个**宽松上界**做回归门限：只要不显著恶化就不红（它是已知限制，不是缺陷）。
const KNOWN_REBOUND_BOUND := 0.15

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


## 把可能为 null 的数值安全转成 float（断言失败时给哨兵值而不是崩掉）。
func _f(v: Variant) -> float:
	return float(v) if v != null else -99999.0


func _ready() -> void:
	print("=== 章鱼敌人资产 + 场景接线验证（含已知限制记录）===")
	await _asset_and_scene()
	await _known_limitation()

	print("")
	if _fail == 0:
		print("结论：全部通过 ✓")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


## ==================================================================
## [1][2][3][4] 资产 + 场景（含两帧 await 让 enemy.gd 完成运行时装配）
## ==================================================================
func _asset_and_scene() -> void:
	# ---------- [1] 骨架 + 缩放 + 脚底 ----------
	print("\n[1] 资产：骨架与缩放")
	var model_scene := load(MODEL_PATH) as PackedScene
	if model_scene == null:
		_fail += 1
		print("  ✗ 资产未导入：%s" % MODEL_PATH)
		return
	var model := model_scene.instantiate() as Node3D
	var skel := _find_skeleton(model)
	if skel == null:
		_fail += 1
		print("  ✗ 模型里没有 Skeleton3D")
	else:
		_check(skel.get_bone_count() == EXPECT_BONES, "骨骼数 = %d" % EXPECT_BONES,
			"实际 %d" % skel.get_bone_count())
		_check(skel.find_bone("weapon.R") < 0, "骨架里没有 weapon.R（章鱼徒手，八腕=武器）")

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
	print("  原始总高 = %.4f m（脚底 y=%.4f, 顶 y=%.4f）；缩放系数 = %.4f" % [raw_h, mn.y, mx.y, s])
	_check(absf(raw_h * s - TARGET_HEIGHT) < 0.01, "缩放后总高 = 0.90 ±0.01", "%.4f" % (raw_h * s))
	_check(absf(mn.y) < 0.001, "模型最低点在 y=0 平面", "min.y=%.4f" % mn.y)
	print("  原始水平展开直径 = %.4f m（八腕摊开；★ 章鱼全场最宽）" % Vector2(mx.x - mn.x, mx.z - mn.z).length())

	# ---------- [2] 6 段动画：名 / 时长 / 首末帧 ----------
	print("\n[2] 资产：6 段动画")
	var anim := _find_animation_player(model)
	if anim == null:
		_fail += 1
		print("  ✗ 没有 AnimationPlayer")
	else:
		var names := anim.get_animation_list()
		print("  导入的动画名 = %s" % str(names))
		for a in EXPECT_ANIMS:
			_check(names.has(a), "存在动画 %s" % a)
		_check(names.size() == EXPECT_ANIMS.size(), "动画段数 = 6（无多余段）", "实际 %d" % names.size())
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
				"%s 末帧时刻 = length（尾部没有空播段）" % a, "%.4f vs %.4f" % [last_t, a_res.length])
		for a in ["Idle", "Walk"]:
			if names.has(a):
				print("  · %s 导入时 loop_mode = %d（enemy.gd 的 _set_loop 会置为 LOOP_LINEAR=1）"
					% [a, anim.get_animation(a).loop_mode])
	model.free()

	# ---------- [3] octopus.tscn 运行时装配 + 数值哨兵 ----------
	print("\n[3] octopus.tscn export 与运行时装配")
	var oscn := load(OCTOPUS_TSCN) as PackedScene
	if oscn == null:
		_fail += 1
		print("  ✗ 加载不到 %s" % OCTOPUS_TSCN)
		return
	var oct := oscn.instantiate()
	add_child(oct)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(oct.get("enemy_id") == "octopus", "enemy_id == \"octopus\"", "实际 %s" % str(oct.get("enemy_id")))
	_check(oct.get("enemy_model_path") == MODEL_PATH, "enemy_model_path 指向章鱼 GLB",
		str(oct.get("enemy_model_path")))
	_check(oct.get("enemy_weapon_path") == "", "enemy_weapon_path == \"\"（空串=无武器）")
	_check(oct.get("drop_item_id") == "", "drop_item_id == \"\"（不掉落）")
	_check(oct.get("_use_model") == true, "成功使用模型外观（_use_model=true）")
	_check(oct.get("_weapon_socket") == null, "无 WeaponSocket（空串武器路径 → 静默跳过）")
	_check(oct.get("_weapon") == null, "无武器节点（_weapon == null）")

	# 动画识别（enemy.gd 关键字匹配的结果）
	_check(oct.get("_idle_anim") == "Idle", "识别 _idle_anim = Idle")
	_check(oct.get("_walk_anim") == "Walk", "识别 _walk_anim = Walk")
	_check(oct.get("_run_anim") == "", "★ 识别 _run_anim = \"\"（无 Run 段：6 段里无 run/gallop 关键字）")
	_check(oct.get("_windup_anim") == "AttackWindup", "识别 _windup_anim = AttackWindup")
	_check(oct.get("_attack_anim") == "Attack", "识别 _attack_anim = Attack")
	_check(oct.get("_hit_anim") == "Hit", "识别 _hit_anim = Hit")
	_check(oct.get("_death_anim") == "Death", "识别 _death_anim = Death")

	# 数值参数（资产漂移哨兵，D3 已拍板）
	_check(absf(_f(oct.get("move_speed")) - OCTO_MOVE_SPEED) < 0.001, "move_speed == 2.2（全场最慢）")
	_check(absf(_f(oct.get("model_target_height")) - TARGET_HEIGHT) < 0.001, "model_target_height == 0.90（全场最矮）")
	_check(int(_f(oct.get("attack_damage"))) == OCTO_DAMAGE, "attack_damage == 14")
	_check(absf(_f(oct.get("attack_interval")) - OCTO_INTERVAL) < 0.001, "attack_interval == 2.0（全场最长）")
	_check(absf(_f(oct.get("recover_time")) - OCTO_RECOVER) < 0.001, "recover_time == 1.2（全场最长破绽）")
	_check(absf(_f(oct.get("parry_poise_percent")) - OCTO_PARRY) < 0.001, "parry_poise_percent == 25（4 次失衡，全场最难）")
	_check(absf(_f(oct.get("walk_natural_speed")) - OCTO_WALK_NATURAL) < 0.0001,
		"walk_natural_speed == %.4f（§3.2 实测）" % OCTO_WALK_NATURAL)
	_check(absf(_f(oct.get("walk_max_speed_scale")) - OCTO_WALK_MAX) < 0.001,
		"walk_max_speed_scale == %.2f" % OCTO_WALK_MAX)
	_check(absf(_f(oct.get("run_natural_speed")) - 0.0) < 1e-6, "run_natural_speed == 0.0（无 Run）")
	var want := OCTO_MOVE_SPEED / OCTO_WALK_NATURAL
	_check(absf(want - OCTO_WANT) < 0.01 and want >= 1.20 and want <= 1.45,
		"★ 实播倍速 want = 2.2/%.4f = %.4f ∈ [1.20,1.45]（自然重定时带）" % [OCTO_WALK_NATURAL, want])

	# 命中盒几何（@export 生效；★ 全场最宽最矮）
	var hb: Node = oct.get("_hitbox")
	if hb == null:
		_fail += 1
		print("  ✗ 命中盒未创建")
	else:
		var shape_node: Node = hb.get_node_or_null("HitboxShape")
		_check(shape_node != null, "命中盒有 HitboxShape 子节点")
		if shape_node != null:
			var bs := shape_node.shape as BoxShape3D
			_check(bs != null and bs.size.is_equal_approx(OCTO_HITBOX),
				"命中盒尺寸 = (2.6, 1.1, 2.2)（最宽最矮）", str(bs.size) if bs != null else "null")
			_check(shape_node.position.is_equal_approx(OCTO_HITBOX_OFF),
				"命中盒偏移 = (0, 0.45, -1.1)（贴地前伸）", str(shape_node.position))

	# 组件数值
	var hp := oct.get_node_or_null("Health")
	_check(hp != null and hp.max_hp == OCTO_HP, "Health.max_hp == 80", "%d" % (hp.max_hp if hp != null else -1))
	var po := oct.get_node_or_null("Poise")
	_check(po != null and absf(po.max_poise - 100.0) < 0.001, "Poise.max_poise == 100",
		"%.1f" % (po.max_poise if po != null else -1.0))
	if po != null:
		_check(absf(po.break_time - 3.0) < 0.001, "Poise.break_time == 3.0", "%.2f" % po.break_time)

	oct.free()

	# ---------- [4] octopus_test.tscn 地图接线 ----------
	print("\n[4] octopus_test.tscn 地图接线")
	var map_scene := load(OCTOPUS_TEST_TSCN) as PackedScene
	if map_scene == null:
		_fail += 1
		print("  ✗ 加载不到 %s" % OCTOPUS_TEST_TSCN)
	else:
		var map := map_scene.instantiate()
		var es: Variant = map.get("enemy_scene")
		_check(es is PackedScene, "octopus_test.tscn 覆盖了 enemy_scene")
		if es is PackedScene:
			var espawn := (es as PackedScene).instantiate()
			_check(espawn.get("enemy_id") == "octopus", "地图的 enemy_scene 指向章鱼",
				str(espawn.get("enemy_id")))
			espawn.free()
		map.free()


## ==================================================================
## [5] ★ 已知限制：Walk 支撑相 arm1/arm4 的前冲回弹（DESIGN §3.5）
## ==================================================================
## 【为什么探针要量它】这一处"回弹"是**刚性腕绕肩 yaw** 的几何必然（≥ 单一竖直轴做不到纯向后），
##   用户裁决"保均匀、接受回弹"。但**接受 ≠ 不监控**：把它变成**可证的边界**——
##   arm2/arm3 必须单调（前冲 ≤ CLEAN_MONO_TOL），arm1/arm4 的前冲不得超过 KNOWN_REBOUND_BOUND。
##   若哪天有人改了 Walk 让它恶化，本探针立刻变红。
func _known_limitation() -> void:
	print("\n[5] ★ 已知限制记录：Walk 支撑相 arm1/arm4 前冲回弹（DESIGN §3.5）")
	_ground()
	var oct := await _spawn_no_warmup()
	if oct == null:
		return
	oct.set_physics_process(false)
	oct.set_process(false)
	var skel: Skeleton3D = oct.get("_skeleton")
	var ap: AnimationPlayer = oct.get("_anim_player")
	if skel == null or ap == null:
		_fail += 1
		print("  ✗ 缺少 _skeleton / _anim_player，无法量腕尖轨迹")
		return
	ap.play("Walk")
	ap.speed_scale = 1.0
	await get_tree().process_frame          # 让 Walk 成为 current
	ap.seek(0.0, true)                      # ★ 之后一律 seek(update=true) 同步取姿势，**不再 await**
	#   （若在 seek 之后再 await 一帧，AnimationPlayer 会自行前进 ~1 帧 ⇒ 采样漂移、行程被削半）

	# Walk 内容 = 13 键、t = i/24；前组支撑相 = 键 0..6（触地 t=0 → 离地 t=6/24）
	var WALK_KEYS := 13
	var STANCE_END := 6
	var arms := ["arm1_tip.L", "arm1_tip.R", "arm2_tip.L", "arm2_tip.R",
		"arm3_tip.L", "arm3_tip.R", "arm4_tip.L", "arm4_tip.R"]
	var tracks := {}
	for a in arms:
		var idx := skel.find_bone(a)
		if idx < 0:
			continue
		# 【量测点说明】用骨 head（= 腕节骨心）—— Godot 4.7 的 Skeleton3D 无 get_bone_length，
		#   拿不到骨 tail；骨心与真腕尖同向运动（幅度偏小），足够做"回弹方向/模式"的定性交叉核对。
		#   权威幅度以 Blender 侧 probe_stance_stride.py 的**腕尖**实测为准（DESIGN §3.5）。
		var pts: Array = []
		for i in WALK_KEYS:
			ap.seek(float(i) / 24.0, true)
			pts.append(skel.get_bone_global_pose(idx).origin)
		tracks[a] = pts

	if tracks.is_empty():
		print("  ⚠ 未找到任何 armN_tip 骨骼（骨骼名可能被导入改写）—— 跳过量测，仅保留文字记录")
		print("     文字记录：arm1/arm4 前冲 ≈ +0.047 m（Blender 原始），机制见 DESIGN §3.5")
		oct.free()
		return

	# Godot 里前向 = −Z（Blender +Y 前 → Godot −Z）；支撑相腕尖应沿 +Z 后退。
	# 前冲 = 相邻键里 Z 反而**减小**（向前）的量。
	print("  腕节骨心（非腕尖；真腕尖见 DESIGN §3.5）沿世界 Z 的逐键位移（+Z = 向后拖；负值 = 前冲）：")
	var rebound_max := 0.0
	var clean_worst := 0.0
	for a in ["arm1_tip.L", "arm1_tip.R", "arm2_tip.L", "arm2_tip.R",
			"arm3_tip.L", "arm3_tip.R", "arm4_tip.L", "arm4_tip.R"]:
		if not tracks.has(a):
			continue
		var pts: Array = tracks[a]
		var td := 0
		var te := STANCE_END
		if a.begins_with("arm3") or a.begins_with("arm4"):
			td = STANCE_END          # 后组触地 = 键 6
			te = WALK_KEYS - 1       # 离地 = 键 12
		var fwd := 0.0
		var line := ""
		for i in range(td, te):
			var dz: float = (pts[i + 1] as Vector3).z - (pts[i] as Vector3).z
			if dz < 0.0:
				fwd = maxf(fwd, -dz)
			line += "%+.4f " % dz
		var affected: bool = a.begins_with("arm1") or a.begins_with("arm4")
		print("    %-12s [%s] Z 位移: %s → 最大前冲 %.4f m"
			% [a, "受影响" if affected else "参照（小）", line, fwd])
		if affected:
			rebound_max = maxf(rebound_max, fwd)
		else:
			clean_worst = maxf(clean_worst, fwd)

	print("  · 受影响腕（arm1/arm4）最大前冲 = %.4f m；参照腕（arm2/arm3）最大前冲 = %.4f m"
		% [rebound_max, clean_worst])
	print("  · 文字记录（DESIGN §3.5）：原始（Blender 腕尖，权威）= arm1 +0.0469 / arm4 +0.0430 m；")
	print("    机制 = 竖直轴 yaw 无法让前/后朝向腕纯向后；取舍 = 保「均匀」(极差 0%)，")
	print("    因「单调 + 均匀」在 want ≤ 1.45 下不可兼得（0.214→v=0.856→want=2.57）。")
	# ★ 断言只锁两件事（都稳健、都可证伪）：
	#   ① 受影响腕前冲不得超已知上界（防回归恶化）；
	#   ② 本探针确实抓到了"arm1/arm4 明显、arm2/arm3 小"这个模式（防空洞）。
	_check(rebound_max <= KNOWN_REBOUND_BOUND,
		"arm1/arm4 前冲不超已知上界 %.2f m（已知限制，非缺陷）" % KNOWN_REBOUND_BOUND,
		"实际 %.4f m" % rebound_max)
	_check(rebound_max > clean_worst,
		"模式成立：arm1/arm4 前冲 > arm2/arm3（非空洞）",
		"%.4f > %.4f" % [rebound_max, clean_worst])
	oct.free()


func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(200.0, 1.0, 200.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)


## 起一只章鱼（不做 M-2 预热，量测 [5] 用；直接驱 AnimationPlayer）。
func _spawn_no_warmup() -> EnemyBrute:
	var e := (load(OCTOPUS_TSCN) as PackedScene).instantiate() as EnemyBrute
	if e == null:
		_fail += 1
		print("  ✗ 实例化 %s 失败（不是 EnemyBrute？）" % OCTOPUS_TSCN)
		return null
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	for _i in 5:
		await get_tree().physics_frame
	return e


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
