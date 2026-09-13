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
    # 模型内含 RollLeap 翻滚动画，应被自动识别到
    _expect(player._anim_player != null, "模型含 AnimationPlayer")
    _expect(player._roll_anim != "", "已识别翻滚动画: %s" % player._roll_anim)
    _expect(player._roll_anim_speed > 0.1, "翻滚动画倍速有效: %.3f" % player._roll_anim_speed)
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

    # ---- 1) 翻滚无敌帧 + 翻滚动画是否真的驱动了模型节点 ----
    var roll_pivot: Node3D = player._roll_pivot
    if roll_pivot == null:
        roll_pivot = _find_by_name(player, "EMT-RollPivot") as Node3D
    _expect(roll_pivot != null, "模型含动画节点 EMT-RollPivot")
    var pos_before: Vector3 = player.global_position
    player._try_start_roll()
    await _wait(0.1)
    player.take_damage(15, player.global_position + Vector3(0, 0, 1))
    _expect(player.health.current_hp == 100, "[翻滚无敌] 翻滚期间扣血了: %d" % player.health.current_hp)
    # 翻滚中段：动画节点应已明显旋转/前移(证明 GLB 动画在播放，而不是静止姿势)
    await _wait(0.12)   # 累计约 0.22s，接近翻滚中段
    if roll_pivot != null:
        var mid_rot: float = absf(roll_pivot.rotation.x)
        var mid_z: float = absf(roll_pivot.position.z)
        _expect(mid_rot > 0.8 or mid_z > 0.25,
            "翻滚中段模型已翻滚(rot.x=%.2f, z=%.2f)" % [mid_rot, mid_z])
    await _wait(0.4)    # 等整段翻滚播完(roll_time=0.42s)
    # 翻滚结束：动画独有的"前跃 1m"根位移应已过继给本体 → 模型复位站姿 + 角色实际前移
    if roll_pivot != null:
        _expect(absf(roll_pivot.rotation.x) < 0.25 and absf(roll_pivot.position.z) < 0.08,
            "翻滚结束模型复位站姿(rot.x=%.2f, z=%.2f)" % [absf(roll_pivot.rotation.x), absf(roll_pivot.position.z)])
    var moved: float = Vector2(player.global_position.x - pos_before.x,
        player.global_position.z - pos_before.z).length()
    _expect(moved > 1.3, "翻滚位移含动画根位移(期望 >1.3m)，实际 %.2fm" % moved)

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


func _expect(cond: bool, msg: String) -> void:
    if cond:
        print("AUTOTEST OK: " + msg)
    else:
        failures.append(msg)
        print("AUTOTEST FAIL: " + msg)


func _wait(sec: float) -> void:
    await get_tree().create_timer(sec).timeout
