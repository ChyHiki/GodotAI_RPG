class_name QuestObjective
extends Resource
## ============================================================
## 任务目标（一条任务里的一个"待办项"）
## ============================================================
## 【为什么做成 Resource 而不是 Dictionary】
##   1. 能在编辑器检视面板里直接新建/编辑，`@export` 的类型会即时校验；
##      Dictionary 拼错一个键名要等运行到那一行才炸，而且报的是"键不存在"这种含糊错误。
##   2. 能被 .tres 引用与复用（同一个"杀 3 只狼"目标可以给两条任务共用）。
##
## 【怎么用】在 QuestDefinition 的 objectives 数组里加元素 → 新建 QuestObjective。
## ============================================================

## 目标类型。QuestSystem 靠它决定"监听哪一类事件、跟哪个字段比对"。
enum Kind {
	KILL,     ## 击杀：监听 enemy_died，匹配 target_id
	COLLECT,  ## 收集：监听 item_collected，累计 amount
	REACH,    ## 抵达：监听 area_entered
	TALK,     ## 对话：监听 npc_interacted
}

@export var kind: Kind = Kind.KILL

## 匹配用的目标标识，含义随 kind 变化：
##   KILL    → 敌人类型 id（"brute"）
##   COLLECT → 物品 id（"wolf_fang"）
##   REACH   → 区域 id（"north_forest"）
##   TALK    → NPC id（"quartermaster"）
@export var target_id: String = ""

## 需要多少个才算完成（杀 3 只、收集 5 个…）。
## ★ 下限锁 1：如果是 0，任务一接取就会立刻判定"已完成"，这是几乎必然的配置事故。
@export_range(1, 999) var required_count: int = 1

## 给玩家看的一行描述。留空时 QuestSystem 会用 kind + target_id 拼一个兜底文案，
## 所以填不填都不会显示成空白。
@export var description: String = ""
