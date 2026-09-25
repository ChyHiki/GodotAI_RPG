extends Node
## ============================================================
## ★ 动画倍速不变式验证器（方案 β 的常驻回归守门）
## ============================================================
## 运行（★ 跑场景，不是 --script；原因见 verify_wolf_hitbox.gd 顶部：
##   --script 不注册 autoload，而 enemy.gd:699 以标识符方式用 EventBus，会**编译期**失败）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_playback_invariant.tscn
##
## 【背景：β 修了什么】Godot 的实播倍速 = 属性 speed_scale × play() 的第 4 参 custom_speed
##   （两个独立因子相乘）。旧代码是"两层"写法：换名那一帧把倍速当 custom_speed 传给 play()
##   （custom 就此**冻结**），之后每帧只改 speed_scale ⇒ 实播倍速既不等于想要的倍速，也
##   **不可复现**（同一场景同一二进制实测到 2.4668 / 1.4096 / 2.025 / 1.0155 / 0.5704）。
##   β：play() 的 custom_speed 恒传 1.0，倍速的唯一真源是 speed_scale ⇒
##      get_playing_speed() ≡ speed_scale（单层、可复现）。
##
## 【本验证器钉死的三条不变式】
##   INV-1（头号）：**每一物理帧**、**两个物种**、状态覆盖
##       {IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, BROKEN}
##       只要 _anim_player.is_playing()，就必须 |get_playing_speed() − speed_scale| < 1e-6。
##       ⟺ custom ≡ 1.0。这条**完整刻画 β**，且能精确证伪任何"只改一半"的实现：
##         · 若 play() 仍传 speed        ⇒ playing = speed² ≠ speed_scale（首帧即红）
##         · 若 speed_scale 写在 else 里 ⇒ 换名那一帧 playing = 旧 speed_scale × 1.0（红）
##         · 若两处都写但漏了某条链路    ⇒ 该链路首帧即红
##   G-11：死亡链路不受影响 —— 狼 Death length == 1.0417、守卫 == 1.2917，
##         且死亡时实播倍速 == 1.0（_die() 本来就写对了：两个因子都显式设 1.0）。
##   G-12：_play_once 的链路实播倍速必须 **== spd**（不是 spd²），
##         spd = length / maxf(0.05, duration)。
##         覆盖五条：WINDUP(windup_time) / STRIKE(strike_time) /
##                   STAGGER(_stagger_time=0.4) / STAGGER-被完美格挡(_stagger_time=0.8) /
##                   BROKEN(0.6)。
##
## 【★ 为什么测速度前必须先"预热相"（M-2）】
##   不预热的话，headless 下动画系统要晚几帧才被驱动（曾实测晚 6 帧），首次 play("Walk")
##   发生在速度已经爬起来之后 ⇒ 测到的是**启动时序假象**，不是倍速语义。
##   故必须等敌人停在 IDLE 且 velocity≈0 **连续 ≥10 帧**、动画系统完全上身，再拉近触发。
##
## 【★ 为什么禁止用区间做倍速断言】
##   β 的因子恰好 = 1.0，落在任何"打折区间"内部 ⇒ 区间断言**天生无法证伪**
##   （v2 就有一条恒绿的死断言）。所以这里一律用：
##     (a) 精确相等（|a − b| < 1e-6），或
##     (b) 确定性强制条件 + 精确期望值：把 move_speed 临时调到使 want 落在 clamp 端点
##         （下限 0.4 / 上限 walk_max_speed_scale）⇒ 期望值精确、且不可能靠区间蒙混。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const BRUTE_TSCN := "res://scenes/enemy/enemy.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"

## ★ INV-1 的容差：精确相等（不是区间）。β 的两个因子都是双精度，实测差为 0.0。
const INV_EPS := 1e-6
## 相 A：玩家摆这么远 ⇒ 敌人停在 IDLE（wolf aggro 13 / brute aggro 11）。
const FAR_DIST := 30.0
## 相 B：拉近到这个距离 ⇒ 进 CHASE，并在覆盖相里自然打出 WINDUP→STRIKE→RECOVER。
## 比 attack_range(2.0/2.3) 大、比 aggro_range 小 ⇒ 先追一段再出手。
const NEAR_DIST := 5.0
## clamp 端点实验里玩家每帧被钉在这个偏移上 ⇒ 敌人永远追不到，稳定停在 CHASE。
const CHASE_LEASH := 8.0
const WARMUP_MIN := 10      # ★ M-2：IDLE + velocity≈0 + 动画在播，需连续这么多帧
const WARMUP_MAX := 300
const COVER_FRAMES := 600   # 覆盖相长度（10s，足够跑完若干个攻击循环）
const DEATH_SAMPLE := 20    # 死亡后采样帧数（Death 1.0417s ≈ 62 帧，够）

