extends Node
## ============================================================
## 引擎内实拍狼的 6 段表现（给"要不要加大步幅 / 招式读不读得懂"提供真实证据）。
## ============================================================
## 为什么必须有它：Blender 侧 previews 只是离线渲染，**必须在 Godot 里真跑一遍**
##   才能看到"缩放 0.885 后 + 追敌镜头下"的真实观感（步态、招式预警、死亡塌倒）。
##
## 用法（★ 不要 --headless：headless 用空渲染驱动，出不来图；★ 输出目录必须先建好）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     --fixed-fps 30 --resolution 960x540 \
##     --write-movie D:\GodotProject\first-game\.tmp_wolf\frame.png \
##     res://tools/anim_capture/wolf_capture.tscn
##
## 输出：`.tmp_wolf/frame%08d.png`（每渲染一帧一张，序号 = Engine.get_frames_drawn() − 1）
##   本脚本在每个片段开始处打印 `CAPTURE_SEG <名字> frame=<frames_drawn>`，
##   据此把序列切成两段 GIF：1/2/3 → walk；4/5/6 → combat。
##
## 【相机】不用玩家视角 —— 那看不清步态。这里自带一台**固定机位 + 每帧跟住狼**的相机：
##   步态段用**正侧视**（看四足迈步），招式段用**斜前 45°**（看下蹲蓄力→前扑咬合）。
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const SPEED_TROT_MED := 2.5      # 中速 trot（m/s）
const SPEED_TROT_FULL := 3.4     # 全速 trot（= wolf.tscn 的 move_speed；β 后由 4.2 改为 3.4）

var _wolf: Node3D = null
var _cam: Camera3D = null
var _cam_offset: Vector3 = Vector3(0, 0.85, 3.4)      # 近景：狼约占画面高 ~40%，腿看得清
var _cam_look_at: Vector3 = Vector3(0, 0.50, 0)


func _ready() -> void:
	_build_world()
	var wolf_scene := load(WOLF_TSCN) as PackedScene
	if wolf_scene == null:
		print("CAPTURE: 找不到 %s" % WOLF_TSCN)
		get_tree().quit(1)
		return
	_wolf = wolf_scene.instantiate() as Node3D
	_wolf.position = Vector3(0, 0.05, 0)      # ★ 先定位，再入树（避免原点去穿透）
	add_child(_wolf)
	# ★ 关掉 AI、强制 CHASE → 由本脚本用 manual_wish_dir 精确控制速度（见 enemy.gd 的手动操控说明）
	_wolf.set("ai_enabled", false)
	_wolf.set("state", 1)                     # 1 = CHASE（这样 _animate_model 才会播 Walk）
	_wolf.call("_face_instant_dir", Vector3(1, 0, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	print("CAPTURE: 狼动画 = Idle:%s Walk:%s Windup:%s Attack:%s Hit:%s Death:%s" % [
		_wolf.get("_idle_anim"), _wolf.get("_walk_anim"), _wolf.get("_windup_anim"),
		_wolf.get("_attack_anim"), _wolf.get("_hit_anim"), _wolf.get("_death_anim")])

	await _wait(0.4)                          # 让场景稳定几帧

	# ---------- 1) Idle（2s，正侧视看站姿呼吸）----------
	_set_cam(Vector3(0, 0.85, 3.4), Vector3(0, 0.50, 0))
	_stop()
	_seg("idle")
	await _wait(2.0)

	# ---------- 2) trot 中速（2.5 m/s，正侧视看四足步态）----------
	_seg("trot_med_2.5")
	_drive(SPEED_TROT_MED)
	await _wait(3.0)

	# ---------- 3) ★ trot 全速（4.2 m/s，正侧视、镜头跟住）—— 判断"要不要加大步幅"的核心证据 ----------
	_seg("trot_full_4.2")
	_drive(SPEED_TROT_FULL)
	await _wait(3.0)
	_stop()
	await _wait(0.5)

	# ---------- 4) AttackWindup → Attack（斜前 45°，看"下蹲蓄力 → 前扑咬合"）----------
	_set_cam(Vector3(3.0, 1.2, 3.0), Vector3(0, 0.48, 0))
	_seg("attack")
	_wolf.call("request_attack", Vector3(1, 0, 0))
	await _wait(2.4)

	# ---------- 5) Hit（受击硬直：看被打退）----------
	_seg("hit")
	_wolf.call("take_damage", 12, _wolf.global_position + Vector3(-1, 0, 0))
	await _wait(1.0)

	# ---------- 6) Death + 尸体停留（看侧躺是否自然、~1.29s 后消失）----------
	_seg("death")
	_wolf.call("take_damage", 999, _wolf.global_position + Vector3(-1, 0, 0))
	await _wait(3.2)

	print("CAPTURE: 结束 frames_drawn=%d" % Engine.get_frames_drawn())
	get_tree().quit(0)


# ------------------------------------------------------------------ 场景搭建

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.34, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.70)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -132, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# 地面：足够大（狼全速会跑出 ~13m），并给个中性色方便看"脚有没有打滑"
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(300, 1, 300)
	gcol.shape = gshape
	gcol.position = Vector3(0, -0.5, 0)
	ground.add_child(gcol)
	var gmesh := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(300, 1, 300)
	gmesh.mesh = gbox
	gmesh.position = Vector3(0, -0.5, 0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.36, 0.31)
	gmat.roughness = 1.0
	gmesh.material_override = gmat
	ground.add_child(gmesh)
	add_child(ground)

	_cam = Camera3D.new()
	_cam.name = "CaptureCam"
	_cam.fov = 42.0
	_cam.near = 0.05
	_cam.far = 400.0
	_cam.current = true
	add_child(_cam)


func _process(_delta: float) -> void:
	if _wolf == null or _cam == null or not is_instance_valid(_wolf):
		return
	var p: Vector3 = _wolf.global_position
	_cam.global_position = p + _cam_offset
	_cam.look_at(p + _cam_look_at, Vector3.UP)


# ------------------------------------------------------------------ 驱动

func _set_cam(offset: Vector3, look: Vector3) -> void:
	_cam_offset = offset
	_cam_look_at = look


func _drive(speed: float) -> void:
	_wolf.set("move_speed", speed)
	_wolf.set("manual_wish_dir", Vector3(1, 0, 0))


func _stop() -> void:
	_wolf.set("manual_wish_dir", Vector3.ZERO)


func _seg(name: String) -> void:
	# PNG 序号 = frames_drawn − 1（见项目 README 抓帧坑①），这里如实打印 frames_drawn
	print("CAPTURE_SEG %s frame=%d" % [name, Engine.get_frames_drawn()])


## 按**真实（固定步长）时间**等待 —— --fixed-fps 下 timer 走的是固定 dt，切段因此可复现。
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
