extends SceneTree
## 验证"武器挂点"是否正确：模型是否有挂点骨骼、武器挂上去后是否落在拳心、缩放是否与角色一致。
##
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##        --script res://tools/verify_weapon_socket.gd

const MODEL_PATH := "res://assets/characters/player_knight/player_knight.glb"
const WEAPON_PATH := "res://assets/weapons/sword_01/sword_01.glb"
const SOCKET := "weapon.R"
const TARGET_HEIGHT := 1.8      # player.gd 会把模型缩放到这个身高

func _init() -> void:
	var model_scene := load(MODEL_PATH) as PackedScene
	var weapon_scene := load(WEAPON_PATH) as PackedScene
	if model_scene == null or weapon_scene == null:
		push_error("资产未导入：%s / %s" % [MODEL_PATH, WEAPON_PATH])
		quit(1)
		return

	var model := model_scene.instantiate() as Node3D
	var skel := _find_skeleton(model)
	if skel == null:
		push_error("模型里没有 Skeleton3D")
		quit(1)
		return

	var bone := skel.find_bone(SOCKET)
	print("骨骼数 = %d，挂点 '%s' 索引 = %d" % [skel.get_bone_count(), SOCKET, bone])
	if bone < 0:
		push_error("没有挂点骨骼 %s" % SOCKET)
		quit(1)
		return
	print("挂点静置位置(模型局部) = %s" % str(skel.get_bone_rest(bone).origin))

	# 与 player.gd 相同的缩放逻辑（按网格包围盒缩放到 1.8m）
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for mi in _all_meshes(model):
		var aabb: AABB = mi.get_aabb()
		mn = mn.min(aabb.position)
		mx = mx.max(aabb.position + aabb.size)
	var s := TARGET_HEIGHT / (mx.y - mn.y)
	model.scale = Vector3.ONE * s
	print("模型缩放系数 = %.4f（原始高 %.3f m）" % [s, mx.y - mn.y])

	# 挂点 + 武器（与 player.gd 的 _attach_weapon 一致）
	var socket := BoneAttachment3D.new()
	socket.name = "WeaponSocket"
	skel.add_child(socket)
	socket.bone_name = SOCKET
	var weapon := weapon_scene.instantiate() as Node3D
	socket.add_child(weapon)

	root.add_child(model)
	await process_frame
	await process_frame

	var grip := weapon.global_position
	var fist := skel.global_transform * skel.get_bone_global_pose(bone).origin
	print("武器原点(全局) = %s" % str(grip))
	print("拳心位置(全局) = %s" % str(fist))
	print("偏差 = %.4f m（应 ≈ 0）" % grip.distance_to(fist))

	var wmn := Vector3.INF
	var wmx := -Vector3.INF
	for mi in _all_meshes(weapon):
		var aabb: AABB = mi.get_aabb()
		wmn = wmn.min(aabb.position)
		wmx = wmx.max(aabb.position + aabb.size)
	print("武器包围盒(局部) = %.3f × %.3f × %.3f m（刃长应 ≈ 1.13 m）" % [
		wmx.x - wmn.x, wmx.y - wmn.y, wmx.z - wmn.z])

	var anim := _find_animation_player(model)
	if anim != null:
		print("动画: %s" % str(anim.get_animation_list()))
	print("结论：挂点存在，武器已挂到 %s" % SOCKET)
	quit(0)

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

func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_all_meshes(child))
	return out
