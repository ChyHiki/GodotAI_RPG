extends Node
## ============================================================
## 对话系统（autoload，节点名 DialogueSystem）
## ============================================================
## 【这个文件是做什么的】
##   对话的**执行器**：持有一张已解析的 DialogueGraph，维护"现在停在哪一句"，
##   处理玩家推进/选择，并执行节点上的动作（接任务、交任务…）。
##   它不画任何东西 —— UI 由 dialogue_box.gd 订阅本文件的信号来画。
##   这样"对话逻辑"和"对话框长什么样"可以各自替换。
##
## 【对外接口（UI / NPC 调用）】
##   start(graph, npc_id)        开始一段对话；已有对话进行中时返回 false
##   advance()                   无选项时"继续"到下一句
##   choose(index)               有选项时选中第 index 项（index 是**过滤后**的下标）
##   stop()                      强制结束
##   is_active() / current_line() 查询当前状态
##
## 【信号】dialogue_started / dialogue_line / dialogue_finished —— UI 只订阅这三个。
##
## 【注册顺序】依赖 EventBus 与 QuestSystem，project.godot 里必须排在它们后面。
## ============================================================

## 节点自动跳转的步数上限。纯路由节点会连续穿过，但万一 DSL 写出环（A→B→A）
## 就是死循环 —— 有上限才能变成一条报错而不是卡死整个游戏。
const MAX_STEPS := 64

## 对话开始（NPC 侧可用于播"转头看你"之类的表现）。
signal dialogue_started(npc_id: String)
## 显示一句新台词。choices 是**已按条件过滤过**的选项数组（空 = 只能按确认继续）。
signal dialogue_line(speaker: String, text: String, choices: Array)
## 对话结束（NPC 侧可用于播回头的动作）。
signal dialogue_finished(npc_id: String)

## ---- 运行时状态 ----
var _graph: DialogueGraph = null
var _node_id: String = ""
var _npc_id: String = ""
var _choices: Array = []
var _active: bool = false


## 开始一段对话。
## @return false 表示没开起来（已有对话在进行 / 图是空的），调用方据此决定要不要冻结玩家。
func start(graph: DialogueGraph, npc_id: String) -> bool:
	if _active:
		return false
	if graph == null or graph.size() == 0:
		push_warning("DialogueSystem：对话图是空的，无法开始（检查 .dlg 路径与内容）。")
		return false
	_graph = graph
	_npc_id = npc_id
	_active = true
	# 广播"和某人说话了"：TALK 类任务目标靠它推进。
	# 放在这里而不是 NPC 里，是因为"什么算一次对话"的判定权属于对话系统。
	EventBus.npc_interacted.emit(npc_id)
	dialogue_started.emit(npc_id)
	_enter(graph.start_id)
	return true


## 无选项时"继续"。有选项时**故意不生效** —— 否则玩家一通狂按确认就会跳过选择。
func advance() -> bool:
	if not _active or _graph == null:
		return false
	if not _choices.is_empty():
		return false
	var nxt := String(_graph.node_at(_node_id).get("next", ""))
	if nxt.is_empty():
		stop()
	else:
		_enter(nxt)
	return true


## 选中第 index 个选项。⚠️ index 是 **dialogue_line 信号里那个已过滤数组**的下标，
## 不是 DSL 里选项的原始行号 —— 有条件不满足被过滤掉的项不能在 UI 上占位。
func choose(index: int) -> bool:
	if not _active or index < 0 or index >= _choices.size():
		return false
	var nxt := String((_choices[index] as Dictionary).get("next", ""))
	if nxt.is_empty():
		stop()
	else:
		_enter(nxt)
	return true


## 强制结束对话（玩家按 Esc / 外部中断时调用）。
func stop() -> void:
	if not _active:
		return
	var npc := _npc_id
	_active = false
	_graph = null
	_node_id = ""
	_npc_id = ""
	_choices = []
	dialogue_finished.emit(npc)


func is_active() -> bool:
	return _active


func current_npc_id() -> String:
	return _npc_id


## 当前这一句的完整快照。UI 在订阅信号之外还可以主动拉一次，
## 避免"UI 创建晚于信号发出"导致的空对话框。
func current_line() -> Dictionary:
	if not _active or _graph == null:
		return {}
	var nd := _graph.node_at(_node_id)
	return {
		"npc_id": _npc_id,
		"speaker": String(nd.get("speaker", "")),
		"text": String(nd.get("text", "")),
		"choices": _choices,
	}


# ------------------------------------------------------------------
# 节点推进
# ------------------------------------------------------------------

