class_name DialogueBox
extends Control
## ============================================================
## 对话框（HUD 上的对话 UI）
## ============================================================
## 【作用】屏幕底部的大面板：说话人 + 台词（打字机逐字出现）+ 选项列表。
##   它**只订阅 DialogueSystem 的信号**，自己不保存任何对话进度 ——
##   对话框可以随时销毁重建，对话照样进行。
##
## 【为什么用键盘而不是鼠标选选项】
##   游戏里鼠标是 MOUSE_MODE_CAPTURED（镜头靠它转）。想让鼠标点选项就得先释放鼠标，
##   而主场景的 _unhandled_input 里有一条"鼠标可见时点一下窗口就重新捕获"的逻辑，
##   会把玩家的第一次点击吃掉 —— 表现为"选项点了没反应"。
##   所以这里完全走键盘：↑↓ 选择、Enter/Space 确认、1-9 直选、Esc 关闭。
##
## 【为什么用 _input 而不是 _unhandled_input】
##   主场景把 Esc(ui_cancel) 接成了"切换鼠标捕获"。_input 比 _unhandled_input 更早，
##   在这里调 set_input_as_handled() 就能把按键吃掉，主场景收不到 —— 对话期间按 Esc
##   只会关对话，不会顺手把鼠标放出来。
##
## 【怎么挂】new 出来后 add_child 到 HUD 上（或任何 CanvasLayer），无需配置。
## ============================================================

## 打字机速度（字符/秒）。中文 30 字/秒约等于"一眼扫过去正好读完"。
const CHARS_PER_SEC := 30.0

var _panel: ColorRect
var _speaker: Label
var _text: Label
var _choices_box: VBoxContainer
var _hint: Label

var _choices: Array = []
var _choice_labels: Array[Label] = []
var _selected: int = 0
var _typing: bool = false
var _type_elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # 对话期间也别挡住镜头
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	DialogueSystem.dialogue_line.connect(_on_line)
	DialogueSystem.dialogue_finished.connect(_on_finished)
	visible = false
	# 兜底：万一本节点创建得比对话开始还晚，主动拉一次当前状态，避免出现空白框。
	if DialogueSystem.is_active():
		var line := DialogueSystem.current_line()
		_on_line(String(line.get("speaker", "")), String(line.get("text", "")), line.get("choices", []))


# ------------------------------------------------------------------
# 构建
# ------------------------------------------------------------------

func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.05, 0.06, 0.09, 0.86)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 80.0
	_panel.offset_right = -80.0
	_panel.offset_top = -300.0
	_panel.offset_bottom = -48.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_speaker = Label.new()
	_speaker.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_speaker.offset_left = 28.0
	_speaker.offset_right = -28.0
	_speaker.offset_top = 16.0
	_speaker.offset_bottom = 48.0
	_speaker.add_theme_font_size_override("font_size", 20)
	_speaker.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_panel.add_child(_speaker)

	var rule := ColorRect.new()
	rule.color = Color(1.0, 0.86, 0.5, 0.35)
	rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = 28.0
	rule.offset_right = -28.0
	rule.offset_top = 54.0
	rule.offset_bottom = 55.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(rule)

	_text = Label.new()
	_text.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_text.offset_left = 28.0
	_text.offset_right = -28.0
	_text.offset_top = 68.0
	_text.offset_bottom = 168.0
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97))
	_text.add_theme_constant_override("line_spacing", 6)
	_panel.add_child(_text)

	_choices_box = VBoxContainer.new()
	_choices_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_choices_box.offset_left = 28.0
	_choices_box.offset_right = -28.0
	_choices_box.offset_top = 176.0
	_choices_box.offset_bottom = -38.0
	_choices_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_choices_box)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -34.0
	_hint.offset_bottom = -8.0
	_hint.offset_right = -28.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	_panel.add_child(_hint)


# ------------------------------------------------------------------
# 打字机
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _typing:
		return
	_type_elapsed += delta
	var total := _text.text.length()
	var shown := int(_type_elapsed * CHARS_PER_SEC)
	if shown >= total:
		_finish_typing()
	else:
		_text.visible_characters = shown


## 打字结束：显示全文 + 把选项亮出来。
## ★ 选项必须**等台词打完才出现**：否则玩家会一边读字一边被选项抢注意力，
##   而且打字过程中按确认到底算"跳过"还是"选中"会变得说不清。
func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_rebuild_choices()


func _start_typing(text: String) -> void:
	_text.text = text
	_text.visible_characters = 0
	_type_elapsed = 0.0
	_typing = true
	_rebuild_choices()          # 先把上一句的选项清掉
	if text.is_empty():
		_finish_typing()


# ------------------------------------------------------------------
# 选项
# ------------------------------------------------------------------

func _rebuild_choices() -> void:
	for lb in _choice_labels:
		lb.queue_free()
	_choice_labels.clear()
	if _typing:
		return
	for i in _choices.size():
		var lb := Label.new()
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_font_size_override("font_size", 16)
		_choices_box.add_child(lb)
		_choice_labels.append(lb)
	_selected = clampi(_selected, 0, maxi(0, _choices.size() - 1))
	_update_highlight()


func _update_highlight() -> void:
	for i in _choice_labels.size():
		var lb: Label = _choice_labels[i]
		var chosen := i == _selected
		var body := String((_choices[i] as Dictionary).get("text", ""))
		lb.text = ("▶  " if chosen else "      ") + "%d. %s" % [i + 1, body]
		lb.add_theme_color_override("font_color",
			Color(1.0, 0.9, 0.45) if chosen else Color(0.78, 0.83, 0.9))


func _move_selection(step: int) -> void:
	if _choices.size() <= 1:
		return
	_selected = wrapi(_selected + step, 0, _choices.size())
	_update_highlight()


## 确认：有选项就选，没选项就推进到下一句。
func _confirm() -> void:
	if _choices.is_empty():
		DialogueSystem.advance()
	else:
		DialogueSystem.choose(_selected)


# ------------------------------------------------------------------
# 输入
# ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not DialogueSystem.is_active() or not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _consume(key):
		# 吃掉事件：主场景的 Esc→鼠标捕获、R→重开都不会在对话里被误触发
		get_viewport().set_input_as_handled()


func _consume(key: InputEventKey) -> bool:
	# 数字键 1..9 直选（打字中先当作"跳过打字"）
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		if _typing:
			_finish_typing()
			return true
		var index := int(key.keycode - KEY_1)
		if index < _choices.size():
			_selected = index
			_update_highlight()
			_confirm()
		return true
	match key.keycode:
		KEY_UP:
			_move_selection(-1)
			return true
		KEY_DOWN:
			_move_selection(1)
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _typing:
				_finish_typing()      # 打字中按确认 = 立刻显示全文（不跳过这句台词）
			else:
				_confirm()
			return true
		KEY_ESCAPE:
			DialogueSystem.stop()
			return true
	return false


# ------------------------------------------------------------------
# DialogueSystem 信号
# ------------------------------------------------------------------

func _on_line(speaker: String, text: String, choices: Array) -> void:
	visible = true
	_speaker.text = speaker
	_choices = choices
	_selected = 0
	_start_typing(text)
	_update_hint()


func _on_finished(_npc_id: String) -> void:
	visible = false
	_choices = []
	_typing = false
	_rebuild_choices()


func _update_hint() -> void:
	if _choices.is_empty():
		_hint.text = "Enter / 空格 继续　·　Esc 结束"
	else:
		_hint.text = "↑↓ 或 数字键 选择　·　Enter 确认"
