extends Node
## ============================================================
## ★ 实机验证：狼的 Walk / Run 切换接线（T08 的行为面）
## ============================================================
## 运行（★ 跑场景，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_wolf_run.tscn
##
## 【为什么必须 .tscn】本探针要真实驱动物理帧 / `_process` → `_animate_model` 这条链路，
##   且 enemy.gd 以标识符方式引用 autoload `EventBus` —— `--script` 下 autoload 不注册，
##   会在**编译期**报 `Identifier not found: EventBus` 并连锁挂掉所有依赖脚本。
##
## 【本探针覆盖的断言（DESIGN-RUN §9.2）】
##   G-2  root loc（竖直分量）逐帧 ∈ [−0.0150, +0.1001] m（引擎空间）
##   G-3  root 的侧向/前进分量 ≡ 0、rotation ≡ 0
##   G-4  Run 的 key 通道白名单（root 只允许 location；rotation 轨道全 0；无 scale 轨道）
##   G-5  守卫恒 Walk（三层：档位 / speed_scale / get_playing_speed() 逐位精确相等）
##   G-5b 狼把 run_natural_speed 置 0 后也恒 Walk（回退规则）
##   G-6  狼的 Run 用自己的分母（rwant = spd / run_natural_speed，不是 / walk_natural_speed）
##   G-6b 狼的 Walk 可复现（IDLE→Walk 与 Run→Walk 回切必须给出同一个 playing）
##   G-7  Run.loop_mode == LOOP_LINEAR（识别链不能漏 _set_loop）
##   G-8  15% 滞回不抖动 + clamp 端点（run_min / run_max）可强制到精确值
##
## 【★ 明确不在这里实现（避免"同义探针各自腐烂"）】
##   G-9  walk_natural_speed / walk_max_speed_scale / run_natural_speed 的资产哨兵
##        → 归 tools/verify_enemy_wolf.gd（§9.2 的探针列指定的就是它）。
##   G-10 守卫 playing == speed_scale 的"全状态逐帧"版、G-11 死亡链路、G-12 _play_once 五链路
##        → 已由 tools/verify_playback_invariant.gd 实现（含 INV-1 头号断言）。
##        本探针**刻意不重复**它们：本项目约定"同目录下的同义探针必须合并"。
##
## 【★ 三个项目踩过的坑，本探针已按规矩避开】
##   1. 倍速断言一律**精确相等**（容差 1e-6），**禁止区间** —— β 的因子恰好 1.0，
##      落在任何"打折区间"内部，区间断言天生无法证伪（DESIGN-RUN §9.0 / 附录 C #10）。
##   2. 测倍速必有**预热相**（M-2）：先让敌人在 IDLE 停 ≥10 帧、动画系统完全上身，
##      否则测到的是"动画系统何时才被驱动"的启动时序假象（附录 C #8）。
##   3. 期望值写成**解析式**（clampf(spd/nat, ...)）或 clamp 端点常量，
##      **不写"实测值 ± 容差"**（DESIGN-RUN §9.0 M-5）。
##
## 【★ 速度怎么造（M-1：确定性强制条件）】
##   不靠"让它自己跑起来"造速度。本探针把敌人的 `_physics_process` 关掉，
##   **直接写 `enemy.velocity`**，再让 `_process → _animate_model` 读它 ——
##   这样 `spd` 是精确值，`want = clampf(spd / walk_natural_speed, ...)` 也就是精确值。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const BRUTE_TSCN := "res://scenes/enemy/enemy.tscn"

## 精确相等容差（倍速断言专用，禁止放宽成区间）。
const EPS := 1e-6
## 资产/动画轨道的数值容差（只用于 G-2/G-3/G-4 的"恒 0 / 落在带内"判定）。
const ANIM_EPS := 1e-5
## G-2 引擎空间上下界（DESIGN-RUN §4.2 E1/E2：Blender [−0.0143, +0.0953] × 1.049869）。
## 下界 −0.0143 × 1.049869 = −0.015013，比设计值 −0.0150 略低 ⇒ 给 1e-3 富余吸收换算误差。
const ROOT_Z_MIN := -0.0150
const ROOT_Z_MAX := 0.1001
const ROOT_Z_TOL := 1e-3
## 预热相（M-2）：IDLE + velocity≈0 + 动画在播，连续这么多帧才算"动画系统已上身"。
const WARMUP_MIN := 10

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


