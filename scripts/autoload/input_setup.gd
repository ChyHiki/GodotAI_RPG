extends Node
## 运行时注册自定义输入动作。
## 说明：M1 阶段采用代码注册（简单可靠），这些动作不会出现在编辑器 Input Map 面板中，
## 但运行时与 F6 试玩均有效。M2 阶段将迁移为 project.godot 中的正式配置以支持玩家自定义按键。

func _ready() -> void:
    _add_key("move_forward", [KEY_W, KEY_UP])
    _add_key("move_back", [KEY_S, KEY_DOWN])
    _add_key("move_left", [KEY_A, KEY_LEFT])
    _add_key("move_right", [KEY_D, KEY_RIGHT])
    _add_key("roll", [KEY_SHIFT])
    _add_key("restart", [KEY_R])
    _add_mouse_button("attack", MOUSE_BUTTON_LEFT)


func _add_key(action: StringName, keys: Array) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    for key in keys:
        var ev := InputEventKey.new()
        ev.physical_keycode = key
        InputMap.action_add_event(action, ev)


func _add_mouse_button(action: StringName, button: MouseButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventMouseButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)
