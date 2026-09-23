extends SceneTree
## 把导入的玩家模型（assets/characters/player_knight/player_knight.glb）里的动画
## 逐个导出为独立的 Animation 资源，分类存放到 animations/ 子目录。
##
## 运行方式（headless，一次性生成）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/split_player_animations.gd
##
## 说明：游戏里通常直接播放导入场景内 AnimationPlayer 的动画（名字即 Walk / Slash / ...）；
## 这里额外导出的 .tres 便于在编辑器里预览、复用，或挂到 AnimationLibrary 上。
## 对"循环类"动画（Walk / JumpAir）会额外裁掉末尾重复帧，让循环无缝。

const MODEL_PATH := "res://assets/characters/player_knight/player_knight.glb"
const OUT_DIR := "res://assets/characters/player_knight/animations"
const FPS := 24.0                      # 源动画的帧率（Blender 导出时按 24fps 烘焙）
## 名字命中这些关键词的动画按"循环"处理（首尾帧姿势相同 → 需要裁掉末尾重复帧 + 开循环）。
## 注意 blockhold / idle 必须列在这里：它们的名字里既没有 walk 也没有 air，
## 漏掉的话导出的 block_hold.tres / idle.tres 会是"单次播放"，编辑器里预览循环会一顿一顿
## （游戏内不受影响 —— player.gd 的 _set_loop() 会在运行时把 loop_mode 打开）。
const LOOP_HINTS := ["walk", "air", "blockhold", "idle"]

func _init() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("模型不存在: %s（请先运行 --import 导入资源）" % MODEL_PATH)
		quit(1)
		return

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("无法加载: %s" % MODEL_PATH)
		quit(1)
		return

	var inst := packed.instantiate()
	var player := _find_animation_player(inst)
	if player == null:
		push_error("未在模型中找到 AnimationPlayer")
		inst.free()
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var names := player.get_animation_list()
	print("=== 模型内动画 (%d 个) ===" % names.size())
	var saved := 0
	for anim_name in names:
		var anim: Animation = player.get_animation(anim_name)
		if anim == null:
			continue
		var dup: Animation = anim.duplicate(true) as Animation
		dup.resource_name = anim_name
		var is_loop := _is_loop_name(String(anim_name))
		if is_loop:
			# 首尾帧姿势相同的循环动画：把时长裁掉一帧，循环回到第 0 帧时不会"停一拍"
			dup.loop_mode = Animation.LOOP_LINEAR
			dup.length = maxf(0.05, dup.length - 1.0 / FPS)
		var file_name := String(anim_name).to_snake_case() + ".tres"
		var path := OUT_DIR.path_join(file_name)
		var err := ResourceSaver.save(dup, path)
		if err == OK:
			saved += 1
			print("  已导出 %-10s -> %s  (轨道 %d, 时长 %.3fs%s)" % [
				anim_name, path, anim.get_track_count(), dup.length, ", 循环" if is_loop else ""])
		else:
			push_error("  导出失败 %s (err=%d)" % [anim_name, err])

	var skel := _find_node_of_class(inst, "Skeleton3D")
	print("=== 导入信息 ===")
	print("  骨骼: %s" % ("未找到" if skel == null else "%s（%d 根）" % [skel.name, skel.get_bone_count()]))
	print("  网格节点: %d" % _count_meshes(inst))
	print("  动画导出: %d/%d -> %s" % [saved, names.size(), OUT_DIR])
	inst.free()
	quit(0 if saved == names.size() else 1)

func _is_loop_name(anim_name: String) -> bool:
	var key := anim_name.to_lower()
	for hint in LOOP_HINTS:
		if key.contains(hint):
			return true
	return false

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _find_node_of_class(node: Node, klass: String) -> Node:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found := _find_node_of_class(child, klass)
		if found != null:
			return found
	return null

func _count_meshes(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count_meshes(child)
	return n
