extends SceneTree
## ============================================================
## 一次性工具：生成示例任务的 .tres
## ============================================================
## 【为什么用脚本生成，而不是手写 .tres 文本】
##   手写 .tres 要自己拼 ext_resource 的 id、sub_resource 的 id、类型化数组的写法
##   （Array[QuestObjective] 到底序列化成什么样）。写错一处 Godot **不会报错**，
##   只会安静地把那个字段丢掉 —— 排查起来极其痛苦。
##   ResourceSaver 写出来的格式一定是引擎自己认得的。
##
## 【运行】（注意用的是 --script，不是跑场景）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://tools/gen_quest_definitions.gd
##
## 【已有的 .tres 会被覆盖】想改任务数值，请直接在编辑器里打开 .tres 编辑，
##   不要再跑本脚本 —— 本脚本只是"从零造一份正确的骨架"。
## ============================================================

const QUEST_DIR := "res://assets/quests"


func _initialize() -> void:
	var err := DirAccess.make_dir_recursive_absolute(QUEST_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("无法创建 %s（错误码 %d）" % [QUEST_DIR, err])
		quit(1)
		return

	_save(_build_q_guards())
	_save(_build_q_aftermath())
	quit(0)


## 示例任务：肃清红甲守卫。
## 【设计意图】两个目标刻意用**不同的目标类型**，把两条事件链路都跑通：
##   KILL    ← EventBus.enemy_died       （打了几只）
##   COLLECT ← EventBus.item_collected   （捡了多少战利品）
##   这两条在战斗里是**同一次死亡**先后发出的，顺带验证"一个事件源推进多个目标"。
func _build_q_guards() -> QuestDefinition:
	var def := QuestDefinition.new()
	def.id = "q_guards"
	def.title = "肃清红甲守卫"
	def.summary = "北边林地的红甲守卫袭扰商队已久。军需官要你清掉他们，并带回徽记作凭证。"
	def.objectives = _objectives([
		_make_objective(QuestObjective.Kind.KILL, "brute", 2, "击败红甲守卫"),
		_make_objective(QuestObjective.Kind.COLLECT, "guard_insignia", 3, "收集守卫徽记"),
	])
	def.required_quests = []
	def.reward_item_id = "gold_coin"
	def.reward_amount = 50
	return def


## 第二个示例任务：刻意做成 **q_guards 的后续**，用来演示"任务链"。
## 【链条怎么接】`required_quests` 里写上一条任务的 id —— QuestSystem 要求它已 **TURNED_IN**
##   才允许接取。注意是"已交付"而不是"目标达成"：没回 NPC 交差就还不算走完，
##   前置链等玩家真的走完流程，剧情上才说得通。
## 【编排故事时的用法】把一串任务用 required_quests 串起来，就得到了章节推进：
##   q_guards → q_aftermath → q_xxx ……
func _build_q_aftermath() -> QuestDefinition:
	var def := QuestDefinition.new()
	def.id = "q_aftermath"
	def.title = "扫荡残部"
	def.summary = "守卫的头目还带着残部缩在林地深处。军需官要你再清掉四只。"
	def.objectives = _objectives([
		_make_objective(QuestObjective.Kind.KILL, "brute", 4, "击败红甲守卫"),
	])
	def.required_quests = ["q_guards"]
	def.reward_item_id = "gold_coin"
	def.reward_amount = 120
	return def


func _make_objective(kind: QuestObjective.Kind, target_id: String, count: int, description: String) -> QuestObjective:
	var obj := QuestObjective.new()
	obj.kind = kind
	obj.target_id = target_id
	obj.required_count = count
	obj.description = description
	return obj


## Array → Array[QuestObjective] 的显式转换。
## 【为什么需要它】实测（Godot 4.7）：
##   · `def.objectives = [o1, o2]` —— **字面量可以直接赋**，编译器能推断出元素类型 ✅
##   · 但把数组先装进**无类型的 `Array` 变量**再赋值会**运行时**炸：
##     `Invalid assignment of property or key 'objectives' with value of type 'Array'`
##   本函数收的正是"已经装进无类型 Array 的那批"（比如从别处传进来的列表），所以必须显式转一次。
func _objectives(list: Array) -> Array[QuestObjective]:
	var out: Array[QuestObjective] = []
	for item in list:
		out.append(item as QuestObjective)
	return out


func _save(def: QuestDefinition) -> void:
	var path := QUEST_DIR.path_join(def.id + ".tres")
	var err := ResourceSaver.save(def, path)
	if err == OK:
		print("[gen_quest_definitions] 已写出 %s" % path)
	else:
		push_error("[gen_quest_definitions] 写出 %s 失败（错误码 %d）" % [path, err])
