extends Node3D
## ============================================================
## 主场景（Main）—— 一场可玩的"对决"编排者
## ============================================================
## 【作用】
##   1. 程序化搭建整个世界：天空/光照环境、地板围墙立柱（竞技场）；
##   2. 实例化 HUD、镜头、玩家、敌人，并把它们的信号接好；
##   3. 处理游戏级事件：敌人被击败→计时重生；玩家死亡→死亡遮罩；R/Esc；
##   4. 挂上【调试用】角色切换器（Tab/F）：让玩家可以直接操控敌人，
##      用来验证敌人的出手节奏与判定范围（详见 character_switcher.gd）。
##
## 【为什么用代码搭场景而不是手摆】
##   M1 全部是原语占位美术，代码生成便于统一调整尺寸/颜色，
##   也能减少 .tscn 手写错误的可能。后续换正式关卡再用编辑器摆放。
## ============================================================

## ---- 预加载场景（只加载一次，避免每帧重复读盘）----
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy/enemy.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
## 【调试】角色切换器（纯脚本节点，不用做场景）
const SWITCHER_SCRIPT := preload("res://scripts/debug/character_switcher.gd")

## 玩家出生点（y=1 让其轻微下落落地；z=+9 面向敌人所在 -Z 方向）
const PLAYER_SPAWN := Vector3(0, 1.0, 9.0)
## 敌人出生点（约 18m 外，先于仇恨距离之外，等玩家靠近才会激活）
const ENEMY_SPAWN := Vector3(0, 1.0, -9.0)
## 竞技场内场半宽（米）：围墙围成的正方形从 -23 到 +23
const ARENA_WALL := 23.0
## 敌人被击败到重生的间隔（秒）
const ENEMY_RESPAWN_TIME := 3.0

## 当前场上的引用（重生/重连信号都要用它）
var _player: PlayerCharacter
var _enemy: EnemyBrute
var _hud: Hud
var _camera: ThirdPersonCamera
## 电影化分镜导演：处决时接管相机做特写运镜 + 遮幅黑边（见 scripts/camera/cinematic_director.gd）
var _director: CinematicDirector
## 【调试】角色切换器：决定"现在这双手在操控谁"
var _switcher: CharacterSwitcher = null
## 玩家是否死亡：死亡遮罩期间不强行捕获鼠标（否则玩家看不到"按R重来"提示）
var _player_dead: bool = false


## 场景启动入口：按依赖顺序搭好一切，最后捕获鼠标并显示操作提示。
func _ready() -> void:
	# 1) 先有世界（环境与地面），角色才有地方站
	_build_environment()
	_build_arena()
	# 2) UI 与镜头（镜头此时还没有目标，稍后 set_target）
	_hud = HUD_SCENE.instantiate() as Hud
	add_child(_hud)
	_camera = CAMERA_SCENE.instantiate() as ThirdPersonCamera
	add_child(_camera)
	# 2.5) 电影化分镜导演：自包含（自己找相机、自建遮幅），紧跟相机之后加入即可。
	#      玩家脚本通过 "cinematic" 组找它 → 处决时把相机交给它。
	_director = CinematicDirector.new()
	_director.name = "CinematicDirector"
	add_child(_director)
	# 3) 角色
	_spawn_player()
	_spawn_enemy()
	# 4) 【调试】角色切换器：它负责把镜头对准"当前受控角色"（启动时就是玩家），
	#    并按"谁被操控"重新接 HUD 的两条血条。
	_switcher = SWITCHER_SCRIPT.new()
	_switcher.name = "CharacterSwitcher"
	add_child(_switcher)
	_switcher.setup(_hud, _camera)
	_switcher.controlled_changed.connect(_on_controlled_changed)
	# 5) 捕获鼠标（第一人称视角操作），并弹出操作提示
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.show_message("击败红甲守卫！\nWASD 移动 · 鼠标视角 · 左键攻击 · Shift 翻滚 · 右键格挡\n格挡瞬间(0.22s 内)挡下 = 完美格挡 → 攒满黄色失衡条 → 走近按左键【处决】\n【调试】Tab / F = 切换操控 玩家 ⇄ 守卫（拿守卫的手感去撞判定）\n（若视角转不动，先点一下游戏窗口）", 8.0)


