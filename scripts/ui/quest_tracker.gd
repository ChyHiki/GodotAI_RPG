class_name QuestTracker
extends Control
## ============================================================
## 任务追踪栏（HUD 上的常驻小面板）
## ============================================================
## 【作用】屏幕左上角、玩家血条下方，显示所有"进行中"任务的名字与每个目标的 x/y 进度；
##   接取/达成/交付时顺带用 HUD 的顶部提示条喊一句。
##
## 【为什么不做轮询】它只订阅 EventBus 上的两个信号（状态变化 / 进度变化），
##   信号不来就什么都不做。若改成 _process 里每帧读 QuestSystem 再比对字符串，
##   就是"每帧重建一遍同一段文本"——白白产生垃圾，还得自己处理"值没变"的判重。
##
## 【怎么挂】由主场景创建后 add_child 到 HUD（CanvasLayer）上即可，没有别的依赖。
##   找不到 HUD 时只是不弹顶部提示，面板本身照常工作。
## ============================================================

## 面板宽带。固定值：任务文本本来就短，跟随窗口拉伸反而不好读。
const PANEL_WIDTH := 320.0
## 每一行的行高（字号 + 行距），用于算背景板高度。
const LINE_HEIGHT := 24.0

var _bg: ColorRect
var _label: Label
var _hud: Hud = null
## 已经提示过的任务名，避免同一任务反复弹提示（例如重复 emit 同状态）。
var _announced: Dictionary = {}


func _ready() -> void:
	# 【为什么要等一帧再找 HUD】主场景通常是 "先 add_child(hud) 再 new 本节点"，
	# 但反过来挂的情况也存在 —— 等一帧能保证 HUD 已进树并被 add_to_group 注册过。
	await get_tree().process_frame
	_hud = get_tree().get_first_node_in_group("hud") as Hud
	EventBus.quest_state_changed.connect(_on_state_changed)
	EventBus.quest_progress_changed.connect(_on_progress_changed)
	_build()
	_refresh()


# ------------------------------------------------------------------
# 构建
# ------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # 不拦截鼠标，免得挡住镜头环绕
	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.06, 0.09, 0.55)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.86))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("line_spacing", 6)   # 中文字挨太紧不好读
	add_child(_label)


# ------------------------------------------------------------------
# 刷新
# ------------------------------------------------------------------

## 按当前所有进行中的任务重建文本与背景尺寸。
func _refresh() -> void:
	var lines: Array[String] = []
	for quest_id in QuestSystem.active_quest_ids():
		var def := QuestSystem.get_def(quest_id)
		if def == null:
			continue
		lines.append("◆ " + def.display_title())
		for line in QuestSystem.tracker_lines(quest_id):
			lines.append("    " + line)
	# 图上没有进行中的任务时整块收起 —— 空面板会挡住视野还传达"系统坏了"的错觉
	visible = not lines.is_empty()
	if not visible:
		return
	_label.text = "\n".join(lines)
	var height := 14.0 + float(lines.size()) * LINE_HEIGHT
	_bg.size = Vector2(PANEL_WIDTH, height)
	_label.position = Vector2(12.0, 7.0)
	_label.size = Vector2(PANEL_WIDTH - 24.0, height - 14.0)


func _on_progress_changed(_quest_id: String) -> void:
	_refresh()


## 状态变化 → 刷新面板 + 顶部喊一句（"有反馈"是任务系统能被玩家感知的关键）。
func _on_state_changed(quest_id: String, state: int) -> void:
	_refresh()
	var def := QuestSystem.get_def(quest_id)
	if def == null:
		return
	var title := def.display_title()
	match state:
		QuestDefinition.State.ACTIVE:
			if _announced.has(quest_id + ":active"):
				return
			_announced[quest_id + ":active"] = true
			_hud_show("新任务：%s" % title)
		QuestDefinition.State.COMPLETED:
			if _announced.has(quest_id + ":done"):
				return
			_announced[quest_id + ":done"] = true
			_hud_show("%s · 目标达成，回去复命" % title)
		QuestDefinition.State.TURNED_IN:
			_announced[quest_id + ":active"] = false
			_hud_show("任务完成：%s" % title)


func _hud_show(text: String) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.show_message(text, 3.0)
