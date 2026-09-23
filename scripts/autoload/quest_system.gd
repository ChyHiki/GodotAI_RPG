extends Node
## ============================================================
## 任务系统（autoload，节点名 QuestSystem）
## ============================================================
## 【这个文件是做什么的】
##   任务系统的**唯一运行时**。它做三件事：
##     1. 启动时把 assets/quests/ 下所有 .tres 定义读进内存；
##     2. 订阅 EventBus 上的世界事件，把它们换算成"某个任务的目标进度 +1"；
##     3. 对外提供接取/查询/交付的接口（对话系统、HUD 都通过它操作任务）。
##
## 【为什么是 autoload 而不是场景里的节点】
##   任务状态必须**跨场景存活**（从森林走到营地，接了任务不能丢），而且要能在
##   任何时刻被任何对象查询。autoload 天生满足这两点。
##   ⚠️ 但 autoload 里**不许出现玩法逻辑**（这里是纯状态管理 + 计数，属于合格的 autoload）——
##      别把"怪怎么打"这类代码塞进来，那会让它无法单测、也无法随场景回收。
##
## 【注册顺序】本文件依赖 EventBus，所以 project.godot 里 EventBus 必须排在它**前面**
##   （autoload 按书写顺序初始化，排在后面的才能安全访问前面的）。
##
## 【设计要点：为什么用事件而不是轮询】
##   世界那一侧只在 enemy.gd 的死亡分支里 emit 一句，任务这边自己订阅。
##   任务系统完全不认识"敌人"这个类，也不知道场景里有什么 —— 这条耦合只存在于信号签名上。
## ============================================================

## 任务定义目录。文件名随意，识别靠每个 .tres 内部的 id 字段。
const QUEST_DIR := "res://assets/quests"

## ---- 运行时状态（全部以 quest_id 为键）----
var _defs: Dictionary = {}     # quest_id -> QuestDefinition（静态配置）
var _states: Dictionary = {}   # quest_id -> QuestDefinition.State（当前状态）
var _counts: Dictionary = {}   # "quest_id#目标序号" -> 已完成计数
var _items: Dictionary = {}    # item_id -> 历史累计拾取量（不随任务重置）


func _ready() -> void:
	# 【顺序】先订阅、再读盘：万一读盘里有耗时操作，订阅已经就位不会漏事件。
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.area_entered.connect(_on_area_entered)
	EventBus.npc_interacted.connect(_on_npc_interacted)
	_load_definitions()


# ------------------------------------------------------------------
# 加载
# ------------------------------------------------------------------

## 扫描 QUEST_DIR 下所有 .tres 并登记为任务定义。
## 非法条目（不是 QuestDefinition、id 为空）跳过并警告，**不让一条坏数据拖垮整个启动**。
func _load_definitions() -> void:
	var dir := DirAccess.open(QUEST_DIR)
	if dir == null:
		push_warning("QuestSystem：任务目录不存在 %s，本次启动没有任何任务。" % QUEST_DIR)
		return
	for file_name in dir.get_files():
		# 导出成发行版后，资源在目录里会显示为 "xxx.tres.remap" —— 这里统一剥掉后缀，
		# 保证编辑器里跑和导出后跑看到的是同一批文件。
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := load(QUEST_DIR.path_join(clean))
		var def := res as QuestDefinition
		if def == null or def.id.is_empty():
			push_warning("QuestSystem：%s 不是有效的 QuestDefinition（或 id 为空），已跳过。" % clean)
			continue
		if _defs.has(def.id):
			push_warning("QuestSystem：任务 id 重复 '%s'（%s），后一个覆盖前一个。" % [def.id, clean])
		_defs[def.id] = def
		_states[def.id] = QuestDefinition.State.INACTIVE
	print("[QuestSystem] 载入任务 %d 条：%s" % [_defs.size(), ", ".join(_defs.keys())])


# ------------------------------------------------------------------
# 世界事件 → 目标进度
# ------------------------------------------------------------------

func _on_enemy_died(enemy_id: String) -> void:
	_bump(QuestObjective.Kind.KILL, enemy_id, 1)


