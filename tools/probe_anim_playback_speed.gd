extends Node3D
## ============================================================
## 诊断探针：核实"AnimationPlayer 实播倍速 = speed_scale(属性) × custom_speed"，
## 以及 custom_speed 是否被 `_play_loop` 冻结在"进入该段的那一次 play()"上；
## 并测出**真实游戏条件下**（动画系统已预热在播 Idle）的冻结值。
## ============================================================
## 运行（★ 跑场景，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/probe_anim_playback_speed.tscn
##
## 【只测量，不判定】本探针 exit 恒为 0（除非 setup 失败），故意**不**纳入
##   tools/run_probes.ps1 —— 一个永不失败的守门项没有意义。它的值是给人读的。
##
## ============================================================
## 【背景】enemy.gd 的 _play_loop(:1167-1173) 是两层写法：
##   动画名变化那一帧 → play(name, blend, want)，第 4 参 custom_speed 就此**钉死**
##   之后每帧        → 只改 speed_scale 属性
##   ⇒ get_playing_speed() = speed_scale × 被钉住的 custom_speed
##   而 want 只在换名那一帧求值一次。实测同一个 nominal 场景量到过
##   2.4668 / 1.4096 / 1.0155 / 0.5704 四个不同的钉住因子 ⇒ **不可复现**。
## ============================================================
## 【为什么必须有"预热相"】初版探针一上来就让狼进 CHASE，观测到 `current_animation`
##   在前 6 帧为空（动画系统尚未驱动），于是首次 play("Walk") 发生在 spd 已爬到 2.892 时，
##   钉住因子 = 2.4668。但真实游戏里敌人开局就 spawn、动画系统早已在播 Idle，
##   首次 play("Walk") 会发生在**速度爬升的第一帧**（实测 spd=1.653 ⇒ 钉住 1.4096）。
##   两种时序差好几倍，所以必须用预热相复现真实条件，否则测出来的是 headless 启动假象。
##
## 相 A（预热）：玩家摆在 aggro_range(13) 之外 ⇒ 狼停在 IDLE，动画系统完全上身。
## 相 B（实测）：把玩家瞬移到 12m ⇒ 狼进 CHASE，记录 Idle→Walk 换名那一帧的一切。
##
## 【读法】
##   implied custom = get_playing_speed() / speed_scale
##   · 恒为同一常数（且首帧即定）⇒ "custom_speed 被钉住"成立；
##   · ≈ 1.0 ⇒ play() 未冻结，speed_scale 是唯一真源。
##   slide = get_playing_speed() × walk_natural_speed ÷ 身体水平速度
##     （≈1 = 脚与地同步；<1 = 脚打滑；>1 = 脚倒退/刨地）
## ============================================================
## 【本文件是合并版】曾有两支重复探针（probe_speed_freeze / probe_anim_playback_speed），
##   内容重叠。已合并为本文件，取本文更完整的版本（含预热相 + 单层语义对照）。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"

## 相 A：玩家摆这么远 —— 必须在 aggro_range(13.0) 之外，狼才会停在 IDLE。
const FAR_DIST := 30.0
## 相 B：拉近到 12m —— 在 aggro_range 内、远超 attack_range(2.0)，
## 4.2m/s 追上 12m 约需 2.86s = 172 物理帧，故取 150 帧全程停在 CHASE。
const NEAR_DIST := 12.0
const WARMUP_FRAMES := 30
const RUN_FRAMES := 150


func _row(i: int, st: int, spd: float, cur: String, ss: float, ps: float) -> void:
	var cs := (ps / ss) if absf(ss) > 0.0001 else 0.0
	print("%5d | %5d | %5.3f | %-12s | %11.4f | %7.4f | %13.4f" % [i, st, spd, cur, ss, ps, cs])


## 与 enemy.gd 各状态分支 `_play_once(anim, duration)` 的第 2 参保持一致。
## 改 enemy.gd 的这些分支时必须同步改这里，否则判定 4 的期望值会算错。
func _duration_for(wolf: Node, st: int, anim_name: String) -> float:
	match st:
		2: return float(wolf.get("windup_time"))    # WINDUP  : _play_once(_windup_anim, windup_time)
		3: return float(wolf.get("strike_time"))    # STRIKE  : _play_once(_attack_anim, strike_time)
		5: return float(wolf.get("stagger_time"))   # STAGGER : _play_once(_hit_anim, _stagger_time)
		6: return 0.6                               # BROKEN  : _play_once(_hit_anim, 0.6) 写死
	return 0.0


