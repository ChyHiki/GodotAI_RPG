class_name Npc
extends StaticBody3D
## ============================================================
## 可对话的 NPC
## ============================================================
## 【作用】一个站在原地不动的角色：有碰撞（会挡路）、有名字牌、玩家靠近时头顶浮出
##   "E 交谈"提示，按 E 就开一段对话；对话期间把玩家的操控权收走（冻结）并转过来面对玩家。
##
## 【为什么用"距离判断"而不是 Area3D 进出检测】
##   Area3D 要配碰撞层，而"玩家该不该被检测到"取决于角色身上的 layer/mask 配置 ——
##   项目里层号是各角色自己设的，接错一层就会表现为"走到跟前也不提示"，排查很绕。
##   这里每帧算一次水平距离，NPC 数量是个位数，开销可以忽略且行为绝对可预测。
##
## 【为什么用 static 列表】多个 NPC 同时在范围内时，只能有一个响应 E。
##   谁离得近谁响应 —— 这个"评选"需要所有 NPC 互相可见，static 数组是最轻的做法。
##
## 【怎么用】代码 new 出来后设好 npc_id / display_name / dialogue_script 再 add_child；
##   或在编辑器里建一个 StaticBody3D 挂本脚本，检视面板里填这几个 @export。
## ============================================================

## 所有已进树的 NPC。用于"谁离玩家最近谁响应 E"的评选。
static var _all: Array = []

## NPC 标识。对话条件/任务目标里用它引用（如 TALK 目标的 target_id）。
@export var npc_id: String = "quartermaster"
## 显示在头顶与对话框上的名字。
@export var display_name: String = "军需官"
## 对话脚本（.dlg）。相对 res:// 的路径，用 @export_file 能在编辑器里点选。
@export_file("*.dlg") var dialogue_script: String = ""
## 交互距离（米）。玩家水平距离小于它才会出现提示。
@export var interact_range: float = 3.5
## 外观颜色（占位美术）。
@export var body_color: Color = Color(0.30, 0.45, 0.78)

var _graph: DialogueGraph = null
var _prompt: Label3D = null
## 被本 NPC 冻住的玩家（非 null 表示"这场对话是我开的，结束时要我负责解冻"）
var _frozen_player: PlayerCharacter = null
var _cached_player: PlayerCharacter = null


func _ready() -> void:
	_all.append(self)
	add_to_group("npc")
	_build_body()
	_load_graph()
	DialogueSystem.dialogue_finished.connect(_on_dialogue_finished)


func _exit_tree() -> void:
	# static 数组不会随实例回收，必须手动摘掉，否则会越积越多（而且存的是已销毁节点）
	_all.erase(self)


# ------------------------------------------------------------------
# 外观与数据
# ------------------------------------------------------------------

func _build_body() -> void:
	collision_layer = 1        # 站在地面上，玩家撞得到（会挡路）
	collision_mask = 0

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.9, 0.0)
	add_child(col)

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.85
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.9, 0.0)
	add_child(mi)

	var name_label := Label3D.new()
	name_label.text = display_name
	name_label.position = Vector3(0.0, 2.05, 0.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 64
	name_label.pixel_size = 0.005
	name_label.modulate = Color(0.85, 0.92, 1.0)
	name_label.outline_size = 12
	add_child(name_label)

	_prompt = Label3D.new()
	_prompt.text = "[E] 交谈"
	_prompt.position = Vector3(0.0, 1.62, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 52
	_prompt.pixel_size = 0.005
	_prompt.modulate = Color(1.0, 0.9, 0.45)
	_prompt.outline_size = 12
	_prompt.visible = false
	add_child(_prompt)


## 读 .dlg 并解析成对话图。
## ⚠️ .dlg 不是 Godot 资源类型，所以用 FileAccess 读文本再交给 DialogueGraph.parse，
##   不能用 load()。发行版打包时记得把这个扩展名加进导出过滤（非资源文件默认会被剥掉）。
func _load_graph() -> void:
	if dialogue_script.is_empty():
		push_warning("Npc '%s'：没有配置 dialogue_script，按 E 不会有反应。" % npc_id)
		return
	if not FileAccess.file_exists(dialogue_script):
		push_error("Npc '%s'：对话脚本不存在 %s" % [npc_id, dialogue_script])
		return
	var source := FileAccess.get_file_as_string(dialogue_script)
	_graph = DialogueGraph.parse(source)
	if _graph.size() == 0:
		push_error("Npc '%s'：对话脚本解析出 0 个节点，检查 %s 的格式。" % [npc_id, dialogue_script])


# ------------------------------------------------------------------
# 每帧：提示 + 转身 + 响应 E
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	var player := _player()
	if player == null:
		_prompt.visible = false
		return

	var in_range := _distance_to(player) <= interact_range
	var is_chosen := in_range and not DialogueSystem.is_active() and _is_closest(player)

	_prompt.visible = is_chosen
	if not in_range:
		return

	# 玩家在范围内就慢慢转过来面对他（不动位置，只转朝向）——
	# 一个会盯着你转的 NPC 比一块立牌有生气得多，代价只有一次 lerp。
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		# Godot 里 -Z 是前向，所以用 (-x, -z) 求 yaw
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)

	if is_chosen and Input.is_action_just_pressed("interact"):
		_start_dialogue()


## 判断自己是不是"当前该响应 E 的那个"：距离比所有其他在范围内的 NPC 都近。
func _is_closest(player: Node3D) -> bool:
	var my_distance := _distance_to(player)
	for other in _all:
		if other == self or not is_instance_valid(other):
			continue
		var npc := other as Npc
		if npc == null:
			continue
		var d := npc._distance_to(player)
		if d <= npc.interact_range and d < my_distance:
			return false
	return true


## 水平距离：忽略高度差，否则玩家站在石台上就够不着了。
func _distance_to(target: Node3D) -> float:
	var a := global_position
	var b := target.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------------
# 对话
# ------------------------------------------------------------------

func _start_dialogue() -> void:
	if _graph == null or _graph.size() == 0:
		return
	if not DialogueSystem.start(_graph, npc_id):
		return
	_freeze_player()


## 对话期间冻结玩家。
## ★ 复用 player.control_enabled（角色切换器当初留下的开关）：它只掐输入，
##   物理与动画照常跑 —— 玩家会自然收招、回到 Idle 站定，而不是"卡成僵尸"。
##   ⚠️ 千万别用 set_physics_process(false)：玩家在空中对话会直接悬停。
func _freeze_player() -> void:
	var player := _player()
	if player == null:
		return
	_frozen_player = player
	player.control_enabled = false
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	# 转过去面对 NPC（只看朝向，不改位置/镜头）
	var to_npc := global_position - player.global_position
	to_npc.y = 0.0
	if to_npc.length_squared() > 0.01:
		player._face_instant(to_npc.normalized())


func _unfreeze_player() -> void:
	if _frozen_player == null or not is_instance_valid(_frozen_player):
		_frozen_player = null
		return
	_frozen_player.control_enabled = true
	_frozen_player = null


## 只处理"是我开的对话"的结束事件 —— 否则场上两个 NPC 会互相解冻/重复解冻。
func _on_dialogue_finished(finished_npc_id: String) -> void:
	if finished_npc_id == npc_id:
		_unfreeze_player()


func _player() -> PlayerCharacter:
	if is_instance_valid(_cached_player):
		return _cached_player
	_cached_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	return _cached_player
