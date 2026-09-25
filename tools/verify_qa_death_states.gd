extends Node
## ============================================================
## QA 独立验证 · 边界死亡：让狼死在**非正常状态**（WINDUP / BROKEN / STAGGER）
## ============================================================
## 运行（★ 跑场景，不是 --script；原因见 verify_wolf_hitbox.gd 顶部）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_qa_death_states.tscn
##
## 【为什么要单开这个探针】enemy.gd 的 _animate_death() 里加了三行"防御"：
##     _pivot.rotation.x 回零、_pivot.rotation.z 回零、_pivot.scale = ONE
##   理由是：WINDUP 会把 _pivot.scale 写成脉动值(1±0.03)、BROKEN 会把 _pivot.rotation.z 写成
##   左右打晃值(±0.05)。如果死在那一刻，尸体就可能**冻结在这些残留变换上**。
##   工程师的 verify_wolf_death / verify_brute_death 只在 IDLE→Death 路径上采样，
##   从未覆盖"带残留变换时死亡"，所以这三行防御**至今零断言覆盖**。
##
## 【本探针怎么证明防御有效（且能被证伪）】
##   1. 先把狼推进 WINDUP（等脉动 scale 偏离 1 超过 0.02）/ BROKEN（等打晃 |rot.z| 超 0.03）/
##      STAGGER，**记录死前的脏值**；
##   2. 调 _die()；
##   3. 断言：尸体最终 scale ≈ 1、|rot.z| ≈ 0 —— 即"脏值被清掉"，而不是冻结；
##      并断言 |终值 − 脏值| 足够大（证明它确实动了，不是碰巧脏值≈净值的假通过）。
##   4. 同时断言：不缩小、不叠加程序化栽倒、骨骼**没有复位**（最大骨骼偏离 rest 仍很大）。
##
## 【与工程师探针的关系】完全独立编写，不依赖其任何断言；仅共用 wolf.tscn 资产。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"

