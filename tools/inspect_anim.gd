extends SceneTree
## 开发辅助：打印 GLB 动画的每条轨道及其关键帧数值（用于把动画位移与控制器位移对齐）。
## 用法：godot --headless --path . --script res://tools/inspect_anim.gd -- <res路径> [动画名]

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var path := "res://artifacts/models/player_knight/player_knight_roll.glb"
    if args.size() > 0:
        path = args[0]
    var want := "" if args.size() < 2 else args[1]
    var scene: PackedScene = load(path)
    if scene == null:
        print("加载失败")
        quit(1)
        return
    var root: Node = scene.instantiate()
    var players: Array = []
    _find(root, "AnimationPlayer", players)
    if players.is_empty():
        print("无 AnimationPlayer")
        quit(1)
        return
    var ap := players[0] as AnimationPlayer
    for anim_name in ap.get_animation_list():
        if want != "" and anim_name != want:
            continue
        var a: Animation = ap.get_animation(anim_name)
        print("=== 动画 %s | 时长=%.4fs | 轨道=%d ===" % [anim_name, a.length, a.get_track_count()])
        for i in a.get_track_count():
            var t_path := a.track_get_path(i)
            var t_type := a.track_get_type(i)
            var keys := a.track_get_key_count(i)
            print("轨道%d 类型=%d 路径=%s 关键帧=%d" % [i, t_type, t_path, keys])
            for k in keys:
                var tm := a.track_get_key_time(i, k)
                var val = a.track_get_key_value(i, k)
                print("    t=%.3f  值=%s" % [tm, str(val)])
    root.free()
    quit(0)


func _find(node: Node, target_class: String, out: Array) -> void:
    if node.get_class() == target_class:
        out.append(node)
    for c in node.get_children():
        _find(c, target_class, out)
