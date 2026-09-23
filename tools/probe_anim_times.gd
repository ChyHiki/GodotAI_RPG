extends SceneTree
## 诊断：把 GLB 导入后每条动画的轨道关键帧时间轴原样打出来，
## 用来搞清 Godot 的 glTF 导入器对 Blender 的"首帧 t=1/24"做了什么处理
## （平移？补一个 t=0 的键？关键帧数量变没变？）。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> \
##       --script res://tools/probe_anim_times.gd

const MODEL_PATH := "res://assets/enemies/brute_01/brute_rigged.glb"


func _init() -> void:
	var scene := load(MODEL_PATH) as PackedScene
	var model := scene.instantiate()
	var ap := _find_ap(model)
	print("AnimationPlayer = %s" % str(ap))
	for name in ap.get_animation_list():
		var a: Animation = ap.get_animation(name)
		print("\n=== %s ===  length=%.4f  track_count=%d" % [name, a.length, a.get_track_count()])
		# 只看第一条轨道，够说明问题
		var ti := 0
		var kc := a.track_get_key_count(ti)
		var times: Array[float] = []
		for k in kc:
			times.append(a.track_get_key_time(ti, k))
		print("  track0 关键帧数 = %d" % kc)
		print("  前 4 个时刻 = %s" % str(times.slice(0, min(4, kc))))
		print("  后 4 个时刻 = %s" % str(times.slice(max(0, kc - 4), kc)))
		if kc >= 2:
			var d0 := times[1] - times[0]
			var d1 := times[kc - 1] - times[kc - 2]
			print("  首间隔 = %.4f s   末间隔 = %.4f s   (1/24=%.4f)" % [d0, d1, 1.0 / 24.0])
			print("  跨度 = %.4f s" % (times[kc - 1] - times[0]))
	model.free()   # 不释放会在退出时报一堆 RID / ObjectDB 泄漏，干扰看结果
	quit(0)


func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f := _find_ap(c)
		if f != null:
			return f
	return null