var _fail := 0
var _viol := 0          # INV-1 累计违反次数
var _viol_prints := 0   # 只打印前若干条，避免刷屏
var _seen: Dictionary = {}   # 当前物种已覆盖到的 state int -> 帧数


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


## INV-1 采样：只要动画在播，就断言 get_playing_speed() ≡ speed_scale。
func _sample_inv(e: EnemyBrute, anim: AnimationPlayer, _tag: String) -> void:
	if anim == null or not anim.is_playing():
		return
	if e.state != EnemyBrute.State.DEAD:
		_seen[e.state] = int(_seen.get(e.state, 0)) + 1
	var ss := anim.speed_scale
	var ps := anim.get_playing_speed()
	if absf(ps - ss) > INV_EPS:
		_viol += 1
		if _viol_prints < 6:
			_viol_prints += 1
			print("  ✗ INV-1 违反 [%s] state=%s anim=%s  speed_scale=%.6f  playing=%.6f  差=%.6f" % [
				_tag, _state_name(e.state), anim.current_animation, ss, ps, ps - ss])


func _state_name(st: int) -> String:
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


func _ready() -> void:
	print("=== 动画倍速不变式验证（方案 β：实播倍速 ≡ speed_scale）===")
	_ground()

	await _run_species(WOLF_TSCN, "狼 wolf")
	await _run_species(BRUTE_TSCN, "红甲守卫 brute")

	# ---- G-11：死亡链路（用全新实例，避免受前面夹具污染）----
	await _check_death(WOLF_TSCN, "狼", 1.0417)
	await _check_death(BRUTE_TSCN, "守卫", 1.2917)

	print("")
	if _fail == 0:
		print("结论：β 不变式全部成立 ✓（INV-1 / G-11 / G-12）")
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


func _spawn_player(dist: float) -> Node3D:
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as Node3D
	player.position = Vector3(0.0, 0.1, -dist)
	add_child(player)
	return player


