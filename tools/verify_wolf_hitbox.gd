extends Node
## ============================================================
## 实机验证狼的命中盒：把玩家摆在狼正面 1.3m，狼走真实 WINDUP→STRIKE 流程，
## 断言玩家**真的掉血**（不是算出来的，是物理帧跑出来的）。
## ============================================================
## 运行（★ 必须跑**场景**，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_wolf_hitbox.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##
## 【为什么必须跑场景而不是 --script】本探针直接引用了 `EnemyBrute` / `PlayerCharacter`
##   两个 class_name，这会强制编译 enemy.gd —— 而 enemy.gd 引用了 autoload `EventBus`。
##   `--script` 模式下 autoload 尚未注册 → enemy.gd 编译失败（"Identifier not found: EventBus"）。
##   跑场景时 autoload 先于关卡脚本注册，故一切正常。（见 tools/run_probes.ps1 顶部说明。）
##
## 【为什么必须实机测】命中盒几何（hitbox_size/offset）是"算出来的坐标"，看着对不代表
##   真的能罩住玩家：还要看狼的缩放、VisualPivot 朝向、玩家碰撞胶囊高度、以及
##   Area3D 在 monitoring 置 true 时对"已在重叠区"的物体是否发 body_entered。
##   这些只有让物理真的跑几帧才能确认。
##
## 【踩坑记录 · 先设 position 再 add_child】若先 add_child 再设 global_position，
##   节点会在**原点**上先注册一次；两个角色都在原点的那一帧会被 Jolt 判为重叠并做一次
##   去穿透位移（实测狼被推开 +0.46m）。真实游戏里两个出生点相距 18m 不会遇到，
##   但本探针把两者摆得很近，所以必须"先定位再入树"。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"
## 玩家摆在狼正前方的距离（米）。狼命中盒 z 覆盖 [-1.95, -0.45]，1.3 落在正中。
const FORWARD_DIST := 1.3

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 狼命中盒实机验证 ===")

	# ---- 地面（让两个角色都能站住）----
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(40.0, 1.0, 40.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	# ---- 狼（面朝 -Z；★ 先定位再入树，避免原点重叠）----
	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate() as EnemyBrute
	wolf.ai_enabled = false              # 不让 AI 自己乱跑，本测试只验证"出手打不打得到"
	wolf.position = Vector3(0, 0.1, 0)
	add_child(wolf)

	# ---- 玩家：摆在狼正前方 -Z 方向 1.3m（★ 同样先定位再入树）----
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as PlayerCharacter
	player.position = Vector3(0, 0.2, -FORWARD_DIST)
	add_child(player)

	await get_tree().process_frame
	await get_tree().process_frame
	for i in 10:                          # 稳定几帧：落地、_ready 完成
		await get_tree().physics_frame

	var hp0 := player.health.current_hp
	var dz := player.global_position.z - wolf.global_position.z
	print("  狼 z=%.3f（面朝 -Z），玩家 z=%.3f，间距 %.2f m"
		% [wolf.global_position.z, player.global_position.z, absf(dz)])
	print("  玩家初始 hp = %d" % hp0)
	_check(absf(dz + FORWARD_DIST) < 0.1, "玩家确实站在狼正前方约 %.1fm" % FORWARD_DIST)

	# ---- 触发狼的一场真实攻击（WINDUP → STRIKE，命中盒在 STRIKE 开）----
	wolf.state = EnemyBrute.State.WINDUP
	wolf._state_time = 0.0

	var hp1 := hp0
	var frames := 0
	var reached_strike := false
	for i in 240:                          # 最多 4s（60fps）
		await get_tree().physics_frame
		frames += 1
		if wolf.state == EnemyBrute.State.STRIKE:
			reached_strike = true
		if player.health.current_hp != hp0:
			hp1 = player.health.current_hp
			break

	print("  经过 %d 物理帧：狼 state=%d（到过 STRIKE=%s），玩家 hp=%d"
		% [frames, wolf.state, str(reached_strike), hp1])
	_check(reached_strike, "狼走完了 WINDUP→STRIKE（命中盒确实开过）")
	_check(hp1 < hp0, "★ 狼出手时玩家真的掉血（take_damage 触发）",
		"hp %d → %d" % [hp0, hp1])
	_check(hp0 - hp1 == wolf.attack_damage,
		"掉血量 = attack_damage = %d" % wolf.attack_damage, "实际 %d" % (hp0 - hp1))

	print("")
	if _fail == 0:
		print("结论：命中盒实机验证通过 ✓")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)
