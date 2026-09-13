extends SceneTree
## 开发辅助：为"武器挂到右手骨骼"和"挥砍判定窗对齐"提供数值依据。
## 用法：
##   godot --headless --path . --script res://tools/inspect_rig.gd -- <模型glb> [动画名]
## 输出：
##   A) 节点树 + 各网格包围盒
##   B) 骨骼静止姿势（骨骼空间的世界位置；含 hand.R / weapon.R 的完整变换）
##   C) 若给出动画名：采样手部/武器骨骼的角速度曲线，找出最快的那一段（= 挥砍命中窗）

var _skel: Skeleton3D = null
var _bone_parent: Array[int] = []


func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var path := "res://assets/characters/player_knight/player_knight.glb"
    var anim_name := ""
    if args.size() > 0:
        path = args[0]
    if args.size() > 1:
        anim_name = args[1]

    print("=== 检查: ", path, " ===")
    var scene: PackedScene = load(path)
    if scene == null:
        print("加载失败")
        quit(1)
        return
    var root: Node = scene.instantiate()

    print("--- A) 节点树 / 网格包围盒 ---")
    _walk(root, 0)

    var skeletons: Array = []
    _find(root, "Skeleton3D", skeletons)
    if not skeletons.is_empty():
        _skel = skeletons[0] as Skeleton3D
        print("--- B) 骨骼静止姿势(骨骼空间) ---")
        _cache_parents()
        for i in _skel.get_bone_count():
            var g := _global_rest(i)
            var mark := "  <<<" if _skel.get_bone_name(i) in ["hand.R", "weapon.R", "hand.L"] else ""
            print("%-12s pos=(%.3f, %.3f, %.3f) euler=(%.1f, %.1f, %.1f)%s" % [
                _skel.get_bone_name(i), g.origin.x, g.origin.y, g.origin.z,
                rad_to_deg(g.basis.get_euler().x), rad_to_deg(g.basis.get_euler().y),
                rad_to_deg(g.basis.get_euler().z), mark])

    var players: Array = []
    _find(root, "AnimationPlayer", players)
    if not players.is_empty() and anim_name != "":
        var ap := players[0] as AnimationPlayer
        var anim: Animation = ap.get_animation(anim_name)
        if anim == null:
            print("找不到动画: ", anim_name)
        else:
            print("--- C) %s 手部/武器角速度曲线 (时长 %.4fs) ---" % [anim_name, anim.length])
            _print_swing_profile(anim)
    root.free()
    quit(0)


func _print_swing_profile(anim: Animation) -> void:
    # 找出手部/武器骨骼的旋转轨道
    var tracks: Array[int] = []
    for i in anim.get_track_count():
        var p := String(anim.track_get_path(i))
        if (p.contains("hand.R") or p.contains("weapon.R")) and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
            tracks.append(i)
            print("  采样轨道: ", p)
    if tracks.is_empty():
        return
    var dt := 0.02
    var prev: Array[Quaternion] = []
    var peak := 0.0
    var peak_t := 0.0
    var samples: Array = []   # [t, deg_per_sec]
    var t := 0.0
    while t <= anim.length + 0.0001:
        var cur: Array[Quaternion] = []
        for i in tracks:
            cur.append(_sample_rotation(anim, i, t))
        if prev.size() == cur.size():
            var max_deg := 0.0
            for k in cur.size():
                max_deg = maxf(max_deg, rad_to_deg(prev[k].angle_to(cur[k])) / dt)
            samples.append([t, max_deg])
            if max_deg > peak:
                peak = max_deg
                peak_t = t
        prev = cur
        t += dt
    for s in samples:
        var bar := ""
        for j in int(s[1] / maxf(1.0, peak) * 30.0):
            bar += "#"
        print("  t=%.2fs  %6.0f deg/s  %s" % [s[0], s[1], bar])
    # 找出 >= 50% 峰值的连续区间 = 挥砍最快段
    var start := -1.0
    var end := -1.0
    for s in samples:
        if s[1] >= peak * 0.5:
            if start < 0.0:
                start = s[0]
            end = s[0]
    print("  峰值 %.0f deg/s @ t=%.2fs；>=50%% 峰值区间: %.2fs ~ %.2fs（动画时间）" % [peak, peak_t, start, end])


## 手动按关键帧插值采样一条旋转轨道（这个 Godot 版本没有现成的 interpolate API）。
func _sample_rotation(anim: Animation, track: int, t: float) -> Quaternion:
    var n := anim.track_get_key_count(track)
    if n == 0:
        return Quaternion()
    if n == 1:
        return anim.track_get_key_value(track, 0) as Quaternion
    if t <= anim.track_get_key_time(track, 0):
        return anim.track_get_key_value(track, 0) as Quaternion
    for k in range(1, n):
        var t1 := anim.track_get_key_time(track, k)
        if t <= t1:
            var t0 := anim.track_get_key_time(track, k - 1)
            var q0: Quaternion = anim.track_get_key_value(track, k - 1)
            var q1: Quaternion = anim.track_get_key_value(track, k)
            var a := (t - t0) / maxf(0.0001, t1 - t0)
            return q0.slerp(q1, a)
    return anim.track_get_key_value(track, n - 1) as Quaternion


func _cache_parents() -> void:
    _bone_parent.clear()
    for i in _skel.get_bone_count():
        _bone_parent.append(_skel.get_bone_parent(i))


func _global_rest(idx: int) -> Transform3D:
    var t: Transform3D = _skel.get_bone_rest(idx)
    var p := _bone_parent[idx]
    while p >= 0:
        t = _skel.get_bone_rest(p) * t
        p = _bone_parent[p]
    return t


func _walk(node: Node, depth: int) -> void:
    var indent := ""
    for i in depth:
        indent += "  "
    var extra := ""
    if node is Node3D:
        var n3 := node as Node3D
        var e := n3.transform.basis.get_euler()
        var sc := n3.transform.basis.get_scale()
        extra = "  pos=(%.3f,%.3f,%.3f) scale=(%.3f,%.3f,%.3f) euler=(%.0f,%.0f,%.0f)" % [
            n3.transform.origin.x, n3.transform.origin.y, n3.transform.origin.z,
            sc.x, sc.y, sc.z, rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var aabb: AABB = mi.get_aabb()
        extra += "  AABB pos=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f)" % [
            aabb.position.x, aabb.position.y, aabb.position.z,
            aabb.size.x, aabb.size.y, aabb.size.z]
    print("%s%s(%s)%s" % [indent, node.name, node.get_class(), extra])
    for c in node.get_children():
        _walk(c, depth + 1)


func _find(node: Node, target_class: String, out: Array) -> void:
    if node.get_class() == target_class:
        out.append(node)
    for c in node.get_children():
        _find(c, target_class, out)
