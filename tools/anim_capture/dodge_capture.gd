extends Node
## 开发辅助：自动演示"行走 → 挥砍 → 跳跃 → 前冲 → 后撤"，用于抓帧验证骨骼动画与武器。
## 用法：godot --path . res://tools/anim_capture/dodge_capture.tscn --write-movie <目录>/frame.png
##
## 【改名沿革】本工具原名 roll_capture（演示翻滚）。2026-09-20 翻滚被闪避取代，
##   演示的第四段自然从"翻滚"换成"前冲 + 后撤"两段 —— 文件名跟着改，别再找 roll_capture。

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
    print("CAPTURE: 动画 Walk:%s Slash:%s JumpStart:%s JumpAir:%s 前冲:%s 后撤:%s | 武器:%s" % [
        player._walk_anim, player._slash_anim, player._jump_start_anim,
        player._jump_air_anim, player._dodge_fwd_anim, player._dodge_back_anim, player._weapon])

    # 1) 行走（约 0.6s，帧 48~84）
    Input.action_press("move_forward")
    await get_tree().create_timer(0.6).timeout
    Input.action_release("move_forward")
    await get_tree().create_timer(0.3).timeout

    # 2) 挥砍（起手 0.17s 后进入劈砍）
    player._try_start_attack()
    await get_tree().create_timer(0.65).timeout

    # 3) 跳跃
    Input.action_press("jump")
    player._try_start_jump()
    await get_tree().create_timer(0.5).timeout
    Input.action_release("jump")
    await get_tree().create_timer(0.5).timeout

    # 4) 前闪：**任意方向键 + Shift 都是前闪**，这里用 W 代表（换成 A/S/D 就朝那边閃）。
    #    ⚠ 前闪会**把身体转向**按键方向后再冲出去 —— 初版是"有 W 才前冲"且不转身，
    #      2026-09-20 改成现在的规则（"我要去那边"就直接去，不用先转镜头）。
    Input.action_press("move_forward")
    await get_tree().process_frame
    player._try_start_dodge()
    await get_tree().create_timer(0.55).timeout
    Input.action_release("move_forward")
    await get_tree().create_timer(0.35).timeout

    # 5) 后闪：**单按 Shift（不按任何方向键）** = 朝身体正后方跳开，且不改朝向
    player._try_start_dodge()
    await get_tree().create_timer(0.8).timeout
    get_tree().quit(0)