## 拾取同时做两件事：① 记进"历史累计物品表"（对话条件要用：玩家手上有没有狼牙）；
## ② 推进 COLLECT 类目标。注意这两件事的生命周期不同 —— 物品表**不随任务重置**，
## 因为"玩家捡过什么"是世界的客观事实，与有没有接任务无关。
func _on_item_collected(item_id: String, amount: int) -> void:
	_items[item_id] = item_total(item_id) + amount
	_bump(QuestObjective.Kind.COLLECT, item_id, amount)


func _on_area_entered(area_id: String) -> void:
	_bump(QuestObjective.Kind.REACH, area_id, 1)


func _on_npc_interacted(npc_id: String) -> void:
	_bump(QuestObjective.Kind.TALK, npc_id, 1)


## ★ 核心推进函数：把"某个 kind 的某个 target 发生了 amount 次"分发给所有进行中的任务。
## 【为什么只遍历 ACTIVE 的任务】未接取/已完成的任务不该被计数 —— 玩家在接任务之前
##   杀掉的狼不算数（这是 RPG 的通行语义，也让"0/3"这个显示从接取那一刻起才合理）。
func _bump(kind: int, target_id: String, amount: int) -> void:
	if amount <= 0 or target_id.is_empty():
		return
	for quest_id in _defs:
		if _states.get(quest_id) != QuestDefinition.State.ACTIVE:
			continue
		var def: QuestDefinition = _defs[quest_id]
		var touched := false          # 本任务是否真的涨了进度（没涨就别发信号）
		for i in def.objectives.size():
			var obj: QuestObjective = def.objectives[i]
			if obj == null or obj.kind != kind or obj.target_id != target_id:
				continue
			var key := _key(quest_id, i)
			var before: int = _counts.get(key, 0)
			# 封顶 required_count：计数只用于显示与判定，涨过头会让 "3/3" 变成 "5/3"
			var after: int = mini(before + amount, obj.required_count)
			if after == before:
				continue
			_counts[key] = after
			touched = true
		if not touched:
			continue
		EventBus.quest_progress_changed.emit(quest_id)
		if _objectives_done(quest_id):
			_set_state(quest_id, QuestDefinition.State.COMPLETED)


## 全部目标是否都达到了要求数量。
func _objectives_done(quest_id: String) -> bool:
	var def: QuestDefinition = _defs.get(quest_id)
	if def == null:
		return false
	for i in def.objectives.size():
		var obj: QuestObjective = def.objectives[i]
		if obj == null:
			continue
		if int(_counts.get(_key(quest_id, i), 0)) < obj.required_count:
			return false
	return true


# ------------------------------------------------------------------
# 对外接口
# ------------------------------------------------------------------

## 这条任务 id 是否已注册（对话脚本里写错 id 时用它兜底，避免整段对话崩掉）。
func has(quest_id: String) -> bool:
	return _defs.has(quest_id)


func get_def(quest_id: String) -> QuestDefinition:
	return _defs.get(quest_id) as QuestDefinition


func state_of(quest_id: String) -> int:
	return int(_states.get(quest_id, QuestDefinition.State.INACTIVE))


## 现在能不能接取：任务存在 + 还没接（INACTIVE）+ 前置任务都已交付。
func is_available(quest_id: String) -> bool:
	var def: QuestDefinition = _defs.get(quest_id)
	if def == null:
		return false
	if state_of(quest_id) != QuestDefinition.State.INACTIVE:
		return false
	for req in def.required_quests:
		if state_of(req) != QuestDefinition.State.TURNED_IN:
			return false
	return true


## 接取任务：状态 INACTIVE → ACTIVE。
## 返回 false 表示没接成（不存在 / 已经接过 / 前置没满足），调用方无需区分原因。
func accept(quest_id: String) -> bool:
	if not is_available(quest_id):
		return false
	_set_state(quest_id, QuestDefinition.State.ACTIVE)
	return true