## 进入某个节点：执行动作 → 过滤选项 → 发信号给 UI。
## 纯"路由节点"（没台词、没选项、只有 next）会被**自动穿过**，
## 这样 DSL 里可以把"给个奖励再跳到 n20"这种逻辑单独写成一个小节点。
func _enter(node_id: String) -> void:
	var id := node_id
	var guard := 0
	while true:
		guard += 1
		if guard > MAX_STEPS:
			push_error("DialogueSystem：节点跳转超过 %d 步，疑似成环（最后停在 '%s'）。" % [MAX_STEPS, id])
			stop()
			return
		if id.is_empty() or id == "end" or _graph == null or not _graph.has_node(id):
			# 跳到空 id / end / 不存在的节点 = 对话自然结束。
			# 不存在的节点只警告不报错：写错一个 next 不该让整局游戏崩掉。
			if not id.is_empty() and id != "end" and _graph != null and not _graph.has_node(id):
				push_warning("DialogueSystem：节点 '%s' 不存在，对话提前结束。" % id)
			stop()
			return
		_node_id = id
		var nd := _graph.node_at(id)
		_run_actions(nd.get("actions", []))
		_choices = _visible_choices(nd.get("choices", []))
		var text := String(nd.get("text", ""))
		var nxt := String(nd.get("next", ""))
		if text.is_empty() and _choices.is_empty() and not nxt.is_empty():
			id = nxt
			continue                      # 路由节点：不停留，继续往下
		dialogue_line.emit(String(nd.get("speaker", "")), text, _choices)
		return


## 按条件过滤选项。条件不满足的选项**直接不出现**（不是变灰）——
## "没有狼牙就不会有交差这个选项"比"有个灰选项点不动"更像 RPG。
func _visible_choices(raw_choices: Array) -> Array:
	var out: Array = []
	for raw_choice in raw_choices:
		var choice := raw_choice as Dictionary
		if choice == null:
			continue
		if _eval_condition(String(choice.get("condition", ""))):
			out.append(choice)
	return out


## 条件求值。语法：`<谓词> <参数...>`，空字符串恒为真。
##   has <item_id> [n]      历史累计拾取过 n 个（默认 1）
##   quest_not_taken <id>   任务还没接过
##   quest_active <id>      任务进行中
##   quest_ready <id>       目标已达成、**可以交付**（最常用的一个）
##   quest_done <id>        目标已达成或已交付
## ⚠️ quest_ready 与 quest_done 必须分开：交付完任务后如果还用 quest_done，
##   "徽记我带回来了"这种交差选项会一直挂着，点了只会触发一次 complete 失败警告。
##
## ★ 支持用 `&` 组合多个子条件（AND，全真才为真）：
##     [quest_done q_guards & quest_not_taken q_aftermath]
##   编排任务链时"前置已交付 **且** 后续还没接"是最常见的组合 ——
##   没有 AND 就只能靠多插几个中间节点绕过去，结构会迅速变得难读。
func _eval_condition(cond: String) -> bool:
	if cond.is_empty():
		return true
	for part in cond.split("&", false):
		if not _eval_single_condition(String(part).strip_edges()):
			return false
	return true


## 单个谓词求值：`<谓词> <参数...>`（可用谓词见上面的列表）。
func _eval_single_condition(cond: String) -> bool:
	if cond.is_empty():
		return true
	var parts := cond.split(" ", false)
	if parts.is_empty():
		return true
	var verb := String(parts[0])
	match verb:
		"has":
			if parts.size() < 2:
				return false
			var need: int = int(parts[2]) if parts.size() > 2 else 1
			return QuestSystem.item_total(String(parts[1])) >= need
		"quest_not_taken":
			if parts.size() < 2:
				return false
			return QuestSystem.state_of(String(parts[1])) == QuestDefinition.State.INACTIVE
		"quest_active":
			if parts.size() < 2:
				return false
			return QuestSystem.state_of(String(parts[1])) == QuestDefinition.State.ACTIVE
		"quest_ready":
			if parts.size() < 2:
				return false
			return QuestSystem.state_of(String(parts[1])) == QuestDefinition.State.COMPLETED
		"quest_done":
			if parts.size() < 2:
				return false
			return QuestSystem.state_of(String(parts[1])) >= QuestDefinition.State.COMPLETED
	# 不认识的谓词按"满足"处理并警告：宁可多显示一个选项，也不要让整段对话卡住。
	push_warning("DialogueSystem：无法识别的条件 '%s'（按满足处理）。" % cond)
	return true


## 执行节点动作。动作都是"对其它系统的一次调用"，本文件不保存任何任务状态。
## 语法：`<动词> <参数...>`
##   accept <quest_id>    接取任务
##   complete <quest_id>  交付任务（发奖励）
##   log <文本>           调试用：往控制台打一行
func _run_actions(actions: Array) -> void:
	for raw_action in actions:
		var parts := String(raw_action).split(" ", false)
		if parts.is_empty():
			continue
		match String(parts[0]):
			"accept":
				if parts.size() < 2:
					push_warning("DialogueSystem：accept 缺任务 id。")
				elif not QuestSystem.accept(String(parts[1])):
					push_warning("DialogueSystem：接取任务 '%s' 失败（不存在 / 已接 / 前置未满足）。" % parts[1])
			"complete":
				if parts.size() < 2:
					push_warning("DialogueSystem：complete 缺任务 id。")
				elif not QuestSystem.turn_in(String(parts[1])):
					push_warning("DialogueSystem：交付任务 '%s' 失败（当前不是「目标达成」状态）。" % parts[1])
			"log":
				print("[Dialogue] ", " ".join(parts.slice(1)))
			_:
				push_warning("DialogueSystem：无法识别的动作 '%s'。" % raw_action)
