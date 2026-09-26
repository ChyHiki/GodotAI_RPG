extends Node
## ============================================================
## 验证鸟敌人：资产（骨骼/缩放/7 段动画）+ 场景接线（bird.tscn / bird_test.tscn）
##            + Walk/Run 换挡（T11b；见 bird_01/DESIGN.md §9）
## ============================================================
## 运行（★ 必须跑场景，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_enemy_bird.tscn
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
##   [1][2] 资产：22 骨 / 无 weapon.R / 缩放到 1.60 / 7 段动画名与时长 / 首末帧
##   [3]    bird.tscn：enemy_id / 模型 / 无武器 / 动画识别（含 _run_anim）/ run_* 哨兵 /
##                      自洽约束 / 命中盒 / 组件
##   [4]    bird_test.tscn 地图接线
##   [5]    Walk/Run 换挡：
##            校验① spd=2.6 ⇒ 播 Run，ss==ps==clampf(2.6/run_nat, run_min, run_max)
##            校验② spd < 回切速度（2.0 m/s）⇒ 回切 Walk
##            校验②-b 起切速度附近 ±0.02 悬停 60 帧 ⇒ 档位切换 0 次（15% 滞回在 latch）
##            校验②-c 把滞回置 0 ⇒ 同一悬停必抖动（证明 ②-b 非空洞、可证伪）
## ============================================================

const MODEL_PATH := "res://assets/enemies/bird_01/bird_rigged.glb"
const BIRD_TSCN := "res://scenes/enemy/bird.tscn"
const BIRD_TEST_TSCN := "res://maps/bird_test.tscn"
## 与 enemy.gd 的 model_target_height 一致（鸟 1.60m）
const TARGET_HEIGHT := 1.60
## 期望动画名（enemy.gd 按关键字识别；7 段含 T11a 追加的 Run）
const EXPECT_ANIMS := ["Idle", "Walk", "Run", "AttackWindup", "Attack", "Hit", "Death"]
## 7 段动画的设计内容时长（Blender Action 帧区间跨度，24 fps）
## ★ DESIGN_LEN 的键必须与 EXPECT_ANIMS 完全同步，否则 DESIGN_LEN[a] 返回 null → 运行时类型错。
const DESIGN_LEN := {
	"Idle": 2.0000, "Walk": 0.7500, "Run": 0.5000, "AttackWindup": 0.5000,
	"Attack": 0.2500, "Hit": 0.4167, "Death": 1.0000,
}
## ---- run_* / walk_* 资产哨兵（bird.tscn 被改坏 / 与 DESIGN §9 漂移 ⇒ 立刻变红）----
## 权威口径：run_natural_speed=1.9370（probe_stride_bird 实测）、walk_natural_speed=1.6226。
## ★ run_switch_speed_scale 必须 = 1.45（不是 enemy.gd 默认的 2.40、也不是狼的 2.40）：
##   鸟 want@2.6 = 1.602；若取 2.40 则 Run 永不播 ⇒ Run 段成死内容（DESIGN §9.5）。
const BIRD_WALK_NATURAL := 1.6226
const BIRD_WALK_MAX := 2.0
const BIRD_RUN_NATURAL := 1.9370
const BIRD_RUN_MIN := 0.80
const BIRD_RUN_MAX := 1.75
const BIRD_RUN_SWITCH := 1.45
const BIRD_RUN_HYST := 0.15

