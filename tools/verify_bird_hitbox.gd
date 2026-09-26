extends Node
## ============================================================
## 实机验证鸟的命中盒：几何边界 + 真实伤害 + 命中盒参考系（不随"跃扑"动画飘）
## ============================================================
## 运行（★ 必须跑**场景**，不是 --script；原因见 run_probes.ps1 文件头）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_bird_hitbox.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##
## ----------------------------------------------------------------------------
## ★ 与 verify_wolf_hitbox 的三点不同（这三点正是本文件存在的理由）：
##   1) **走真实 AI 入口**：不直接赋 `state = WINDUP`，而是把玩家摆进鸟的
##      aggro/attack 半径，让鸟自己 CHASE → WINDUP → STRIKE。这样测到的是
##      "玩家真会被这只怪咬到"的端到端事实，而不是"手推状态机能咬到"。
##   2) **同时覆盖几何 + 真掉血**：狼那条只断言"真掉血"（几何靠文件头论证）；
##      本文件把 `hitbox_size/hitbox_offset` 的**几何量**与**真实 Health 掉血**
##      两条都断言，并给出**可证伪的负控**（见 3）。
##   3) **负控（本文件最有价值的一条）**：跑第二遍，把 `hitbox_offset` 清零后
##      在同一距离、同一堵墙下再打一次 —— 必须**打不到**。这一遍专治假绿：
##      若"命中"其实来自鸟身体前冲 / 命中盒跟着动画前伸，那么清零 offset 也照样
##      掉血、负控就会**变红**。负控通过 ⇒ 主测的掉血**只可能**来自前伸的盒几何。
##      （形制同 verify_enemy_bird 的 [校验②-c]：断言一个"把条件破坏掉就该失败"
##        的场景，证明主断言不是空洞的。）
##
## ----------------------------------------------------------------------------
## ★ 命中盒参考系（"跃扑"专属的坑，狼没有）：
##   鸟的攻击是**跃扑**：`Attack` 段 root 有竖直位移（build_bird.py §④：f3 跃起
##   +0.14、f5 +0.05、f7 −0.02，**仅竖直**），且引擎侧 STRIKE 还会给一个
##   前冲速度（enemy.gd `velocity = _lunge_dir * 8 * k`）。这两件事都会"让身体动"。
##   enemy.gd 把命中盒挂在 **VisualPivot**（只随朝向绕 Y 转、不随骨骼动画位移），
##   所以命中盒与角色的**相对偏移应当是恒定的**；若哪天有人把它挪到"随动画位移的
##   节点"下（例如挂到模型骨骼上），命中盒就会跟着跃扑一起飘 → 够到不该够到的距离。
##   本文件用两条**结构性 + 动态性**断言钉死参考系：
##     · 结构：命中盒的父节点必须是 VisualPivot，且命中盒**不是**模型节点的后代；
##     · 动态：STRIKE 全程 `bird.global_transform⁻¹ · hitbox.global_position`
##       的竖直分量恒 ≈ 1.05、水平长度恒 ≈ 1.30（= |hitbox_offset|）。同时打印
##       骨架 root 骨的世界高度**确实在跃**（body_rise）—— 身体在动、命中盒不动，
##       正是"参考系正确"的直接证据。
##
## ----------------------------------------------------------------------------
## ★ 几何依据（bird.tscn：hitbox_size=(1.0,0.9,1.6), hitbox_offset=(0,1.05,−1.3)）：
##   命中盒是挂在 VisualPivot 下的 BoxShape3D，中心局部 (0,1.05,−1.3) → 局部 z ∈ [−2.1,−0.5]。
##   玩家胶囊 radius=0.35（player.tscn）→ 玩家近端 z = −(FORWARD_DIST) + 0.35。
##   鸟胶囊 radius=0.35 → 鸟前端 z = −0.35；墙立其后 0.02m 处把身体前冲钉住。
##   FORWARD_DIST=1.6 → 玩家近端 z=−1.25：
##     · −1.25 < −0.80  ⇒ **零偏移**盒（z∈[−0.8,0.8]）够不着（差 0.45m）★ 负控依据
##     · −1.25 > −2.10  ⇒ **有偏移**盒（z∈[−2.1,−0.5]）把玩家罩住（深入 0.85m）
## ============================================================

