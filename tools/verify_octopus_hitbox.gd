extends Node
## ============================================================
## 实机验证章鱼的命中盒：几何边界 + 真实伤害 + 命中盒参考系（不随挥腕动画飘）+ ★ 可证伪负控
## ============================================================
## 运行（★ 必须跑**场景**，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_octopus_hitbox.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##   【为什么必须 .tscn】enemy.gd 以标识符方式引用 autoload `EventBus`；`--script` 下 autoload
##   不注册，会在**编译期**报 `Identifier not found: EventBus` 并连锁挂掉所有依赖脚本。
##
## ----------------------------------------------------------------------------
## ★ 本文件守的盲区（为什么它必须存在）：
##   章鱼此前**只有** verify_enemy_octopus —— 那条管的是"场景接线"（enemy_id / 数值哨兵 /
##   命中盒尺寸偏移是不是对），**没有任何**探针在真实物理世界里验证"章鱼真能咬到这个距离的玩家"。
##   三物种里狼有 verify_wolf_hitbox、鸟有 verify_bird_hitbox，**章鱼这一格是空的**。
##   本项目刚吃过一次教训：一套 15 项全绿的回归套件里，四个物种的尸体穿地 bug 照样活着 ——
##   因为套件里**没有任何一条**属性被断言到"尸体不会穿地"。**全绿只能证明被断言过的属性。**
##   本探针就是补齐三物种最后一个命中盒覆盖缺口：把"章鱼出手真能命中玩家"变成
##   端到端、可证伪的断言。
##
## ----------------------------------------------------------------------------
## ★ 照 verify_bird_hitbox 的骨架移植（鸟是章鱼在"需真实 AI 出手 + 几何边界"上的最近同类）：
##   1) **走真实 AI 入口**：不直接赋 `state = WINDUP`，而是把玩家摆进章鱼的 aggro/attack 半径，
##      让章鱼自己 IDLE→CHASE→WINDUP→STRIKE。这样测到的是"玩家真会被这只怪咬到"的端到端事实，
##      而不是"手推状态机能咬到"。
##   2) **几何 + 真掉血双断言**：既断言命中盒的**几何量**（尺寸/偏移，资产漂移哨兵），
##      也断言玩家 Health **真的掉了 attack_damage（14）点**，并给出**可证伪的负控**（见 3）。
##   3) **★ 负控（本文件最有价值的一条）**：跑第二遍，把 `hitbox_offset` 清零后，在**同一距离、
##      同一堵墙**下再打一次 —— 必须**打不到**。这一遍专治假绿：若"命中"其实来自章鱼身体前冲 /
##      命中盒跟着挥腕动画前伸，那么清零 offset 也照样掉血、负控就会**变红**。
##      负控通过 ⇒ 主测掉血**只可能**来自前伸的盒几何。
##
## ----------------------------------------------------------------------------
## ★ 隔离前冲的两个手法（缺一不可，理由同 verify_wolf_hitbox / verify_bird_hitbox）：
##   1) **物理墙 LungeBlocker**：立在章鱼（z=0，胶囊半径 0.45 → 前端 z=−0.45）与玩家
##      （z=−FORWARD_DIST）之间。章鱼 STRIKE 会给一个前冲速度（enemy.gd `velocity = _lunge_dir*8*k`，
##      积分可达 ~1.1 m），墙把它钉住 —— 命中**只能**来自盒子往前伸出的那段几何，与身体是否前冲无关。
##      ★ 关键原理：**墙只挡 `CharacterBody3D` 的位移，不影响 `Area3D` 的几何重叠判定** ——
##      所以它隔离了"靠前冲撞进玩家身体"这条假绿路径，却**不**会改掉命中盒本身的几何判定。
##   2) **边界距离** FORWARD_DIST：见下方几何依据 —— 玩家近端落在
##      （零偏移盒前沿, 有偏移盒前沿）之间 ⇒ 有偏移命中、零偏移够不着。
##   ★ 墙的**承重性**（它是否真的在承载这条负控）由一次**独立证伪实验**证明，
##     不靠嘴说：临时去掉墙 + 清零 offset ⇒ 负控立刻变红（玩家又掉血）。
##     本文件 `_build_world(with_wall)` 的参数即为该实验的复现开关（默认 true）。
##
## ----------------------------------------------------------------------------
## ★ 几何依据（octopus.tscn：hitbox_size=(2.6,1.1,2.2), hitbox_offset=(0,0.45,−1.1)）：
##   命中盒是挂在 VisualPivot 下的 BoxShape3D，中心局部 (0,0.45,−1.1)、z 尺寸 2.2 → 半宽 1.1：
##     · 有偏移盒  局部 z ∈ [−2.2,  0.0]（**前沿 −2.2**）
##     · 零偏移盒（负控）局部 z ∈ [−1.1, +1.1]（前沿 −1.1）
##   玩家胶囊 radius=0.35（player.tscn）→ 玩家近端 z = −FORWARD_DIST + 0.35。
##   要同时"零偏移够不着"且"有偏移罩得住"：−2.2 < −D + 0.35 < −1.1 ⇒ 1.45 < D < 2.55。
##   取 FORWARD_DIST = 2.0（玩家近端 z = −1.65）：
##     · −1.65 < −1.10  ⇒ 零偏移盒够不着（差 0.55 m）★ 负控依据
##     · −1.65 > −2.20  ⇒ 有偏移盒把玩家罩住（深入 0.55 m）
##   墙位：章鱼前端 z=−0.45；墙后表面放在其前 WALL_LUNGE_GAP(=0.05) 处（z=−0.50）
##         ⇒ 允许前冲 ≈ 0.05 m ≪ MAX_HIT_LUNGE(=0.10)。
##
## ----------------------------------------------------------------------------
## ★ 参考系（"挥腕/伏地"专属的坑，狼版没有）：
##   enemy.gd 把命中盒挂在 **VisualPivot**（只随朝向绕 Y 转、不随骨骼动画位移），
##   所以命中盒与角色的**相对偏移应当恒定**；若哪天有人把它挪到"随动画位移的节点"下
##   （例如挂到模型骨骼上），命中盒就会跟着挥腕一起飘 → 够到不该够到的距离。
##   本文件用两条断言钉死参考系：
##     · 结构：命中盒的父节点必须是 VisualPivot，且命中盒**不是**模型节点的后代；
##     · 动态：STRIKE 全程 `octopus.global_transform⁻¹ · hitbox.global_position`
##       与 HITBOX_OFFSET 逐分量相等（容差 1e-3）。
##   ★ 关于"身体在动"这条证据：鸟用 `BODY_RISE_MIN := 0.04` 断言跃扑抬升；**章鱼不能照抄**
##     —— 它是伏地体型、Attack 无跃起（不像鸟的跃扑）。本文件改为**如实实测并打印** STRIKE 期间
##     root 骨的竖直位移范围，断言它"稳定在实测量附近"（跨度 < ROOT_Y_TOL），并额外打印一条腕节骨
##     的运动幅度，证明"命中盒不动"不是因为"整个骨架根本没动"。为凑一条断言而放宽阈值是本项目
##     明令禁止的，故这里不写一个章鱼达不到的抬升门限。
## ============================================================

