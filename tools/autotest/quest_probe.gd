extends Node
## ============================================================
## 回归探针：任务系统 + NPC 对话
## ============================================================
## 【为什么单独写一份】m1_autotest 是"工程师自己写的断言"，跑它不算独立验证。
##   本探针主动证伪这套新系统里最容易悄悄坏掉的几条：
##     · 对话脚本解析：选项/条件/动作/自动跳转有没有被切错一格（写错就整段剧情的走向变了）
##     · 事件驱动计数：未接取的任务不该被计数、计数该封顶、一个目标达成不该提前完成整条任务
##     · 「目标达成」与「已交付」是两个状态：合成一个就会**重复发奖励**
##     · 对话选项要随任务状态变化（没接/进行中/可交付三个分支必须互斥且各自只亮一个）
##     · 对话期间玩家被冻结、结束后必须恢复（冻住不解 = 玩家看着屏幕干瞪眼）
##
## 【为什么这套系统特别好测】它全程事件驱动、不依赖画面、不依赖帧数 ——
##   直接 EventBus.xxx.emit() 就能把世界推进到任意状态，断言全是"状态查询"。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       res://tools/autotest/quest_probe.tscn
## 退出码 0 = 全部通过；1 = 有失败（失败项以 "PROBE FAIL:" 打印）。
## ============================================================

const DIALOGUE_PATH := "res://assets/dialogue/quartermaster.dlg"

var failures: Array[String] = []
var _rows: Array[String] = []
var _violations: int = 0

var _main: Node = null
var _player: PlayerCharacter = null
var _npc: Npc = null
var _graph: DialogueGraph = null


