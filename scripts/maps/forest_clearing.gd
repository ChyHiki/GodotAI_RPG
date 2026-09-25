extends Node3D
## ============================================================
## 小型开放森林空地（独立可玩场景）
## ============================================================
## 【定位】一张"正式关卡"的雏形：开放式森林空场，带树干/巨石掩体、
##   一两处抬升岩石做高低差，柔光天光 + 体积雾藏边。战斗系统(玩家/敌人/镜头/HUD)
##   全部复用现有场景，本脚本只换了一张地皮与氛围，并把角色编排接好。
##
## 【为什么仍是"代码生成几何"】和 main.tscn 同思路——占位阶段改参数比重摆 .tscn 快。
##   但本场景把"出生点"做成了编辑器里可拖的 Marker3D(PlayerSpawn/EnemySpawn)，
##   掩体布局也提成顶部 @export 数组(tree_positions 等)，你想手摆细化直接改这些即可；
##   要完全手摆网格，就把 _build_* 里生成的节点删掉、自己往场景里塞 MeshInstance3D 即可
##   （出生点 Marker 与下方的编排逻辑不依赖代码生成的几何）。
##
## 【怎么跑】在编辑器把本场景设为运行主场景，或直接 F5 运行本 .tscn；
##   想换回旧竞技场，把 project.godot 的 run/main_scene 改回 res://scenes/main/main.tscn。

## ---- 预加载（只加载一次）----
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## ★ 敌人场景改成 @export：默认仍是 enemy.tscn（红甲守卫），
##   具体关卡（如 wolf_test.tscn）在场景里覆盖成别的物种即可 —— 本脚本一行不改。
##   ⚠️ 现有 maps/forest_clearing.tscn 不覆盖它 ⇒ 默认就是守卫，测试线不受影响。
@export var enemy_scene: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
const SWITCHER_SCRIPT := preload("res://scripts/debug/character_switcher.gd")

## ---- 可编辑的地编参数（检视面板直接调，不必改代码）----
@export var ground_size: Vector2 = Vector2(60.0, 60.0)
## 树干(碰撞+树干网格)的摆放点；树冠是装饰无碰撞，玩家可从下方穿过
@export var tree_positions: Array[Vector3] = [
	Vector3(-10, 0, -6), Vector3(11, 0, -4), Vector3(-7, 0, 10),
	Vector3(8, 0, 9), Vector3(-16, 0, 2), Vector3(15, 0, 3),
	Vector3(0, 0, -16), Vector3(-13, 0, -13), Vector3(13, 0, -14),
]
## 巨石(圆石，带球碰撞近似)摆放点
@export var boulder_positions: Array[Vector3] = [
	Vector3(-4, 0, 4), Vector3(5, 0, -2), Vector3(-2, 0, -10), Vector3(9, 0, 6),
]
## 抬升岩石平台(做高低差/卡视角)摆放点；顶面约 0.7m，可作为小掩体或据高点
@export var platform_positions: Array[Vector3] = [
	Vector3(0, 0, 0),
]
@export var enemy_respawn_time: float = 3.0

## ---- 任务系统 / 对话（2026-09-22 新增）----
## NPC 出生点。场景里有名为 "NpcSpawn" 的 Marker3D 时以 Marker 为准，否则用这个默认值。
@export var npc_position: Vector3 = Vector3(6.0, 0.0, 4.0)
## 军需官的对话脚本（.dlg）。
@export_file("*.dlg") var npc_dialogue: String = "res://assets/dialogue/quartermaster.dlg"

## 场上引用（重生/重连信号都要用）
var _player: PlayerCharacter
var _enemy: EnemyBrute
var _hud: Hud
var _camera: ThirdPersonCamera
## 电影化分镜导演：处决时接管相机做特写运镜 + 遮幅黑边（见 scripts/camera/cinematic_director.gd）
var _director: CinematicDirector
var _switcher: CharacterSwitcher = null
var _player_dead: bool = false
## 场边的可对话 NPC
var _npc: Npc = null


