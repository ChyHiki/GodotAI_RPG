class_name Health
extends Node
## ============================================================
## 通用生命值组件（玩家与敌人共用）
## ============================================================
## 【作用】管理一个战斗单位的血量：扣血、回血、死亡广播、无敌开关。
## 【挂载方式】作为战斗单位(CharacterBody3D)的子节点，例如：
##     Player(CharacterBody3D)
##       └─ Health(本脚本)   ← max_hp 可在场景里/编辑器里设置
## 【对外广播】其他系统通过信号了解血量变化，而不直接读数值：
##     changed → HUD 血条刷新
##     died    → 播放死亡流程 / 触发重生
## 【无敌机制】invincible=true 期间 damage() 直接返回 false（伤害被吞掉），
##    翻滚的无敌帧就是靠玩家脚本在翻滚期间把 invincible 置 true 实现的。
## ============================================================

## 信号：血量变化（谁改的都能监听；两个参数：当前值/最大值，单位都是 int）
signal changed(current_hp: int, max_hp: int)
## 信号：生命归零时发出（真正的"死没死"由单位自己的状态机决定，
##       组件只负责报告"血被打空了"这个事实）
signal died

## 最大生命值（可在编辑器里改；M1 玩家与敌人都用默认 100）
@export var max_hp: int = 100

## 当前生命值（初始化为 max_hp，永不高于 max_hp、不低于 0）
var current_hp: int = 100
## 无敌开关：true 时一切伤害无效（翻滚/受击后的短暂保护期都会用到）
var invincible: bool = false


func _ready() -> void:
	# 组件进入场景树时把血回满，并广播一次初始值（让血条 UI 立刻对上）
	current_hp = max_hp
	changed.emit(current_hp, max_hp)


## 造成伤害。
## @param amount  伤害数值（正整数）
## @return true=伤害生效扣了血；false=被无敌/已死状态挡下
## 实现：先检查是否可受伤 → 扣血并钳制到 [0, max_hp] →
##       广播 changed → 若归零则广播 died。
func damage(amount: int) -> bool:
	if invincible or current_hp <= 0:
		return false
	current_hp = maxi(0, current_hp - amount)   # maxi：确保不为负
	changed.emit(current_hp, max_hp)
	if current_hp == 0:
		died.emit()
	return true


## 治疗 amount 点血（不会超过 max_hp；死亡后不可复活）
func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = mini(max_hp, current_hp + amount)  # mini：确保不超过上限
	changed.emit(current_hp, max_hp)


## 重置为满血并解除无敌（游戏重开/重生时调用）
func reset() -> void:
	current_hp = max_hp
	invincible = false
	changed.emit(current_hp, max_hp)
