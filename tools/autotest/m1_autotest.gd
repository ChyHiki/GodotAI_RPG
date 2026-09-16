extends Node
## M1 战斗闭环自动化测试（headless 运行）：
##   翻滚无敌帧 / 敌人挥击扣血 / 玩家挥砍扣血 / 击杀→重生 / 玩家死亡遮罩
## 运行：Godot --headless --path . res://tools/autotest/m1_autotest.tscn
## 退出码 0 = 全部通过；1 = 存在失败项。

var failures: Array[String] = []


func _ready() -> void:
    await _run()
    if failures.is_empty():
        print("AUTOTEST RESULT: ALL PASS")
        get_tree().quit(0)
    else:
        for f in failures:
            push_error("AUTOTEST FAIL: " + f)
        print("AUTOTEST RESULT: %d FAILED" % failures.size())
        get_tree().quit(1)


func _run() -> void:
    await _wait(0.6)  # 让主场景生成并落地

    var main: Node = load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    await _wait(0.8)  # 等待玩家/敌人出生与落地

    var player := get_tree().get_first_node_in_group("player")
    var enemy := get_tree().get_first_node_in_group("enemy")
    _expect(player != null, "玩家已生成")
    _expect(enemy != null, "敌人已生成")
    if player == null or enemy == null:
        return
    _expect(player.is_alive(), "玩家初始存活")
    _expect(enemy.is_alive(), "敌人初始存活")
    _expect(player.health.current_hp == 100, "玩家初始 HP=100，实际 %d" % player.health.current_hp)
    _expect(enemy.health.current_hp == 100, "敌人初始 HP=100，实际 %d" % enemy.health.current_hp)

    # ---- 0) 玩家外观：应加载骑士模型（KnightModel 挂在 VisualPivot 下）----
    var pivot = player.get_node_or_null("VisualPivot")
    var has_knight: bool = pivot != null and pivot.has_node("KnightModel")
    _expect(has_knight, "玩家使用外部模型 KnightModel")
    # 模型是骨骼版，含 5 段动画，应被自动识别（名字大小写/下划线无关）
    _expect(player._anim_player != null, "模型含 AnimationPlayer")
    _expect(player._skeleton != null, "模型含 Skeleton3D")
    if player._skeleton != null:
        _expect(player._skeleton.get_bone_count() >= 15,
            "骨骼数量正常(%d 根)" % player._skeleton.get_bone_count())
    _expect(player._roll_anim == "RollLeap", "识别翻滚动画: %s" % player._roll_anim)
    _expect(player._walk_anim == "Walk", "识别行走动画: %s" % player._walk_anim)
    _expect(player._slash_anim == "Slash", "识别挥砍动画: %s" % player._slash_anim)
    _expect(player._jump_start_anim == "JumpStart", "识别起跳动画: %s" % player._jump_start_anim)
    _expect(player._jump_air_anim == "JumpAir", "识别滞空动画: %s" % player._jump_air_anim)
    _expect(player._roll_anim_speed > 0.1, "翻滚动画倍速有效: %.3f" % player._roll_anim_speed)
    # 循环类动画必须开循环，否则只播一次就定住
    _expect(_loop_ok(player, "Walk"), "Walk 已设为循环播放")
    _expect(_loop_ok(player, "JumpAir"), "JumpAir 已设为循环播放")
    # 命中判定窗应与"剑刃最快段"对齐（实测 Slash 动画 0.19~0.30s 为劈砍段）
    if player._anim_player != null and player._slash_anim != "":
        var slash_anim: Animation = player._anim_player.get_animation(player._slash_anim)
        var atk_spd: float = slash_anim.length / player.attack_total
        var win0: float = player.attack_active_start * atk_spd
        var win1: float = player.attack_active_end * atk_spd
        _expect(win0 > 0.14 and win1 < 0.33,
            "命中判定窗落在剑刃最快段(动画时间 %.2f~%.2fs)" % [win0, win1])
    # 模型应被自动缩放到约 1.8m 站高、脚底贴地（换模型时的回归保护）
    if pivot != null and pivot.has_node("KnightModel"):
        var model = pivot.get_node("KnightModel")
        var meshes: Array = []
        player._collect_meshes(model, Transform3D.IDENTITY, meshes)
        var mn := Vector3.INF
        var mx := -Vector3.INF
        for info in meshes:
            var mi: MeshInstance3D = info["node"]
            var aabb: AABB = mi.get_aabb()
            for corner in player._aabb_corners(aabb):
                var p: Vector3 = model.transform * ((info["xform"] as Transform3D) * corner)
                mn = mn.min(p)
                mx = mx.max(p)
        var height: float = mx.y - mn.y
        _expect(absf(height - 1.8) < 0.35, "模型站高被缩放到 1.8m 附近，实际 %.3f" % height)
        _expect(absf(mn.y) < 0.12, "模型脚底贴地(y≈0)，实际 %.3f" % mn.y)

    # ---- 0b) 武器：独立武器应挂在 weapon.R 骨骼上，静止位置与"分离前"一致 ----
    var socket = player._weapon_socket
    var weapon = player._weapon
    _expect(socket != null, "武器挂点已创建(BoneAttachment3D)")
    _expect(weapon != null, "武器已装备")
    if socket != null:
        _expect(String(socket.bone_name) == "weapon.R",
            "武器挂在骨骼 weapon.R 上(实际 %s)" % socket.bone_name)
    if weapon != null and pivot != null and pivot.has_node("KnightModel"):
        var wmodel = pivot.get_node("KnightModel")
        var winv: Transform3D = wmodel.global_transform.affine_inverse()
        # ① 握柄应落在拳心（= 挂点骨骼原点）
        var grip: Vector3 = winv * weapon.global_position
        var socket_idx: int = player._skeleton.find_bone("weapon.R")
        var bone_pos: Vector3 = player._skeleton.get_bone_global_pose(socket_idx).origin
        var grip_off: float = grip.distance_to(bone_pos)
        _expect(grip_off < 0.06, "握柄位于拳心(偏差 %.3fm)" % grip_off)
        # ② 刀身应朝向身前(模型 -Z)，而不是贴在手臂上
        var blade: Vector3 = ((winv.basis * weapon.global_basis) * Vector3(0, 0, -1)).normalized()
        var blade_ang: float = rad_to_deg(blade.angle_to(Vector3(0, 0, -1)))
        _expect(blade_ang < 25.0, "刀身朝身前(与前方夹角 %.1f°)" % blade_ang)
        # ③ 剑刃应伸到身体前方（不再和手臂叠在一起）
        var wbounds: Array = [Vector3.INF, -Vector3.INF]
        _accumulate_bounds(weapon, winv, wbounds)
        var wmn: Vector3 = wbounds[0]
        _expect(wmn.z < -0.6, "剑刃伸向身体前方(最前端 z=%.2f)" % wmn.z)
        # ④ 挥砍时剑应随手臂骨骼大幅移动（证明是骨骼挂载，不是钉死在原地）
        var rel_before: Vector3 = winv * weapon.global_position
        player._try_start_attack()
        await _wait(0.3)                       # 劈砍段
        var rel_mid: Vector3 = winv * weapon.global_position
        _expect(rel_mid.distance_to(rel_before) > 0.25,
            "挥砍时剑跟随手臂骨骼(相对位移 %.2fm)" % rel_mid.distance_to(rel_before))
        await _wait(0.5)                       # 等攻击结束

    # ---- 1) 翻滚：无敌帧 + 播放 RollLeap + 结束复位骨骼 ----
    var pos_before: Vector3 = player.global_position
    player._try_start_roll()
    await _wait(0.1)
    _expect(player._anim_player.current_animation == player._roll_anim,
        "翻滚时播放 %s(实际 %s)" % [player._roll_anim, player._anim_player.current_animation])
    player.take_damage(15, player.global_position + Vector3(0, 0, 1))
    _expect(player.health.current_hp == 100, "[翻滚无敌] 翻滚期间扣血了: %d" % player.health.current_hp)
    await _wait(0.5)          # 等整段翻滚播完(roll_time=0.42s)
    _expect(not player._anim_player.is_playing(), "翻滚结束后动画已停止")
    _expect(_bones_at_rest(player), "翻滚结束后骨骼复位到绑定姿势")
    var moved: float = Vector2(player.global_position.x - pos_before.x,
        player.global_position.z - pos_before.z).length()
    _expect(moved > 0.9, "翻滚有实际位移(%.2fm)" % moved)

    # ---- 1b) 行走动画：移动时播放并按速度调倍速；停下复位骨骼 ----
    Input.action_press("move_forward")
    await _wait(0.4)
    _expect(player._anim_player.current_animation == player._walk_anim,
        "移动时播放行走动画(实际 %s)" % player._anim_player.current_animation)
    _expect(player._anim_player.speed_scale > 0.6,
        "行走动画倍速随速度调整(%.2f)" % player._anim_player.speed_scale)
    Input.action_release("move_forward")
    await _wait(0.5)
    _expect(not player._anim_player.is_playing(), "停下后行走动画已停止")
    _expect(_bones_at_rest(player), "停下后骨骼复位到绑定姿势")

    # ---- 1c) 挥砍动画：攻击播放 Slash，结束复位 ----
    _face_player_to(player, Vector3(0, 0, -1))
    player._try_start_attack()
    await _wait(0.1)
    _expect(player._anim_player.current_animation == player._slash_anim,
        "攻击时播放 %s(实际 %s)" % [player._slash_anim, player._anim_player.current_animation])
    await _wait(0.75)
    _expect(not player._anim_player.is_playing(), "攻击结束后动画已停止")
    _expect(_bones_at_rest(player), "攻击结束后骨骼复位")

    # ---- 1d) 跳跃：地面蓄力(JumpStart) → 离地(JumpAir) → 落地复位 ----
    var gy_before: float = player.global_position.y
    Input.action_press("jump")                       # 模拟"按住跳跃键"
    player._try_start_jump()
    await _wait(0.06)
    _expect(player._anim_player.current_animation == player._jump_start_anim,
        "起跳蓄力段播放 %s(实际 %s)" % [player._jump_start_anim, player._anim_player.current_animation])
    _expect(player.global_position.y <= gy_before + 0.05,
        "蓄力段仍留在地面(未提前离地, y=%.2f)" % player.global_position.y)

    # 采样整段：蓄力 → 离地 → 滞空 → 落地；同时验证最高点/滞空动画/无二段跳
    var full_peak: float = player.global_position.y
    var saw_air_anim := false
    var launched := false
    var double_jump_blocked := true
    for i in 55:                                     # 约 1.1s（含 0.18s 蓄力）
        await _wait(0.02)
        full_peak = maxf(full_peak, player.global_position.y)
        if player.global_position.y > gy_before + 0.12:
            launched = true
        if player._anim_player.current_animation == player._jump_air_anim:
            saw_air_anim = true
        if i == 25:                                  # 约 0.5s：蓄力已结束、人在空中
            var vy_before: float = player.velocity.y
            player._try_start_jump()                 # 空中再按 → 不应生效
            await _wait(0.02)
            double_jump_blocked = player.velocity.y <= vy_before + 0.01
    Input.action_release("jump")
    _expect(launched, "蓄力结束后才真正离地升空")
    _expect(saw_air_anim, "滞空阶段播放 %s" % player._jump_air_anim)
    _expect(double_jump_blocked, "空中不能二段跳")
    var full_h: float = full_peak - gy_before
    _expect(full_h > 0.9 and full_h < 1.6, "按住跳跃的高度约 1.1m，实际 %.2fm" % full_h)
    await _wait(0.7)                                 # 等落地
    _expect(player.is_on_floor(), "跳跃后已落地")
    _expect(absf(player.global_position.y - gy_before) < 0.15,
        "落地后回到地面高度(%.2f)" % player.global_position.y)
    _expect(not player._anim_player.is_playing(), "落地后跳跃动画已停止")
    _expect(_bones_at_rest(player), "落地后骨骼复位到绑定姿势")

    # 轻点跳跃(不按住) → 可变跳跃高度应该明显更低
    var hop_base: float = player.global_position.y
    player._try_start_jump()
    var hop_peak: float = hop_base
    for i in 30:                                     # 采样约 0.6s
        await _wait(0.02)
        hop_peak = maxf(hop_peak, player.global_position.y)
    var hop_h: float = hop_peak - hop_base
    _expect(hop_h < full_h - 0.15, "轻点跳跃更矮(轻点 %.2fm < 按住 %.2fm)" % [hop_h, full_h])
    await _wait(0.6)

    # ---- 2) 敌人挥击命中玩家：扣 15 ----
    _place_enemy_in_front_of(enemy, player, 1.3)
    await _wait(0.2)
    enemy._begin_strike(player)
    await _wait(0.35)  # 覆盖 strike 窗口
    _expect(player.health.current_hp == 85, "[敌人攻击] 期望 85，实际 %d" % player.health.current_hp)

    # ---- 3) 玩家挥砍命中敌人：扣 25 ----
    _place_enemy_in_front_of(enemy, player, 1.3)
    enemy.health.reset()
    var enemy_before: int = enemy.health.current_hp
    _face_player_to(player, Vector3(0, 0, -1))
    player._try_start_attack()
    await _wait(0.65)  # 覆盖整个攻击状态
    _expect(enemy.health.current_hp == enemy_before - 25,
        "[玩家攻击] 期望 %d，实际 %d" % [enemy_before - 25, enemy.health.current_hp])

    # ---- 4) 连续攻击击杀敌人 → 触发重生 ----
    var killed_id := enemy.get_instance_id()
    enemy.take_damage(1000, player.global_position)
    await _wait(0.1)
    _expect(not enemy.is_alive(), "敌人已被击杀")
    var hud := get_tree().get_first_node_in_group("hud")
    await _wait(4.0)  # 等待重生计时
    var alive_enemies := _alive_nodes_in_group("enemy")
    var respawned := false
    for e in alive_enemies:
        if e.get_instance_id() != killed_id:
            respawned = true
    _expect(respawned, "敌人已重生为新实例")
    var new_enemy := get_tree().get_first_node_in_group("enemy")
    if new_enemy != null:
        _expect(new_enemy.health.current_hp == 100, "重生敌人 HP 满值")

    # ---- 5) 玩家死亡 → 死亡遮罩出现 ----
    player.health.reset()
    await _wait(0.1)
    player.take_damage(1000, player.global_position + Vector3(0, 0, 1))
    await _wait(0.3)
    _expect(not player.is_alive(), "玩家已死亡")
    if hud != null:
        var overlay = hud.get("_death_overlay")
        _expect(overlay != null and overlay.visible, "死亡遮罩已显示")


