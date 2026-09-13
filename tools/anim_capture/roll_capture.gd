extends Node
## 开发辅助：自动演示"行走 → 跳跃 → 翻滚"，用于抓帧验证骨骼动画是否正常。
## 用法：godot --path . res://tools/anim_capture/roll_capture.tscn --write-movie <目录>/frame.png

func _ready() -> void:
    var main: Node = load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    await get_tree().create_timer(0.8).timeout
    # 抓帧期间把鼠标设为可见：否则真实鼠标的移动会带动镜头，污染画面分析
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

    var player = get_tree().get_first_node_in_group("player")
    if player == null:
        print("CAPTURE: 找不到玩家")
        get_tree().quit(1)
        return
    print("CAPTURE: 动画 = Walk:%s JumpStart:%s JumpAir:%s Roll:%s Slash:%s" % [
        player._walk_anim, player._jump_start_anim, player._jump_air_anim,
        player._roll_anim, player._slash_anim])

    # 1) 行走（约 0.8s，对应帧 48~96）
    Input.action_press("move_forward")
    await get_tree().create_timer(0.8).timeout
    Input.action_release("move_forward")
    await get_tree().create_timer(0.4).timeout

    # 2) 跳跃（按住，约 1.1s，对应帧 120~186）
    Input.action_press("jump")
    player._try_start_jump()
    await get_tree().create_timer(0.5).timeout
    Input.action_release("jump")
    await get_tree().create_timer(0.6).timeout

    # 3) 翻滚（约 0.8s，对应帧 186~234）
    player._try_start_roll()
    await get_tree().create_timer(0.8).timeout
    get_tree().quit(0)
