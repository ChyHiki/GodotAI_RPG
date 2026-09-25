extends Node
## ============================================================
## 实机验证红甲守卫的死亡观感：尸体**仰面躺平不动、不缩小、不弹回站立**，
## 骨骼**冻在 Death 末帧（不复位）**，并按"死亡动画长度 + 余量"后消失。
## ============================================================
## 运行（★ 跑场景，不是 --script；原因见 verify_wolf_hitbox.gd 顶部）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_brute_death.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##
## 【为什么必须实机测】"尸体不缩小/不弹回站立/骨骼不复位"这三条依赖
##   enemy.gd 的 _animate_death() 与 _die() 的时序（timer、anim blend、free），
##   纯读代码推不出来 —— 必须让真实节点跑过真实的物理/处理帧。
##
## 【守卫 vs 狼】守卫的 Death 是 1.25s 内容（Godot length 1.2917s），比狼的 1.0s 长；
##   于是销毁时长 = max(corpse_linger_time=1.2, 1.2917+0.25) = 1.5417s（狼是 1.2917s）。
##
## 【踩坑记录 · 先设 position 再 add_child】若先 add_child 再设 global_position，
##   节点会先在原点注册一次；本探针只有一个角色，但沿用同一纪律以免将来加玩家时踩坑。
## ============================================================

const BRUTE_TSCN := "res://scenes/enemy/enemy.tscn"

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 红甲守卫死亡观感验证 ===")

	var brute := (load(BRUTE_TSCN) as PackedScene).instantiate() as EnemyBrute
	brute.position = Vector3(0, 0.1, 0)      # ★ 先定位，再入树
	add_child(brute)
	await get_tree().process_frame
	await get_tree().process_frame

	var pivot: Node3D = brute.get("_pivot")
	var anim: AnimationPlayer = brute.get("_anim_player")
	var skel: Skeleton3D = brute.get("_skeleton")
	_check(pivot != null, "拿到 VisualPivot")
	_check(anim != null, "模型带 AnimationPlayer（非程序化兜底）")
	_check(skel != null, "模型带 Skeleton3D")
	_check(brute.get("_death_anim") == "Death", "★ 识别到 Death 动画",
		str(brute.get("_death_anim")))

	# Death 末帧 root 应绕本地 X 转 ~92°（仰面）；先记下 rest，稍后比对
	var root_rest: Quaternion = skel.get_bone_rest(0).basis.get_rotation_quaternion() if skel != null else Quaternion()

	# ---- 触发死亡 ----
	brute._die()
	var t_start := Time.get_ticks_msec()
	var playing: String = anim.current_animation if anim != null else ""
	print("  死亡瞬间：动画 = %s，state = %d" % [playing, brute.state])
	_check(playing == "Death", "死亡时正在播 Death 动画", playing)

	# ---- 逐帧采样：不弹回站立 / 不缩小 / 末帧冻结 ----
	var min_scale := 999.0
	var max_rot_x := 0.0
	var max_rot_z := 0.0
	var frames := 0
	var freed_at := -1.0
	var frozen_checked := false
	var anim_stopped := false
	var pose_root_angle := -1.0
	for i in 400:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(brute):
			freed_at = (Time.get_ticks_msec() - t_start) / 1000.0
			break
		if pivot != null:
			min_scale = minf(min_scale, pivot.scale.x)
			max_rot_x = maxf(max_rot_x, absf(pivot.rotation.x))
			max_rot_z = maxf(max_rot_z, absf(pivot.rotation.z))
		# 在"动画已播完、尸体还没被清"的窗口里检查末帧冻结
		var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
		if not frozen_checked and elapsed >= 1.35 and anim != null:
			anim_stopped = not anim.is_playing()
			var q_pose: Quaternion = skel.get_bone_pose_rotation(0) if skel != null else Quaternion()
			pose_root_angle = rad_to_deg(q_pose.angle_to(root_rest))
			frozen_checked = true

	print("  采样 %d 帧：min_scale=%.4f  max|rot.x|=%.4f  max|rot.z|=%.4f" %
		[frames, min_scale, max_rot_x, max_rot_z])

	_check(min_scale > 0.95, "★ 尸体不缩小消失（scale 恒 ≈ 1）", "min_scale=%.4f" % min_scale)
	_check(max_rot_x < 0.2, "★ 尸体不叠加程序化栽倒（|rot.x| 保持 ≈ 0）", "max=%.4f" % max_rot_x)
	_check(max_rot_z < 0.2, "整体节点侧倾被清零（|rot.z| ≈ 0）", "max=%.4f" % max_rot_z)

	print("  末帧冻结检查：动画已停(not is_playing)=%s   root 姿势↔rest 夹角=%.1f°" %
		[anim_stopped, pose_root_angle])
	_check(frozen_checked, "在动画播完后、尸体清空前取到了末帧样本")
	_check(anim_stopped, "★ 末帧动画已停（单次播完冻结，不是循环）")
	_check(pose_root_angle > 30.0,
		"★ 骨骼**没有复位**（root 仍保持 Death 末帧的大角度，而非回到 rest）",
		"%.1f°" % pose_root_angle)

	print("  尸体在 %.3f s 后被销毁（期望 ≈ 1.542s = max(1.2, Death 1.2917+0.25)）" % freed_at)
	_check(absf(freed_at - 1.5417) < 0.15, "★ 销毁发生在死亡动画长度之后（±0.15s）",
		"%.3fs" % freed_at)

	print("")
	if _fail == 0:
		print("结论：死亡观感验证通过 ✓（仰面躺平、不缩小、不弹回站立、骨骼冻末帧）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)