## 实播倍速容差（复核 β 不变式：get_playing_speed() ≡ speed_scale）。
const PS_TOL := 1e-4
## 预热相：IDLE + velocity≈0 + 动画在播，连续这么多帧才算"动画系统已上身"。
const WARMUP_MIN := 10

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
	print("=== 鸟敌人资产 + 场景接线 + Walk/Run 换挡验证 ===")
	await _asset_and_scene()
	await _switching()

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
		_check(skel.get_bone_count() == 22, "骨骼数 = 22", "实际 %d" % skel.get_bone_count())
		_check(skel.find_bone("weapon.R") < 0, "骨架里没有 weapon.R（鸟徒手，喙=武器）")

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
	_check(absf(raw_h * s - TARGET_HEIGHT) < 0.01, "缩放后总高 = 1.60 ±0.01", "%.4f" % (raw_h * s))
	_check(absf(mn.y) < 0.001, "模型脚底在 y=0 平面", "min.y=%.4f" % mn.y)

	# ---------- [2] 7 段动画：名 / 时长 / 首末帧 ----------
	print("\n[2] 资产：7 段动画")
	var anim := _find_animation_player(model)
	if anim == null:
		_fail += 1
		print("  ✗ 没有 AnimationPlayer")
	else:
		var names := anim.get_animation_list()
		print("  导入的动画名 = %s" % str(names))
		for a in EXPECT_ANIMS:
			_check(names.has(a), "存在动画 %s" % a)
		_check(names.size() == EXPECT_ANIMS.size(), "动画段数 = 7（无多余段）", "实际 %d" % names.size())
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
		for a in ["Idle", "Walk", "Run"]:
			if names.has(a):
				print("  · %s 导入时 loop_mode = %d（enemy.gd 的 _set_loop 会置为 LOOP_LINEAR=1）"
					% [a, anim.get_animation(a).loop_mode])
	model.free()

	# ---------- [3] bird.tscn 运行时装配 + 数值哨兵 ----------
	print("\n[3] bird.tscn export 与运行时装配")
	var bscn := load(BIRD_TSCN) as PackedScene
	if bscn == null:
		_fail += 1
		print("  ✗ 加载不到 %s" % BIRD_TSCN)
		return
	var bird := bscn.instantiate()
	add_child(bird)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(bird.get("enemy_id") == "bird", "enemy_id == \"bird\"", "实际 %s" % str(bird.get("enemy_id")))
	_check(bird.get("enemy_model_path") == MODEL_PATH, "enemy_model_path 指向鸟 GLB",
		str(bird.get("enemy_model_path")))
	_check(bird.get("enemy_weapon_path") == "", "enemy_weapon_path == \"\"（空串=无武器）")
	_check(bird.get("drop_item_id") == "", "drop_item_id == \"\"（不掉落）")
	_check(bird.get("_use_model") == true, "成功使用模型外观（_use_model=true）")
	_check(bird.get("_weapon_socket") == null, "无 WeaponSocket（空串武器路径 → 静默跳过）")
	_check(bird.get("_weapon") == null, "无武器节点（_weapon == null）")

	# 动画识别（enemy.gd 关键字匹配的结果）
	_check(bird.get("_idle_anim") == "Idle", "识别 _idle_anim = Idle")
	_check(bird.get("_walk_anim") == "Walk", "识别 _walk_anim = Walk")
	_check(bird.get("_run_anim") == "Run", "★ 识别 _run_anim = Run")
	_check(bird.get("_windup_anim") == "AttackWindup", "识别 _windup_anim = AttackWindup")
	_check(bird.get("_attack_anim") == "Attack", "识别 _attack_anim = Attack")
	_check(bird.get("_hit_anim") == "Hit", "识别 _hit_anim = Hit")
	_check(bird.get("_death_anim") == "Death", "识别 _death_anim = Death")

	# 数值参数（资产漂移哨兵）
	_check(absf(_f(bird.get("move_speed")) - 2.6) < 0.001, "move_speed == 2.6")
	_check(absf(_f(bird.get("model_target_height")) - 1.60) < 0.001, "model_target_height == 1.60")
	_check(int(_f(bird.get("attack_damage"))) == 10, "attack_damage == 10")
	_check(absf(_f(bird.get("attack_interval")) - 1.0) < 0.001, "attack_interval == 1.0")
	_check(absf(_f(bird.get("parry_poise_percent")) - 100.0) < 0.001, "parry_poise_percent == 100")
	_check(absf(_f(bird.get("walk_natural_speed")) - BIRD_WALK_NATURAL) < 0.0001,
		"walk_natural_speed == %.4f" % BIRD_WALK_NATURAL)
	_check(absf(_f(bird.get("walk_max_speed_scale")) - BIRD_WALK_MAX) < 0.001,
		"walk_max_speed_scale == %.2f" % BIRD_WALK_MAX)
	_check(absf(_f(bird.get("run_natural_speed")) - BIRD_RUN_NATURAL) < 0.0001,
		"run_natural_speed == %.4f" % BIRD_RUN_NATURAL)
	_check(absf(_f(bird.get("run_min_speed_scale")) - BIRD_RUN_MIN) < 0.001,
		"run_min_speed_scale == %.2f" % BIRD_RUN_MIN)
	_check(absf(_f(bird.get("run_max_speed_scale")) - BIRD_RUN_MAX) < 0.001,
		"run_max_speed_scale == %.2f" % BIRD_RUN_MAX)
	_check(absf(_f(bird.get("run_switch_speed_scale")) - BIRD_RUN_SWITCH) < 0.001,
		"★ run_switch_speed_scale == %.2f（≠ 默认/狼的 2.40）" % BIRD_RUN_SWITCH)
	_check(absf(_f(bird.get("run_switch_hysteresis")) - BIRD_RUN_HYST) < 0.001,
		"run_switch_hysteresis == %.2f" % BIRD_RUN_HYST)
	# 自洽约束（enemy.gd:212-219）：switch×walk_nat ≥ run_min×run_nat
	var lhs := BIRD_RUN_SWITCH * BIRD_WALK_NATURAL
	var rhs := BIRD_RUN_MIN * BIRD_RUN_NATURAL
	_check(lhs >= rhs, "自洽：switch×walk_nat(%.4f) ≥ run_min×run_nat(%.4f)" % [lhs, rhs])

	# 命中盒几何（@export 生效）
	var hb: Node = bird.get("_hitbox")
	if hb == null:
		_fail += 1
		print("  ✗ 命中盒未创建")
	else:
		var shape_node: Node = hb.get_node_or_null("HitboxShape")
		_check(shape_node != null, "命中盒有 HitboxShape 子节点")
		if shape_node != null:
			var bs := shape_node.shape as BoxShape3D
			_check(bs != null and bs.size.is_equal_approx(Vector3(1.0, 0.9, 1.6)),
				"命中盒尺寸 = (1.0, 0.9, 1.6)", str(bs.size) if bs != null else "null")
			_check(shape_node.position.is_equal_approx(Vector3(0.0, 1.05, -1.3)),
				"命中盒偏移 = (0, 1.05, -1.3)", str(shape_node.position))

	# 组件数值
	var hp := bird.get_node_or_null("Health")
	_check(hp != null and hp.max_hp == 45, "Health.max_hp == 45", "%d" % (hp.max_hp if hp != null else -1))
	var po := bird.get_node_or_null("Poise")
	_check(po != null and absf(po.max_poise - 100.0) < 0.001, "Poise.max_poise == 100",
		"%.1f" % (po.max_poise if po != null else -1.0))

	bird.free()

	# ---------- [4] bird_test.tscn 地图接线 ----------
	print("\n[4] bird_test.tscn 地图接线")
	var map_scene := load(BIRD_TEST_TSCN) as PackedScene
	if map_scene == null:
		_fail += 1
		print("  ✗ 加载不到 %s" % BIRD_TEST_TSCN)
	else:
		var map := map_scene.instantiate()
		var es: Variant = map.get("enemy_scene")
		_check(es is PackedScene, "bird_test.tscn 覆盖了 enemy_scene")
		if es is PackedScene:
			var espawn := (es as PackedScene).instantiate()
			_check(espawn.get("enemy_id") == "bird", "地图的 enemy_scene 指向鸟",
				str(espawn.get("enemy_id")))
			espawn.free()
		map.free()