## ------------------------------------------------------------------
## 单物种全流程：预热 → 覆盖相（CHASE/WINDUP/STRIKE/RECOVER）→ STAGGER×2 → BROKEN
##             → CHASE clamp 端点精确值实验 → 状态覆盖自检
## ------------------------------------------------------------------
func _run_species(path: String, label: String) -> void:
	print("\n========== [%s] ==========" % label)
	_seen = {}

	var e := (load(path) as PackedScene).instantiate() as EnemyBrute
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	var player := _spawn_player(FAR_DIST)
	# 夹具：覆盖相要跑 10s，不想让玩家被打死（玩家一死 target=null ⇒ 敌人回 IDLE，
	# 覆盖相就白跑了）。伤害置 0 只影响本次实例，不碰任何资产文件。
	e.attack_damage = 0

	await get_tree().physics_frame
	await get_tree().physics_frame

	var anim: AnimationPlayer = e.get("_anim_player")
	_check(anim != null, "[%s] 拿到 AnimationPlayer" % label)
	if anim == null:
		return

	# ================= 相 A：★ M-2 预热 =================
	var still := 0
	for _i in WARMUP_MAX:
		await get_tree().physics_frame
		var hs := Vector2(e.velocity.x, e.velocity.z).length()
		if e.state == EnemyBrute.State.IDLE and hs < 0.01 and anim.is_playing():
			still += 1
		else:
			still = 0
		_sample_inv(e, anim, "warmup")
		if still >= WARMUP_MIN:
			break
	_check(still >= WARMUP_MIN,
		"[%s] ★ M-2 预热完成：IDLE + velocity≈0 + 动画在播 连续 ≥%d 帧" % [label, WARMUP_MIN],
		"连续 %d 帧，anim=%s" % [still, anim.current_animation])

	# ================= 相 B：覆盖相（自然追击 + 攻击循环）=================
	player.position = Vector3(0.0, 0.1, -NEAR_DIST)
	var before := _viol
	var windup_acc := _OnceSample.new()
	var strike_acc := _OnceSample.new()
	for _i in COVER_FRAMES:
		await get_tree().physics_frame
		_sample_inv(e, anim, "cover")
		if e.state == EnemyBrute.State.WINDUP:
			_g12(e, anim, String(e.get("_windup_anim")), float(e.get("windup_time")), windup_acc)
		elif e.state == EnemyBrute.State.STRIKE:
			_g12(e, anim, String(e.get("_attack_anim")), float(e.get("strike_time")), strike_acc)
	print("  覆盖相 state 分布：%s" % _seen_str())
	_check(_viol - before == 0, "[%s] ★ INV-1：覆盖相每帧成立（%d 帧）" % [label, COVER_FRAMES],
		"违反 %d 次" % (_viol - before))
	_check(windup_acc.n > 0, "[%s] G-12：抓到 WINDUP 链路样本" % label, "%d 帧" % windup_acc.n)
	_check(windup_acc.n > 0 and windup_acc.bad == 0,
		"[%s] ★ G-12：WINDUP 实播倍速 == spd（不是 spd²）" % label,
		"样本 %d 帧，不符 %d 帧，末次 spd=%.6f playing=%.6f" % [
			windup_acc.n, windup_acc.bad, windup_acc.last_want, windup_acc.last_got])
	_check(strike_acc.n > 0, "[%s] G-12：抓到 STRIKE 链路样本" % label, "%d 帧" % strike_acc.n)
	_check(strike_acc.n > 0 and strike_acc.bad == 0,
		"[%s] ★ G-12：STRIKE 实播倍速 == spd（不是 spd²）" % label,
		"样本 %d 帧，不符 %d 帧，末次 spd=%.6f playing=%.6f" % [
			strike_acc.n, strike_acc.bad, strike_acc.last_want, strike_acc.last_got])

	# ================= 相 C：STAGGER（普通受击 0.4s）=================
	before = _viol
	var stg := _OnceSample.new()
	e.state = EnemyBrute.State.STAGGER
	e._state_time = 0.0
	e._stagger_time = float(e.get("stagger_time"))
	_check(absf(e._stagger_time - 0.4) < 1e-9, "[%s] 夹具：_stagger_time == stagger_time(0.4)" % label,
		"%.4f" % e._stagger_time)
	for _i in 20:
		await get_tree().physics_frame
		_sample_inv(e, anim, "stagger")
		if e.state == EnemyBrute.State.STAGGER:
			_g12(e, anim, String(e.get("_hit_anim")), e._stagger_time, stg)
	_check(_viol - before == 0, "[%s] ★ INV-1：STAGGER(0.4s) 每帧成立" % label,
		"违反 %d 次" % (_viol - before))
	_check(stg.n > 0 and stg.bad == 0, "[%s] ★ G-12：STAGGER(0.4s) 实播倍速 == spd" % label,
		"样本 %d 帧，不符 %d，spd=%.6f playing=%.6f" % [stg.n, stg.bad, stg.last_want, stg.last_got])

	# ================= 相 D：STAGGER（被完美格挡 0.8s）=================
	before = _viol
	var parry := _OnceSample.new()
	e.state = EnemyBrute.State.STAGGER
	e._state_time = 0.0
	e._stagger_time = 0.8     # 完美格挡的硬直（player.gd 的 block_parry_stagger 默认值）
	for _i in 40:
		await get_tree().physics_frame
		_sample_inv(e, anim, "parry-stagger")
		if e.state == EnemyBrute.State.STAGGER:
			_g12(e, anim, String(e.get("_hit_anim")), e._stagger_time, parry)
	_check(_viol - before == 0, "[%s] ★ INV-1：STAGGER(0.8s 被弹开) 每帧成立" % label,
		"违反 %d 次" % (_viol - before))
	_check(parry.n > 0 and parry.bad == 0, "[%s] ★ G-12：STAGGER(0.8s 被弹开) 实播倍速 == spd" % label,
		"样本 %d 帧，不符 %d，spd=%.6f playing=%.6f" % [parry.n, parry.bad, parry.last_want, parry.last_got])

	# ================= 相 E：BROKEN（_play_once(_hit_anim, 0.6)）=================
	before = _viol
	var brk := _OnceSample.new()
	if e.poise != null:
		e.poise.percent(100.0)     # 顶满失衡 → broken_started → state=BROKEN
	await get_tree().physics_frame
	_check(e.state == EnemyBrute.State.BROKEN, "[%s] 已进入 BROKEN" % label, "state=%d" % e.state)
	for _i in 30:
		await get_tree().physics_frame
		_sample_inv(e, anim, "broken")
		if e.state == EnemyBrute.State.BROKEN:
			_g12(e, anim, String(e.get("_hit_anim")), 0.6, brk)
	_check(_viol - before == 0, "[%s] ★ INV-1：BROKEN 每帧成立" % label, "违反 %d 次" % (_viol - before))
	_check(brk.n > 0 and brk.bad == 0, "[%s] ★ G-12：BROKEN 实播倍速 == spd" % label,
		"样本 %d 帧，不符 %d，spd=%.6f playing=%.6f" % [brk.n, brk.bad, brk.last_want, brk.last_got])

	# ================= 相 F：CHASE 的 clamp 端点（确定性强制条件 + 精确期望值）=================
	# 【为什么还要这一段】INV-1 只钉死"两个量相等"，没钉死"等于多少"；
	#   若有人把 speed_scale 的写入整个删掉（恒为默认 1.0），INV-1 仍然"相等"而绿。
	#   这里把 move_speed 调到使 want 落在 clamp 的两个端点上 ⇒ 期望值是**精确常数**，
	#   且必然 ≠ 1.0 ⇒ 既能证伪"没写 speed_scale"，也天然免疫区间蒙混。
	var natural := float(e.get("walk_natural_speed"))
	var cap := float(e.get("walk_max_speed_scale"))
	await _check_chase_endpoint(e, anim, player, label, "下限", 0.4 * natural * 0.98, 0.4, natural)
	await _check_chase_endpoint(e, anim, player, label, "上限", cap * natural * 1.05, cap, natural)

	# ================= 状态覆盖 =================
	var need := [EnemyBrute.State.IDLE, EnemyBrute.State.CHASE, EnemyBrute.State.WINDUP,
		EnemyBrute.State.STRIKE, EnemyBrute.State.RECOVER, EnemyBrute.State.STAGGER,
		EnemyBrute.State.BROKEN]
	var missing: Array = []
	for st in need:
		if not _seen.has(st):
			missing.append(_state_name(st))
	_check(missing.is_empty(), "[%s] ★ 状态覆盖 {IDLE,CHASE,WINDUP,STRIKE,RECOVER,STAGGER,BROKEN}" % label,
			("缺 " + ", ".join(missing)) if not missing.is_empty() else "7/7")

	player.free()
	e.free()