# ------------------------------------------------------------------ 工具

func _alive_nodes_in_group(group: StringName) -> Array:
    var out: Array = []
    for n in get_tree().get_nodes_in_group(group):
        if n.has_method("is_alive") and n.is_alive():
            out.append(n)
    return out


func _place_enemy_in_front_of(enemy: Node3D, player: Node3D, dist: float) -> void:
    var f := Vector3(0, 0, -1) # 玩家默认朝 -Z
    enemy.global_position = player.global_position + f * dist
    enemy.velocity = Vector3.ZERO


func _face_player_to(player: Node3D, dir: Vector3) -> void:
    if player.has_method("_face_instant"):
        player._face_instant(dir)


## 按节点名递归查找（用于定位模型内部的动画节点，如 EMT-RollPivot）。
func _find_by_name(root: Node, target: String) -> Node:
    if root.name == target:
        return root
    for c in root.get_children():
        var found := _find_by_name(c, target)
        if found != null:
            return found
    return null


## 把某个节点下的所有网格包围盒换算到指定空间并求并集（用于武器位置校验）。
func _accumulate_bounds(node: Node, inv: Transform3D, bounds: Array) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var aabb: AABB = mi.get_aabb()
        var xform: Transform3D = inv * mi.global_transform
        for i in 8:
            var off := Vector3.ZERO
            if (i & 1) != 0:
                off.x = aabb.size.x
            if (i & 2) != 0:
                off.y = aabb.size.y
            if (i & 4) != 0:
                off.z = aabb.size.z
            var p: Vector3 = xform * (aabb.position + off)
            bounds[0] = (bounds[0] as Vector3).min(p)
            bounds[1] = (bounds[1] as Vector3).max(p)
    for child in node.get_children():
        _accumulate_bounds(child, inv, bounds)