## ------------------------------------------------------------------
## 生命循环
## ------------------------------------------------------------------
func _ready() -> void:
	print("=== 狼 Run 接线验证（Walk/Run 选档 + 滞回 + Run 归一）===")
	_ground()

	var wolf := await _spawn(WOLF_TSCN, "狼")
	var brute := await _spawn(BRUTE_TSCN, "守卫")

	# --- 资产层：Run 的 root 通道（G-2/G-3/G-4）与循环标记（G-7）---
	_g2_g3_g4(wolf)
	_g7(wolf)

	# --- 行为层：档位选择（先把两条物理关掉，改为直接写 velocity）---
	_prep(wolf)
	_prep(brute)
	await _g5(brute)
	await _g6(wolf)
	await _g6b(wolf, brute)
	await _g8(wolf)
	await _g5b(wolf)

	print("")
	if _fail == 0:
		print("结论：狼 Run 接线全部通过 ✓（G-2/3/4/5/5b/6/6b/7/8）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


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


## 起一只敌人 + 预热相（M-2）。返回实例。
func _spawn(path: String, label: String) -> EnemyBrute:
	var e := (load(path) as PackedScene).instantiate() as EnemyBrute
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	# 没有玩家 ⇒ 敌人自然停在 IDLE，正好当预热相。
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
	var a2: AnimationPlayer = e.get("_anim_player")
	_check(still >= WARMUP_MIN,
		"[%s] ★ M-2 预热完成：IDLE + velocity≈0 + 动画在播 连续 ≥%d 帧" % [label, WARMUP_MIN],
		"连续 %d 帧，anim=%s" % [still, a2.current_animation if a2 != null else "<空>"])
	_check(a2 != null, "[%s] 拿到 AnimationPlayer" % label)
	return e


## M-1：关掉 AI 物理，改由探针直接写 velocity（见文件头）。
func _prep(e: EnemyBrute) -> void:
	e.set_physics_process(false)


## 推进一个"帧"：把敌人钉在 CHASE + 直接写 velocity，等 `_process` 跑完，读三个量。
## 返回 [current_animation:String, speed_scale:float, get_playing_speed():float]。
func _tick(e: EnemyBrute, spd: float) -> Array:
	e.state = EnemyBrute.State.CHASE
	e.velocity = Vector3(0.0, 0.0, -spd)
	await get_tree().process_frame
	var anim: AnimationPlayer = e.get("_anim_player")
	return [String(anim.current_animation), anim.speed_scale, anim.get_playing_speed()]


## 稳态采样（M-3）：先跑 3 帧收敛，再取连续 10 帧返回。
func _measure(e: EnemyBrute, spd: float) -> Array:
	for _i in 3:
		await _tick(e, spd)
	var out: Array = []
	for _i in 10:
		out.append(await _tick(e, spd))
	return out


## 断言这 10 帧逐帧都是 cur / speed_scale == val / get_playing_speed() == val。
func _expect(arr: Array, cur: String, val: float, label: String) -> void:
	var ok := true
	var detail := ""
	for s in arr:
		if String(s[0]) != cur or absf(float(s[1]) - val) > EPS or absf(float(s[2]) - val) > EPS:
			ok = false
			detail = "cur=%s  ss=%.6f  ps=%.6f（期望 %s / %.6f）" % [s[0], s[1], s[2], cur, val]
			break
	_check(ok, label, detail if detail != "" else "10 帧逐帧 = %s，ss==ps==%.6f" % [cur, val])


## ------------------------------------------------------------------
## G-2 / G-3 / G-4：读 Run 动画的 root 通道（导入后）
## ------------------------------------------------------------------
func _g2_g3_g4(e: EnemyBrute) -> void:
	print("\n[G-2 / G-3 / G-4] Run 的 root 通道（导入后）")
	_check(String(e.get("_run_anim")) == "Run", "狼识别 _run_anim = Run", String(e.get("_run_anim")))
	var anim: AnimationPlayer = e.get("_anim_player")
	if anim == null:
		return
	var a := anim.get_animation("Run")
	if a == null:
		_fail += 1
		print("  ✗ 拿不到 Run 动画资源")
		return

	# 模型缩放系数：enemy.gd 的 _setup_model 把模型缩放到 model_target_height / 原始总高，
	# 动画里的 root 位移是"模型局部米"，乘这个系数才是**引擎空间**（DESIGN-RUN §4.1）。
	var pivot: Node3D = e.get("_pivot")
	var model: Node3D = null
	if pivot != null and pivot.get_child_count() > 0:
		model = pivot.get_child(0) as Node3D
	var k := model.scale.y if model != null else 1.0

	var min_y := INF
	var max_y := -INF
	var pos_seen := 0
	var non_root_pos: Array = []
	var bad_xz: Array = []
	var rot_bad: Array = []
	var extra_channels: Array = []
	for ti in a.get_track_count():
		var path := str(a.track_get_path(ti))
		var is_root := path.ends_with(":root")
		var ty := a.track_get_type(ti)
		if ty == Animation.TYPE_POSITION_3D:
			if not is_root:
				non_root_pos.append(path)
				continue
			for ki in a.track_get_key_count(ti):
				var v: Vector3 = a.track_get_key_value(ti, ki)
				pos_seen += 1
				min_y = minf(min_y, v.y)
				max_y = maxf(max_y, v.y)
				# Godot 是 Y-up：竖直分量=Y；Blender 的侧向 x / 前进 y 映射到 Godot 的 x / z。
				if absf(v.x) > ANIM_EPS or absf(v.z) > ANIM_EPS:
					bad_xz.append("t=%.4f v=%s" % [a.track_get_key_time(ti, ki), str(v)])
		elif ty == Animation.TYPE_ROTATION_3D:
			if is_root:
				for ki in a.track_get_key_count(ti):
					var q: Quaternion = a.track_get_key_value(ti, ki)
					if absf(q.x) > ANIM_EPS or absf(q.y) > ANIM_EPS or absf(q.z) > ANIM_EPS \
							or absf(absf(q.w) - 1.0) > ANIM_EPS:
						rot_bad.append(str(q))
		elif ty == Animation.TYPE_SCALE_3D:
			extra_channels.append("scale 轨道：%s" % path)
		else:
			extra_channels.append("未知轨道类型 %d：%s" % [ty, path])

	var eng_min := min_y * k
	var eng_max := max_y * k
	_check(pos_seen > 0, "Run 有 root position 轨道", "关键帧 %d 个" % pos_seen)
	# G-2：root 竖直位移落在允许带内（引擎空间）。
	_check(eng_min >= ROOT_Z_MIN - ROOT_Z_TOL and eng_max <= ROOT_Z_MAX + ROOT_Z_TOL,
		"G-2 root loc（竖直）∈ [%.4f, %.4f] m（引擎空间，k=%.6f）" % [ROOT_Z_MIN, ROOT_Z_MAX, k],
		"实测 [%.6f, %.6f]" % [eng_min, eng_max])
	# G-3：无净水平位移 —— 侧向/前进分量恒 0，rotation 恒 0。
	_check(bad_xz.is_empty(), "G-3 root loc 的侧向/前进分量 ≡ 0", "" if bad_xz.is_empty() else str(bad_xz))
	_check(rot_bad.is_empty(), "G-3 root rotation ≡ 0", "" if rot_bad.is_empty() else str(rot_bad[0]))
	# G-4：通道白名单 —— root 只允许 location，非 root 骨只允许 rotation，无 scale。
	_check(non_root_pos.is_empty(), "G-4 非 root 骨没有 position 轨道", "" if non_root_pos.is_empty() else str(non_root_pos))
	_check(extra_channels.is_empty(), "G-4 没有 scale / 未知轨道", "" if extra_channels.is_empty() else str(extra_channels))


## ------------------------------------------------------------------
## G-7：Run 是循环段
## ------------------------------------------------------------------
func _g7(e: EnemyBrute) -> void:
	print("\n[G-7] Run 循环标记")
	var anim: AnimationPlayer = e.get("_anim_player")
	if anim == null:
		return
	var a := anim.get_animation("Run")
	if a == null:
		_fail += 1
		print("  ✗ 拿不到 Run 动画资源")
		return
	_check(a.loop_mode == Animation.LOOP_LINEAR,
		"G-7 Run.loop_mode == LOOP_LINEAR（_setup_animations 的 _set_loop 没漏）",
		"实际 %d" % a.loop_mode)


## ------------------------------------------------------------------
## G-5：守卫恒 Walk（三层）
## ------------------------------------------------------------------
func _g5(brute: EnemyBrute) -> void:
	print("\n[G-5] 守卫恒 Walk（档位 / 属性倍速 / 实播倍速 三层）")
	_check(String(brute.get("_run_anim")) == "", "守卫没有 Run 段（_run_anim == \"\"）", str(brute.get("_run_anim")))
	var nat := float(brute.get("walk_natural_speed"))
	var cap := float(brute.get("walk_max_speed_scale"))
	for raw in [0.5, 1.0, 1.66, 2.5, 4.2]:
		var spd := float(raw)
		var want := clampf(spd / maxf(0.2, nat), 0.4, cap)
		var arr := await _measure(brute, spd)
		_expect(arr, "Walk", want,
			"[G-5] 守卫 spd=%.4f ⇒ (i)恒 Walk (ii)(iii)ss==ps==clampf(spd/%.4f,0.4,%.1f)=%.4f" % [
				spd, nat, cap, want])


## ------------------------------------------------------------------
## G-6：狼的 Run 用自己的分母
## ------------------------------------------------------------------
func _g6(wolf: EnemyBrute) -> void:
	print("\n[G-6] 狼的 Run 归一（分母 = run_natural_speed）")
	var rnat := float(wolf.get("run_natural_speed"))
	var rmin := float(wolf.get("run_min_speed_scale"))
	var rmax := float(wolf.get("run_max_speed_scale"))
	# 常态 = 狼的 move_speed = 3.4（4.2 只是极限上界，见 DESIGN-RUN §5.4 与 v4 更正表）。
	var spd := 3.4
	var rwant := clampf(spd / maxf(0.2, rnat), rmin, rmax)
	var arr := await _measure(wolf, spd)
	_expect(arr, "Run", rwant,
		"[G-6] 狼 spd=%.4f ⇒ 播 Run，ss==ps==clampf(%.4f/%.4f, %.2f, %.2f)=%.4f" % [
			spd, spd, rnat, rmin, rmax, rwant])
	var walk_denominator := clampf(spd / float(wolf.get("walk_natural_speed")), 0.4, float(wolf.get("walk_max_speed_scale")))
	_check(absf(rwant - walk_denominator) > 1.0,
		"[G-6] Run 的倍速≠用 Walk 分母算出的值（%.4f vs %.4f）" % [rwant, walk_denominator])


## ------------------------------------------------------------------
## G-6b：狼的 Walk 可复现（四路径）
## ------------------------------------------------------------------
func _g6b(wolf: EnemyBrute, brute: EnemyBrute) -> void:
	print("\n[G-6b] 狼的 Walk 可复现（IDLE→Walk 与 Run→Walk 回切同值）")
	var wnat := float(wolf.get("walk_natural_speed"))   # 1.1724

	# 路径 A：IDLE → Walk 首次切段，spd == walk_natural_speed ⇒ playing == 1.0000
	wolf._run_latched = false
	var a_arr := await _measure(wolf, wnat)
	_expect(a_arr, "Walk", wnat / wnat,
		"[G-6b] 路径 A（IDLE→Walk，spd=%.4f）⇒ ss==ps==1.0000" % wnat)

	# 路径 B：先 spd=3.4 锁 Run，再经滞回边界降到 wnat 触发 Run→Walk 回切 ⇒ 必须同样是 1.0000。
	#   中间那一步（略低于回切速度）是**故意的**：它让"回切那一帧的 want≈2.0"暴露出来 ——
	#   若 _play_loop 被改回两层（换名帧传 speed），这一帧的 custom 会被冻结成 ≈2.0，
	#   于是回切后的 playing = want × 2.0 = 2.0 ≠ 1.0（本断言即捕获网，见 DESIGN-RUN §6.8）。
	wolf._run_latched = false
	var switch_ss := float(wolf.get("run_switch_speed_scale"))
	var hyst := float(wolf.get("run_switch_hysteresis"))
	for _i in 5:
		await _tick(wolf, 3.4)                                   # 锁 Run
	var mid_spd := switch_ss * (1.0 - hyst) * wnat * 0.98        # 略低于回切速度 ⇒ want 刚跌破 2.04
	for _i in 3:
		await _tick(wolf, mid_spd)                               # 触发 Run→Walk 回切
	var b_arr := await _measure(wolf, wnat)
	_expect(b_arr, "Walk", wnat / wnat,
		"[G-6b] 路径 B（Run→Walk 回切，回切帧 want≈%.2f）⇒ ss==ps==1.0000" % (mid_spd / wnat))

	# 路径 C（clamp 下界端点）：狼 spd=0.45（0.45/1.1724=0.3838<0.4）⇒ 0.4000；守卫 0.5 ⇒ 0.4000
	var c_wolf := await _measure(wolf, 0.45)
	_expect(c_wolf, "Walk", 0.4000, "[G-6b] 路径 C / 狼（spd=0.45，clamp 下界）⇒ ss==ps==0.4000")
	var guard_nat := float(brute.get("walk_natural_speed"))
	var c_guard := await _measure(brute, 0.5)
	_expect(c_guard, "Walk", 0.4000, "[G-6b] 路径 C / 守卫（spd=0.5，clamp 下界）⇒ ss==ps==0.4000")

	# 路径 D（clamp 上界端点，仅守卫）：spd=4.2（4.2/1.66=2.5301>2.0）⇒ 2.0000
	var d_guard := await _measure(brute, 4.2)
	_expect(d_guard, "Walk", 2.0000, "[G-6b] 路径 D / 守卫（spd=4.2，clamp 上界）⇒ ss==ps==2.0000")

	print("  · 对照：wolf walk_natural_speed=%.4f  守卫 walk_natural_speed=%.4f" % [wnat, guard_nat])


## ------------------------------------------------------------------
## G-8：滞回 + clamp 端点
## ------------------------------------------------------------------
func _g8(wolf: EnemyBrute) -> void:
	print("\n[G-8] 滞回不抖动 + Run 的 clamp 端点可强制")
	var wnat := float(wolf.get("walk_natural_speed"))
	var switch_ss := float(wolf.get("run_switch_speed_scale"))
	var switch_speed := switch_ss * wnat          # 狼：2.40 × 1.1724 = 2.8138 m/s
	var rnat := float(wolf.get("run_natural_speed"))
	var rmin := float(wolf.get("run_min_speed_scale"))
	var rmax := float(wolf.get("run_max_speed_scale"))

	# ---- 抖动：在起切速度附近 ±0.02 m/s、周期 10 帧、共 60 帧 ----
	# ★ 用**实例当前的**滞回值（不写死 0.15）：这样"把 run_switch_hysteresis 改成 0.0"的
	#   变异才能真正打到这条断言 —— 探针里写死 0.15 会把变异屏蔽掉（探针恒绿 = 不是探针）。
	var hyst := float(wolf.get("run_switch_hysteresis"))
	wolf._run_latched = false
	var last := ""
	var switches := 0
	var first := true
	for i in 60:
		var spd := switch_speed + 0.02 * sin(TAU * float(i) / 10.0)
		var r := await _tick(wolf, spd)
		var cur := String(r[0])
		if first:
			last = cur
			first = false
		elif cur != last:
			switches += 1
			last = cur
	_check(switches <= 2,
		"[G-8] 滞回：起切速度 %.4f 附近 ±0.02 m/s 抖动 60 帧，档位切换次数 ≤ 2" % switch_speed,
		"实际切换 %d 次" % switches)

	# ---- clamp 下界端点：强制 spd = run_min × run_natural_speed ⇒ playing == 0.8000 ----
	# 【为什么要"中和回切"】★ v4 数值下这个端点**经正常滞回逻辑不可达**：
	#   run_min × run_nat = 0.80 × 2.7104 = 2.1683 m/s ⇒ want = 1.8495 < 回切阈值
	#   (2.40 × 0.85 = 2.04) ⇒ 一帧就被回切成 Walk，根本进不了 Run 支路。
	#   所以按 M-1"强制构造已知条件"：显式置 _run_latched=true，并临时把滞回置 1.0
	#   （回切阈值 = 2.40 × (1−1.0) = 0 ⇒ 不再回切），从而把 Run 支路的 clamp 端点点亮。
	#   （v3 时 run_nat=3.3257 ⇒ 该端点 want≈2.27 > 2.04，天然可达；v4 Run 变慢后不可达。）
	var hyst_saved := hyst
	wolf.run_switch_hysteresis = 1.0
	wolf._run_latched = true
	var min_arr := await _measure(wolf, rmin * rnat)
	_expect(min_arr, "Run", 0.8000,
		"[G-8] clamp 下界：spd = run_min×run_nat = %.2f×%.4f = %.5f ⇒ ss==ps==0.8000" % [rmin, rnat, rmin * rnat])

	# ---- clamp 上界端点：spd = run_max × run_natural_speed ⇒ playing == 1.7500 ----
	# 这个端点在正常滞回下**可达**（want = 4.7432/1.1724 = 4.05 ≥ 2.40 ⇒ 自然锁 Run）。
	wolf.run_switch_hysteresis = hyst_saved
	wolf._run_latched = false
	var max_arr := await _measure(wolf, rmax * rnat)
	_expect(max_arr, "Run", 1.7500,
		"[G-8] clamp 上界：spd = run_max×run_nat = %.2f×%.4f = %.5f ⇒ ss==ps==1.7500" % [rmax, rnat, rmax * rnat])


## ------------------------------------------------------------------
## G-5b：狼把 Run 关掉也恒 Walk（回退规则）
## ------------------------------------------------------------------
func _g5b(wolf: EnemyBrute) -> void:
	print("\n[G-5b] 狼 run_natural_speed = 0.0 ⇒ 恒 Walk（回退规则）")
	var wnat := float(wolf.get("walk_natural_speed"))
	var cap := float(wolf.get("walk_max_speed_scale"))
	var saved := wolf.run_natural_speed
	wolf.run_natural_speed = 0.0
	# 含 3.4（若 Run 还在会播 Run 的速度）—— 关掉后必须回落到 Walk。
	for raw in [0.45, wnat, 2.5, 3.4, 4.2]:
		var spd := float(raw)
		var want := clampf(spd / maxf(0.2, wnat), 0.4, cap)
		var arr := await _measure(wolf, spd)
		_expect(arr, "Walk", want,
			"[G-5b] spd=%.4f ⇒ 恒 Walk，ss==ps==clampf(spd/%.4f,0.4,%.1f)=%.4f" % [spd, wnat, cap, want])
	wolf.run_natural_speed = saved