const SCALE_EPS := 0.005       # 终值 scale 允许偏离 1 的上限
const ROTX_MAX := 0.2          # 程序化栽倒会把 rot.x 拉到 ~-1.57，超过 0.2 即视为叠加
const ROTZ_EPS := 0.01         # 终值 |rot.z| 上限
const DIRTY_SCALE_MIN := 0.02  # WINDUP 脉动必须偏离到这么大才继续（保证测试有意义）
const DIRTY_ROTZ_MIN := 0.03   # BROKEN 打晃必须打到这么大才继续
const BONE_MIN_DEG := 10.0     # 骨骼**未复位**阈值：末帧至少有一根骨偏离 rest ≥ 此值

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== QA 边界死亡验证（WINDUP / BROKEN / STAGGER）===")
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

	await _run_case("WINDUP")
	await _run_case("BROKEN")
	await _run_case("STAGGER")

	print("")
	if _fail == 0:
		print("结论：边界死亡全部通过 ✓（脏值被清、不缩小、不栽倒、骨骼不复位）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


func _run_case(case_name: String) -> void:
	print("\n---- 死在 %s ----" % case_name)

	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate() as EnemyBrute
	wolf.position = Vector3(0, 0.1, 0)
	add_child(wolf)
	await get_tree().process_frame
	await get_tree().process_frame

	var pre_scale := 1.0
	var pre_rotz := 0.0
	var want_state := -1
	var dirty_ready := false

	match case_name:
		"WINDUP":
			want_state = EnemyBrute.State.WINDUP
			wolf.windup_time = 30.0                # 测试夹具：不让它自己走完蓄力去 STRIKE
			wolf.state = EnemyBrute.State.WINDUP
			wolf._state_time = 0.0
			for i in 200:
				await get_tree().process_frame
				pre_scale = wolf._pivot.scale.x
				if absf(pre_scale - 1.0) > DIRTY_SCALE_MIN:
					dirty_ready = true
					break
		"BROKEN":
			want_state = EnemyBrute.State.BROKEN
			wolf.poise.percent(100.0)              # 顶满失衡 → broken_started → state=BROKEN
			for i in 200:
				await get_tree().process_frame
				pre_rotz = wolf._pivot.rotation.z
				if absf(pre_rotz) > DIRTY_ROTZ_MIN:
					dirty_ready = true
					break
		"STAGGER":
			want_state = EnemyBrute.State.STAGGER
			wolf.state = EnemyBrute.State.STAGGER
			wolf._state_time = 0.0
			wolf._stagger_time = 30.0              # 测试夹具：不让它自己走完硬直
			await get_tree().process_frame
			pre_scale = wolf._pivot.scale.x
			pre_rotz = wolf._pivot.rotation.z
			dirty_ready = true

	_check(wolf.state == want_state, "死前确实处于 %s" % case_name,
		"state=%d" % wolf.state)
	_check(dirty_ready, "死前已产生/捕捉到状态残留量",
		"pre_scale=%.4f pre_rotz=%.4f" % [pre_scale, pre_rotz])
	print("  死前脏值：scale=%.4f  rot.z=%.4f" % [pre_scale, pre_rotz])

	# ---- 触发死亡 ----
	wolf._die()
	_check(wolf.state == EnemyBrute.State.DEAD, "切到 DEAD")
	var anim: AnimationPlayer = wolf.get("_anim_player")
	_check(anim != null and anim.current_animation == "Death", "死亡时开始播 Death")

	var t0 := Time.get_ticks_msec()
	var frames := 0
	var freed := false
	var min_scale := 999.0
	var max_rotx := 0.0
	var max_rotz := 0.0
	var final_scale := pre_scale
	var final_rotz := pre_rotz
	var bone_dev := -1.0
	var bone_at := -1.0

	for i in 300:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(wolf):
			freed = true
			break
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		min_scale = minf(min_scale, wolf._pivot.scale.x)
		max_rotx = maxf(max_rotx, absf(wolf._pivot.rotation.x))
		max_rotz = maxf(max_rotz, absf(wolf._pivot.rotation.z))
		final_scale = wolf._pivot.scale.x
		final_rotz = wolf._pivot.rotation.z
		# 在"死亡动画已播完、尸体未清"的窗口取骨骼末帧（狼 Death 1.0417s，销毁 1.297s）
		if bone_dev < 0.0 and el >= 1.10 and el <= 1.30:
			var skel: Skeleton3D = wolf.get("_skeleton")
			if skel != null:
				bone_dev = _max_bone_dev_deg(skel)
				bone_at = el

	print("  采样 %d 帧：min_scale=%.4f max|rot.x|=%.4f max|rot.z|=%.4f  freed=%s" %
		[frames, min_scale, max_rotx, max_rotz, str(freed)])
	print("  终值：scale=%.4f rot.z=%.4f   骨骼最大偏离 rest=%.1f°@%.2fs" %
		[final_scale, final_rotz, bone_dev, bone_at])

	_check(freed, "[%s] 尸体最终被 queue_free 清场" % case_name)
	# 1) 不缩小
	_check(min_scale > 0.95, "[%s] 尸体不缩小（min scale ≈ 1）" % case_name, "%.4f" % min_scale)
	# 2) 不叠加程序化栽倒
	_check(max_rotx < ROTX_MAX, "[%s] 不叠加程序化栽倒（|rot.x| < %.1f）" % [case_name, ROTX_MAX],
		"max=%.4f" % max_rotx)
	# 3) WINDUP 残留 scale 必须被清
	_check(absf(final_scale - 1.0) < SCALE_EPS,
		"[%s] ★ 尸体 scale 被清零回 1（不冻结在脉动值）" % case_name, "终值 %.4f" % final_scale)
	if case_name == "WINDUP":
		_check(absf(final_scale - pre_scale) > DIRTY_SCALE_MIN,
			"[%s] ★ 终值确实离开了死前脏值（非碰巧通过）" % case_name,
			"%.4f → %.4f" % [pre_scale, final_scale])
	# 4) BROKEN 残留 rot.z 必须被清
	_check(absf(final_rotz) < ROTZ_EPS,
		"[%s] ★ 尸体 rot.z 被清零（不冻结在打晃值）" % case_name, "终值 %.4f" % final_rotz)
	if case_name == "BROKEN":
		_check(absf(final_rotz - pre_rotz) > DIRTY_ROTZ_MIN,
			"[%s] ★ 终值确实离开了死前脏值（非碰巧通过）" % case_name,
			"%.4f → %.4f" % [pre_rotz, final_rotz])
	_check(max_rotz < ROTX_MAX, "[%s] 全程 |rot.z| 也被压住" % case_name, "max=%.4f" % max_rotz)
	# 5) 骨骼不复位
	_check(bone_dev > BONE_MIN_DEG,
		"[%s] ★ 骨骼未复位（末帧仍大幅偏离 rest）" % case_name, "%.1f°" % bone_dev)

	if is_instance_valid(wolf):
		wolf.free()


## 所有骨骼"当前 pose 旋转"与 rest 旋转的最大夹角（度）。复位后应≈0；末帧冻结后应显著>0。
func _max_bone_dev_deg(skel: Skeleton3D) -> float:
	var m := 0.0
	for i in skel.get_bone_count():
		var rest: Quaternion = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		var pose: Quaternion = skel.get_bone_pose_rotation(i)
		m = maxf(m, rad_to_deg(pose.angle_to(rest)))
	return m
