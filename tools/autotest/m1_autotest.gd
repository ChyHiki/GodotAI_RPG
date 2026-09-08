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

    # ---- 1) 翻滚无敌帧：翻滚期间受伤不扣血 ----
    player._try_start_roll()
    await _wait(0.1)
    player.take_damage(15, player.global_position + Vector3(0, 0, 1))
    _expect(player.health.current_hp == 100, "[翻滚无敌] 翻滚期间扣血了: %d" % player.health.current_hp)
    await _wait(0.5)  # 等翻滚结束

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


func _expect(cond: bool, msg: String) -> void:
    if cond:
        print("AUTOTEST OK: " + msg)
    else:
        failures.append(msg)
        print("AUTOTEST FAIL: " + msg)


func _wait(sec: float) -> void:
    await get_tree().create_timer(sec).timeout
