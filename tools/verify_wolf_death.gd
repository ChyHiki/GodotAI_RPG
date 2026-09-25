extends Node
## ============================================================
## 实机验证狼的死亡观感：尸体**侧躺不动、不缩小、不弹回站立**，并按动画长度后消失。
## ============================================================
## 运行（★ 跑场景，不是 --script；原因见 verify_wolf_hitbox.gd 顶部）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_wolf_death.tscn
##
## 【验证的三条"死亡必须不做的事"】
##   1. 不复位骨骼（复位会让尸体"啪"地站回去）—— 有 Death 动画时走"末帧保持"分支；
##   2. 不叠加程序化栽倒（rotation.x 不应被拉到 -90°）；
##   3. 不缩小消失（scale 应恒为 1，而不是 lerp 到 0）。
##   同时确认：销毁发生在"死亡动画长度之后"（本体 1.0417s + 0.25 余量 = 1.2917s）。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 狼死亡观感验证 ===")

	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate() as EnemyBrute
	wolf.position = Vector3(0, 0.1, 0)
	add_child(wolf)
	await get_tree().process_frame
	await get_tree().process_frame

	var pivot: Node3D = wolf.get("_pivot")
	var anim: AnimationPlayer = wolf.get("_anim_player")
	_check(pivot != null, "拿到 VisualPivot")
	_check(anim != null and wolf.get("_death_anim") == "Death", "识别到 Death 动画")

	# ---- 触发死亡 ----
	wolf._die()
	var t_start := Time.get_ticks_msec()
	var playing: String = anim.current_animation if anim != null else ""
	print("  死亡瞬间：动画 = %s，state = %d" % [playing, wolf.state])
	_check(playing == "Death", "死亡时正在播 Death 动画", playing)

	# ---- 采样若干帧，检查"不弹回站立 / 不缩小"----
	var min_scale := 999.0
	var max_rot_x := 0.0
	var max_rot_z := 0.0
	var frames := 0
	var freed_at := -1.0
	for i in 200:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(wolf):
			freed_at = (Time.get_ticks_msec() - t_start) / 1000.0
			break
		if pivot != null:
			min_scale = minf(min_scale, pivot.scale.x)
			max_rot_x = maxf(max_rot_x, absf(pivot.rotation.x))
			max_rot_z = maxf(max_rot_z, absf(pivot.rotation.z))

	print("  采样 %d 帧：min_scale=%.4f  max|rot.x|=%.4f  max|rot.z|=%.4f" %
		[frames, min_scale, max_rot_x, max_rot_z])

	_check(min_scale > 0.95, "★ 尸体不缩小消失（scale 恒 ≈ 1）", "min_scale=%.4f" % min_scale)
	_check(max_rot_x < 0.2, "★ 尸体不叠加程序化栽倒（|rot.x| 保持 ≈ 0）", "max=%.4f" % max_rot_x)
	_check(max_rot_z < 0.2, "整体节点侧倾被清零（|rot.z| ≈ 0）", "max=%.4f" % max_rot_z)

	print("  尸体在 %.3f s 后被销毁（期望 ≈ 1.29s = Death 长度 1.0417 + 0.25）" % freed_at)
	_check(freed_at > 1.15, "★ 销毁不早于死亡动画长度", "%.3fs" % freed_at)
	_check(freed_at > 0.0 and freed_at < 2.0, "尸体在 2s 内被清场", "%.3fs" % freed_at)

	print("")
	if _fail == 0:
		print("结论：死亡观感验证通过 ✓（侧躺不动、不缩小、不弹回站立）")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)
