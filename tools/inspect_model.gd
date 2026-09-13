extends SceneTree
## 开发辅助：打印 GLB 模型内部结构（节点树/骨骼/动画名/时长）。
## 用法：godot --headless --path . --script res://tools/inspect_model.gd -- <res路径>

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var path := "res://artifacts/models/player_knight/player_knight_roll.glb"
    if not args.is_empty():
        path = args[0]
    print("== 检查模型: ", path, " ==")
    var scene: PackedScene = load(path)
    if scene == null:
        print("加载失败")
        quit(1)
        return
    var root: Node = scene.instantiate()
    _walk(root, 0)
    var anim_players := []
    _find(root, "AnimationPlayer", anim_players)
    if anim_players.is_empty():
        print("动画: 无 AnimationPlayer")
    for ap in anim_players:
        var ap_node := ap as AnimationPlayer
        print("AnimationPlayer: ", ap_node.name)
        for anim_name in ap_node.get_animation_list():
            var a: Animation = ap_node.get_animation(anim_name)
            print("   - 动画名=", anim_name, "  时长=", a.length, "s  轨道数=", a.get_track_count())
    var skeletons := []
    _find(root, "Skeleton3D", skeletons)
    print("骨骼节点数: ", skeletons.size())
    for sk in skeletons:
        var skel := sk as Skeleton3D
        print("  骨骼数=", skel.get_bone_count(), " 骨骼: ", _bone_names(skel))
    root.free()
    quit(0)


func _bone_names(skel: Skeleton3D) -> String:
    var names: Array[String] = []
    for i in skel.get_bone_count():
        names.append(skel.get_bone_name(i))
    return ", ".join(names)


func _walk(node: Node, depth: int) -> void:
    var indent := ""
    for i in depth:
        indent += "  "
    var extra := ""
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var aabb: AABB = mi.get_aabb()
        extra = "  [AABB size=%.2f,%.2f,%.2f]" % [aabb.size.x, aabb.size.y, aabb.size.z]
    print("%s%s(%s)%s" % [indent, node.name, node.get_class(), extra])
    for c in node.get_children():
        _walk(c, depth + 1)


func _find(node: Node, target_class: String, out: Array) -> void:
    if node.get_class() == target_class:
        out.append(node)
    for c in node.get_children():
        _find(c, target_class, out)
