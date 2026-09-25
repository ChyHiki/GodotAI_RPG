extends Node3D
## ============================================================
## QA-beta 独立测量探针：实播倍速是否 ≡ speed_scale，且**可复现**
## ============================================================
## 运行（★ 必须跑 .tscn，不能 --script；理由见 run_probes.ps1 文件头）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/qa_probe_playback_speed.tscn
##
## 【与 verify_playback_invariant.gd 的区别（刻意设计的差异，不是重复实现）】
##   实施者那支为了"稳定"用了若干夹具；本探针故意**不用**那些夹具，用真用法覆盖：
##     · ✗ 不用"每帧把玩家钉在正前方 8m"的牵绳（会掩盖转向/距离相关问题）
##       ✓ 只在追击相开头**瞬移一次**到 60m 外，之后完全交给 AI 自己追（直线、无牵制）
##     · ✗ 不把 attack_damage 改成 0（会让"挥击真的打到人"这条链路上真实缺席）
##       ✓ 保持原始伤害，用真实 AI 自己打出 WINDUP→STRIKE→RECOVER
##     · ✗ 不直接赋值 state / _stagger_time 绕过状态机
##       ✓ 走**真实入口**：take_damage() → STAGGER；deflect(0.8) → 被弹开 STAGGER；
##         连弹到失衡条满 → 真实 BROKEN（回调驱动）；血量归零 → 真实 _die()
##   ⇒ 若两支探针都绿，就同时排除了"夹具恰好让 bug 不显形"和"测量不真实"这两个方向。
##
## 【本探针打算证明/证伪的三件事】
##   Q1  每一物理帧 get_playing_speed() 是否**恒等于** speed_scale（不是"差不多"）
##   Q2  同一场景**连跑 3 次**（进程内 3 份全新实例 + 进程外跑 3 遍）结果是否逐位相同
##       —— β 之前这条是不成立的（同一二进制量到过 2.4668/1.4096/2.025/1.7431/1.0155/0.5704），
##          所以"不复现 = 没修好"，这条是整个 β 的验收核心。
##   Q3  滑移比 ≈ 1.000（画面上的脚底速度 == 身体实际速度）
##
## 【★ 为什么它**不在** run_probes.ps1 里】
##   它是"独立复核"探针，不是回归守门：与 verify_playback_invariant.gd 的 INV-1 重叠，
##   且 6 份实例 × ~900 帧跑得慢。回归守门交给后者（已在套件里）；本探针在
##   **改完倍速相关代码后手工跑一次**做交叉验证即可。⚠️ 别因为它"现在全绿"就塞进
##   套件 —— 那只会拖慢回归（项目既有约定：诊断类探针不入库）。
##
## 【★ 2026-09-24 实测结论（β 定稿后）】
##   Q1 狼 ss=ps=2.900033474 / 守卫 1.686746478，max|ps−ss| = 0.000000000000，违反 0 帧
##   Q2 两物种各连跑 3 次，DIGEST **逐字符一致**（β 前同二进制曾量到 6 个不同值）
##   Q3 滑移比 1.000000（β 前 1.743，脚比地面快 74%）
##   8 个状态全部采到样（8/8，非空真）；死亡帧 speed_scale=playing=1.0
##
## 【★ DIGEST 设计的三个坑（都踩过，别再踩）】
##   修 BUG 时"可复现性"比对比的是 DIGEST 字符串，所以它只能含**本 run 的不变式量**：
##     ① 不能含跨 run 累加计数器（once=323→648→972）⇒ 取增量
##     ② 不能含采样计数（once=323/324/325 抖 ±1，取决于攻击循环哪帧进入）
##     ③ 不能含 run 序号本身（run=0/1/2 不是"条件"）
##   三次误报都是探针自己的错，不是被测代码的错 —— 每次改完先自问"这字段是条件还是结果"。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const BRUTE_TSCN := "res://scenes/enemy/enemy.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"

## 相 A（预热）：必须在两个物种的 aggro_range（狼 13 / 守卫 11）之外 ⇒ 停在 IDLE
const FAR_DIST := 30.0
## 触发相：拉到仇恨范围内、攻击范围外 ⇒ AI 自己进 CHASE
const AGGRO_DIST := 8.0
## ★ 追击稳态相：进 CHASE 之后**只在这里瞬移一次**到 60m 外。
##   之后不再干预 ⇒ 敌人自己在一条直线上全速追 5s（约 300 帧），全程够不到 attack_range。
const CHASE_DIST := 60.0
## 攻击循环相：贴到攻击范围内 ⇒ AI 自己打出 WINDUP→STRIKE→RECOVER（真实 exprot 伤害）
const NEAR_DIST := 1.5

