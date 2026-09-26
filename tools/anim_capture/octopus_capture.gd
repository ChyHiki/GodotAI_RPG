extends Node
## ============================================================
## 引擎内实拍章鱼的 4 段表现（给"Walk 自然速 vs 全速观感 / 招式读不读得懂 / 死亡塌倒"提供真实证据）。
## ============================================================
## 为什么必须有它：Blender 侧 previews 只是离线渲染，**必须在 Godot 里真跑一遍**
##   才能看到"缩放到 0.90 后 + 跟住镜头下"的真实观感（步态、慢速拖行、多腕前抽、塌成一摊）。
##
## 用法（★ 不要 --headless：headless 用空渲染驱动，出不来图；★ 输出目录必须先建好）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     --fixed-fps 30 --resolution 960x540 \
##     --write-movie D:\GodotProject\first-game\.tmp_octopus\frame.png \
##     res://tools/anim_capture/octopus_capture.tscn
##
## 输出：`.tmp_octopus/frame%08d.png`（每渲染一帧一张，序号 = Engine.get_frames_drawn() − 1）
##   本脚本在每个片段开头打印 `CAPTURE_SEG <名字> frame=<frames_drawn>`，
##   并在该刻 + 稳定后各打印一条**真实播放状态** `CAPTURE_STATE <名字>[start|settle]
##   anim=… playing=… speed_scale=…` —— 这就是"这一刻播的到底是哪段、倍速多少"的当场证据。
##
## 【★ 为什么特意拍 Walk@全速 2.2】章鱼只有 Walk（无 Run），CHASE 里 Walk 会按
##   want = speed / walk_natural_speed(1.68) 重定时：
##     · Walk@自然速 1.68  ⇒ want = 1.000（1× 原速，看"自然步态"）
##     · Walk@全速   2.2   ⇒ want = 1.310（实播倍速，交战时的真实观感）
##   2.2 这一段是**肉眼判断 DESIGN §3.5 那处"arm1/arm4 支撑相起始前冲回弹"是否可见**的唯一证据 ——
##   用户据此裁决"保均匀、接受回弹"的取舍。
##
## 【相机】不用玩家视角——那样看不清步态。自带**固定机位 + 每帧跟住章鱼**的相机：
##   步态段用**正侧视**（看八腕前后拖行 / 前冲回弹），招式段用**斜前 45°**（看前腕回收→八腕前抽）。
## ============================================================

const OCTOPUS_TSCN := "res://scenes/enemy/octopus.tscn"
const SPEED_WALK_NATURAL := 1.68   # = walk_natural_speed ⇒ want = 1.000（1× 原速）
const SPEED_WALK_FULL := 2.2       # = move_speed ⇒ want = 1.310（交战实播倍速）

var _oct: Node3D = null
var _cam: Camera3D = null
var _cam_offset: Vector3 = Vector3(0, 0.85, 3.6)     # 正侧视近景（章鱼矮而宽）
var _cam_look_at: Vector3 = Vector3(0, 0.35, 0)