func _ready() -> void:
	# 1) 先有世界（森林环境 + 地形 + 掩体），角色才有地方站
	_build_environment()
	_build_terrain()
	_build_cover()
	# 2) UI 与镜头（镜头此时还没有目标，稍后由切换器 set_target）
	_hud = HUD_SCENE.instantiate() as Hud
	add_child(_hud)
	_camera = CAMERA_SCENE.instantiate() as ThirdPersonCamera
	add_child(_camera)
	# 2.5) 电影化分镜导演：自包含，紧跟相机之后加入即可（处决时接管相机做特写分镜）
	_director = CinematicDirector.new()
	_director.name = "CinematicDirector"
	add_child(_director)
	# 3) 角色（出生点从场景里的 Marker3D 读，方便在编辑器拖）
	_spawn_player()
	_spawn_enemy()
	# 3.5) 任务与对话的"看得见的那部分" + 场边的军需官
	#      （任务状态与对话进度住在 autoload 里，本场景重载也不会丢）
	_setup_quest_layer()
	# 4) 【调试】角色切换器：负责把镜头对准"当前受控角色"并接好 HUD 两条血条
	_switcher = SWITCHER_SCRIPT.new()
	_switcher.name = "CharacterSwitcher"
	add_child(_switcher)
	_switcher.setup(_hud, _camera)
	_switcher.controlled_changed.connect(_on_controlled_changed)
	# 5) 捕获鼠标 + 操作提示
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.show_message("森林空地 · 击败红甲守卫！\nWASD 移动 · 鼠标视角 · 左键攻击 · Shift 闪避 · 右键格挡\n格挡瞬间挡下 = 完美格挡 → 攒满黄色失衡条 → 走近按左键【处决】\n【调试】Tab / F = 切换操控 玩家 ⇄ 守卫", 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not _player_dead and event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not _player_dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------
# 生成与事件接线（与 main.tscn 同套编排）
# ------------------------------------------------------------------

func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	add_child(_player)
	_player.global_position = _spawn_point("PlayerSpawn", Vector3(0, 1.0, 9.0))
	_player.player_died.connect(_on_player_died)
	_player.perfect_parry.connect(_hud.flash_parry)
	_player.perfect_dodge.connect(_hud.flash_dodge)


func _spawn_enemy() -> void:
	if is_instance_valid(_enemy):
		_enemy.queue_free()
	if enemy_scene == null:
		return
	_enemy = enemy_scene.instantiate() as EnemyBrute
	add_child(_enemy)
	_enemy.global_position = _spawn_point("EnemySpawn", Vector3(0, 1.0, -9.0))
	_enemy.died.connect(_on_enemy_died)
	if _switcher != null:
		_switcher.refresh_cast()


func _spawn_point(marker_name: String, fallback: Vector3) -> Vector3:
	var m := get_node_or_null(marker_name)
	if m != null and is_instance_valid(m):
		return (m as Node3D).global_position
	return fallback


func _on_controlled_changed(actor: Node3D) -> void:
	if _hud == null or actor == null:
		return
	if actor.is_in_group("player"):
		_hud.show_message("现在操控：玩家骑士（左键挥剑 / 右键格挡）", 2.0)
	else:
		_hud.show_message("现在操控：红甲守卫（左键挥棒，含 0.5s 蓄力）", 2.0)


func _on_enemy_died() -> void:
	if _hud != null:
		_hud.show_message("守卫被击败了！它会在 %d 秒后重生…" % enemy_respawn_time, 2.0)
	var timer := get_tree().create_timer(enemy_respawn_time)
	timer.timeout.connect(_spawn_enemy)


func _on_player_died() -> void:
	_player_dead = true
	_hud.show_death()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------
# 任务与对话层（2026-09-22 新增）
# ------------------------------------------------------------------

## 摆出"看得见"的三样东西：任务追踪栏、对话框、军需官。
## 【为什么前两个要挂到 HUD 上】它们是屏幕 UI，跟着 CanvasLayer 才能盖住 3D 世界。
## 【为什么逻辑不在这里】任务状态与对话进度都住在 autoload 里 —— 本场景被重载（按 R）时
##   UI 会跟着重建，但"玩家已经接过哪些任务"必须留着，这正是分层的意义。
func _setup_quest_layer() -> void:
	var tracker := QuestTracker.new()
	_hud.add_child(tracker)
	tracker.position = Vector2(20.0, 56.0)      # 玩家血条(位置 20,20、高 20)正下方

	var box := DialogueBox.new()
	_hud.add_child(box)                          # 全屏铺满，自己按底部锚点排版

	# 默认军需官。★ 场景里**已经摆了 NPC 就不再生成** —— 否则"编辑器里摆了一个 + 代码又生一个"
	# 会变成两个同名角色。这条判断是"用编辑器编排故事"的前提：
	# 想加角色，就往 maps/forest_clearing.tscn 里拖一个 StaticBody3D、挂上 scripts/npc/npc.gd、
	# 填好三个 @export（npc_id / display_name / dialogue_script），代码一行都不用动。
	if get_tree().get_nodes_in_group("npc").is_empty():
		_npc = Npc.new()
		_npc.npc_id = "quartermaster"
		_npc.display_name = "军需官"
		_npc.dialogue_script = npc_dialogue
		add_child(_npc)
		_npc.global_position = _spawn_point("NpcSpawn", npc_position)


# ------------------------------------------------------------------
# 森林环境 / 地形 / 掩体
# ------------------------------------------------------------------

## 森林版环境：更亮的天空 + 绿调地平线 + 体积雾藏边 + 柔和一些的太阳。
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.66, 0.92)        # 头顶偏蓝
	sky_mat.sky_horizon_color = Color(0.82, 0.9, 0.84)     # 地平线发白发绿
	sky_mat.ground_bottom_color = Color(0.25, 0.32, 0.24)  # 脚下林地色
	sky_mat.ground_horizon_color = Color(0.4, 0.5, 0.38)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9                        # 林间环境光略强，防死黑
	# 体积雾：把 60m 场地的边缘融进雾里，制造"空地外还是林子"的纵深感
	env.fog_enabled = true
	# Godot 4.7 的 FogMode 只有 EXPONENTIAL(0) 与 DEPTH(1) 两种；
	# 指数雾 + fog_density 即可把 60m 场地边缘融进雾里（默认就是 EXPONENTIAL，这里显式写出更清晰）
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.014
	env.fog_light_color = Color(0.82, 0.9, 0.84)
	we.environment = env
	add_child(we)

	# 太阳：角度更高、能量更柔（林间斑驳光，不是正午暴晒）
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	# 补光：弱冷光从对侧补亮暗部
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(28, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.6, 0.7, 0.85)
	add_child(fill)


