extends Node
## 开发辅助：启动主场景后自动触发一次翻滚，用于抓帧 / 录制验证 RollLeap 动画。
## 用法：godot --path . res://tools/anim_capture/roll_capture.tscn --write-movie <目录>/frame.png

func _ready() -> void:
    var main: Node = load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    await get_tree().create_timer(1.0).timeout        # 等镜头与落地稳定
    var player = get_tree().get_first_node_in_group("player")
    if player != null:
        print("CAPTURE: 触发翻滚, 动画=", player._roll_anim, " 倍速=", player._roll_anim_speed)
        player._try_start_roll()
    await get_tree().create_timer(0.9).timeout        # 录完整段翻滚
    get_tree().quit(0)