## 把敌人钉在 CHASE（玩家每帧被牵到正前方 CHASE_LEASH 米处 ⇒ 追不到，不会进 WINDUP），
## 速度收敛后 want 必被 clamp 到 target ⇒ 实播倍速必须**精确等于** target。
func _check_chase_endpoint(e: EnemyBrute, anim: AnimationPlayer, player: Node3D, label: String,
		which: String, move_speed: float, target: float, natural: float) -> void:
	e.move_speed = move_speed
	e.state = EnemyBrute.State.CHASE
	e._state_time = 0.0
	# ★ T08（Run 段接线后）：本用例只钉 **Walk** 的 clamp 端点（下限 0.4 / 上限 walk_max_speed_scale）。
	#   狼的 Walk 上限端点 want == 3.8 ≥ 起切阈值 2.40，在有 Run 时会**合法地**切到 Run，
	#   于是下面 `current_animation != _walk_anim` 永远命中、永远等不到 Walk 样本（body 恒 0）。
	#   故本用例**临时关掉 Run**（run_natural_speed = 0.0）⇒ 恒 Walk，语义与"加 Run 之前"逐位一致。
	#   狼的 **Run** clamp 端点（0.80 / 1.75）改由 tools/verify_wolf_run.gd 的 G-8 单独覆盖。
	#   （守卫 `_run_anim == ""`，本行对它无影响。）
	e.run_natural_speed = 0.0
	var ok := false
	var got := 0.0
	var body := 0.0
	var frames := 0
	for _i in 400:
		await get_tree().physics_frame
		frames += 1
		# 牵绳：玩家恒在正前方 CHASE_LEASH 米 ⇒ 敌人稳定停在 CHASE
		player.global_position = e.global_position + Vector3(0.0, 0.0, -CHASE_LEASH)
		_sample_inv(e, anim, "chase-%s" % which)
		if e.state != EnemyBrute.State.CHASE or not anim.is_playing():
			continue
		if anim.current_animation != String(e.get("_walk_anim")):
			continue
		var hs := Vector2(e.velocity.x, e.velocity.z).length()
		# 速度收敛（相对误差 <2%）才判定，避免拿爬升期的瞬时值下结论
		if hs < 0.4 or absf(hs - move_speed) > 0.02 * maxf(0.001, move_speed):
			continue
		got = anim.get_playing_speed()
		body = hs
		if absf(got - target) <= INV_EPS:
			ok = true
			break
	_check(ok, "[%s] ★ CHASE clamp %s：want 被强制到 %.4f ⇒ 实播倍速精确 == %.4f" % [
			label, which, target, target],
		"move_speed=%.4f  身体速度=%.4f  want=%.4f  实测 playing=%.6f（%d 帧内）" % [
			move_speed, body, clampf(body / maxf(0.2, natural), 0.4, float(e.get("walk_max_speed_scale"))),
			got, frames])