## 处理"全局性"输入：R 重开 / Esc 释放鼠标 / 点击重新捕获。
func _unhandled_input(event: InputEvent) -> void:
	# R：无论死活都重载整个场景（最彻底的"重开"）
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return
	# Esc：切换 捕获鼠标 ⇄ 释放鼠标（释放后方便点别的窗口）
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# 鼠标可见状态下点击窗口任意处 → 重新捕获鼠标（继续游戏）。
	# 死亡遮罩期间不抢鼠标（免得遮住"按R重来"提示）。
	if not _player_dead and event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 窗口重新获得焦点时自动恢复鼠标捕获。
## 修复场景：游戏刚启动时窗口没拿到焦点，鼠标一直未被捕获 → 无法转视角。
## 只要玩家还活着，切回游戏窗口就会自动重新捕获。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not _player_dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------
# 生成与事件接线
# ------------------------------------------------------------------

## 生成玩家：实例化 → 定位 → 把"死亡"接到死亡处理、完美格挡/闪避接到全屏光效。
## ⚠ 血量 → HUD 血条的接线**不在这里**：那条线归角色切换器管
##   （"下方绿条 = 当前受控角色"，换人时要跟着换，见 character_switcher.gd）。
func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	add_child(_player)
	_player.global_position = PLAYER_SPAWN
	_player.player_died.connect(_on_player_died)
	# 完美格挡 → 让 HUD 闪一下全屏金光（技能特效的一部分：屏幕层面的反馈）
	_player.perfect_parry.connect(_hud.flash_parry)
	# 完美闪避 → 全屏青光（青色与格挡的金色一眼区分：躲开了 / 顶回去了）
	_player.perfect_dodge.connect(_hud.flash_dodge)


## 生成敌人：先清掉旧实例（如果还活着），再生成新的并接上"死亡→重生"的线。
## ⚠ 血条/失衡条的接线同样归角色切换器管（谁是"对手"由操控权决定）。
## 【为什么重生后要 refresh_cast】新敌人是个全新实例，切换器名单里还留着旧的
##   （且旧实例即将被销毁）；重收一遍名单，新怪才能进"可操控列表"。
func _spawn_enemy() -> void:
	if is_instance_valid(_enemy):       # 旧敌人可能仍在场上(死亡动画未播完)
		_enemy.queue_free()
	_enemy = ENEMY_SCENE.instantiate() as EnemyBrute
	add_child(_enemy)
	_enemy.global_position = ENEMY_SPAWN
	_enemy.died.connect(_on_enemy_died)
	if _switcher != null:
		_switcher.refresh_cast()


## 【调试】操控权换人 → 顶部提示一句，免得切完忘了自己现在是谁。
func _on_controlled_changed(actor: Node3D) -> void:
	if _hud == null or actor == null:
		return
	if actor.is_in_group("player"):
		_hud.show_message("现在操控：玩家骑士（左键挥剑 / 右键格挡）", 2.0)
	else:
		_hud.show_message("现在操控：红甲守卫（左键挥棒，含 0.5s 蓄力）", 2.0)


## 敌人死亡 → 提示玩家 + 用场景树计时器延时重生（延时到点自动再调 _spawn_enemy）。
func _on_enemy_died() -> void:
	if _hud != null:
		_hud.show_message("守卫被击败了！它会在 %d 秒后重生…" % ENEMY_RESPAWN_TIME, 2.0)
	# create_timer：创建后自动销毁的计时器，timeout 信号触发时执行 _spawn_enemy
	var timer := get_tree().create_timer(ENEMY_RESPAWN_TIME)
	timer.timeout.connect(_spawn_enemy)


## 玩家死亡 → 记录状态、显示死亡遮罩、释放鼠标（方便看到"按 R 重来"提示）。
func _on_player_died() -> void:
	_player_dead = true
	_hud.show_death()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------
# 环境（天空 + 光照）与竞技场（地板/围墙/立柱）
# ------------------------------------------------------------------

