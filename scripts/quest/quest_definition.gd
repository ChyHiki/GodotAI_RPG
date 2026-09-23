class_name QuestDefinition
extends Resource
## ============================================================
## 任务定义（一份 .tres）
## ============================================================
## 【这个文件是做什么的】
##   把"一条任务"的所有**静态数据**装在一起：id、标题、目标清单、前置任务、奖励。
##   它是**只读配置**，不保存任何运行时状态 —— "玩家接了没、进度到哪了"全部由
##   QuestSystem 单独维护。这样同一份 .tres 可以被任务系统、UI、存档工具同时读取
##   而互不污染；策划改数值也不用碰代码。
##
## 【怎么新建一条任务】
##   assets/quests/ 目录右键 → 新建 → 资源 → 搜 QuestDefinition → 保存成 .tres。
##   objectives 数组里每加一项 → 新建 QuestObjective。
##   ⚠️ id 必须唯一且非空：QuestSystem 拿它当字典键，重名会**静默覆盖**（只留一条）。
## ============================================================

## 任务的运行时状态。
## ★ 为什么定义在"定义"类里而不是 QuestSystem 里：GDScript **不能通过实例访问类常量**
##   （`QuestSystem.QuestState.X` 非法），而 autoload 拿到的永远是实例 ——
##   所以枚举必须挂在一个带 class_name 的脚本上，`QuestDefinition.State.ACTIVE` 才可用。
enum State {
	INACTIVE,   ## 未接取（可能在等前置任务，也可能玩家还没找到发布者）
	ACTIVE,     ## 进行中（相关事件会被 QuestSystem 计入进度）
	COMPLETED,  ## 目标全部达成，但玩家还没回去交付
	TURNED_IN,  ## 已交付、奖励已发（终态）
}

## 唯一标识，代码与对话脚本里都用它引用这条任务（如 "q_wolves"）。
@export var id: String = ""

## 任务名，显示在追踪栏首行与"新任务"提示里。
@export var title: String = ""

## 任务详情（暂未在 HUD 上展示，留给以后的任务日志面板）。
@export_multiline var summary: String = ""

## 目标清单。全部达成才算 COMPLETED。
@export var objectives: Array[QuestObjective] = []

## 前置任务：这些任务必须都处于 TURNED_IN（已交付）状态，本条才可接取。
## 【为什么要求"已交付"而不是"已达成"】目标达成还没回NPC交差的任务，
##   在剧情上等于没做完 —— 前置链应该等玩家真的走完流程。
@export var required_quests: Array[String] = []

## 奖励物品 id 与数量。
## ⚠️ 项目目前还没有背包/物品系统，这里只做**记录**并在交付时用 HUD 提示一句。
##    等物品系统落地后，只需在 QuestSystem.turn_in() 里补一处真正的发放调用。
@export var reward_item_id: String = ""
@export var reward_amount: int = 0


## 生成"新任务：XXX"这类提示用的短文本。
func display_title() -> String:
	return title if not title.is_empty() else id
