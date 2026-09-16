extends Node
## 开发辅助：验证武器挂载是否正确。
## 判定标准（两条，都是"看得见"的标准）：
##   ① 握柄在拳心：武器原点与挂点骨骼 weapon.R 原点的距离 ≈ 0
##   ② 刀身朝身前：武器刀身方向(自身 -Z)与模型前方(模型 -Z)的夹角足够小（< 25°）
## 用法：godot --headless --path . res://tools/check_weapon.tscn

func _ready() -> void:
    var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
    add_child(player)
    await get_tree().process_frame
    await get_tree().process_frame

    var pivot: Node3D = player.get_node_or_null("VisualPivot")
    var model: Node3D = pivot.get_node_or_null("KnightModel") if pivot != null else null
    var weapon: Node3D = player._weapon
    var skel: Skeleton3D = player._skeleton
    if model == null or weapon == null or skel == null:
        print("CHECK: 模型/武器/骨骼缺失 (model=%s weapon=%s skel=%s)" % [model, weapon, skel])
        get_tree().quit(1)
        return

    # ① 握柄 ↔ 拳心
    var inv := model.global_transform.affine_inverse()
    var grip_model: Vector3 = inv * weapon.global_position
    var idx: int = skel.find_bone("weapon.R")
    var bone_model: Vector3 = skel.get_bone_global_pose(idx).origin
    print("CHECK: 握柄(模型空间)=(%.3f, %.3f, %.3f)  挂点骨骼=(%.3f, %.3f, %.3f)  距离=%.4f m" % [
        grip_model.x, grip_model.y, grip_model.z, bone_model.x, bone_model.y, bone_model.z,
        grip_model.distance_to(bone_model)])

    # ② 刀身朝向 ↔ 模型前方
    var blade_dir: Vector3 = ((inv.basis * weapon.global_basis) * Vector3(0, 0, -1)).normalized()
    var ang := rad_to_deg(blade_dir.angle_to(Vector3(0, 0, -1)))   # 模型正面朝 -Z
    print("CHECK: 刀身方向(模型空间)=(%.2f, %.2f, %.2f)  模型前方=(0,0,-1)  夹角=%.1f°" % [
        blade_dir.x, blade_dir.y, blade_dir.z, ang])

    # 参考：武器在模型空间的包围盒
    var bounds: Array = [Vector3.INF, -Vector3.INF]
    _accumulate(weapon, inv, bounds)
    var wmn: Vector3 = bounds[0]
    var wmx: Vector3 = bounds[1]
    print("CHECK: 武器包围盒(模型空间) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
        wmn.x, wmn.y, wmn.z, wmx.x, wmx.y, wmx.z])

    # 参考：右臂网格范围（看剑是否还压在手臂里）
    var arm: Node3D = _find_by_name(model, "GEO-arm_R")
    if arm != null and arm is MeshInstance3D:
        var aabb: AABB = (arm as MeshInstance3D).get_aabb()
        print("CHECK: 右臂网格(模型空间) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
            aabb.position.x, aabb.position.y, aabb.position.z,
            aabb.end.x, aabb.end.y, aabb.end.z])

    var ok_grip: bool = grip_model.distance_to(bone_model) < 0.06
    var ok_dir: bool = ang < 25.0
    print("CHECK: 结论 → 握柄在拳心:%s  刀身朝身前:%s" % [
        "OK" if ok_grip else "FAIL", "OK" if ok_dir else "FAIL"])
    get_tree().quit(0 if (ok_grip and ok_dir) else 1)


func _accumulate(node: Node, inv: Transform3D, bounds: Array) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var aabb: AABB = mi.get_aabb()
        var xform := inv * mi.global_transform
        for i in 8:
            var off := Vector3.ZERO
            if (i & 1) != 0:
                off.x = aabb.size.x
            if (i & 2) != 0:
                off.y = aabb.size.y
            if (i & 4) != 0:
                off.z = aabb.size.z
            var p := xform * (aabb.position + off)
            bounds[0] = (bounds[0] as Vector3).min(p)
            bounds[1] = (bounds[1] as Vector3).max(p)
    for child in node.get_children():
        _accumulate(child, inv, bounds)


func _find_by_name(node: Node, target: String) -> Node3D:
    if node.name == target and node is Node3D:
        return node as Node3D
    for c in node.get_children():
        var found := _find_by_name(c, target)
        if found != null:
            return found
    return null