const BIRD_TSCN := "res://scenes/enemy/bird.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"
const MODEL_PATH := "res://assets/enemies/bird_01/bird_rigged.glb"

## 玩家摆在鸟正前方的距离（米）。取值论证见文件头（1.6 落在"只有前伸才够得着"的窗口）。
const FORWARD_DIST := 1.6
## 命中瞬间 / 整场 STRIKE 允许的"鸟身体前冲位移"上限（m）。墙会把它钉住，故实测应 ≈ 0；
## 该断言显式证明本探针的命中不是靠前冲补偿的。
const MAX_HIT_LUNGE := 0.10
## 单场景最多推进的物理帧数（60fps ⇒ 360 帧 = 6s）：足够 CHASE→WINDUP(0.5s)→STRIKE(0.22s)。
const MAX_FRAMES := 360
## 落位后稳定帧数（等落地、_ready 装配、贴墙）。
const SETTLE_FRAMES := 12

## 命中盒几何（与 bird.tscn 的 @export 一致，作为资产漂移哨兵）
const HITBOX_SIZE := Vector3(1.0, 0.9, 1.6)
const HITBOX_OFFSET := Vector3(0.0, 1.05, -1.3)
## 玩家 / 鸟的碰撞胶囊半径（player.tscn / bird.tscn）
const PLAYER_RADIUS := 0.35
const BIRD_RADIUS := 0.35

## 参考系断言容差：命中盒相对**角色根**的偏移在 STRIKE 全程应基本不变。
##   · 竖直分量 = |offset.y| = 1.05（若命中盒跟着跃扑的 +0.14 竖直位移，会飙到 ~1.19 → 超标）
##   · 水平长度 = |offset.xz| = 1.30
const REF_Y_TOL := 0.05
const REF_H_TOL := 0.08
## 骨架 root 骨在 STRIKE 期间的竖直抬升下限（"身体确实在跃"的证据阈值）。
## Attack 设计跃起 +0.14m（build_bird.py §④），取 0.04 留足裕度。
const BODY_RISE_MIN := 0.04