const WARMUP_MIN := 10        # ★ M-2：连续 10 帧 IDLE + velocity≈0 + 动画在播才算预热完
const WARMUP_MAX := 400
const CHASE_FRAMES := 300     # 追击稳态采样帧数（5s）
const STEADY_FROM := 60       # 前 60 帧是加速度爬升期，不计入"稳态"统计
const CYCLE_FRAMES := 360     # 攻击循环相（6s，够跑 3 个完整循环）
const STAGGER_FRAMES := 40    # 真实 take_damage → STAGGER(0.4s)
const PARRY_FRAMES := 60      # 真实 deflect(0.8)   → STAGGER(0.8s)
const BROKEN_FRAMES := 120    # 真实连弹到失衡条满 → BROKEN
const DEATH_FRAMES := 30      # 真实血量归零 → _die()

const RUNS := 3               # 进程内每个物种跑几份**全新**实例（可复现性）
const EPS := 1e-6             # 精确相等（不用区间：β 的因子恰好 1.0，区间断言无法证伪）

var _bad := 0            # 粗粒度断言失败数（会让 exit != 0）
var _inv_checks := 0
var _inv_viol := 0
var _once_checks := 0
var _once_bad := 0
var _seen: Dictionary = {}
var _digests: Array = []


func _stname(st: int) -> String:
	match st:
		0: return "IDLE"
		1: return "CHASE"
		2: return "WINDUP"
		3: return "STRIKE"
		4: return "RECOVER"
		5: return "STAGGER"
		6: return "BROKEN"
		7: return "DEAD"
	return "?%d" % st


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  [OK] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_bad += 1
		print("  [BAD] %s%s" % [label, ("  " + detail) if detail != "" else ""])


## Q1 的核心采样：**每一物理帧**、**包括 DEAD 在内的全部 8 个状态**，
## 只要动画在播就断言 |get_playing_speed() − speed_scale| < EPS。
## 【为什么这里不排除 DEAD】实施者那支在 _sample_inv 里写了 `if e.state != DEAD` 才计数，
##   所以它的"状态覆盖"只有 7 态、DEAD 是另一支 G-11 单独查的。本探针把 DEAD 也纳进来，
##   就是要回答"8 个状态是否**全都**被 INV-1 真的采到样"这个问题。
func _sample_inv(e: EnemyBrute, anim: AnimationPlayer, tag: String) -> void:
	if anim == null or not anim.is_playing():
		return
	_seen[e.state] = int(_seen.get(e.state, 0)) + 1
	_inv_checks += 1
	var ss := anim.speed_scale
	var ps := anim.get_playing_speed()
	if absf(ps - ss) > EPS:
		_inv_viol += 1
		if _inv_viol <= 8:
			print("  [BAD] INV 违反 [%s] state=%s anim=%s speed_scale=%.9f playing=%.9f 差=%.9f" % [
				tag, _stname(e.state), anim.current_animation, ss, ps, ps - ss])


## 单次动画链路（_play_once）：正在播的正是该动画时，断言实播倍速 == length/duration。
func _sample_once(e: EnemyBrute, anim: AnimationPlayer, anim_name: String, duration: float) -> void:
	if anim == null or anim_name == "" or duration <= 0.0 or not anim.is_playing():
		return
	if anim.current_animation != anim_name:
		return
	var a := anim.get_animation(anim_name)
	if a == null:
		return
	var spd := a.length / maxf(0.05, duration)
	_once_checks += 1
	var ps := anim.get_playing_speed()
	if absf(ps - spd) > EPS:
		_once_bad += 1
		if _once_bad <= 8:
			print("  [BAD] ONCE 违反 state=%s anim=%s length=%.6f duration=%.6f spd=%.6f playing=%.6f spd²=%.6f" % [
				_stname(e.state), anim_name, a.length, duration, spd, ps, spd * spd])


func _seen_str() -> String:
	var parts: Array = []
	for st in [0, 1, 2, 3, 4, 5, 6, 7]:
		parts.append("%s=%d" % [_stname(st), int(_seen.get(st, 0))])
	return " ".join(parts)


