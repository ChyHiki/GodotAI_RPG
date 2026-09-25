extends Node
## ============================================================
## 实机验证狼的命中盒：把玩家摆在「**只有**因为盒子前伸 1.2m 才够得着」的距离，
## 断言玩家**真的掉血**；并用物理墙**挡住 STRIKE 前冲**，使失败路径不经过前冲。
## ============================================================
## 运行（★ 必须跑**场景**，不是 --script；原因见文件底部/verify_qa_negative.gd 顶部）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_wolf_hitbox.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##
## ----------------------------------------------------------------------------
## ★ 为什么重写（旧版的致命盲区）：旧版把玩家摆在 1.3m，但 STRIKE 期狼会朝玩家
##   前冲（velocity = lunge_dir * 8 * k，总位移可达 ~0.88m），把 **零偏移** 的盒子
##   推进玩家身体 ⇒ 即使 hitbox_offset 被清零也照样掉 12 血 ⇒ 探针照样过。
##   实测（变异实验）：把 hitbox_offset 清零后旧版仍 exit=0、hp 照掉 —— 说明旧版
##   **根本不能证伪 hitbox_offset**。本版要修掉这个盲区。
##
## ----------------------------------------------------------------------------
## ★ 隔离前冲的两个手法（缺一不可）：
##   1) **物理墙**：在狼与玩家之间（z≈-0.52）立一堵 StaticBody3D。狼前冲会在墙前
##      停下 —— 命中**只能**来自盒子往前伸出的那段几何，与狼是否前冲无关。
##      墙只挡 CharacterBody（狼），不影响 Area3D 的几何重叠判定。
##   2) **边界距离**：见 FORWARD_DIST 的取值论证 —— 玩家近端落在
##      (零偏移盒前沿 0.75, 有偏移盒前沿 1.95) 之间，于是：
##        有偏移 → 命中；零偏移 → 够不着（且被墙挡住无法靠前冲补偿）。
##   本探针还显式打印/断言"命中瞬间狼的前冲位移 ≈ 0"，把"失败路径不经过前冲"钉死。
##
## ----------------------------------------------------------------------------
## ★ 几何依据（狼 wolf.tscn：hitbox_size=(1.4,1.1,1.5), hitbox_offset=(0,0.65,-1.2)）：
##   命中盒是挂在 VisualPivot 下的 BoxShape3D，中心局部 (0,0.65,-1.2) → 局部 z ∈ [-1.95,-0.45]。
##   玩家胶囊 radius=0.35（player.tscn）→ 玩家近端 z = -(FORWARD_DIST) + 0.35。
##   FORWARD_DIST=1.6 → 玩家近端 z=-1.25：
##     · -1.25 < -0.75  ⇒ 零偏移盒（z∈[-0.75,0.75]）够不着（差 0.50m）
##     · -1.25 > -1.95  ⇒ 有偏移盒（z∈[-1.95,-0.45]）把玩家罩住（深入 0.70m）
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"