const OCTOPUS_TSCN := "res://scenes/enemy/octopus.tscn"
const PLAYER_TSCN := "res://scenes/player/player.tscn"
const MODEL_PATH := "res://assets/enemies/octopus_01/octopus_rigged.glb"

## 玩家摆在章鱼正前方的距离（米）。取值论证见文件头（2.0 落在"只有前伸才够得着"的窗口）。
const FORWARD_DIST := 2.0
## 命中瞬间 / 整场 STRIKE 允许的"章鱼身体前冲位移"上限（m）。墙会把它钉住，故实测应 ≈ 0；
## 该断言显式证明本探针的命中不是靠前冲补偿的。
const MAX_HIT_LUNGE := 0.10
## 单场景最多推进的物理帧数（60fps ⇒ 480 帧 = 8s）：足够 CHASE→WINDUP(0.5s)→STRIKE(0.28s)。
const MAX_FRAMES := 480
## 落位后稳定帧数（等落地、_ready 装配、贴墙）。
const SETTLE_FRAMES := 12
## 观测到一次完整 STRIKE 后，再多跑几帧再收尾 —— 让"负控的零掉血"覆盖到出手之后，防漏判。
const TAIL_FRAMES := 6

## 命中盒几何（与 octopus.tscn 的 @export 一致，作为资产漂移哨兵）
const HITBOX_SIZE := Vector3(2.6, 1.1, 2.2)
const HITBOX_OFFSET := Vector3(0.0, 0.45, -1.1)
## 玩家 / 章鱼的碰撞胶囊半径（player.tscn / octopus.tscn）
const PLAYER_RADIUS := 0.35
const OCTOPUS_RADIUS := 0.45

