class_name Health
extends Node
## 通用生命值组件。挂在战斗单位的子节点上，通过信号对外广播变化。

signal changed(current_hp: int, max_hp: int)
signal died

@export var max_hp: int = 100

var current_hp: int = 100
var invincible: bool = false


func _ready() -> void:
	current_hp = max_hp
	changed.emit(current_hp, max_hp)


## 造成伤害。若处于无敌/已死亡状态则忽略并返回 false。
func damage(amount: int) -> bool:
	if invincible or current_hp <= 0:
		return false
	current_hp = maxi(0, current_hp - amount)
	changed.emit(current_hp, max_hp)
	if current_hp == 0:
		died.emit()
	return true


func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = mini(max_hp, current_hp + amount)
	changed.emit(current_hp, max_hp)


func reset() -> void:
	current_hp = max_hp
	invincible = false
	changed.emit(current_hp, max_hp)