## ==================================================================
## [5] Walk/Run 换挡（T11b；M-1 确定性强制速度，见 verify_wolf_run.gd 文件头）
## ==================================================================
func _switching() -> void:
	print("\n[5] Walk/Run 换挡（校验① / 校验②）")
	_ground()
	var bird := await _spawn(BIRD_TSCN)
	if bird == null:
		return
	bird.set_physics_process(false)

	var wnat := float(bird.get("walk_natural_speed"))
	var rnat := float(bird.get("run_natural_speed"))
	var rmin := float(bird.get("run_min_speed_scale"))
	var rmax := float(bird.get("run_max_speed_scale"))
	var switch_ss := float(bird.get("run_switch_speed_scale"))
	var hyst := float(bird.get("run_switch_hysteresis"))
	var cap := float(bird.get("walk_max_speed_scale"))
	var switch_speed := switch_ss * wnat
	var retreat_speed := switch_ss * (1.0 - hyst) * wnat
	print("  换挡口径：起切 speed = %.2f×%.4f = %.4f m/s；回切 speed = %.2f×%.2f×%.4f = %.4f m/s"
		% [switch_ss, wnat, switch_speed, switch_ss, 1.0 - hyst, wnat, retreat_speed])

	# ---- 校验①：move_speed = 2.6 ⇒ 播 Run，实播倍速 == 2.6/run_nat ----
	var spd := 2.6
	var want_run := clampf(spd / maxf(0.2, rnat), rmin, rmax)
	bird._run_latched = false
	var arr := await _measure(bird, spd)
	_expect(arr, "Run", want_run,
		"[校验①] spd=%.2f ⇒ 播 Run，ss==ps==clampf(%.2f/%.4f, %.2f, %.2f)=%.5f" % [spd, spd, rnat, rmin, rmax, want_run])

	# ---- 校验②：先锁 Run，再降到 < 回切速度 ⇒ 回切 Walk ----
	bird._run_latched = false
	for _i in 5:
		await _tick(bird, 3.0)                                   # 3.0 ⇒ want=1.849 ≥ 1.45 ⇒ 锁 Run
	var slow := 1.9                                              # 1.9 ⇒ want=1.171 < 回切 1.2325 ⇒ Walk
	var slow_arr := await _measure(bird, slow)
	_expect(slow_arr, "Walk", clampf(slow / maxf(0.2, wnat), 0.4, cap),
		"[校验②] spd=%.2f（< 回切速度 %.4f）⇒ 回切 Walk" % [slow, retreat_speed])

	# ---- 校验②-b：起切速度附近 ±0.02 悬停 60 帧 ⇒ 切换 0 次 ----
	bird._run_latched = true
	var sw := await _hover_switches(bird, switch_speed)
	_check(sw == 0, "[校验②-b] 起切速度 %.4f 附近 ±0.02 悬停 60 帧 ⇒ 切换次数 == 0" % switch_speed,
		"实际 %d 次" % sw)

	# ---- 校验②-c：把滞回置 0 ⇒ 同一悬停必抖动（证明 ②-b 非空洞、可证伪）----
	bird.run_switch_hysteresis = 0.0
	bird._run_latched = true
	var sw0 := await _hover_switches(bird, switch_speed)
	_check(sw0 >= 1, "[校验②-c] 把滞回置 0 ⇒ 同一悬停抖动 ≥1 次（证明 ②-b 非空洞）",
		"实际 %d 次" % sw0)
	bird.run_switch_hysteresis = hyst

	bird.free()


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