func _ready() -> void:
	await _run()
	print("")
	print("=== PROBE TABLE ===")
	for r in _rows:
		print(r)
	print("")
	print("=== INVARIANT VIOLATIONS: %d ===" % _violations)
	print("")
	if failures.is_empty():
		print("PROBE RESULT: ALL PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("PROBE FAIL: " + f)
		print("PROBE RESULT: %d FAILED" % failures.size())
		get_tree().quit(1)


# ------------------------------------------------------------------
# 断言 / 工具
# ------------------------------------------------------------------

func _check(ok: bool, label: String, detail: String = "") -> void:
	var tag := "PASS" if ok else "FAIL"
	_rows.append("[%s] %s%s" % [tag, label, ("  | " + detail) if detail != "" else ""])
	if ok:
		print("PROBE OK: " + label + (("  [" + detail + "]") if detail != "" else ""))
	else:
		failures.append(label)
		print("PROBE FAIL: " + label + (("  [" + detail + "]") if detail != "" else ""))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 选项目标节点的文本（省得每处都写两层类型转换）。
func _choice_text(choices: Array, index: int) -> String:
	if index < 0 or index >= choices.size():
		return "<越界>"
	return String((choices[index] as Dictionary).get("text", ""))


func _visible_choices() -> Array:
	return DialogueSystem.current_line().get("choices", [])


## 选项列表里是否含有某段文本的选项。
## ★ 比"数个数 + 按下标取"健壮：剧情会不断加分支，按下标断言每次都要回来改，
##   而"该出现的分支出现了没 / 不该出现的分支有没有混进来"才是真正想守住的东西。
func _has_choice(choices: Array, text: String) -> bool:
	for c in choices:
		if String((c as Dictionary).get("text", "")) == text:
			return true
	return false


## 把"击杀 + 掉落"推进到目标达成。示例任务要 2 杀 + 3 徽记。
func _grant_objectives() -> void:
	EventBus.enemy_died.emit("brute")
	EventBus.enemy_died.emit("brute")
	EventBus.item_collected.emit("guard_insignia", 3)


# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------

func _run() -> void:
	# ---- T1 对话脚本解析（纯函数，不依赖场景）----
	var source := FileAccess.get_file_as_string(DIALOGUE_PATH)
	_check(not source.is_empty(), "T1 对话脚本可读", DIALOGUE_PATH)
	_graph = DialogueGraph.parse(source)
	# 剧情会持续增长，所以断言"至少这么多"而不是"恰好" ——
	# 否则每加一段对话都要回来改探针，断言就从助力变成负担了。
	_check(_graph.size() >= 5, "T1 解析出至少 5 个节点", "实际 %d" % _graph.size())
	for required_node in ["start", "offer", "accept", "remind", "turnin", "offer2", "turnin2"]:
		_check(_graph.has_node(required_node), "T1 关键节点 @%s 存在" % required_node)
	_check(_graph.start_id == "start", "T1 入口节点是 start", _graph.start_id)

	var start_node := _graph.node_at("start")
	_check(String(start_node.get("speaker", "")) == "军需官", "T1 说话人解析正确",
		String(start_node.get("speaker", "")))
	_check(String(start_node.get("text", "")).begins_with("又一位骑士"), "T1 台词解析正确")
	var start_choices: Array = start_node.get("choices", [])
	_check(start_choices.size() >= 4, "T1 start 至少有 4 个选项", "实际 %d" % start_choices.size())
	_check(_has_choice(start_choices, "这边有什么需要帮忙的吗？"), "T1 start 含接取分支")
	_check(_has_choice(start_choices, "没什么，我先走了。"), "T1 start 含告别分支")
	_check(String((start_choices[0] as Dictionary).get("condition", "")) == "quest_not_taken q_guards",
		"T1 选项条件解析正确")
	_check(String((start_choices[0] as Dictionary).get("next", "")) == "offer", "T1 选项目标解析正确")
	_check(String((start_choices[2] as Dictionary).get("condition", "")) == "quest_ready q_guards",
		"T1 另一个选项的条件也解析正确")
	# ★ 组合条件里的 `&` 必须被原样保留在 condition 字符串里，交给 DialogueSystem 去分词求值
	_check(String((start_choices[5] as Dictionary).get("condition", ""))
			== "quest_done q_guards & quest_not_taken q_aftermath",
		"T1 组合条件（&）原样解析")
	var last_choice: Dictionary = start_choices[start_choices.size() - 1]
	_check(String(last_choice.get("condition", "")) == "", "T1 无条件选项的条件为空串")

	var accept_node := _graph.node_at("accept")
	var actions: Array = accept_node.get("actions", [])
	_check(actions.size() == 1 and String(actions[0]) == "accept q_guards", "T1 动作行解析正确",
		str(actions))
	# `=> end` 写在 @remind 上（一个"看完就结束"的节点），这里验它落到了 next 字段
	_check(String(_graph.node_at("remind").get("next", "")) == "end", "T1 自动去向（=>）解析正确")

	# ★ 多行台词必须**拼接**而不是"后一行覆盖前一行"：@offer 写了两句，
	#   若只留最后一句，玩家就会看到一个没头没尾的悬赏说明。
	var offer_text := String(_graph.node_at("offer").get("text", ""))
	_check(offer_text.contains("\n") and offer_text.begins_with("北边林地"),
		"T1 连续两行台词被拼接为一段", offer_text.replace("\n", " / "))

	# ---- T2 解析容错 ----
	_check(DialogueGraph.parse("# 只有注释\n\n").size() == 0, "T2 空脚本解析出 0 节点")
	_check(DialogueGraph.parse("孤立台词，前面没有 @节点\n").size() == 0, "T2 未声明节点的台词被忽略")
	var no_text := DialogueGraph.parse("@a\n- 只有选项 -> b\n@b\n一句台词\n")
	_check(no_text.size() == 2 and String(no_text.node_at("a").get("text", "")) == "",
		"T2 无台词节点文本为空串")
	_check(not _graph.has_node("不存在的节点") and _graph.node_at("不存在的节点").is_empty(),
		"T2 查询不存在的节点返回空字典而不是报错")

	# ---- 起场景（后面几组都要用到真实的玩家 / NPC）----
	_main = load("res://maps/forest_clearing.tscn").instantiate()
	add_child(_main)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	_npc = get_tree().get_first_node_in_group("npc") as Npc
	_check(_player != null, "前置：玩家已生成")
	_check(_npc != null, "前置：NPC 已生成")
	_check(_npc != null and _npc._graph != null, "前置：NPC 对话图已加载")
	_check(InputMap.has_action("interact"), "前置：interact 动作已注册")
	if _player == null or _npc == null or _npc._graph == null:
		return

	# ---- T3 任务系统基础 ----
	QuestSystem.reset_all()
	_check(QuestSystem.has("q_guards"), "T3 示例任务已载入")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.INACTIVE, "T3 初始状态为未接取")
	_check(QuestSystem.is_available("q_guards"), "T3 无前置任务 → 可接取")
	_check(not QuestSystem.has("根本没这条任务"), "T3 查询不存在的任务返回 false")
	_check(QuestSystem.accept("q_guards"), "T3 接取成功")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.ACTIVE, "T3 接取后状态为进行中")
	_check(not QuestSystem.accept("q_guards"), "T3 重复接取被拒")
	_check(QuestSystem.active_quest_ids().size() == 1, "T3 进行中任务计数为 1")

	# ---- T4 击杀事件推进 ----
	EventBus.enemy_died.emit("brute")
	EventBus.enemy_died.emit("brute")
	var progress := QuestSystem.progress_of("q_guards")
	_check(int(progress[0][0]) == 2, "T4 击杀目标进度 2/2", str(progress[0]))
	_check(int(progress[1][0]) == 0, "T4 击杀事件不推进收集目标", str(progress[1]))
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.ACTIVE,
		"T4 ★ 单个目标达成不足以完成整条任务")
	EventBus.enemy_died.emit("brute")
	progress = QuestSystem.progress_of("q_guards")
	_check(int(progress[0][0]) == 2, "T4 击杀计数封顶，不出现 3/2", str(progress[0]))

	# ---- T5 收集事件 + 完成 ----
	EventBus.item_collected.emit("guard_insignia", 3)
	progress = QuestSystem.progress_of("q_guards")
	_check(int(progress[1][0]) == 3, "T5 收集目标进度 3/3", str(progress[1]))
	_check(QuestSystem.item_total("guard_insignia") == 3, "T5 物品历史累计正确")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.COMPLETED,
		"T5 全部目标达成 → 目标达成状态")

	# ---- T6 无关事件不误伤 ----
	EventBus.item_collected.emit("不存在的物品", 5)
	progress = QuestSystem.progress_of("q_guards")
	_check(int(progress[1][0]) == 3, "T6 无关物品不影响已有进度", str(progress[1]))
	EventBus.enemy_died.emit("别的怪")
	progress = QuestSystem.progress_of("q_guards")
	_check(int(progress[0][0]) == 2, "T6 无关敌人类型不影响进度", str(progress[0]))

	# ---- T7 未接取的任务不被计数 ----
	QuestSystem.reset_all()
	EventBus.enemy_died.emit("brute")
	EventBus.item_collected.emit("guard_insignia", 3)
	var idle_progress := QuestSystem.progress_of("q_guards")
	_check(int(idle_progress[0][0]) == 0 and int(idle_progress[1][0]) == 0,
		"T7 ★ 未接取时世界事件不计入进度")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.INACTIVE, "T7 未接取状态不因事件改变")

	# ---- T8 交付与防重复发奖 ----
	_check(QuestSystem.accept("q_guards"), "T8 重新接取成功")
	_grant_objectives()
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.COMPLETED, "T8 目标已达成")
	_check(QuestSystem.turn_in("q_guards"), "T8 首次交付成功")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.TURNED_IN, "T8 状态为已交付")
	_check(not QuestSystem.turn_in("q_guards"), "T8 ★ 重复交付被拒（防重复发奖励）")
	_check(not QuestSystem.is_available("q_guards"), "T8 已交付的任务不再出现在可接列表")
	_check(QuestSystem.active_quest_ids().is_empty(), "T8 已交付任务不算进行中")

	# ---- T9 对话：未接取分支 ----
	QuestSystem.reset_all()
	DialogueSystem.stop()
	_check(DialogueSystem.start(_graph, "quartermaster"), "T9 对话开始")
	_check(DialogueSystem.is_active(), "T9 对话处于进行中")
	_check(not DialogueSystem.start(_graph, "quartermaster"), "T9 已在对话中时重复开始被拒")
	var choices := _visible_choices()
	_check(_has_choice(choices, "这边有什么需要帮忙的吗？"), "T9 未接任务时显示接取分支")
	_check(not _has_choice(choices, "悬赏我还在办。"), "T9 未接任务时不显示进行中分支")
	_check(not _has_choice(choices, "徽记我带回来了。"), "T9 未接任务时不显示交差分支")
	_check(not _has_choice(choices, "还有别的活儿吗？"), "T9 ★ 前置未交付时下一章入口不出现")
	# ★ 有选项时 advance() 必须无效 —— 否则玩家狂按确认会直接把选择跳过去
	_check(not DialogueSystem.advance(), "T9 ★ 有选项时 advance 不生效")

	# ---- T10 对话选项驱动任务 ----
	_check(DialogueSystem.choose(0), "T10 选择接取分支")
	_check(String(DialogueSystem.current_line().get("text", "")).begins_with("北边林地"),
		"T10 进入 offer 节点")
	_check(_visible_choices().size() == 2, "T10 offer 有 2 个选项")
	_check(DialogueSystem.choose(0), "T10 选择「交给我」")
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.ACTIVE,
		"T10 ★ 对话动作 [accept] 真的把任务接到了")
	_check(String(DialogueSystem.current_line().get("text", "")).begins_with("好！"),
		"T10 进入 accept 节点")

	# ---- T11 选项指向 end → 对话结束 ----
	_check(DialogueSystem.choose(0), "T11 选择「我这就去」")
	_check(not DialogueSystem.is_active(), "T11 选项指向 end → 对话结束")
	_check(not DialogueSystem.advance(), "T11 非对话状态下 advance 无效")

	# ---- T12 选项随任务状态变化（进行中分支）+ `=>` 自动去向 ----
	DialogueSystem.start(_graph, "quartermaster")
	var mid_choices := _visible_choices()
	_check(_has_choice(mid_choices, "悬赏我还在办。"), "T12 ★ 进行中时出现进度分支")
	_check(not _has_choice(mid_choices, "这边有什么需要帮忙的吗？"), "T12 已接取后不再显示接取分支")
	_check(not _has_choice(mid_choices, "徽记我带回来了。"), "T12 目标未达成时没有交差分支")
	_check(DialogueSystem.choose(0), "T12 选择「悬赏我还在办」")
	_check(String(DialogueSystem.current_line().get("text", "")).begins_with("悬赏还算数"),
		"T12 进入 remind 节点")
	_check(_visible_choices().is_empty(), "T12 remind 节点没有选项")
	_check(DialogueSystem.advance(), "T12 ★ 无选项时 advance 生效")
	_check(not DialogueSystem.is_active(), "T12 ★ 沿 => end 自动结束对话")

	# ---- T13 选项随任务状态变化（可交付分支）+ 交付 ----
	_grant_objectives()
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.COMPLETED, "T13 目标已达成")
	DialogueSystem.start(_graph, "quartermaster")
	var ready_choices := _visible_choices()
	_check(_has_choice(ready_choices, "徽记我带回来了。"), "T13 ★ 可交付时出现交差分支")
	_check(not _has_choice(ready_choices, "悬赏我还在办。"), "T13 目标达成后不再显示进度分支")
	DialogueSystem.choose(0)
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.TURNED_IN,
		"T13 ★ 对话动作 [complete] 完成了交付")
	_check(String(DialogueSystem.current_line().get("text", "")).begins_with("干得漂亮"),
		"T13 进入 turnin 节点")
	DialogueSystem.choose(0)
	_check(not DialogueSystem.is_active(), "T13 交付对话走到结束")

	# ---- T14 已交付后的选项 ----
	DialogueSystem.start(_graph, "quartermaster")
	var done_choices := _visible_choices()
	_check(not _has_choice(done_choices, "徽记我带回来了。"), "T14 ★ 交付后不再显示交差分支")
	_check(not _has_choice(done_choices, "悬赏我还在办。"), "T14 交付后不再显示进度分支")
	_check(_has_choice(done_choices, "还有别的活儿吗？"), "T14 ★ 前置交付后解锁下一章入口")
	_check(_has_choice(done_choices, "没什么，我先走了。"), "T14 始终保留告别选项")
	DialogueSystem.stop()

	# ---- T15 NPC 交互与玩家冻结 ----
	QuestSystem.reset_all()
	DialogueSystem.stop()
	_check(_player.control_enabled, "T15 对话前玩家可操控")
	_npc._start_dialogue()
	_check(DialogueSystem.is_active(), "T15 NPC 发起了对话")
	_check(not _player.control_enabled, "T15 ★ 对话期间玩家被冻结（只掐输入，物理照常）")
	DialogueSystem.stop()
	_check(_player.control_enabled, "T15 ★ 对话结束后玩家恢复操控")
	_check(_npc._frozen_player == null, "T15 解冻后不再持有玩家引用")
	_check(is_instance_valid(_npc) and _npc.is_in_group("npc"), "T15 NPC 正常挂在 npc 组里")

	# ---- T16 不变量：对话结束时玩家必定可操控 ----
	# （避免"某个分支忘了解冻"这类只在特定选项下才暴露的死角）
	# ⚠️ GDScript **没有** Python 的 for-else 语法，这里用标志位表达"一次都没坏"。
	var all_unfrozen := true
	for round_index in 3:
		QuestSystem.reset_all()
		DialogueSystem.start(_graph, "quartermaster")
		DialogueSystem.choose(0)
		DialogueSystem.stop()
		if not _player.control_enabled:
			all_unfrozen = false
			_violations += 1
			_check(false, "★ 不变量[T16 第 %d 轮]：对话结束后玩家必定可操控" % (round_index + 1))
			break
	if all_unfrozen:
		_rows.append("[PASS] ★ 不变量[T16]：任意分支结束对话后玩家都可操控")
		print("PROBE OK: ★ 不变量[T16]：任意分支结束对话后玩家都可操控")

	# ---- T17 任务链：前置必须"已交付"才解锁后续 ----
	QuestSystem.reset_all()
	_check(not QuestSystem.is_available("q_aftermath"), "T17 ★ 前置未完成时后续任务不可接")
	_check(not QuestSystem.accept("q_aftermath"), "T17 ★ 前置未完成时接取被拒")
	_check(QuestSystem.accept("q_guards"), "T17 接取第一章")
	_grant_objectives()
	_check(QuestSystem.state_of("q_guards") == QuestDefinition.State.COMPLETED, "T17 第一章目标达成")
	_check(not QuestSystem.is_available("q_aftermath"),
		"T17 ★ 前置只是「目标达成」还不够 —— 必须回 NPC 交付才算走完")
	_check(QuestSystem.turn_in("q_guards"), "T17 第一章交付")
	_check(QuestSystem.is_available("q_aftermath"), "T17 ★ 前置交付后后续任务解锁")
	_check(QuestSystem.accept("q_aftermath"), "T17 第二章接取成功")
	_check(QuestSystem.active_quest_ids().size() == 1, "T17 此时只有第二章在进行中")

	# ---- T18 组合条件 `&`（且）----
	_check(DialogueSystem._eval_condition("quest_done q_guards & quest_active q_aftermath"),
		"T18 ★ 组合条件：两个子条件都满足时为真")
	_check(not DialogueSystem._eval_condition("quest_done q_guards & quest_ready q_aftermath"),
		"T18 ★ 组合条件：有一个不满足即为假")
	_check(not DialogueSystem._eval_condition("quest_not_taken q_guards & quest_active q_aftermath"),
		"T18 ★ 组合条件：前一个子条件为假即为假")
	_check(DialogueSystem._eval_condition(""), "T18 空条件恒为真")
	_check(DialogueSystem._eval_condition("quest_active q_aftermath"), "T18 单个谓词仍然可用")