## 检查某段动画是否已设为循环播放（Walk / JumpAir 必须是循环）。
func _loop_ok(player, anim_name: String) -> bool:
    if player._anim_player == null:
        return false
    var a: Animation = player._anim_player.get_animation(anim_name)
    return a != null and a.loop_mode != Animation.LOOP_NONE


## 检查所有骨骼是否都回到"绑定姿势"(rest pose)（容差内）。
## 用于验证"停下/落地/受击后骨骼没有僵在动画中途的姿势"。
func _bones_at_rest(player) -> bool:
    var skel = player._skeleton
    if skel == null:
        return false
    for i in skel.get_bone_count():
        var rest: Transform3D = skel.get_bone_rest(i)
        var q_rest: Quaternion = rest.basis.get_rotation_quaternion()
        var q_pose: Quaternion = skel.get_bone_pose_rotation(i)
        if absf(q_pose.angle_to(q_rest)) > 0.08:
            return false
        if skel.get_bone_pose_position(i).distance_to(rest.origin) > 0.02:
            return false
    return true


func _expect(cond: bool, msg: String) -> void:
    if cond:
        print("AUTOTEST OK: " + msg)
    else:
        failures.append(msg)
        print("AUTOTEST FAIL: " + msg)


func _wait(sec: float) -> void:
    await get_tree().create_timer(sec).timeout