## 玩家摆在狼正前方的距离（米）。取值论证见文件头（1.6 落在"只有前伸才够得着"的窗口）。
const FORWARD_DIST := 1.6
## 命中瞬间允许的"狼前冲位移"上限（m）。墙会把狼钉住，故实测应 ≈ 0；
## 该断言的作用是**显式证明本探针的命中不是前冲造成的**。
const MAX_HIT_LUNGE := 0.10

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 狼命中盒实机验证（几何边界 + 前冲隔离）===")

	# ---- 地面 ----
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(40.0, 1.0, 40.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	# ---- ★ 挡前冲的墙：立在狼（z=0，半径 0.45）与玩家（z=-1.6）之间 ----
	# 狼前边缘 z=-0.45；墙后表面放到 z=-0.47 留 0.02 缝隙 → 狼最多前移 ~0.02 就被挡住。
	# 墙只从 z=-0.51 到 -0.47、极高极宽：只挡 CharacterBody 的位移，不挡 Area3D 重叠。
	var wall := StaticBody3D.new()
	wall.name = "LungeBlocker"
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(40.0, 3.0, 0.04)
	wcol.shape = wbox
	wall.add_child(wcol)
	wall.position = Vector3(0, 1.0, -0.49)
	add_child(wall)

	# ---- 狼（面朝 -Z；★ 先定位再入树）----
	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate() as EnemyBrute
	wolf.ai_enabled = false              # 不让 AI 乱跑；本测试只验证"出手打不打得到"
	wolf.position = Vector3(0, 0.1, 0)
	add_child(wolf)

	# ---- 玩家：摆在狼正前方 -Z 方向 FORWARD_DIST（★ 同样先定位再入树）----
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as PlayerCharacter
	player.position = Vector3(0, 0.2, -FORWARD_DIST)
	add_child(player)

	await get_tree().process_frame
	await get_tree().process_frame
	for i in 12:                          # 稳定几帧：落地、_ready 完成、贴墙
		await get_tree().physics_frame

	var hp0 := player.health.current_hp
	var dz := player.global_position.z - wolf.global_position.z
	print("  狼 z=%.3f（面朝 -Z），玩家 z=%.3f，间距 %.2f m（本地前伸盒 z∈[-1.95,-0.45]）"
		% [wolf.global_position.z, player.global_position.z, absf(dz)])
	print("  玩家初始 hp = %d" % hp0)
	_check(absf(-dz - FORWARD_DIST) < 0.1, "玩家站在狼正前方约 %.1fm" % FORWARD_DIST)

	# ---- 触发狼的一场真实攻击（WINDUP → STRIKE）----
	var p_before := wolf.global_position
	wolf.state = EnemyBrute.State.WINDUP
	wolf._state_time = 0.0

	var hitbox: Area3D = wolf.get("_hitbox")
	var hp1 := hp0
	var frames := 0
	var reached_strike := false
	var strike_frame := -1
	var mon_frame := -1
	var hit_frame := -1
	var p_strike := wolf.global_position
	var p_hit := wolf.global_position
	var max_fwd_travel := 0.0             # 整场 STRIKE 里狼相对出手位置的最大前冲位移
	for i in 300:                         # 最多 5s（60fps），足够 WINDUP 0.5s + 前冲
		await get_tree().physics_frame
		frames += 1
		if wolf.state == EnemyBrute.State.STRIKE:
			if not reached_strike:
				reached_strike = true
				strike_frame = frames
				p_strike = wolf.global_position
			# 记录 STRIKE 期间狼到底往前冲了多少（用于论证失败路径不含前冲）
			max_fwd_travel = maxf(max_fwd_travel, p_before.distance_to(Vector3(
				p_before.x, p_before.y, wolf.global_position.z)))
		if mon_frame < 0 and hitbox != null and hitbox.monitoring:
			mon_frame = frames
		if player.health.current_hp != hp0:
			hp1 = player.health.current_hp
			hit_frame = frames
			p_hit = wolf.global_position
			break

	var lunge_at_hit := p_strike.distance_to(p_hit)
	print("  STRIKE 起始帧=%d  命中盒 monitoring 帧=%d  命中帧=%d" %
		[strike_frame, mon_frame, hit_frame])
	print("  命中瞬间：狼 p_strike.z=%.4f → p_hit.z=%.4f，前冲位移=%.4f m；" %
		[p_strike.z, p_hit.z, lunge_at_hit])
	print("  STRIKE 期间狼最大前冲位移=%.4f m（墙应把它钉在 ~0）  玩家 hp=%d" %
		[max_fwd_travel, hp1])

	_check(reached_strike, "狼走完了 WINDUP→STRIKE（命中盒确实开过）")
	# ---- ① 命中：只有盒子前伸 1.2m 才够得着 ----
	_check(hp1 < hp0, "★ 狼出手时玩家真的掉血（命中盒前伸 1.2m 罩住了玩家）",
		"hp %d → %d" % [hp0, hp1])
	_check(hp0 - hp1 == wolf.attack_damage,
		"掉血量 = attack_damage = %d" % wolf.attack_damage, "实际 %d" % (hp0 - hp1))
	# ---- ② 显式证明"失败路径不经过前冲" ----
	_check(lunge_at_hit < MAX_HIT_LUNGE,
		"★ 命中瞬间狼前冲位移 ≈ 0（命中来自盒子前伸，而非前冲）",
		"%.4f m < %.2f" % [lunge_at_hit, MAX_HIT_LUNGE])
	_check(max_fwd_travel < MAX_HIT_LUNGE,
		"★ 整场 STRIKE 狼前冲被墙钉住（≤ %.2f m）" % MAX_HIT_LUNGE,
		"%.4f m" % max_fwd_travel)

	print("")
	if _fail == 0:
		print("结论：命中盒几何实机验证通过 ✓（前伸够得着、前冲被隔离）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)
