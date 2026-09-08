extends Node3D
## M1 主场景：程序化构建竞技场环境、光照；生成玩家/敌人/HUD/镜头；
## 管理敌人重生、玩家死亡遮罩与重开。

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy/enemy.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")

const PLAYER_SPAWN := Vector3(0, 1.0, 9.0)
const ENEMY_SPAWN := Vector3(0, 1.0, -9.0)
const ARENA_WALL := 23.0     # 内场半宽
const ENEMY_RESPAWN_TIME := 3.0

var _player: PlayerCharacter
var _enemy: EnemyBrute
var _hud: Hud
var _camera: ThirdPersonCamera


func _ready() -> void:
    _build_environment()
    _build_arena()

    _hud = HUD_SCENE.instantiate() as Hud
    add_child(_hud)

    _camera = CAMERA_SCENE.instantiate() as ThirdPersonCamera
    add_child(_camera)

    _spawn_player()
    _spawn_enemy()

    _camera.set_target(_player)

    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _hud.show_message("击败红甲守卫！\nWASD 移动 · 鼠标视角 · 左键攻击 · Shift 翻滚", 6.0)


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
    # 鼠标可见状态下点击窗口任意处 → 重新捕获鼠标
    if event is InputEventMouseButton and event.pressed:
        if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ 生成逻辑

func _spawn_player() -> void:
    _player = PLAYER_SCENE.instantiate() as PlayerCharacter
    add_child(_player)
    _player.global_position = PLAYER_SPAWN
    _player.health.changed.connect(_hud.set_player_hp)
    _player.player_died.connect(_on_player_died)
    _hud.set_player_hp(_player.health.current_hp, _player.health.max_hp)


func _spawn_enemy() -> void:
    if is_instance_valid(_enemy):
        _enemy.queue_free()
    _enemy = ENEMY_SCENE.instantiate() as EnemyBrute
    add_child(_enemy)
    _enemy.global_position = ENEMY_SPAWN
    _enemy.health.changed.connect(_on_enemy_hp_changed)
    _enemy.died.connect(_on_enemy_died)
    _hud.set_enemy_hp(_enemy.health.current_hp, _enemy.health.max_hp)


func _on_enemy_hp_changed(current: int, max_hp: int) -> void:
    if _hud != null:
        _hud.set_enemy_hp(current, max_hp)


func _on_enemy_died() -> void:
    if _hud != null:
        _hud.show_message("守卫被击败了！它会在 %d 秒后重生…" % ENEMY_RESPAWN_TIME, 2.0)
    var timer := get_tree().create_timer(ENEMY_RESPAWN_TIME)
    timer.timeout.connect(_spawn_enemy)


func _on_player_died() -> void:
    _hud.show_death()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ 环境与竞技场

func _build_environment() -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.42, 0.62, 0.88)
    sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.92)
    sky_mat.ground_bottom_color = Color(0.3, 0.34, 0.38)
    sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.7)
    var sky := Sky.new()
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.7
    we.environment = env
    add_child(we)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-52, -30, 0)
    sun.shadow_enabled = true
    sun.light_energy = 1.15
    sun.directional_shadow_max_distance = 90.0
    add_child(sun)

    var fill := DirectionalLight3D.new()
    fill.name = "FillLight"
    fill.rotation_degrees = Vector3(35, 140, 0)
    fill.light_energy = 0.35
    fill.light_color = Color(0.55, 0.65, 0.85)
    add_child(fill)


func _build_arena() -> void:
    # 地板（顶面 y=0）
    _add_box_body("Floor", Vector3(ARENA_WALL * 2 + 2, 0.5, ARENA_WALL * 2 + 2), Vector3(0, -0.25, 0),
        Color(0.34, 0.36, 0.4), 0.05, 0.85)
    # 场内浅色对战场地标记
    _add_box_body("CombatPlate", Vector3(26.0, 0.06, 26.0), Vector3(0, 0.02, 0),
        Color(0.46, 0.5, 0.56), 0.05, 0.8)

    var wall_h := 3.6
    var wall_t := 0.8
    var wall_len := ARENA_WALL * 2 + wall_t + 2
    var wall_col := Color(0.52, 0.42, 0.36)
    # 四面围墙
    _add_box_body("WallN", Vector3(wall_len, wall_h, wall_t), Vector3(0, wall_h / 2, -ARENA_WALL - 1), wall_col, 0.1, 0.75)
    _add_box_body("WallS", Vector3(wall_len, wall_h, wall_t), Vector3(0, wall_h / 2, ARENA_WALL + 1), wall_col, 0.1, 0.75)
    _add_box_body("WallW", Vector3(wall_t, wall_h, wall_len), Vector3(-ARENA_WALL - 1, wall_h / 2, 0), wall_col, 0.1, 0.75)
    _add_box_body("WallE", Vector3(wall_t, wall_h, wall_len), Vector3(ARENA_WALL + 1, wall_h / 2, 0), wall_col, 0.1, 0.75)

    # 四根立柱（战术遮蔽物）
    var pillar_col := Color(0.6, 0.55, 0.45)
    for px in [-8.0, 8.0]:
        for pz in [-8.0, 8.0]:
            _add_box_body("Pillar", Vector3(2.0, 6.0, 2.0), Vector3(px, 3.0, pz), pillar_col, 0.2, 0.6)


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