func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(400.0, 1.0, 400.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)


func _ready() -> void:
	print("=== QA-beta 独立测量：实播倍速 ≡ speed_scale ? 可复现吗? 滑移比? ===")
	# ★ 本文件禁止写 %.Ne：Godot 4 的 String % 运算符**不支持 e/E 格式符**，
	#   一旦出现会 push_error 并**原样返回格式串**（不抛异常、不中断），
	#   结果就是"打印出来的不是数字而是 %s run=%d ..."——极易被误读成"探针坏了"。
	#   （本探针 v1 就栽在这上面：DIGEST 退化成格式串 → begins_with("wolf") 恒假
	#    → wolf_d 为空 → line 161 越界退出 1。）小数值一律用 %.12f 代替科学计数法。
	print("physics_ticks_per_second=%d  EPS=%.12f  RUNS=%d" % [Engine.physics_ticks_per_second, EPS, RUNS])
	_ground()

	for r in RUNS:
		await _run_species(WOLF_TSCN, "wolf", r)
		await _run_species(BRUTE_TSCN, "brute", r)

	# ---------------- 可复现性比对（进程内） ----------------
	print("\n================ 可复现性（进程内 %d 份全新实例）================" % RUNS)
	var wolf_d: Array = []
	var brute_d: Array = []
	for d in _digests:
		if String(d).begins_with("wolf"):
			wolf_d.append(d)
		else:
			brute_d.append(d)
	# ★ 用 _check 而不是裸 print：可复现性（Q2）是 β 的验收核心，必须能让 exit != 0。
	#   v1 只 print 不判定，且 wolf_d[i] 在数组为空时直接越界崩溃（exit=1 但原因被掩盖）。
	for tag in ["wolf", "brute"]:
		var arr: Array = wolf_d if tag == "wolf" else brute_d
		for i in arr.size():
			print("  %s run %d | %s" % [tag, i, str(arr[i])])
		var same := arr.size() == RUNS
		if same:
			for i in range(1, arr.size()):
				if str(arr[i]) != str(arr[0]):
					same = false
					break
		_check(same and arr.size() == RUNS,
			"★ Q2：%s 连跑 %d 次 DIGEST 逐字符一致（β 前这条不成立：同二进制量到过 6 个不同值）" % [tag, RUNS],
			"实得 %d 份：%s" % [arr.size(), ("完全一致" if same else "★ 出现分歧")])
	_check(_inv_viol == 0, "全局 INV-1：每帧 get_playing_speed() == speed_scale",
		"采样 %d 帧，违反 %d 帧" % [_inv_checks, _inv_viol])
	_check(_once_bad == 0, "全局 ONCE：_play_once 链路实播倍速 == length/duration",
		"采样 %d 帧，违反 %d 帧" % [_once_checks, _once_bad])

	print("")
	print("DIGEST-FINAL bad=%d inv_checks=%d inv_viol=%d once_checks=%d once_bad=%d" % [
		_bad, _inv_checks, _inv_viol, _once_checks, _once_bad])
	if _bad == 0:
		print("结论：QA-beta 独立测量全部通过 ✓")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _bad)
		get_tree().quit(1)


