class_name DialogueGraph
extends RefCounted
## ============================================================
## 对话图：解析后的对话数据 + 文本 DSL 解析器
## ============================================================
## 【为什么对话要用"图"】
##   对话不是一串文本，而是"这句话 → 玩家能选哪几句 → 分别跳到哪"的**有向图**。
##   真正会变的只有三样东西：说什么、能选什么、选了之后发生什么。把它们拆开，
##   剧情分支才有地方生长（同一句话在不同任务进度下给出不同选项）。
##
## 【为什么不做成 Resource 在检视面板里点】
##   树形 Resource 在 Inspector 里改三层以上就很难看出"谁跳谁"，改错一个 next
##   要跑起来才看得见。用文本 DSL：一屏就能看完整段对话的结构，加分支就是多一行，
##   而且天然能进 git diff、能被非程序员改。
##
## 【DSL 格式】（# 开头是注释行）
##   @start                          节点声明：一个节点从 @id 开始，到下个 @ 为止
##   npc: 又一位骑士？                 说话人: 台词（说话人可省略，冒号紧跟在 12 字符内才认）
##   [accept q_wolves]               进入本节点时执行的动作
##   - 有什么需要帮忙的？ -> offer     选项：文本 [条件] -> 目标节点
##   - 狼牙我拿到了。 [has wolf_fang] -> turnin
##   => end                          没有选项时的默认去向（end = 关闭对话）
## ============================================================

## 起始节点 id。约定用 @start；没写就取文件里的第一个节点。
var start_id: String = ""

## 节点表：node_id -> {speaker, text, actions: Array[String], choices: Array[Dictionary], next: String}
## 每个 choice 是 {text, condition, next}。
var nodes: Dictionary = {}


## 从 DSL 文本解析出对话图。
## 【为什么是 static】解析是纯函数（输入文本 → 输出图），不需要实例状态，
##   做成 static 后调用方可以 `DialogueGraph.parse(text)` 直接用，不必先 new。
static func parse(source: String) -> DialogueGraph:
	var g := DialogueGraph.new()
	var cur_id := ""
	var cur: Dictionary = {}
	for raw_line in source.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("@"):
			_flush(g, cur_id, cur)
			cur_id = line.substr(1).strip_edges()
			cur = _new_node()
			continue
		if cur_id.is_empty():
			continue                      # 还没声明节点就写了台词 → 忽略，不让它污染别的节点
		if line.begins_with("=>"):
			cur["next"] = line.substr(2).strip_edges()
		elif line.begins_with("-"):
			cur["choices"].append(_parse_choice(line.substr(1).strip_edges()))
		elif line.begins_with("[") and line.ends_with("]"):
			cur["actions"].append(line.substr(1, line.length() - 2).strip_edges())
		else:
			_parse_speech(line, cur)
	_flush(g, cur_id, cur)
	if g.start_id.is_empty() and not g.nodes.is_empty():
		g.start_id = String(g.nodes.keys()[0])
	return g


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


## 取节点字典。不存在的 id 返回空字典（调用方不必到处判 null）。
func node_at(node_id: String) -> Dictionary:
	return nodes.get(node_id, {})


func size() -> int:
	return nodes.size()


# ------------------------------------------------------------------
# 解析内部

static func _new_node() -> Dictionary:
	return {"speaker": "", "text": "", "actions": [], "choices": [], "next": ""}


static func _flush(g: DialogueGraph, node_id: String, node: Dictionary) -> void:
	if node_id.is_empty():
		return
	if g.nodes.has(node_id):
		push_warning("DialogueGraph：节点 id 重复 '@%s'，后一个覆盖前一个。" % node_id)
	g.nodes[node_id] = node
	if g.start_id.is_empty():
		g.start_id = node_id


## 解析一行选项："文本 [条件] -> 目标"。
## 三段都可有缺省：没写条件 = 无条件显示；没写目标 = 选了就结束对话。
static func _parse_choice(body: String) -> Dictionary:
	var text := body
	var target := ""
	var cond := ""
	var arrow := text.find("->")
	if arrow >= 0:
		target = text.substr(arrow + 2).strip_edges()
		text = text.substr(0, arrow).strip_edges()
	var lb := text.find("[")
	var rb := text.rfind("]")
	if lb >= 0 and rb > lb:
		cond = text.substr(lb + 1, rb - lb - 1).strip_edges()
		text = (text.substr(0, lb) + text.substr(rb + 1)).strip_edges()
	return {"text": text, "condition": cond, "next": target}


## 解析一行台词。
## ⚠️ 只有当冒号出现在很靠前（≤12 字符）**且它前面没有空格**时才认作"说话人:"前缀。
##   否则台词里正常的英文冒号（比如 "他说: 你好"）会被误切成说话人，台词凭空少一截。
## ★ 一个节点里连写多行台词时**拼接成一段**（换行分隔），而不是后一行覆盖前一行 ——
##   否则编剧写了一屏、玩家只看到最后一句，而且**全程不报错**，极难发现。
static func _parse_speech(line: String, node: Dictionary) -> void:
	var speaker := String(node.get("speaker", ""))
	var text := line
	var colon := line.find(":")
	if colon > 0 and colon <= 12 and line.substr(0, colon).find(" ") < 0:
		# 说话人只认第一次出现的那一行；后续行再写"某某:"也不换人
		# （同一个节点里换说话人是排版事故，不是特性）
		if speaker.is_empty():
			speaker = line.substr(0, colon).strip_edges()
		text = line.substr(colon + 1).strip_edges()
	node["speaker"] = speaker
	var existing := String(node.get("text", ""))
	node["text"] = text if existing.is_empty() else existing + "\n" + text