## 墙后表面相对章鱼前端的预留前冲缝隙（米）：墙后表面 z = 章鱼前端 z − 本值。
const WALL_LUNGE_GAP := 0.05
## 墙厚（米，薄墙）。
const WALL_THICKNESS := 0.10

## 参考系断言容差：STRIKE 全程命中盒相对**章鱼根**的偏移应逐分量恒定（米）。
const REF_OFFSET_TOL := 0.001
## root 骨竖直位移"稳定"容差（米）：章鱼伏地、Attack 无跃起，故只断言"稳定在实测量附近"。
const ROOT_Y_TOL := 0.05

## 期望动画名（enemy.gd 关键字识别的结果）
const WINDUP_ANIM := "AttackWindup"
const ATTACK_ANIM := "Attack"
## AttackWindup / Attack 的设计帧数（1..N，24fps）→ Animation.length = N/24
## （= 章鱼 DESIGN.md 的内容时长 0.5 / 0.25 + 1/24 帧偏移 ⇒ 13/24 与 7/24）
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
	print("=== 章鱼命中盒实机验证（几何边界 + 真实伤害 + 参考系 + 负控）===")
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
## [A] 资产：AttackWindup 1–13 / Attack 1–7 的帧覆盖（length = N/24）
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
## @param with_wall true = 正常（立 LungeBlocker 墙）；false = **仅用于证伪实验**
##        （去掉墙后，负控应立刻变红 —— 这就是"墙是承重的"证明）。
func _build_world(with_wall: bool = true) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(60.0, 1.0, 60.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	if with_wall:
		# ★ 挡前冲的墙：立在章鱼（前端 z=−0.45）与玩家（z=−FORWARD_DIST）之间。
		#   后表面 = 章鱼前端 z − WALL_LUNGE_GAP = −0.45 − 0.05 = −0.50 → 章鱼最多前移 ~0.05 就被挡住。
		#   只挡 CharacterBody3D 的位移，不挡 Area3D 的几何重叠判定。
		var wall := StaticBody3D.new()
		wall.name = "LungeBlocker"
		var wcol := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = Vector3(60.0, 3.0, WALL_THICKNESS)
		wcol.shape = wbox
		wall.add_child(wcol)
		wall.position = Vector3(0, 1.0, -(OCTOPUS_RADIUS + WALL_LUNGE_GAP + WALL_THICKNESS * 0.5))
		add_child(wall)
	else:
		print("  ⚠ [证伪实验] 未立 LungeBlocker 墙 —— 用于复现“墙是承重的”证伪（负控应变红）")

	# 几何窗口自检（打印即可，证明 FORWARD_DIST 落在正确的窗口里）
	var player_near := -(FORWARD_DIST) + PLAYER_RADIUS
	var zero_far := -(HITBOX_SIZE.z * 0.5)
	var off_far := HITBOX_OFFSET.z - HITBOX_SIZE.z * 0.5
	print("  [几何] 玩家近端 z=%.2f；零偏移盒前沿 z=%.2f（够不着? %s，间隙 %.2f m）；有偏移盒前沿 z=%.2f（深入 %.2f m）"
		% [player_near, zero_far, str(player_near < zero_far), absf(player_near - zero_far),
			off_far, absf(player_near - off_far)])


## ==================================================================
## 单个场景：摆好章鱼 + 玩家，让**真实 AI** 打一棒，逐帧取证
## ==================================================================
## @param zero_offset true = 负控（把 hitbox_offset 清零，期望打不到）
func _scenario(zero_offset: bool) -> void:
	var title := "[负控] hitbox_offset 清零 ⇒ 同距离必须打不到" if zero_offset \
		else "[主测] 真实 AI 出手 ⇒ 玩家真掉血（掉血量 == attack_damage）"
	print("\n[B] %s" % title)

	# ---- 章鱼（面朝 −Z；★ 先定位再入树）—— ai_enabled 保持默认 true ⇒ 走真实 AI ----
	var octopus := (load(OCTOPUS_TSCN) as PackedScene).instantiate() as EnemyBrute
	if octopus == null:
		_fail += 1
		print("  ✗ 实例化 octopus.tscn 失败（不是 EnemyBrute？）")
		return
	_check(octopus.ai_enabled, "章鱼以 ai_enabled=true 出场（走真实 AI 入口，非手推状态机）")
	if zero_offset:
		octopus.hitbox_offset = Vector3.ZERO     # ★ 必须在入树前改：_build_hitbox 在 _ready 里读它
	octopus.position = Vector3(0, 0.1, 0)
	add_child(octopus)

	# ---- 玩家：摆在章鱼正前方 −Z 方向 FORWARD_DIST（★ 同样先定位再入树）----
	var player := (load(PLAYER_TSCN) as PackedScene).instantiate() as PlayerCharacter
	if player == null:
		_fail += 1
		print("  ✗ 实例化 player.tscn 失败（不是 PlayerCharacter？）")
		octopus.free()
		return
	player.position = Vector3(0, 0.2, -FORWARD_DIST)
	add_child(player)

	await get_tree().process_frame
	await get_tree().process_frame
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame

	var hitbox: Area3D = octopus.get("_hitbox")
	var anim_player: AnimationPlayer = octopus.get("_anim_player")
	var skel := _find_skeleton(octopus)
	# ★ 骨名大小写防御：章鱼的 root 骨在导入后可能带前后缀，按"含 root"匹配。
	var root_idx := _find_bone_ci(skel, "root")
	var arm_idx := _find_bone_ci(skel, "arm1_tip.l")
	# ★ 模型节点在 VisualPivot 之下（不是章鱼的直接子节点）→ 用 find_child 递归找。
	var model_node: Node = octopus.find_child("octopusModel", true, false)
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
				"★ 命中盒不是模型节点的后代（不会跟着挥腕动画飘）")
		else:
			_fail += 1
			print("  ✗ 找不到模型节点（octopusModel），无法验证命中盒不属于模型")
		if shape_node != null:
			var bs := shape_node.shape as BoxShape3D
			_check(bs != null and bs.size.is_equal_approx(HITBOX_SIZE),
				"命中盒尺寸 = (2.6, 1.1, 2.2)", str(bs.size) if bs != null else "null")
			_check((shape_node.position as Vector3).is_equal_approx(
					Vector3.ZERO if zero_offset else HITBOX_OFFSET),
				"命中盒偏移 = %s" % ("(0,0,0)（负控清零）" if zero_offset else "(0, 0.45, −1.1)"),
				str(shape_node.position))

	# ---- 记录初始血量 ----
	var hp0 := player.health.current_hp
	var dz := player.global_position.z - octopus.global_position.z
	print("  章鱼 z=%.3f（面朝 −Z），玩家 z=%.3f，间距 %.2f m"
		% [octopus.global_position.z, player.global_position.z, absf(dz)])
	print("  玩家初始 hp = %d" % hp0)

	# ---- 逐物理帧取证（★ 不手推 state：让真实 AI 自己走 IDLE→CHASE→WINDUP→STRIKE）----
	# ★ 不在"首次掉血"就 break：要**采满整段 STRIKE**，才能看到挥腕的身体在动、
	#   而命中盒相对章鱼根的偏移纹丝不动（参考系证据）。改为"观测到一次完整 STRIKE 后退出"。
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
	var tail_frames := 0
	var p_before := octopus.global_position
	var max_fwd_travel := 0.0
	var want_off := Vector3.ZERO if zero_offset else HITBOX_OFFSET   # 本场景的期望偏移
	var off_start := Vector3.ZERO       # 章鱼局部系下的命中盒偏移（STRIKE 起始帧）
	var off_hit := Vector3.ZERO         # 同上（首次掉血帧）
	var off_max_dev := 0.0              # STRIKE 全程 |偏移 − 本场景期望偏移| 的最大值
	var root_y_min := INF               # STRIKE 全程 root 骨相对章鱼根的竖直范围
	var root_y_max := -INF
	var root_y_ref := 0.0
	var arm_ref := Vector3.ZERO         # STRIKE 起始时腕节骨的世界位置（证明骨架在动）
	var arm_moved := 0.0
	var arm_have := false
	var p_strike := octopus.global_position
	var p_hit := octopus.global_position

	for _i in MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var st: int = octopus.state
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
				p_strike = octopus.global_position
				if shape_node != null:
					off_start = octopus.global_transform.affine_inverse() * shape_node.global_position
			# 记录 STRIKE 期间章鱼身体到底往前冲了多少（用于论证失败路径不含前冲）
			max_fwd_travel = maxf(max_fwd_travel, p_before.distance_to(Vector3(
				p_before.x, p_before.y, octopus.global_position.z)))
			# 命中盒相对章鱼根的偏移（若命中盒随动画飘，这里就会变）
			if shape_node != null:
				var lv := octopus.global_transform.affine_inverse() * shape_node.global_position
				off_max_dev = maxf(off_max_dev, (lv - want_off).length())
			# 身体在动吗？—— root 骨竖直 + 腕节骨运动（★ 命中的是盒几何，不是骨架）
			if root_idx >= 0:
				var bworld := skel.global_transform * (skel.get_bone_global_pose(root_idx).origin)
				var rel_y := bworld.y - octopus.global_position.y
				if root_y_min == INF:
					root_y_ref = rel_y
				root_y_min = minf(root_y_min, rel_y)
				root_y_max = maxf(root_y_max, rel_y)
			if arm_idx >= 0:
				var aworld := skel.global_transform * (skel.get_bone_global_pose(arm_idx).origin)
				if not arm_have:
					arm_have = true
					arm_ref = aworld
				else:
					arm_moved = maxf(arm_moved, arm_ref.distance_to(aworld))
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
			p_hit = octopus.global_position
			if shape_node != null:
				off_hit = octopus.global_transform.affine_inverse() * shape_node.global_position

		if strike_done:
			tail_frames += 1
			if tail_frames > TAIL_FRAMES:
				break

	var lunge_at_hit := p_strike.distance_to(p_hit)
	print("  WINDUP 帧数=%d（其中播 %s 的帧=%d）  STRIKE 帧数=%d（其中播 %s 的帧=%d）"
		% [windup_frames, WINDUP_ANIM, windup_anim_frames, strike_frames, ATTACK_ANIM, strike_anim_frames])
	print("  STRIKE 起始帧=%d  命中盒 monitoring 帧=%d  首次掉血帧=%d"
		% [strike_frame, mon_frame, hit_frame])
	print("  root 骨在 STRIKE 起始帧的竖直位置 = %.4f m（相对章鱼根；章鱼伏地、Attack 无跃起）" % root_y_ref)
	if root_y_min != INF:
		print("    root 竖直范围 [%.4f, %.4f]（跨度 %.4f m，容差 %.2f）"
			% [root_y_min, root_y_max, root_y_max - root_y_min, ROOT_Y_TOL])
	else:
		print("    （未找到 root 骨，跳过竖直范围统计）")
	print("  腕节骨 arm1_tip 在 STRIKE 期间相对起始的最远位移 = %.4f m（骨架在动）" % arm_moved)
	print("  命中盒相对章鱼根的偏移：STRIKE 起始 %s  命中帧 %s（相对本场景期望 %s 的最大偏差 %.5f m）"
		% [str(off_start), str(off_hit), str(want_off), off_max_dev])
	print("  命中瞬间：p_strike.z=%.4f → p_hit.z=%.4f，前冲位移=%.4f m；"
		% [p_strike.z, p_hit.z, lunge_at_hit])
	print("  STRIKE 期间章鱼最大前冲位移=%.4f m（墙应把它钉在 ~0）  玩家 hp=%d → %d"
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
		_check(reached_strike, "★ [负控] 章鱼仍正常走完出手（不是「没出招所以没打中」）",
			"STRIKE 起始帧=%d" % strike_frame)
	else:
		# ---- 主测：真掉血、掉血量正确、隔离前冲、参考系恒定 ----
		_check(reached_strike, "章鱼走完了 CHASE→WINDUP→STRIKE（命中盒确实开过）")
		_check(hp1 < hp0, "★ 章鱼出手时玩家真的掉血（命中盒前伸 1.1m 罩住了玩家）",
			"hp %d → %d" % [hp0, hp1])
		_check(hp0 - hp1 == octopus.attack_damage,
			"掉血量 = attack_damage = %d" % octopus.attack_damage, "实际 %d" % (hp0 - hp1))
		_check(hit_state == EnemyBrute.State.STRIKE,
			"★ 掉血只发生在攻击帧（Attack），蓄力期（AttackWindup）不掉血",
			"掉血时 state=%d anim=%s" % [hit_state, hit_anim])
		_check(not windup_damage, "★ 蓄力期（AttackWindup 1–13）全程零掉血")
		_check(hit_anim == ATTACK_ANIM, "掉血帧播的正是 %s" % ATTACK_ANIM, "实际 %s" % hit_anim)
		_check(hit_frame == strike_frame,
			"★ 首次掉血帧 == STRIKE 起始帧（掉血来自出手本身，而非别的机制）",
			"strike_frame=%d hit_frame=%d" % [strike_frame, hit_frame])
		_check(lunge_at_hit < MAX_HIT_LUNGE,
			"★ 命中瞬间章鱼前冲位移 ≈ 0（命中来自盒子前伸，而非前冲）",
			"%.4f m < %.2f" % [lunge_at_hit, MAX_HIT_LUNGE])
		_check(max_fwd_travel < MAX_HIT_LUNGE,
			"★ 整场 STRIKE 章鱼前冲被墙钉住（≤ %.2f m）" % MAX_HIT_LUNGE,
			"%.4f m" % max_fwd_travel)
		# ---- 参考系（offset 完好时才有意义）：命中盒相对章鱼根偏移在 STRIKE 全程恒定 ----
		if shape_node != null and strike_frames > 0:
			_check(off_max_dev < REF_OFFSET_TOL,
				"★ 参考系：STRIKE 全程命中盒相对章鱼根偏移恒 == (0, 0.45, −1.1)（不随挥腕动画飘）",
				"最大偏差 %.5f m < %.3f" % [off_max_dev, REF_OFFSET_TOL])
			if root_y_min != INF:
				_check((root_y_max - root_y_min) < ROOT_Y_TOL,
					"★ 参考系：STRIKE 期间 root 骨竖直位移稳定（跨度 < %.2f m；伏地体型，不照抄鸟的跃扑门限）" % ROOT_Y_TOL,
					"范围 [%.4f, %.4f]（跨度 %.4f）" % [root_y_min, root_y_max, root_y_max - root_y_min])

	octopus.free()
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


## 按"含关键字、大小写无关"查骨索引（导入后骨名可能带前后缀/大小写差异）。
func _find_bone_ci(skel: Skeleton3D, key: String) -> int:
	if skel == null:
		return -1
	var k := key.to_lower()
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().contains(k):
			return i
	return -1


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