func _ready() -> void:
	print("=== 诊断：实播倍速 = speed_scale × custom_speed ? ===")

	# ---- 地面（狼是 CharacterBody3D，需要落脚面）----
	var ground := StaticBody3D.new()
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(120.0, 1.0, 120.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)

	# ---- 狼 ----
	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate()
	wolf.position = Vector3(0.0, 0.1, 0.0)
	add_child(wolf)

	# ---- 玩家（提供 group "player" 作为追击目标）----
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate()
	player.position = Vector3(0.0, 0.1, -FAR_DIST)
	add_child(player)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var anim: AnimationPlayer = wolf.get("_anim_player")
	var natural: float = wolf.get("walk_natural_speed")
	var walk_len := 0.0
	if anim != null and anim.has_animation("Walk"):
		walk_len = anim.get_animation("Walk").length

	print("accel=%.1f  move_speed=%.3f  walk_natural_speed=%.4f  walk_max_speed_scale=%.2f" % [
		wolf.get("accel"), wolf.get("move_speed"), natural, wolf.get("walk_max_speed_scale")])
	print("physics_ticks_per_second=%d  Walk.length=%.4fs  aggro_range=%.1f" % [
		Engine.physics_ticks_per_second, walk_len, wolf.get("aggro_range")])
	print("")

	# ================= 相 A：预热 =================
	print("--- 相 A：预热（玩家 %.0fm 外，狼停在 IDLE，等动画系统完全上身）---" % FAR_DIST)
	for i in WARMUP_FRAMES:
		await get_tree().physics_frame
		if i == 0 or i == WARMUP_FRAMES - 1:
			var s := Vector2(wolf.velocity.x, wolf.velocity.z).length()
			_row(i, wolf.state, s, anim.current_animation, anim.speed_scale, anim.get_playing_speed())
	print("  预热结束：state=%d  anim=%s  speed_scale=%.4f  playing=%.4f   ⇒ 动画系统已上身" % [
		wolf.state, anim.current_animation, anim.speed_scale, anim.get_playing_speed()])
	print("")

	# ================= 相 B：拉近，进 CHASE =================
	print("--- 相 B：玩家瞬移到 %.0fm ⇒ 狼进 CHASE ---" % NEAR_DIST)
	player.position = Vector3(0.0, 0.1, -NEAR_DIST)
	print("frame | state |  spd  | anim         | speed_scale | playing | implied custom")
	print("------+-------+-------+--------------+-------------+---------+---------------")

	var first_walk := -1
	var fw_ss := 0.0
	var fw_ps := 0.0
	var fw_cs := 0.0
	var fw_spd := 0.0
	# 稳态 = 最后一个「CHASE 且正在播 Walk」的帧（末帧可能已进 AttackWindup，会误读）
	var st_ss := 0.0
	var st_ps := 0.0
	var st_cs := 0.0
	var st_spd := 0.0
	var st_frame := -1

	for i in RUN_FRAMES:
		await get_tree().physics_frame
		var spd := Vector2(wolf.velocity.x, wolf.velocity.z).length()
		var cur: String = anim.current_animation
		var ss := anim.speed_scale
		var ps := anim.get_playing_speed()
		var cs := (ps / ss) if absf(ss) > 0.0001 else 0.0

		if cur == "Walk" and first_walk < 0:
			first_walk = i
			fw_ss = ss
			fw_ps = ps
			fw_cs = cs
			fw_spd = spd
		if wolf.state == 1 and cur == "Walk":
			st_ss = ss
			st_ps = ps
			st_cs = cs
			st_spd = spd
			st_frame = i

		if i < 12 or i % 12 == 0 or i == RUN_FRAMES - 1:
			_row(i, wolf.state, spd, cur, ss, ps)

	print("")
	print("================ 结论 ================")
	if first_walk < 0:
		print("✗ 整段 %d 帧都没进 Walk（狼没进 CHASE？）—— 本探针无效，请检查 setup" % RUN_FRAMES)
		get_tree().quit(1)
		return

	print("首发 Walk 帧 = %d   【此刻 spd=%.3f  speed_scale=%.4f  playing=%.4f  implied custom=%.4f】" % [
		first_walk, fw_spd, fw_ss, fw_ps, fw_cs])
	print("稳态（第 %d 帧，CHASE+Walk）  speed_scale=%.4f  playing=%.4f  implied custom=%.4f  spd=%.3f" % [
		st_frame, st_ss, st_ps, st_cs, st_spd])
	print("")
	print("【判定 1】custom_speed 是否被冻结？")
	print("  首发 implied custom = %.4f，稳态 implied custom = %.4f，差 %.4f" % [
		fw_cs, st_cs, absf(fw_cs - st_cs)])
	if absf(fw_cs - st_cs) < 0.001 and absf(st_ss) > 0.001 and absf(st_cs - 1.0) > 0.01:
		print("  ⇒ ★ 冻结成立：implied custom 从首帧起就不再变化，而 speed_scale 一路在涨。")
		print("     play() 的第 4 参 custom_speed 一旦设定就固定，此后 _play_loop 只改 speed_scale 属性，")
		print("     两者**相乘** ⇒ get_playing_speed() ≠ speed_scale。")
	elif absf(st_cs - 1.0) <= 0.01:
		print("  ⇒ custom_speed ≈ 1.0，speed_scale 是唯一真源，冻结问题不存在。")
	else:
		print("  ⇒ 不成立或时序复杂，读上表人工判断。")

	print("")
	print("【判定 2】脚底与地面是否匹配（滑移比）")
	print("  实播倍速 = %.4f；若 walk_natural_speed=%.4f m/s 是 speed_scale=1.0 时的步速，" % [st_ps, natural])
	print("  则画面上的脚底步速 = %.4f m/s，而身体实际速度 = %.3f m/s" % [st_ps * natural, st_spd])
	if st_spd > 0.001:
		var slide := st_ps * natural / st_spd
		print("  slide = %.3f  %s" % [slide, "(≈1 匹配；<1 脚在地上打滑；>1 脚倒退/刨地)" if absf(slide - 1.0) > 0.15 else "(匹配)"])
		print("  ⇒ 脚底与地面速度相差 **%.0f%%**" % (absf(slide - 1.0) * 100.0))
	print("  对照：若 speed_scale 是唯一真源，实播倍速应为 %.4f，滑移比 %.3f" % [
		st_ss, (st_ss * natural / st_spd) if st_spd > 0.001 else 0.0])

	# ================= 判定 4：单次动画是否也是两层相乘（playing == spd² ?）=================
	# 【为什么要单独测】_play_once(enemy.gd:1181-1191) 与 _play_loop 是同一个写法：
	#   换名那一帧 play(name, blend, spd) 把 custom_speed 钉成 spd，
	#   之后每帧又把 speed_scale 也写成 spd ⇒ 稳态 playing = spd × spd = spd²。
	#   但这条此前只是"从第 149 帧一个数据点反推"，改动守卫攻击速度前必须坐实，
	#   所以在多段单次动画上分别取样、并与"意图 spd"和"spd²"两个期望值同时比。
	print("")
	print("【判定 4】单次动画（_play_once）是否也两层相乘？")
	print("  意图：spd = length / duration，把动画铺满 duration 秒 ⇒ 期望 playing == spd")
	print("  若与 _play_loop 同病       ⇒ playing == spd²")
	var sampled: Dictionary = {}
	for i in 600:
		await get_tree().physics_frame
		var cur4: String = anim.current_animation
		var st4: int = wolf.state
		if st4 >= 2 and st4 <= 6 and cur4 != "" and not sampled.has(cur4):
			# 先让 speed_scale 被写成稳态（至少走过一帧 else 分支）再取样
			await get_tree().physics_frame
			await get_tree().physics_frame
			var a4 := anim.get_animation(cur4)
			var dur4 := _duration_for(wolf, st4, cur4)
			if a4 != null and dur4 > 0.0:
				var spd4 := a4.length / dur4
				var ss4 := anim.speed_scale
				var ps4 := anim.get_playing_speed()
				sampled[cur4] = true
				print("  ── state=%d  anim=%s  length=%.4fs  状态机 duration=%.4fs" % [st4, cur4, a4.length, dur4])
				print("     意图 spd = length/duration = %.4f" % spd4)
				print("     实测 speed_scale=%.4f  playing=%.4f  ⇒ 反推 custom=%.4f" % [ss4, ps4, ps4 / ss4])
				print("     期望【若单层】playing = %.4f     期望【若两层】playing = spd² = %.4f" % [spd4, spd4 * spd4])
				print("     判定：|playing−spd|=%.4f  vs  |playing−spd²|=%.4f  ⇒ %s" % [
					absf(ps4 - spd4), absf(ps4 - spd4 * spd4),
					"单层（无此病）" if absf(ps4 - spd4) < absf(ps4 - spd4 * spd4) else "★ 两层相乘（= spd²）"])
		if sampled.size() >= 3:
			break
	if sampled.is_empty():
		print("  ⚠ 600 帧内没抓到单次动画状态（狼可能停在 RECOVER/CHASE），本判定未取到样本")
	else:
		print("  共取到 %d 段单次动画样本：%s" % [sampled.size(), ", ".join(sampled.keys())])

	# ================= 单层语义对照（验证修复方向）=================
	print("")
	print("【判定 3】单层语义对照：play(name, blend, 1.0) + speed_scale=want 能否等价于 want？")
	print("  ★ 必须先让狼停手：狼还在 CHASE，_animate_model 每帧都会重写 speed_scale，")
	print("    不关掉它会把本次实验的设置覆盖掉（初版就因此测出 1.3542 这种自相矛盾的值）。")
	wolf.set_process(false)
	wolf.set_physics_process(false)
	await get_tree().physics_frame
	var probe_want := 1.25
	anim.play("Walk", 0.0, 1.0)
	anim.speed_scale = probe_want
	await get_tree().physics_frame
	var got_ps := anim.get_playing_speed()
	print("  设 speed_scale=%.4f 且 play(custom_speed=1.0) ⇒ get_playing_speed()=%.4f  %s" % [
		probe_want, got_ps, "✓ 单层语义成立（修复方向可用）" if absf(got_ps - probe_want) < 0.01 else "✗ 仍不是单层"])
	print("  （复核：此刻 anim.current_animation=%s  anim.speed_scale=%.4f）" % [
		anim.current_animation, anim.speed_scale])
	# 反例：若 play() 时传的 custom_speed 不是 1.0，同样设置下会得到什么
	anim.play("Walk", 0.0, 1.4096)
	anim.speed_scale = probe_want
	await get_tree().physics_frame
	print("  反例：改成 play(custom_speed=1.4096) ⇒ get_playing_speed()=%.4f（应 ≈ %.4f）" % [
		anim.get_playing_speed(), probe_want * 1.4096])

	# ================= 判定 4：_play_once 是否也是两层（playing = spd^2 ?）=================
	# 【为什么要隔离复现】_play_once（enemy.gd:1181-1191）两行是：
	#     换名那帧  play(name, blend, spd)     # custom_speed = spd
	#     之后每帧  speed_scale = spd          # 属性 = spd
	# 若两层成立 ⇒ 稳态 playing = spd × spd = spd^2，而注释明写意图是"拉伸到 duration 秒播完"
	# ⇒ 要求 playing == spd。本判定直接按同样顺序调用同样的 API，不受 AI 每帧干扰。
	print("")
	print("【判定 4】_play_once 是否也是两层（稳态 playing = spd^2 而不是 spd）？")
	var a_name := "AttackWindup"
	if anim.has_animation(a_name):
		var alen := anim.get_animation(a_name).length
		var dur := float(wolf.get("windup_time"))
		var spd := alen / maxf(0.05, dur)
		anim.play(a_name, 0.0, spd)     # 模拟"换名那一帧"
		anim.speed_scale = spd           # 模拟"之后每帧"（else 分支）
		await get_tree().physics_frame
		var p4 := anim.get_playing_speed()
		print("  %s：length=%.4fs  windup_time=%.4fs ⇒ spd = length/duration = %.4f" % [a_name, alen, dur, spd])
		print("  按 _play_once 的两行调用后 ⇒ get_playing_speed() = %.4f" % p4)
		print("    若【两层】成立，应 ≈ spd^2 = %.4f" % (spd * spd))
		print("    若【单层】成立，应 ≈ spd   = %.4f" % spd)
		print("  ⇒ 实测吻合 %s" % ("★ spd^2 ⇒ _play_once **确实双重复用**" if absf(p4 - spd * spd) < 0.01 else ("spd ⇒ 单层，无此问题" if absf(p4 - spd) < 0.01 else "两者都不吻合，需人工判断")))
	else:
		print("  ✗ 找不到动画 %s，判定 4 跳过" % a_name)
	print("")
	get_tree().quit(0)