## 创建天空背景、环境光、主太阳光与补光。
## 实现：代码 new 出 WorldEnvironment + Environment + ProceduralSkyMaterial，
##       Environment 决定背景与全局环境光；DirectionalLight3D 是平行光(太阳)。
func _build_environment() -> void:
	# --- 天空与全局环境 ---
	var we := WorldEnvironment.new()     # 世界环境节点：告诉引擎"用哪个环境参数"
	var env := Environment.new()         # 环境参数本体
	env.background_mode = Environment.BG_SKY  # 背景=天空(而不是纯色)
	# 程序化天空材质：可调天空上下/地平线颜色
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.62, 0.88)       # 头顶偏蓝
	sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.92)   # 地平线发白
	sky_mat.ground_bottom_color = Color(0.3, 0.34, 0.38)  # 脚下地面方向颜色
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.7)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY  # 环境光取自天空
	env.ambient_light_energy = 0.7                             # 环境光强度(防死黑)
	we.environment = env
	add_child(we)

	# --- 主光（太阳，带阴影）---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -30, 0)  # 从斜上方照下来
	sun.shadow_enabled = true                    # 开阴影让角色有体积感
	sun.light_energy = 1.15
	sun.directional_shadow_max_distance = 90.0   # 阴影可见距离
	add_child(sun)

	# --- 补光（弱冷光从对侧补亮暗部）---
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(35, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.55, 0.65, 0.85)   # 偏冷的补光
	add_child(fill)


## 搭建竞技场几何：一块大地板 + 中央浅色地台 + 四面墙 + 四根立柱。
## 实现：所有东西都用 _add_box_body() 生成"带碰撞和外观的立方体"。
func _build_arena() -> void:
	# 地板：比围墙略大一圈，顶面正好 y=0（角色站的地面）
	_add_box_body("Floor", Vector3(ARENA_WALL * 2 + 2, 0.5, ARENA_WALL * 2 + 2), Vector3(0, -0.25, 0),
		Color(0.34, 0.36, 0.4), 0.05, 0.85)
	# 场内浅色"对战场地"标记（装饰，也带一点碰撞）
	_add_box_body("CombatPlate", Vector3(26.0, 0.06, 26.0), Vector3(0, 0.02, 0),
		Color(0.46, 0.5, 0.56), 0.05, 0.8)

	# 四面围墙（高 3.6m，厚 0.8m，围成一个正方形把战斗框在里面）
	var wall_h := 3.6
	var wall_t := 0.8
	var wall_len := ARENA_WALL * 2 + wall_t + 2   # 墙长略大于内场边长以便四角相接
	var wall_col := Color(0.52, 0.42, 0.36)       # 土红色围墙
	_add_box_body("WallN", Vector3(wall_len, wall_h, wall_t), Vector3(0, wall_h / 2, -ARENA_WALL - 1), wall_col, 0.1, 0.75)
	_add_box_body("WallS", Vector3(wall_len, wall_h, wall_t), Vector3(0, wall_h / 2, ARENA_WALL + 1), wall_col, 0.1, 0.75)
	_add_box_body("WallW", Vector3(wall_t, wall_h, wall_len), Vector3(-ARENA_WALL - 1, wall_h / 2, 0), wall_col, 0.1, 0.75)
	_add_box_body("WallE", Vector3(wall_t, wall_h, wall_len), Vector3(ARENA_WALL + 1, wall_h / 2, 0), wall_col, 0.1, 0.75)

	# 四根立柱（放在 ±8、±8 处，作为绕柱/卡视角的战术遮挡物）
	var pillar_col := Color(0.6, 0.55, 0.45)
	for px in [-8.0, 8.0]:
		for pz in [-8.0, 8.0]:
			_add_box_body("Pillar", Vector3(2.0, 6.0, 2.0), Vector3(px, 3.0, pz), pillar_col, 0.2, 0.6)


## 通用工具：创建一个"静态立方体"（静态刚体 StaticBody3D + 碰撞盒 + 外观网格）。
## @param size  立方体尺寸；pos 中心位置；color 颜色；metallic/roughness 金属度与粗糙度
## 实现要点：StaticBody3D 负责物理碰撞；MeshInstance3D(BoxMesh) 负责显示。
## 两者位置都随 body 移动，因此天然对齐。
func _add_box_body(node_name: String, size: Vector3, pos: Vector3, color: Color, metallic: float, roughness: float) -> void:
	var body := StaticBody3D.new()        # 静态刚体：墙/地，不会移动
	body.name = node_name
	body.position = pos
	# 碰撞形状
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	# 外观
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