## 交付任务：状态 COMPLETED → TURNED_IN 并发放奖励。
## ★ 严格只认 COMPLETED，这一条就是"防重复领奖"的全部实现 ——
##   玩家在对话里反复点"交付"，第二次起 state 已经是 TURNED_IN，直接返回 false。
func turn_in(quest_id: String) -> bool:
	if not _defs.has(quest_id):
		return false
	if state_of(quest_id) != QuestDefinition.State.COMPLETED:
		return false
	_set_state(quest_id, QuestDefinition.State.TURNED_IN)
	var def: QuestDefinition = _defs[quest_id]
	if not def.reward_item_id.is_empty() and def.reward_amount > 0:
		# ⚠️ 暂存：等背包系统落地后，这里换成真正的"发放物品"调用。
		#    现在就打印一行，保证奖励不是"静默丢失"，方便验收时确认链路通了。
		print("[QuestSystem] 发放奖励 %s ×%d" % [def.reward_item_id, def.reward_amount])
	return true


## 所有进行中的任务 id（按定义加载顺序，稳定可预测）。
func active_quest_ids() -> Array[String]:
	var out: Array[String] = []
	for quest_id in _defs:
		if _states.get(quest_id) == QuestDefinition.State.ACTIVE:
			out.append(quest_id)
	return out


## 玩家历史累计拾取过某物品多少（对话条件 `[has wolf_fang]` 用它）。
func item_total(item_id: String) -> int:
	return int(_items.get(item_id, 0))


## 取任务目标进度，返回 [[已完成, 需要], ...]，下标与 def.objectives 一一对应。
func progress_of(quest_id: String) -> Array:
	var out: Array = []
	var def: QuestDefinition = _defs.get(quest_id)
	if def == null:
		return out
	for i in def.objectives.size():
		var obj: QuestObjective = def.objectives[i]
		var need: int = obj.required_count if obj != null else 0
		out.append([int(_counts.get(_key(quest_id, i), 0)), need])
	return out


## 生成任务追踪栏要显示的行：第 0 项是任务名，之后每个目标一行（带 x/y 进度）。
## 【为什么文案由系统生成而不是写死在 .tres 里】进度数字是运行时的，
##   必须和计数拼在一起显示；description 留空时还兜底成 "击杀 brute" 这类，
##   保证策划漏填也不会显示成空白行。
func tracker_lines(quest_id: String) -> Array[String]:
	var out: Array[String] = []
	var def: QuestDefinition = _defs.get(quest_id)
	if def == null:
		return out
	for i in def.objectives.size():
		var obj: QuestObjective = def.objectives[i]
		if obj == null:
			continue
		var label := obj.description
		if label.is_empty():
			label = fallback_objective_label(obj)
		out.append("%s  %d/%d" % [label, int(_counts.get(_key(quest_id, i), 0)), obj.required_count])
	return out


## 把状态值翻成中文（日志与调试用）。
static func state_name(s: int) -> String:
	match s:
		QuestDefinition.State.INACTIVE:
			return "未接取"
		QuestDefinition.State.ACTIVE:
			return "进行中"
		QuestDefinition.State.COMPLETED:
			return "目标达成"
		QuestDefinition.State.TURNED_IN:
			return "已交付"
	return "未知(%d)" % s


## 目标没填描述时的兜底文案。
static func fallback_objective_label(obj: QuestObjective) -> String:
	match obj.kind:
		QuestObjective.Kind.KILL:
			return "击败 " + obj.target_id
		QuestObjective.Kind.COLLECT:
			return "收集 " + obj.target_id
		QuestObjective.Kind.REACH:
			return "抵达 " + obj.target_id
		QuestObjective.Kind.TALK:
			return "与 " + obj.target_id + " 交谈"
	return obj.target_id


## 清空所有运行时状态（自动化测试的隔离手段；正式流程里不调用）。
func reset_all() -> void:
	for quest_id in _defs:
		_states[quest_id] = QuestDefinition.State.INACTIVE
	_counts.clear()
	_items.clear()


# ------------------------------------------------------------------
# 内部

func _set_state(quest_id: String, new_state: int) -> void:
	if _states.get(quest_id) == new_state:
		return
	_states[quest_id] = new_state
	print("[QuestSystem] %s：%s" % [quest_id, state_name(new_state)])
	EventBus.quest_state_changed.emit(quest_id, new_state)


func _key(quest_id: String, objective_index: int) -> String:
	return "%s#%d" % [quest_id, objective_index]