func _run_species(path: String, label: String, run: int) -> void:
	print("\n========== [%s] run=%d ==========" % [label, run])
	_seen = {}
	# ★ DIGEST 只允许放"只依赖本 run"的量。_inv_viol / _once_checks / _once_bad 是
	#   **跨 run 累加**的全局计数器；v1 直接把它们写进 DIGEST，导致 3 份 DIGEST
	#   必然互不相同（once=324 → 648 → 972），可复现性断言恒假 —— 是探针的错，
	#   不是被测代码的错。这里在 run 开头取基线，DIGEST 只写**本 run 增量**。
	var base_viol := _inv_viol
	var base_once := _once_checks
	var base_once_bad := _once_bad

	var e := (load(path) as PackedScene).instantiate() as EnemyBrute
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as Node3D
	player.position = Vector3(0.0, 0.1, -FAR_DIST)
	add_child(player)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var anim: AnimationPlayer = e.get("_anim_player")
	var natural := float(e.get("walk_natural_speed"))
	var cap := float(e.get("walk_max_speed_scale"))
	var ms := float(e.get("move_speed"))
	print("  move_speed=%.4f  walk_natural_speed=%.6f  walk_max_speed_scale=%.2f  anim_blend_time=%.3f" % [
		ms, natural, cap, float(e.get("anim_blend_time"))])
	print("  aggro_range=%.1f  attack_range=%.2f  windup=%.2f  strike=%.2f  recover=%.2f  stagger=%.2f" % [
		float(e.get("aggro_range")), float(e.get("attack_range")), float(e.get("windup_time")),
		float(e.get("strike_time")), float(e.get("recover_time")), float(e.get("stagger_time"))])
	_check(anim != null, "拿到 AnimationPlayer")
	if anim == null:
		return

	# ================= 相 A：★ M-2 预热 =================
	var still := 0
	var warm_frames := 0
	for _i in WARMUP_MAX:
		await get_tree().physics_frame
		warm_frames += 1
		var hs := Vector2(e.velocity.x, e.velocity.z).length()
		if e.state == EnemyBrute.State.IDLE and hs < 0.01 and anim.is_playing():
			still += 1
		else:
			still = 0
		_sample_inv(e, anim, "warmup")
		if still >= WARMUP_MIN:
			break
	_check(still >= WARMUP_MIN, "★ 预热完成（IDLE+velocity≈0+动画在播 连续≥%d 帧）" % WARMUP_MIN,
		"连续 %d 帧 / 共 %d 帧，anim=%s，ss=%.6f ps=%.6f" % [
			still, warm_frames, anim.current_animation, anim.speed_scale, anim.get_playing_speed()])

	# ================= 相 B：让 AI 自己进 CHASE =================
	player.position = e.position + Vector3(0.0, 0.0, -AGGRO_DIST)
	var entered := -1
	for i in 200:
		await get_tree().physics_frame
		_sample_inv(e, anim, "aggro")
		if e.state == EnemyBrute.State.CHASE:
			entered = i
			break
	_check(entered >= 0, "AI 自己进入 CHASE", "在第 %d 帧" % entered)

	# ================= 相 C：★ 追击稳态（只在这里瞬移一次，之后完全不干预）=================
	player.position = e.position + Vector3(0.0, 0.0, -CHASE_DIST)
	print("  --- 追击稳态相：玩家瞬移到 %.0fm 外，之后 %d 帧完全不干预 ---" % [CHASE_DIST, CHASE_FRAMES])
	var n_steady := 0
	var max_diff := 0.0
	var ss_min := 1e9
	var ss_max := -1e9
	var ps_last := 0.0
	var ss_last := 0.0
	var hs_last := 0.0
	var slide_last := 0.0
	var distinct: Dictionary = {}
	var vbefore := _inv_viol
	var first := run == 0
	if first:
		print("  frame | state  | anim           | speed_scale | playing      | |ps-ss|     | body_spd | slide")
	for i in CHASE_FRAMES:
		await get_tree().physics_frame
		var ss := anim.speed_scale
		var ps := anim.get_playing_speed()
		var hs := Vector2(e.velocity.x, e.velocity.z).length()
		_sample_inv(e, anim, "chase")
		if anim.is_playing() and e.state == EnemyBrute.State.CHASE:
			var d := absf(ps - ss)
			max_diff = maxf(max_diff, d)
			if i >= STEADY_FROM:
				n_steady += 1
				ss_min = minf(ss_min, ss)
				ss_max = maxf(ss_max, ss)
				ss_last = ss
				ps_last = ps
				hs_last = hs
				slide_last = (ps * natural / hs) if hs > 0.001 else 0.0
				distinct[snappedf(ss, 1e-9)] = true
		if first and (i < 6 or i < 40 or i % 20 == 0 or i == CHASE_FRAMES - 1):
			print("  %5d | %-6s | %-14s | %11.6f | %12.6f | %10.9f | %8.4f | %6.3f" % [
				i, _stname(e.state), anim.current_animation, ss, ps,
				absf(ps - ss), hs, (ps * natural / hs) if hs > 0.001 else 0.0])

	var want := clampf(hs_last / maxf(0.2, natural), 0.4, cap)
	print("  稳态窗口 = 第 %d~%d 帧（%d 帧）" % [STEADY_FROM, CHASE_FRAMES - 1, n_steady])
	print("    body 水平速度      = %.6f m/s（move_speed=%.4f，差 %.6f）" % [hs_last, ms, absf(hs_last - ms)])
	print("    want = clamp(body/natural) = %.9f" % want)
	print("    speed_scale  最后一帧 = %.9f，稳态区间 [%.9f, %.9f]，取值个数 %d" % [
		ss_last, ss_min, ss_max, distinct.size()])
	print("    playing      最后一帧 = %.9f" % ps_last)
	print("    max |ps − ss|      = %.12f  （EPS=%.12f）" % [max_diff, EPS])
	print("    滑移比 slide = playing × natural ÷ body = %.6f" % slide_last)
	_check(_inv_viol - vbefore == 0, "★ INV-1：追击稳态相每帧成立",
		"%d 帧内违反 %d 次" % [CHASE_FRAMES, _inv_viol - vbefore])
	_check(max_diff <= EPS, "★ Q1：追击稳态 max|playing − speed_scale| ≤ EPS",
		"max=%.12f" % max_diff)
	_check(absf(ss_last - want) <= 1e-6, "★ speed_scale 等于按身体速度算出的 want",
		"ss=%.9f want=%.9f" % [ss_last, want])
	_check(absf(ps_last - want) <= 1e-6, "★ 实播倍速等于 want（== move_speed/natural，未 clamping）",
		"ps=%.9f want=%.9f" % [ps_last, want])
	_check(absf(slide_last - 1.0) <= 0.005, "★ Q3：滑移比 ≈ 1.000", "%.6f" % slide_last)

	# ================= 相 D：真实 AI 攻击循环（不置 0 伤害、不绑玩家）=================
	player.position = e.position + Vector3(0.0, 0.0, -NEAR_DIST)
	var obefore := _once_bad
	var vbefore2 := _inv_viol
	var player_died := false
	var cframes := 0
	for i in CYCLE_FRAMES:
		await get_tree().physics_frame
		cframes += 1
		_sample_inv(e, anim, "cycle")
		if e.state == EnemyBrute.State.WINDUP:
			_sample_once(e, anim, String(e.get("_windup_anim")), float(e.get("windup_time")))
		elif e.state == EnemyBrute.State.STRIKE:
			_sample_once(e, anim, String(e.get("_attack_anim")), float(e.get("strike_time")))
		if is_instance_valid(player) and player.has_method("is_alive"):
			if not bool(player.call("is_alive")):
				player_died = true
				break
	_check(true, "攻击循环相跑了 %d 帧，玩家中途阵亡=%s" % [cframes, player_died])
	_check(not player_died, "夹具健康：攻击循环期间玩家没被打死（否则 target=null 会让 AI 回 IDLE）")
	_check(_inv_viol - vbefore2 == 0, "★ INV-1：真实攻击循环每帧成立", "违反 %d 次" % (_inv_viol - vbefore2))
	_check(_once_checks > 0 and _once_bad - obefore == 0,
		"★ ONCE：WINDUP/STRIKE 真实链路实播倍速 == length/duration",
		"本次新增不符 %d 次" % (_once_bad - obefore))
	_check(int(_seen.get(2, 0)) > 0 and int(_seen.get(3, 0)) > 0 and int(_seen.get(4, 0)) > 0,
		"真实路径覆盖到 WINDUP/STRIKE/RECOVER",
		"WINDUP=%d STRIKE=%d RECOVER=%d" % [int(_seen.get(2, 0)), int(_seen.get(3, 0)), int(_seen.get(4, 0))])

	# ================= 相 E：真实 STAGGER（take_damage，不是直接赋值 state）=================
	player.position = e.position + Vector3(0.0, 0.0, -FAR_DIST)
	await get_tree().physics_frame
	var from_pos := e.global_position + Vector3(0.0, 0.0, -2.0)
	e.take_damage(1, from_pos)
	_check(e.state == EnemyBrute.State.STAGGER, "真实 take_damage() → STAGGER", "state=%s" % _stname(e.state))
	var vbefore3 := _inv_viol
	var hit_anim: String = String(e.get("_hit_anim"))
	for _i in STAGGER_FRAMES:
		await get_tree().physics_frame
		_sample_inv(e, anim, "stagger")
		if e.state == EnemyBrute.State.STAGGER:
			_sample_once(e, anim, hit_anim, e._stagger_time)
	_check(_inv_viol - vbefore3 == 0, "★ INV-1：真实 STAGGER 每帧成立", "违反 %d 次" % (_inv_viol - vbefore3))

	# ================= 相 F：真实被完美格挡 STAGGER(0.8s)（deflect 入口）=================
	e.deflect(0.8, from_pos)
	_check(e._stagger_time - 0.8 < 1e-9, "真实 deflect(0.8) → _stagger_time=0.8", "%.4f" % e._stagger_time)
	var vbefore4 := _inv_viol
	for _i in PARRY_FRAMES:
		await get_tree().physics_frame
		_sample_inv(e, anim, "parry")
		if e.state == EnemyBrute.State.STAGGER:
			_sample_once(e, anim, hit_anim, e._stagger_time)
	_check(_inv_viol - vbefore4 == 0, "★ INV-1：真实被弹开 STAGGER(0.8s) 每帧成立",
		"违反 %d 次" % (_inv_viol - vbefore4))

	# ================= 相 G：真实 BROKEN（连弹到失衡条满，回调驱动）=================
	var guard := 0
	while guard < 8 and (e.poise == null or not e.poise.is_broken()):
		e.deflect(0.8, from_pos)
		guard += 1
		await get_tree().physics_frame
	_check(e.state == EnemyBrute.State.BROKEN, "真实连弹到失衡 → BROKEN", "state=%s 弹了%d次" % [_stname(e.state), guard])
	var vbefore5 := _inv_viol
	for _i in BROKEN_FRAMES:
		await get_tree().physics_frame
		_sample_inv(e, anim, "broken")
		if e.state == EnemyBrute.State.BROKEN:
			_sample_once(e, anim, hit_anim, 0.6)
	_check(_inv_viol - vbefore5 == 0, "★ INV-1：真实 BROKEN 每帧成立", "违反 %d 次" % (_inv_viol - vbefore5))

	# ================= 相 H：真实死亡（血量归零 → _die()）=================
	e.take_damage(99999, from_pos)
	_check(e.state == EnemyBrute.State.DEAD, "真实血量归零 → DEAD")
	if anim != null:
		print("  死亡帧：anim=%s speed_scale=%.9f playing=%.9f" % [
			anim.current_animation, anim.speed_scale, anim.get_playing_speed()])
		var worst := 0.0
		var dn := 0
		for _i in DEATH_FRAMES:
			await get_tree().physics_frame
			_sample_inv(e, anim, "death")
			if anim.is_playing():
				dn += 1
				worst = maxf(worst, absf(anim.get_playing_speed() - 1.0))
		_check(dn > 0 and worst <= EPS, "★ DEAD：实播倍速恒 == 1.0（自然速度）",
			"采样 %d 帧，最大偏离 %.12f" % [dn, worst])

	# ================= 本 run 的状态覆盖 + digest =================
	var need := [0, 1, 2, 3, 4, 5, 6, 7]
	var missing: Array = []
	for st in need:
		if int(_seen.get(st, 0)) <= 0:
			missing.append(_stname(st))
	print("  状态采样分布（含 DEAD）：%s" % _seen_str())
	_check(missing.is_empty(), "★ 8 个状态全部采到样（不放过空真）",
		("缺 " + ", ".join(missing)) if not missing.is_empty() else "8/8")

	# ★ DIGEST 只放"不变式量"，**不放采样计数**（v2 又踩了一次）：
	#   once=323 / 324 / 325 逐 run 抖 ±1 —— 那是"攻击循环恰好在哪一帧进入"决定的采样帧数，
	#   天然浮动，不是被测不变量。写进 DIGEST 会让可复现性断言恒假（假红）。
	#   违反数（viol / once_bad）才是真不变量，恒为 0，必须保留。
	# ★ DIGEST 里**不能带 run 序号**（v3 才发现的第三个坑）：Q2 要比对的是
	#   "同样条件是否得到同样结果"，run=0/1/2 只标识第几次跑，不是条件本身；
	#   写进 DIGEST 会让逐字符比对 100% 分歧。序号在汇总行里另外打印即可。
	var dig := "%s steady_n=%d maxdiff=%.12f ss=%.9f ps=%.9f want=%.9f body=%.6f slide=%.6f viol=%d once_bad=%d" % [
		label, n_steady, max_diff, ss_last, ps_last, want, hs_last, slide_last,
		_inv_viol - base_viol, _once_bad - base_once_bad]
	print("  DIGEST %s run=%d" % [dig, run])
	_digests.append(dig)

	player.free()
	if is_instance_valid(e):
		e.free()