## 期望动画名（enemy.gd 关键字识别的结果）
const WINDUP_ANIM := "AttackWindup"
const ATTACK_ANIM := "Attack"
## AttackWindup / Attack 的设计帧数（1..N，24fps）→ Animation.length = N/24
const WINDUP_FRAMES_N := 13
const ATTACK_FRAMES_N := 7

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 鸟命中盒实机验证（几何边界 + 真实伤害 + 参考系）===")
	_assert_asset_geometry()
	_build_world()
	await _scenario(false)     # 主测：真实 AI 出手，玩家应真掉血
	await _scenario(true)      # 负控：offset 清零，玩家必须打不到

	print("")
	if _fail == 0:
		print("结论：命中盒几何 + 真实伤害 + 参考系实机验证通过 ✓（含负控）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


## ==================================================================
## [A] 资产：AttackWindup 1–13 / Attack 1–7 的帧覆盖（长度 = N/24）
## ==================================================================
func _assert_asset_geometry() -> void:
	print("\n[A] 资产：AttackWindup(1–13) / Attack(1–7) 帧覆盖")
	var model_scene := load(MODEL_PATH) as PackedScene
	if model_scene == null:
		_fail += 1
		print("  ✗ 资产未导入：%s" % MODEL_PATH)
		return
	var model := model_scene.instantiate() as Node3D
	var anim := _find_animation_player(model)
	if anim == null:
		_fail += 1
		print("  ✗ 模型里没有 AnimationPlayer")
		model.free()
		return
	var names := anim.get_animation_list()
	_check(names.has(WINDUP_ANIM), "存在动画 %s" % WINDUP_ANIM)
	_check(names.has(ATTACK_ANIM), "存在动画 %s" % ATTACK_ANIM)
	var frame_off := 1.0 / 24.0
	if names.has(WINDUP_ANIM):
		var a := anim.get_animation(WINDUP_ANIM)
		_check(absf(a.length - (float(WINDUP_FRAMES_N) * frame_off)) < 0.005,
			"%s 覆盖 1–%d（length == %d/24）" % [WINDUP_ANIM, WINDUP_FRAMES_N, WINDUP_FRAMES_N],
			"实际 %.4fs（期望 %.4fs）" % [a.length, float(WINDUP_FRAMES_N) * frame_off])
	if names.has(ATTACK_ANIM):
		var a2 := anim.get_animation(ATTACK_ANIM)
		_check(absf(a2.length - (float(ATTACK_FRAMES_N) * frame_off)) < 0.005,
			"%s 覆盖 1–%d（length == %d/24）" % [ATTACK_ANIM, ATTACK_FRAMES_N, ATTACK_FRAMES_N],
			"实际 %.4fs（期望 %.4fs）" % [a2.length, float(ATTACK_FRAMES_N) * frame_off])
	model.free()


## ==================================================================
## [0] 世界：地面 + 挡前冲的墙（两场场景共用）
## ==================================================================
func _build_world() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(60.0, 1.0, 60.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	# ★ 挡前冲的墙：立在鸟（z=0，半径 0.35 → 前端 z=−0.35）与玩家（z=−FORWARD_DIST）之间。
	#   后表面放在 z=−0.37（鸟前端之后 0.02m）→ 鸟最多前移 ~0.02 就被挡住。
	#   只挡 CharacterBody 的位移，不挡 Area3D 的几何重叠判定。
	var wall := StaticBody3D.new()
	wall.name = "LungeBlocker"
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(60.0, 3.0, 0.04)
	wcol.shape = wbox
	wall.add_child(wcol)
	wall.position = Vector3(0, 1.0, -(BIRD_RADIUS + 0.04))
	add_child(wall)

	# 几何窗口自检（打印即可，证明 FORWARD_DIST 落在正确的窗口里）
	var player_near := -(FORWARD_DIST) + PLAYER_RADIUS
	var zero_far := -(HITBOX_SIZE.z * 0.5)
	var off_far := HITBOX_OFFSET.z - HITBOX_SIZE.z * 0.5
	print("  [几何] 玩家近端 z=%.2f；零偏移盒远端 z=%.2f（够不着? %s）；有偏移盒远端 z=%.2f"
		% [player_near, zero_far, str(player_near > zero_far), off_far])


## ==================================================================
## 单个场景：摆好鸟 + 玩家，让**真实 AI** 打一棒，逐帧取证
## ==================================================================
## @param zero_offset true = 负控（把 hitbox_offset 清零，期望打不到）
func _scenario(zero_offset: bool) -> void:
	var title := "[负控] hitbox_offset 清零 ⇒ 同距离必须打不到" if zero_offset \
		else "[主测] 真实 AI 出手 ⇒ 玩家真掉血（掉血量 == attack_damage）"
	print("\n[B] %s" % title)

	# ---- 鸟（面朝 −Z；★ 先定位再入树）—— ai_enabled 保持默认 true ⇒ 走真实 AI ----
	var bird := (load(BIRD_TSCN) as PackedScene).instantiate() as EnemyBrute
	if bird == null:
		_fail += 1
		print("  ✗ 实例化 bird.tscn 失败（不是 EnemyBrute？）")
		return
	_check(bird.ai_enabled, "鸟以 ai_enabled=true 出场（走真实 AI 入口，非手推状态机）")
	if zero_offset:
		bird.hitbox_offset = Vector3.ZERO     # ★ 必须在入树前改：_build_hitbox 在 _ready 里读它
	bird.position = Vector3(0, 0.1, 0)
	add_child(bird)

	# ---- 玩家：摆在鸟正前方 −Z 方向 FORWARD_DIST（★ 同样先定位再入树）----
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as PlayerCharacter
	if player == null:
		_fail += 1
		print("  ✗ 实例化 player.tscn 失败（不是 PlayerCharacter？）")
		bird.free()
		return
	player.position = Vector3(0, 0.2, -FORWARD_DIST)
	add_child(player)

	await get_tree().process_frame
	await get_tree().process_frame
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame

	var hitbox: Area3D = bird.get("_hitbox")
	var anim_player: AnimationPlayer = bird.get("_anim_player")
	var skel := _find_skeleton(bird)
	var root_idx := skel.find_bone("root") if skel != null else -1
	# ★ 模型节点在 VisualPivot 之下（不是 bird 的直接子节点）→ 用 find_child 递归找。
	var model_node: Node = bird.find_child("%sModel" % "bird", true, false)
	# ★ 命中盒 Area3D 自身在 pivot 原点；**偏移挂在 HitboxShape 子节点**上 → 取证必须用它。
	var shape_node: CollisionShape3D = null
	if hitbox != null:
		shape_node = hitbox.get_node_or_null("HitboxShape") as CollisionShape3D

	# ---- 结构化参考系断言：命中盒挂在 VisualPivot 下、不属于模型节点 ----
	if hitbox != null:
		var parent := hitbox.get_parent()
		_check(parent != null and parent.name == "VisualPivot",
			"★ 命中盒的父节点 = VisualPivot（非随动画位移的节点）",
			str(parent.name) if parent != null else "null")
		if model_node != null:
			_check(not model_node.is_ancestor_of(hitbox),
				"★ 命中盒不是模型节点的后代（不会跟着跃扑动画飘）")
		else:
			_fail += 1
			print("  ✗ 找不到模型节点（birdModel），无法验证命中盒不属于模型")
		if shape_node != null:
			var bs := shape_node.shape as BoxShape3D
			_check(bs != null and bs.size.is_equal_approx(HITBOX_SIZE),
				"命中盒尺寸 = (1.0, 0.9, 1.6)", str(bs.size) if bs != null else "null")
			_check((shape_node.position as Vector3).is_equal_approx(
					Vector3.ZERO if zero_offset else HITBOX_OFFSET),
				"命中盒偏移 = %s" % ("(0,0,0)（负控清零）" if zero_offset else "(0, 1.05, −1.3)"),
				str(shape_node.position))

	# ---- 记录初始血量 ----
	var hp0 := player.health.current_hp
	var dz := player.global_position.z - bird.global_position.z
	print("  鸟 z=%.3f（面朝 −Z），玩家 z=%.3f，间距 %.2f m（有偏移盒 z∈[−2.1,−0.5]）"
		% [bird.global_position.z, player.global_position.z, absf(dz)])
	print("  玩家初始 hp = %d" % hp0)

	# ---- 逐物理帧取证（★ 不手推 state：让真实 AI 自己走 IDLE→CHASE→WINDUP→STRIKE）----
	# ★ 不在"首次掉血"就 break：要**采满整段 STRIKE**，才能看到跃扑的身体在动、
	#   而命中盒相对鸟根的偏移纹丝不动（参考系证据）。改为"观测到一次完整 STRIKE 后退出"。
	var frames := 0
	var windup_frames := 0
	var strike_frames := 0
	var windup_damage := false
	var windup_anim_frames := 0
	var strike_anim_frames := 0
	var reached_strike := false
	var strike_frame := -1
	var mon_frame := -1
	var hit_frame := -1
	var hp1 := hp0
	var hit_state := -1
	var hit_anim := ""
	var hit_seen := false
	var strike_done := false
	var p_before := bird.global_position
	var max_fwd_travel := 0.0
	var body_rise := 0.0
	var off_start := Vector3.ZERO       # bird 局部系下的命中盒偏移（STRIKE 起始帧）
	var off_hit := Vector3.ZERO         # 同上（首次掉血帧）
	var y_min := INF                    # STRIKE 全程命中盒相对鸟根竖直偏移的范围
	var y_max := -INF
	var h_len_min := INF                # 同上：水平长度范围
	var h_len_max := -INF
	var p_strike := bird.global_position
	var p_hit := bird.global_position

	for _i in MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var st: int = bird.state
		var hp: int = player.health.current_hp
		var cur_anim := String(anim_player.current_animation) if anim_player != null else ""

		if st == EnemyBrute.State.WINDUP:
			windup_frames += 1
			if cur_anim == WINDUP_ANIM:
				windup_anim_frames += 1
			if hp != hp0:
				windup_damage = true
		elif st == EnemyBrute.State.STRIKE:
			strike_frames += 1
			if cur_anim == ATTACK_ANIM:
				strike_anim_frames += 1
			if not reached_strike:
				reached_strike = true
				strike_frame = frames
				p_strike = bird.global_position
				if shape_node != null:
					off_start = bird.global_transform.affine_inverse() * shape_node.global_position
			# 记录 STRIKE 期间鸟身体到底往前冲了多少（用于论证失败路径不含前冲）
			max_fwd_travel = maxf(max_fwd_travel, p_before.distance_to(Vector3(
				p_before.x, p_before.y, bird.global_position.z)))
			# 身体在动（跃扑的竖直抬升）—— 命中的是 root 骨，不是命中盒
			if root_idx >= 0:
				var bworld := skel.global_transform * (skel.get_bone_global_pose(root_idx).origin)
				body_rise = maxf(body_rise, bworld.y - bird.global_position.y)
			# 命中盒相对鸟根的偏移（若命中盒随动画飘，这里就会变）
			if shape_node != null:
				var lv := bird.global_transform.affine_inverse() * shape_node.global_position
				y_min = minf(y_min, lv.y)
				y_max = maxf(y_max, lv.y)
				var hl := Vector2(lv.x, lv.z).length()
				h_len_min = minf(h_len_min, hl)
				h_len_max = maxf(h_len_max, hl)
		elif reached_strike and not strike_done:
			strike_done = true        # 已观测到一次完整 STRIKE（离开了 STRIKE 相）

		if mon_frame < 0 and hitbox != null and hitbox.monitoring:
			mon_frame = frames
		if hp != hp0 and not hit_seen:
			hit_seen = true
			hp1 = hp
			hit_frame = frames
			hit_state = st
			hit_anim = cur_anim
			p_hit = bird.global_position
			if shape_node != null:
				off_hit = bird.global_transform.affine_inverse() * shape_node.global_position

		if strike_done:
			break

	var lunge_at_hit := p_strike.distance_to(p_hit)
	print("  WINDUP 帧数=%d（其中播 %s 的帧=%d）  STRIKE 帧数=%d（其中播 %s 的帧=%d）"
		% [windup_frames, WINDUP_ANIM, windup_anim_frames, strike_frames, ATTACK_ANIM, strike_anim_frames])
	print("  STRIKE 起始帧=%d  命中盒 monitoring 帧=%d  首次掉血帧=%d"
		% [strike_frame, mon_frame, hit_frame])
	print("  骨骼 root 骨在 STRIKE 期间竖直抬升 body_rise=%.4f m（「跃扑」的身体在动）" % body_rise)
	print("  命中盒相对鸟根的偏移：STRIKE 起始 %s  命中帧 %s"
		% [str(off_start), str(off_hit)])
	print("  命中瞬间：p_strike.z=%.4f → p_hit.z=%.4f，前冲位移=%.4f m；" %
		[p_strike.z, p_hit.z, lunge_at_hit])
	print("  STRIKE 期间鸟最大前冲位移=%.4f m（墙应把它钉在 ~0）  玩家 hp=%d → %d"
		% [max_fwd_travel, hp0, hp1])

	# ---- 序列覆盖：真实 AI 确实走完了 WINDUP（AttackWindup）→ STRIKE（Attack）----
	_check(windup_frames > 0 and windup_anim_frames > 0,
		"★ 覆盖 AttackWindup（1–13）：真实 AI 进了蓄力相并在播 %s" % WINDUP_ANIM,
		"WINDUP %d 帧 / 播对动画 %d 帧" % [windup_frames, windup_anim_frames])
	_check(reached_strike and strike_frames > 0,
		"★ 覆盖 Attack（1–7）：真实 AI 走完了蓄力→出手", "STRIKE %d 帧（起始帧 %d）"
			% [strike_frames, strike_frame])
	_check(hitbox == null or mon_frame > 0, "出手时命中盒真的开过（monitoring=true）",
		"monitoring 帧=%d" % mon_frame)

	if zero_offset:
		# ---- 负控：清零 offset ⇒ 必须打不到（可证伪；证伪"命中来自前冲/动画"这条假绿）----
		_check(hp1 == hp0, "★ [负控] 清零 hitbox_offset 后，同距离玩家**不掉血**（命中确实来自前伸几何）",
			"hp %d → %d" % [hp0, hp1])
		_check(not windup_damage, "★ [负控] 蓄力期也不掉血")
		_check(reached_strike, "★ [负控] 鸟仍正常走完出手（不是「没出招所以没打中」）",
			"STRIKE 起始帧=%d" % strike_frame)
	else:
		# ---- 主测：真掉血、掉血量正确、隔离前冲 ----
		_check(reached_strike, "鸟走完了 CHASE→WINDUP→STRIKE（命中盒确实开过）")
		_check(hp1 < hp0, "★ 鸟出手时玩家真的掉血（命中盒前伸 1.3m 罩住了玩家）",
			"hp %d → %d" % [hp0, hp1])
		_check(hp0 - hp1 == bird.attack_damage,
			"掉血量 = attack_damage = %d" % bird.attack_damage, "实际 %d" % (hp0 - hp1))
		_check(hit_state == EnemyBrute.State.STRIKE,
			"★ 掉血只发生在攻击帧（Attack），蓄力期（AttackWindup）不掉血",
			"掉血时 state=%d anim=%s" % [hit_state, hit_anim])
		_check(not windup_damage, "★ 蓄力期（AttackWindup 1–13）全程零掉血")
		_check(hit_anim == ATTACK_ANIM, "掉血帧播的正是 %s" % ATTACK_ANIM, "实际 %s" % hit_anim)
		_check(lunge_at_hit < MAX_HIT_LUNGE,
			"★ 命中瞬间鸟前冲位移 ≈ 0（命中来自盒子前伸，而非前冲）",
			"%.4f m < %.2f" % [lunge_at_hit, MAX_HIT_LUNGE])
		_check(max_fwd_travel < MAX_HIT_LUNGE,
			"★ 整场 STRIKE 鸟前冲被墙钉住（≤ %.2f m）" % MAX_HIT_LUNGE,
			"%.4f m" % max_fwd_travel)
		# ---- 参考系（offset 完好时才有意义）：命中盒相对鸟根偏移在 STRIKE 全程恒定 ----
		if shape_node != null and strike_frames > 0:
			_check(y_min > HITBOX_OFFSET.y - REF_Y_TOL and y_max < HITBOX_OFFSET.y + REF_Y_TOL,
				"★ 参考系：STRIKE 全程命中盒相对鸟根竖直偏移恒 ≈ %.2f（不随跃扑动画抬升）" % HITBOX_OFFSET.y,
				"范围 [%.4f, %.4f]（跨度 %.4f，容差 %.2f）" % [y_min, y_max, y_max - y_min, REF_Y_TOL])
			var want_h := Vector2(HITBOX_OFFSET.x, HITBOX_OFFSET.z).length()
			_check(h_len_min > want_h - REF_H_TOL and h_len_max < want_h + REF_H_TOL,
				"★ 参考系：STRIKE 全程命中盒相对鸟根水平长度恒 ≈ %.2f" % want_h,
				"范围 [%.4f, %.4f]" % [h_len_min, h_len_max])
			_check(body_rise > BODY_RISE_MIN,
				"★ 身体确实在跃（root 骨抬升 > %.2f）—— 证明「命中盒不动」不是因为它没动" % BODY_RISE_MIN,
				"body_rise=%.4f" % body_rise)

	bird.free()
	player.free()
	await get_tree().process_frame


# ------------------------------------------------------------------
# 工具
# ------------------------------------------------------------------

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