func _ready() -> void:
	_build_world()
	var scene := load(OCTOPUS_TSCN) as PackedScene
	if scene == null:
		print("CAPTURE: 找不到 %s" % OCTOPUS_TSCN)
		get_tree().quit(1)
		return
	_oct = scene.instantiate() as Node3D
	_oct.position = Vector3(0, 0.05, 0)      # ★ 先定位，再入树（避免原点去穿透）
	add_child(_oct)
	# ★ 关掉 AI、强制 CHASE → 由本脚本用 manual_wish_dir 精确控制速度
	_oct.set("ai_enabled", false)
	_oct.set("state", 1)                     # 1 = CHASE（_animate_model 才会按速度选 Walk 并重定时）
	_oct.call("_face_instant_dir", Vector3(1, 0, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	print("CAPTURE: 章鱼动画 = Idle:%s Walk:%s Run:%s Windup:%s Attack:%s Hit:%s Death:%s" % [
		_oct.get("_idle_anim"), _oct.get("_walk_anim"), _oct.get("_run_anim"),
		_oct.get("_windup_anim"), _oct.get("_attack_anim"), _oct.get("_hit_anim"),
		_oct.get("_death_anim")])

	await _wait(0.4)

	# ---------- 1) Walk @ 自然速 1.68（want = 1.000，正侧视看八腕前后拖行）----------
	_set_cam(Vector3(0, 0.85, 3.6), Vector3(0, 0.35, 0))
	_drive(SPEED_WALK_NATURAL)
	_seg("walk_natural_1.68")
	await _wait(0.5)
	_print_state("walk_natural_1.68", "settle")
	await _wait(2.0)

	# ---------- 2) Walk @ 全速 2.2（want = 1.310，交战实播倍速；★ 判前冲回弹可见性）----------
	_seg("walk_full_2.2")
	_drive(SPEED_WALK_FULL)
	await _wait(0.5)
	_print_state("walk_full_2.2", "settle")
	await _wait(2.0)
	_stop()
	await _wait(0.4)

	# ---------- 3) AttackWindup → Attack（斜前 45°，看前腕回收→八腕前抽）----------
	_set_cam(Vector3(2.7, 1.0, 2.7), Vector3(0, 0.35, -0.3))
	_seg("attack")
	_oct.call("request_attack", Vector3(1, 0, 0))
	await _wait(0.4)                          # 仍处于蓄力相
	_print_state("attack_windup", "settle")
	await _wait(2.0)

	# ---------- 4) Death（斜前 45°，看八腕外撑→一软→塌成一摊）----------
	# 【★ 抓帧专用"钉尸"，仅为让死亡演出可读】引擎 _die() 会把 collision_layer/mask 归零，
	#   而 _physics_process 在 not is_on_floor() 时**继续加重力**（enemy.gd L396-397），
	#   于是尸体失去碰撞后**穿地加速下落**，跟随镜头一并坠入虚空 —— 实测 1.2s 内 y 从 0 → -20m。
	#   （狼的 combat 预览末帧同样只剩背景色，是同一**既有**行为，非章鱼特有。）
	#   死亡演出由 AnimationPlayer 在 _process 里驱动（enemy.gd L1200-1219），不依赖物理；
	#   这里在死亡瞬间关掉物理步进，尸体便留在原地把"外撑→一软→塌成一摊"演完。
	#   ⚠️ 这是**取证手段**，不代表引擎行为：引擎实际行为（尸体会穿地）见交付报告。
	_seg("death")
	_oct.call("take_damage", 999, _oct.global_position + Vector3(-1, 0, 0))
	_oct.set_physics_process(false)           # ★ 钉住尸体（抓帧专用，理由见上）
	await _wait(0.4)
	_print_state("death", "settle")
	await _wait(1.1)                          # 死亡动画 1.042s + 尸体 ~1.29s 后 queue_free

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
	if _oct == null or _cam == null or not is_instance_valid(_oct):
		return
	var p: Vector3 = _oct.global_position
	_cam.global_position = p + _cam_offset
	_cam.look_at(p + _cam_look_at, Vector3.UP)


# ------------------------------------------------------------------ 驱动

func _set_cam(offset: Vector3, look: Vector3) -> void:
	_cam_offset = offset
	_cam_look_at = look


func _drive(speed: float) -> void:
	_oct.set("move_speed", speed)
	_oct.set("manual_wish_dir", Vector3(1, 0, 0))


func _stop() -> void:
	_oct.set("manual_wish_dir", Vector3.ZERO)


func _seg(name: String) -> void:
	print("CAPTURE_SEG %s frame=%d" % [name, Engine.get_frames_drawn()])
	_print_state(name, "start")


## 按**真实（固定步长）时间**等待 —— --fixed-fps 下 timer 走的是固定 dt，切段因此可复现。
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


# ------------------------------------------------------------------ 播放状态取证

func _anim_state() -> Array:
	var ap: AnimationPlayer = null
	if _oct != null and is_instance_valid(_oct):
		ap = _oct.get("_anim_player") as AnimationPlayer
	if ap == null:
		return ["<none>", 0.0, 0.0]
	return [String(ap.current_animation), ap.get_playing_speed(), ap.speed_scale]


func _print_state(tag: String, when: String) -> void:
	var st := _anim_state()
	print("CAPTURE_STATE %s[%s] anim=%s playing=%.4f speed_scale=%.4f" % [
		tag, when, st[0], st[1], st[2]])