## G-12 采样：当正在播的正是这条链路期望的动画时，断言实播倍速 == spd。
func _g12(e: EnemyBrute, anim: AnimationPlayer, anim_name: String, duration: float, acc) -> void:
	if anim_name == "" or not anim.is_playing():
		return
	if anim.current_animation != anim_name:
		return
	var a := anim.get_animation(anim_name)
	if a == null or duration <= 0.0:
		return
	var spd := a.length / maxf(0.05, duration)
	acc.n += 1
	acc.last_want = spd
	acc.last_got = anim.get_playing_speed()
	if absf(acc.last_got - spd) > INV_EPS:
		acc.bad += 1
		if acc.bad <= 2:
			print("  ✗ G-12 违反：anim=%s  length=%.4f  duration=%.4f  spd=%.6f  playing=%.6f  spd²=%.6f" % [
				anim_name, a.length, duration, spd, acc.last_got, spd * spd])


func _seen_str() -> String:
	var parts: Array = []
	for st in [0, 1, 2, 3, 4, 5, 6, 7]:
		if _seen.has(st):
			parts.append("%s×%d" % [_state_name(st), int(_seen[st])])
	return ", ".join(parts)


## ------------------------------------------------------------------
## G-11：死亡链路（_die() 本来就写对了，β 之后必须仍然是 1.0 自然速度）
## ------------------------------------------------------------------
func _check_death(path: String, label: String, expect_len: float) -> void:
	print("\n---------- G-11：%s 死亡链路 ----------" % label)
	var e := (load(path) as PackedScene).instantiate() as EnemyBrute
	e.position = Vector3(0.0, 0.1, 0.0)
	add_child(e)
	await get_tree().process_frame
	await get_tree().physics_frame

	var anim: AnimationPlayer = e.get("_anim_player")
	var death_anim: String = String(e.get("_death_anim"))
	_check(anim != null and death_anim == "Death", "[%s] 识别到 Death 动画" % label, death_anim)
	if anim == null:
		e.free()
		return
	var da := anim.get_animation(death_anim)
	var dlen := -1.0 if da == null else da.length
	_check(absf(dlen - expect_len) < 0.005,
		"[%s] ★ Death 动画长度 == %.4fs（资产改时长会 fail）" % [label, expect_len], "实际 %.4fs" % dlen)

	e._die()
	_check(e.state == EnemyBrute.State.DEAD, "[%s] 已切到 DEAD" % label)
	_check(anim.current_animation == death_anim, "[%s] 死亡瞬间正在播 %s" % [label, death_anim],
		anim.current_animation)
	# ★ 精确相等（不是区间）：_die() 把 speed_scale 与 custom 都显式设为 1.0 ⇒ playing ≡ 1.0
	_check(absf(anim.speed_scale - 1.0) <= INV_EPS, "[%s] 死亡时 speed_scale == 1.0" % label,
		"%.6f" % anim.speed_scale)
	_check(absf(anim.get_playing_speed() - 1.0) <= INV_EPS,
		"[%s] ★ 死亡时实播倍速 == 1.0（自然速度，不被 β 影响）" % label,
		"%.6f" % anim.get_playing_speed())

	var worst := 0.0
	var samples := 0
	for _i in DEATH_SAMPLE:
		await get_tree().physics_frame
		if not is_instance_valid(e) or not is_instance_valid(anim):
			break
		if anim.is_playing():
			samples += 1
			worst = maxf(worst, absf(anim.get_playing_speed() - 1.0))
	_check(samples > 0 and worst <= INV_EPS,
		"[%s] ★ 死亡后 %d 帧内实播倍速恒 == 1.0" % [label, DEATH_SAMPLE],
		"采样 %d 帧，最大偏离 %.6f" % [samples, worst])

	if is_instance_valid(e):
		e.free()


## G-12 采样累加器（把"样本数 / 不符数 / 末次值"打包成一个出参）。
class _OnceSample:
	var n := 0
	var bad := 0
	var last_want := 0.0
	var last_got := 0.0