## 草地大地板 + 中央浅色"林间空地"标记（装饰）。
func _build_terrain() -> void:
	_add_box_body("Ground", Vector3(ground_size.x, 1.0, ground_size.y), Vector3(0, -0.5, 0),
		Color(0.3, 0.42, 0.26), 0.0, 1.0)   # 草地绿
	_add_box_body("Clearing", Vector3(24.0, 0.08, 24.0), Vector3(0, 0.02, 0),
		Color(0.42, 0.5, 0.34), 0.0, 1.0)


## 把所有掩体摆出来（位置来自顶部 @export 数组）。
func _build_cover() -> void:
	for p in tree_positions:
		_add_tree(p)
	for p in boulder_positions:
		_add_boulder(p)
	for p in platform_positions:
		_add_platform(p)


## 一棵树：树干(圆柱碰撞+网格) + 树冠(锥台，装饰无碰撞，玩家可从下方穿过)。
func _add_tree(pos: Vector3) -> void:
	var trunk_h := 4.0
	var trunk_r := 0.35
	var body := StaticBody3D.new()
	body.name = "Tree"
	body.position = pos + Vector3(0, trunk_h * 0.5, 0)
	# 碰撞（只包树干，树冠不挡路）
	var col := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = trunk_r
	cshape.height = trunk_h
	col.shape = cshape
	body.add_child(col)
	# 树干外观
	var trunk := MeshInstance3D.new()
	var tmesh := CylinderMesh.new()
	tmesh.top_radius = trunk_r * 0.8
	tmesh.bottom_radius = trunk_r
	tmesh.height = trunk_h
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.36, 0.26, 0.16)
	tmat.roughness = 1.0
	tmesh.surface_set_material(0, tmat)
	trunk.mesh = tmesh
	body.add_child(trunk)
	# 树冠（锥台近似，无碰撞）
	var canopy := MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 0.3
	cmesh.bottom_radius = 2.6
	cmesh.height = 4.0
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.22, 0.45, 0.2)
	cmat.roughness = 1.0
	cmesh.surface_set_material(0, cmat)
	canopy.mesh = cmesh
	canopy.position = Vector3(0, trunk_h * 0.5 + 2.0, 0)
	body.add_child(canopy)
	add_child(body)


## 一块圆石：球网格 + 球碰撞近似（当作掩体）。
func _add_boulder(pos: Vector3, radius := 1.2) -> void:
	var body := StaticBody3D.new()
	body.name = "Boulder"
	body.position = pos + Vector3(0, radius * 0.6, 0)
	var col := CollisionShape3D.new()
	var cshape := SphereShape3D.new()
	cshape.radius = radius * 0.7
	col.shape = cshape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.52)
	mat.roughness = 0.95
	m.surface_set_material(0, mat)
	mi.mesh = m
	body.add_child(mi)
	add_child(body)


## 抬升岩石平台：薄箱体，顶面约 0.7m，做高低差/卡视角（玩家可借跳跃上不去就当掩体）。
func _add_platform(pos: Vector3, size: Vector3 = Vector3(5.0, 0.7, 5.0)) -> void:
	_add_box_body("Platform", size, pos + Vector3(0, size.y * 0.5, 0),
		Color(0.45, 0.42, 0.38), 0.0, 1.0)


## 通用工具：创建一个"静态立方体"（StaticBody3D + 碰撞盒 + 外观网格），与 main.tscn 同款。
func _add_box_body(node_name: String, size: Vector3, pos: Vector3, color: Color, metallic: float, roughness: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)
