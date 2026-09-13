extends Node
## 开发辅助：验证武器挂载是否正确。
## 基准 = 武器分离前的旧模型里 GEO-sword_01 的实测包围盒（模型空间）：
##   x 0.250~0.410、y 0.530~1.720、z -0.015~0.055（握柄在下、刀身朝上）
## 用法：godot --headless --path . res://tools/check_weapon.tscn

const OLD_MIN := Vector3(0.250, 0.530, -0.015)
const OLD_MAX := Vector3(0.410, 1.720, 0.055)


func _ready() -> void:
    var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
    add_child(player)
    await get_tree().process_frame
    await get_tree().process_frame

    var pivot: Node3D = player.get_node_or_null("VisualPivot")
    var model: Node3D = pivot.get_node_or_null("KnightModel") if pivot != null else null
    var weapon: Node3D = player._weapon
    if model == null or weapon == null:
        print("CHECK: 模型或武器缺失 (model=%s weapon=%s)" % [model, weapon])
        get_tree().quit(1)
        return

    # 武器网格的包围盒 → 换算到"模型局部空间"（与旧模型同一坐标系）
    var inv := model.global_transform.affine_inverse()
    var bounds: Array = [Vector3.INF, -Vector3.INF]
    _accumulate(weapon, inv, bounds)
    var mn: Vector3 = bounds[0]
    var mx: Vector3 = bounds[1]

    print("CHECK: 武器挂载后(模型空间) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
        mn.x, mn.y, mn.z, mx.x, mx.y, mx.z])
    print("CHECK: 旧模型基准           min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
        OLD_MIN.x, OLD_MIN.y, OLD_MIN.z, OLD_MAX.x, OLD_MAX.y, OLD_MAX.z])
    print("CHECK: 中心偏差=(%.3f, %.3f, %.3f)  尺寸差=(%.3f, %.3f, %.3f)" % [
        (mn.x + mx.x) * 0.5 - (OLD_MIN.x + OLD_MAX.x) * 0.5,
        (mn.y + mx.y) * 0.5 - (OLD_MIN.y + OLD_MAX.y) * 0.5,
        (mn.z + mx.z) * 0.5 - (OLD_MIN.z + OLD_MAX.z) * 0.5,
        (mx.x - mn.x) - (OLD_MAX.x - OLD_MIN.x),
        (mx.y - mn.y) - (OLD_MAX.y - OLD_MIN.y),
        (mx.z - mn.z) - (OLD_MAX.z - OLD_MIN.z)])

    # 挂点骨骼的静止基：看它的三根轴在模型空间指向哪里
    var skel: Skeleton3D = player._skeleton
    var idx: int = skel.find_bone("weapon.R")
    var rest := _bone_global_rest(skel, idx)
    print("CHECK: weapon.R 静止姿势 pos=(%.3f, %.3f, %.3f)" % [rest.origin.x, rest.origin.y, rest.origin.z])
    print("CHECK:   +X轴=(%.2f, %.2f, %.2f)  +Y轴=(%.2f, %.2f, %.2f)  +Z轴=(%.2f, %.2f, %.2f)" % [
        rest.basis.x.x, rest.basis.x.y, rest.basis.x.z,
        rest.basis.y.x, rest.basis.y.y, rest.basis.y.z,
        rest.basis.z.x, rest.basis.z.y, rest.basis.z.z])

    # ---- 诊断 BoneAttachment3D 的实际组合规则 ----
    var socket: BoneAttachment3D = player._weapon_socket
    if socket != null:
        print("DIAG: skeleton.find_bone('%s') = %d" % [player.WEAPON_SOCKET if false else "weapon.R", skel.find_bone("weapon.R")])
        print("DIAG: socket.bone_name='%s'  socket.bone_idx=%d  override_pose=%s" % [
            socket.bone_name, socket.bone_idx, socket.override_pose])
        for f in 3:
            await get_tree().process_frame
            print("DIAG: [frame+%d] socket.transform.origin=(%.3f, %.3f, %.3f)  socket.global.origin=(%.3f, %.3f, %.3f)" % [
                f, socket.transform.origin.x, socket.transform.origin.y, socket.transform.origin.z,
                socket.global_transform.origin.x, socket.global_transform.origin.y, socket.global_transform.origin.z])
        var gb := socket.global_transform.basis
        print("DIAG: socket.global basis X=(%.2f,%.2f,%.2f) Y=(%.2f,%.2f,%.2f) Z=(%.2f,%.2f,%.2f)" % [
            gb.x.x, gb.x.y, gb.x.z, gb.y.x, gb.y.y, gb.y.z, gb.z.x, gb.z.y, gb.z.z])
        var wb := weapon.global_transform.basis
        print("DIAG: 武器全局 basis X=(%.2f,%.2f,%.2f) Y=(%.2f,%.2f,%.2f) Z=(%.2f,%.2f,%.2f)" % [
            wb.x.x, wb.x.y, wb.x.z, wb.y.x, wb.y.y, wb.y.z, wb.z.x, wb.z.y, wb.z.z])
    get_tree().quit(0)


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


func _bone_global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
    var t: Transform3D = skel.get_bone_rest(idx)
    var p := skel.get_bone_parent(idx)
    while p >= 0:
        t = skel.get_bone_rest(p) * t
        p = skel.get_bone_parent(p)
    return t
