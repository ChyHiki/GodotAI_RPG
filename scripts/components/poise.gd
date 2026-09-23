class_name Poise
extends Node
## ============================================================
## 通用"失衡值"组件（游戏里显示为黄色失衡条）
## ============================================================
## 【作用】管理一个战斗单位的失衡值：从 0 往上涨，涨满 = 进入"失衡"
##   （破绽极大、可被处决）；失衡持续 break_time 秒后自动恢复并清空重来。
##
## 【和 Health 的区别（理解这个就懂了整个设计）】
##   Health 是"被打就掉"的**消耗条**；失衡是"被特定的正确操作顶上去"的**积累条**。
##   本作里只有**完美格挡**会加失衡值，所以它本质上是"弹反奖励的进度条"：
##   玩家格挡得越准，越快把敌人顶到失衡 → 换来一次高伤害处决。
##
## 【挂载方式】与 Health 一样作为战斗单位的子节点：
##     EnemyBrute(CharacterBody3D)
##       ├─ Health    (scripts/components/health.gd)
##       └─ Poise     (本脚本)
##
## 【对外广播】
##     changed         → HUD 刷新黄色条 / 敌人自己也监听
##     broken_started  → 刚进入失衡（敌人切状态、HUD 弹"可处决"提示）
##     break_ended     → 失衡结束（敌人恢复正常 AI）
## ============================================================

## 信号：失衡值变化（current/max 是浮点，HUD 只要比例；broken 表示是否处于失衡）
signal changed(current: float, max_poise: float, broken: bool)
## 信号：刚涨满进入失衡
signal broken_started
## 信号：失衡结束（已恢复、失衡值重置为 keep_ratio 比例）
signal break_ended

## 失衡值上限（"条"的总量）。每次完美格挡加多少，由调用方按**百分比**给：
##   poise.percent(34.0) → 加 34% → 3 次完美格挡刚好顶满
@export var max_poise: float = 100.0

## 失衡持续时长(秒)：这段时间内单位无法行动、可以被处决。
## 注意它要明显长于玩家的处决动作时长，否则处决演到一半敌人就站起来了。
@export var break_time: float = 3.0

## 失衡结束后的残留比例(0~1)：0 = 完全清空重新攒；0.5 = 保留一半。
## 取 0 让节奏确定（"再来 3 次完美格挡"），取大会让连续处决更容易。
@export_range(0.0, 1.0) var break_keep_ratio: float = 0.0

## —— 可选的自然回落（默认关闭）——
## 【为什么默认关】需求是"每次完美格挡都增加" → 只涨不落才能形成
##   "攒够 N 次必然处决"的确定节奏，玩家能规划。
## 想让它更难（不能靠拖时间慢慢磨），把 decay_rate 调成 3~8 即可。
## 单位：最后一次增加后，先静止 decay_delay 秒，然后每秒回落 decay_rate 点。
@export var decay_delay: float = 3.0
@export var decay_rate: float = 0.0         # >0 才生效

## 当前失衡值（0 ~ max_poise）
var current_poise: float = 0.0
## 是否处于失衡状态
var broken: bool = false

## 距离"最后一次增加"过了多久（配合 decay_delay 用）
var _since_add: float = 0.0
## 失衡剩余时间(秒)
var _break_left: float = 0.0


func _ready() -> void:
	# 进场景时广播一次初始值，让 HUD 的黄条立刻对上（与 health.gd 的做法一致）
	changed.emit(current_poise, max_poise, broken)


## 每帧推进失衡计时（这是组件唯一的"主动"逻辑）。
func _process(delta: float) -> void:
	if broken:
		# 失衡中：只走恢复倒计时，不做回落
		_break_left -= delta
		if _break_left <= 0.0:
			end_break()
		return
	# 非失衡：可选的自然回落
	if decay_rate <= 0.0 or current_poise <= 0.0:
		return
	_since_add += delta
	if _since_add < decay_delay:
		return
	current_poise = maxf(0.0, current_poise - decay_rate * delta)
	changed.emit(current_poise, max_poise, broken)


## 失衡值比例 0~1（HUD 直接用这个画黄条长度）。
func ratio() -> float:
	if max_poise <= 0.0:
		return 0.0
	return clampf(current_poise / max_poise, 0.0, 1.0)


## 是否处于失衡（敌人/玩家的"可处决"判定都走这里）。
func is_broken() -> bool:
	return broken


## 增加失衡值（定点数值，单位与 max_poise 相同）。
## 涨满 → 进入失衡并广播 broken_started。
func add(amount: float) -> void:
	if broken or amount <= 0.0:
		return
	_since_add = 0.0
	current_poise = minf(max_poise, current_poise + amount)
	changed.emit(current_poise, max_poise, broken)
	if current_poise >= max_poise:
		_enter_break()


## ★ 按"上限的百分比"增加失衡值 —— 各类敌人差异化就靠这个参数。
## @param percent 百分比（如 34.0 = 加 34%）
## 【为什么用百分比而不是固定数值】不同敌人的失衡条长度/硬度不同，
##   美术与策划只需要调"这只怪挨几次完美格挡会失衡"这一个可读的概念：
##     percent = 100 / 期望次数
##   例：小怪 50（2 次） / 精英 34（3 次） / 重甲 25（4 次） / Boss 20（5 次）
func percent(percent_value: float) -> void:
	add(max_poise * percent_value * 0.01)


## 刷新失衡计时（把"还能失衡多久"重置回满）。
## 【为什么需要】处决演出比失衡时长长的话，敌人会演到一半站起来。
##   玩家在开始处决时调用一次，把目标"按住"到演出结束。
func refresh_break() -> void:
	if broken:
		_break_left = break_time


## 主动结束失衡（一般不用调，倒计时到点会自己调）。
func end_break() -> void:
	if not broken:
		return
	broken = false
	_break_left = 0.0
	_since_add = 0.0
	current_poise = max_poise * clampf(break_keep_ratio, 0.0, 1.0)
	changed.emit(current_poise, max_poise, broken)
	break_ended.emit()


## 重置为"未失衡、失衡值归零"（重生/重开时调用）。
func reset() -> void:
	broken = false
	current_poise = 0.0
	_break_left = 0.0
	_since_add = 0.0
	changed.emit(current_poise, max_poise, broken)


## 进入失衡：开倒计时并广播。
func _enter_break() -> void:
	broken = true
	_break_left = break_time
	changed.emit(current_poise, max_poise, broken)
	broken_started.emit()