## 起一只鸟 + 预热相（M-2）。返回实例或 null。
func _spawn(path: String) -> EnemyBrute:
	var e := (load(path) as PackedScene).instantiate() as EnemyBrute
	if e == null:
		_fail += 1
		print("  ✗ 实例化 %s 失败（不是 EnemyBrute？）" % path)
		return null
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	var still := 0
	for _i in 300:
		await get_tree().physics_frame
		var anim: AnimationPlayer = e.get("_anim_player")
		if e.state == EnemyBrute.State.IDLE \
				and Vector2(e.velocity.x, e.velocity.z).length() < 0.01 \
				and anim != null and anim.is_playing():
			still += 1
		else:
			still = 0
		if still >= WARMUP_MIN:
			break
	_check(still >= WARMUP_MIN,
		"★ M-2 预热完成：IDLE + velocity≈0 + 动画在播 连续 ≥%d 帧" % WARMUP_MIN,
		"连续 %d 帧" % still)
	return e


## 推进一个"帧"：钉在 CHASE + 直接写 velocity，等 `_process` 跑完，读三个量。
func _tick(e: EnemyBrute, spd: float) -> Array:
	e.state = EnemyBrute.State.CHASE
	e.velocity = Vector3(0.0, 0.0, -spd)
	await get_tree().process_frame
	var anim: AnimationPlayer = e.get("_anim_player")
	return [String(anim.current_animation), anim.speed_scale, anim.get_playing_speed()]


## 稳态采样：先跑 3 帧收敛，再取连续 10 帧返回。
func _measure(e: EnemyBrute, spd: float) -> Array:
	for _i in 3:
		await _tick(e, spd)
	var out: Array = []
	for _i in 10:
		out.append(await _tick(e, spd))
	return out


## 断言 10 帧逐帧都是 cur / speed_scale == val / get_playing_speed() == val，并打印末帧实测。
func _expect(arr: Array, cur: String, val: float, label: String) -> void:
	var ok := true
	var detail := ""
	for s in arr:
		if String(s[0]) != cur or absf(float(s[1]) - val) > PS_TOL or absf(float(s[2]) - val) > PS_TOL:
			ok = false
			detail = "cur=%s ss=%.6f ps=%.6f（期望 %s / %.6f）" % [s[0], s[1], s[2], cur, val]
			break
	_check(ok, label, detail if detail != "" else "10 帧逐帧 = %s，ss==ps==%.5f" % [cur, val])
	if not arr.is_empty():
		var last: Array = arr[arr.size() - 1]
		print("       实测（末帧）：cur=%s  speed_scale=%.6f  get_playing_speed()=%.6f"
			% [last[0], last[1], last[2]])


## 在 center ± 0.02 m/s 悬停 60 帧，返回档位切换次数（首帧不计数）。
func _hover_switches(e: EnemyBrute, center: float) -> int:
	var last := ""
	var switches := 0
	var first := true
	for i in 60:
		var spd := center + 0.02 * sin(TAU * float(i) / 10.0)
		var r := await _tick(e, spd)
		var cur := String(r[0])
		if first:
			last = cur
			first = false
		elif cur != last:
			switches += 1
			last = cur
	return switches


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
