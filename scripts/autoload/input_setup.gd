extends Node
## ============================================================
## 输入映射 autoload（自动加载单例，名为 InputSetup）
## ============================================================
## 【这个文件是做什么的】
##   把游戏自定义的按键动作注册到 Godot 的 InputMap（输入映射表）里，
##   这样游戏里才能用 Input.is_action_pressed("dodge") 这类方式来读取按键。
##
## 【怎么实现的 / 为什么放在 autoload】
##   1. Godot 只内置 ui_* 系列动作（如 ui_cancel=Esc），我们的 WASD/攻击等
##      是自定义动作，需要先注册才能使用。
##   2. autoload 节点在【任何场景加载之前】就会执行 _ready()，
##      所以注册一定发生在玩家脚本读取输入之前，不会出现"动作不存在"。
##   3. 注册用的是"物理键位码"(physical_keycode)：不管键盘布局如何，
##      按物理位置相同的键都会触发（比如法语键盘按 W 位置的键也算 W）。
##
## 【M1 说明】这些动作在编辑器的"项目设置→输入映射"面板里看不到，
##   但运行时有效。M2 会迁移到 project.godot 正式配置，以便玩家改键。
## ============================================================


func _ready() -> void:
	# 移动（每个动作可绑定多个键：WASD + 方向键）
	_add_key("move_forward", [KEY_W, KEY_UP])    # 前进：W 或 ↑
	_add_key("move_back", [KEY_S, KEY_DOWN])     # 后退：S 或 ↓
	_add_key("move_left", [KEY_A, KEY_LEFT])     # 左移：A 或 ←
	_add_key("move_right", [KEY_D, KEY_RIGHT])   # 右移：D 或 →
	# 闪避：Shift（方向由 W 决定 —— 按 W = 前冲，其余 = 后撤；见 player.gd 的 _try_start_dodge）
	_add_key("dodge", [KEY_SHIFT])
	_add_key("jump", [KEY_SPACE])                # 跳跃：空格
	_add_key("restart", [KEY_R])                 # 重新开始：R
	_add_mouse_button("attack", MOUSE_BUTTON_LEFT)  # 攻击：鼠标左键
	_add_mouse_button("block", MOUSE_BUTTON_RIGHT)  # 格挡：鼠标右键（按住=持续格挡）
	# 锁定敌人：鼠标中键（**点击切换**：点一次锁定、再点一次解除；读法与 block 不同，是"切换型"）
	_add_mouse_button("lock_on", MOUSE_BUTTON_MIDDLE)
	# 【调试】切换当前操控的角色：Tab 或 F（玩家 ⇄ 敌人循环，见 character_switcher.gd）。
	# 两个键都注册是为了避开不同键盘/输入法下 Tab 被系统抢走的情况。
	_add_key("switch_character", [KEY_TAB, KEY_F])
	# 交互：E（目前用于与 NPC 对话，以后开箱子/拾取地面物也复用这个键）。
	# 对话界面的选项**不用**它 —— 那套走 ui_up/ui_down/ui_accept + 数字键，见 dialogue_box.gd。
	_add_key("interact", [KEY_E])


## 把一个"键盘动作"注册进 InputMap。
## action：动作名（如 "move_forward"）；keys：一组物理键位码（如 [KEY_W]）。
func _add_key(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):          # 防重复注册
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()            # 新建一个"按键事件"
		ev.physical_keycode = key                # 指定物理键位
		InputMap.action_add_event(action, ev)    # 绑定到动作上


## 把一个"鼠标按键动作"注册进 InputMap（同上，只是事件类型不同）。
func _add_mouse_button(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button                     # 指定鼠标键（左/右/中…）
	InputMap.action_add_event(action, ev)
