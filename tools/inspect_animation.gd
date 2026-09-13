extends SceneTree
## 检查导入模型的某段动画里"左右两侧是否都真的动起来了"。
## 用途：排查"走一步"这类疑似动画不全的问题——直接打印每个骨骼轨道的关键帧值。
##
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##        --script res://tools/inspect_animation.gd -- walk
##
## 不传参数时默认检查 walk。

const MODEL_PATH := "res://assets/characters/player_knight/player_knight.glb"

func _init() -> void:
	var want := "walk"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		want = String(args[0]).to_lower()

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("无法加载 %s" % MODEL_PATH)
		quit(1)
		return
	var inst := packed.instantiate()
	var player := _find_animation_player(inst)
	if player == null:
		push_error("未找到 AnimationPlayer")
		quit(1)
		return

	print("=== 动画列表 ===")
	for n in player.get_animation_list():
		var a := player.get_animation(n)
		print("  %-10s 轨道=%d 时长=%.3fs 循环=%s" % [n, a.get_track_count(), a.length,
			"是" if a.loop_mode != Animation.LOOP_NONE else "否"])

	var target := ""
	for n in player.get_animation_list():
		if String(n).to_lower().contains(want):
			target = String(n)
			break
	if target == "":
		push_error("没有名字含 '%s' 的动画" % want)
		inst.free()
		quit(1)
		return

	var anim := player.get_animation(target)
	print("\n=== %s 的骨骼轨道（每个轨道：键数 + 首/中/末值）===" % target)
	var moved_l := 0
	var moved_r := 0
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D \
				and anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i))
		if not (path.contains("thigh") or path.contains("shin") or path.contains("foot")):
			continue
		var keys := anim.track_get_key_count(i)
		if keys == 0:
			continue
		var first: Variant = anim.track_get_key_value(i, 0)
		var mid: Variant = anim.track_get_key_value(i, keys / 2)
		var last: Variant = anim.track_get_key_value(i, keys - 1)
		var spread := _spread(anim, i, keys)
		print("  %-28s 键=%-3d 幅度=%.4f 首=%s 中=%s 末=%s" % [
			path, keys, spread, _fmt(first), _fmt(mid), _fmt(last)])
		if path.contains(".L") or path.contains("_L") or path.contains("Left"):
			if spread > 0.01:
				moved_l += 1
		elif path.contains(".R") or path.contains("_R") or path.contains("Right"):
			if spread > 0.01:
				moved_r += 1
	print("\n结论：左腿有动作的轨道 %d 条，右腿 %d 条 → %s" % [
		moved_l, moved_r,
		"左右两侧都在动（完整两步循环）" if moved_l > 0 and moved_r > 0 else "有一侧没动！"])
	inst.free()
	quit(0)

## 计算某轨道"关键帧值的最大变化幅度"，用来判断这条轨道到底动没动。
func _spread(anim: Animation, track: int, keys: int) -> float:
	var lo := INF
	var hi := -INF
	for k in keys:
		var v: Variant = anim.track_get_key_value(track, k)
		var n := 0.0
		if v is Quaternion:
			n = (v as Quaternion).get_euler().length()
		elif v is Vector3:
			n = (v as Vector3).length()
		elif v is float:
			n = absf(v as float)
		lo = minf(lo, n)
		hi = maxf(hi, n)
	return hi - lo

func _fmt(v: Variant) -> String:
	if v is Quaternion:
		var e := (v as Quaternion).get_euler()
		return "(%.2f,%.2f,%.2f)" % [e.x, e.y, e.z]
	if v is Vector3:
		return "(%.2f,%.2f,%.2f)" % [(v as Vector3).x, (v as Vector3).y, (v as Vector3).z]
	return str(v)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
