extends Node
## ============================================================
## 引擎内实拍鸟的 7 段表现（给"Walk/Run 换挡读不读得出 / 招式读不读得懂"提供真实证据）。
## ============================================================
## 为什么必须有它：Blender 侧 previews 只是离线渲染，**必须在 Godot 里真跑一遍**
##   才能看到"缩放 1.6m 后 + 跟镜头下"的真实观感（双足步态、换挡、跃扑预警、死亡塌倒）。
##
## 用法（★ 不要 --headless：headless 用空渲染驱动，出不来图；★ 输出目录必须先建好）：
##   Godot_v4.7.2-stable_win64_console.exe --path D:\GodotProject\first-game \
##     --fixed-fps 30 --resolution 960x540 \
##     --write-movie D:\GodotProject\first-game\.tmp_bird\frame.png \
##     res://tools/anim_capture/bird_capture.tscn
##
## 输出：`.tmp_bird/frame%08d.png`（每渲染一帧一张，序号 = Engine.get_frames_drawn() − 1）
##   本脚本在每个片段开头打印 `CAPTURE_SEG <名字> frame=<frames_drawn>`，
##   并在该刻 + 稳定后各打印一条**真实播放状态** `CAPTURE_STATE <名字>[start|settle]
##   anim=… playing=… speed_scale=…`；ramp 段还会在**动画名每次变化**时打印
##   `CAPTURE_SWITCH …` —— 这三类日志就是"这一刻播的到底是 Walk 还是 Run、倍速多少"的
##   当场证据（β 之后 get_playing_speed() ≡ speed_scale，两条日志里的两个数应当一致）。
##   据此把序列切成两段 GIF：1/2/3/4 → walk；5/6/7 → combat。
##
## 【★ 鸟的 Walk/Run 换挡口径（bird.tscn，T11b 提交 f2bcd99）】
##   档位判据 = "Walk 的倍速需求"（无量纲）want = spd / walk_natural_speed(1.6226)：
##     want ≥ run_switch_speed_scale(1.45)                      ⇒ 起切 Run
##     want < 1.45 × (1 − 0.15) = 1.2325                        ⇒ 回切 Walk（15% 滞回）
##   换算成速度：> 2.3528 m/s 播 Run；已播 Run 时 < 2.0 m/s 才回 Walk。
##   所以本脚本几段速度各自播什么，**不是猜的**：
##     1.6226 m/s ⇒ want = 1.6226/1.6226 = 1.000 < 1.45 ⇒ **Walk**（自然速）
##     2.6    m/s ⇒ want = 2.6/1.6226   = 1.602 ≥ 1.45 ⇒ **Run**（全速；rwant = 2.6/1.937 = 1.3424）
##   ⚠️ 别照抄狼的 2.40 阈值 —— 鸟 want@2.6 = 1.602 < 2.40，用 2.40 的话 Run 永不播。
##
## 【相机】不用玩家视角 —— 那看不清步态。这里自带一台**固定机位 + 每帧跟住鸟**的相机：
##   步态段用**正侧视**（看双足迈步 / 腾空相），招式段用**斜前 45°**（看蹲伏蓄力→跃起啄下）。
## ============================================================

const BIRD_TSCN := "res://scenes/enemy/bird.tscn"
const SPEED_WALK_NAT := 1.6226   # 自然速：want = 1.000 < 1.45 ⇒ 播 **Walk**
const SPEED_RUN_FULL := 2.6      # 全速（= bird.tscn 的 move_speed）：want = 1.602 ≥ 1.45 ⇒ 播 **Run**
const RAMP_FROM := 1.5           # 换挡段起始速度（want = 0.925 < 1.45 ⇒ 起于 Walk）
const RAMP_TO := 2.6             # 换挡段结束速度（want = 1.602 ≥ 1.45 ⇒ 收于 Run）
const RAMP_TIME := 3.0           # 换挡段时长(秒) —— 连续升速，专门抓换挡瞬间（跨 2.3528 m/s）

var _bird: Node3D = null
var _cam: Camera3D = null
var _cam_offset: Vector3 = Vector3(0, 0.95, 3.8)     # 近景：鸟约占画面高 ~40%，双足看得清
var _cam_look_at: Vector3 = Vector3(0, 0.60, 0)
var _last_anim: String = ""      # ramp 段用来检测"播放中的动画名发生了变化"（换挡瞬间）


func _ready() -> void:
	_build_world()
	var bird_scene := load(BIRD_TSCN) as PackedScene
	if bird_scene == null:
		print("CAPTURE: 找不到 %s" % BIRD_TSCN)
		get_tree().quit(1)
		return
	_bird = bird_scene.instantiate() as Node3D
	_bird.position = Vector3(0, 0.05, 0)      # ★ 先定位，再入树（避免原点去穿透）
	add_child(_bird)
	# ★ 关掉 AI、强制 CHASE → 由本脚本用 manual_wish_dir 精确控制速度（见 enemy.gd 的手动操控说明）
	_bird.set("ai_enabled", false)
	_bird.set("state", 1)                     # 1 = CHASE（这样 _animate_model 才会按速度选 Walk/Run）
	_bird.call("_face_instant_dir", Vector3(1, 0, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	print("CAPTURE: 鸟动画 = Idle:%s Walk:%s Run:%s Windup:%s Attack:%s Hit:%s Death:%s" % [
		_bird.get("_idle_anim"), _bird.get("_walk_anim"), _bird.get("_run_anim"),
		_bird.get("_windup_anim"), _bird.get("_attack_anim"), _bird.get("_hit_anim"),
		_bird.get("_death_anim")])

	await _wait(0.4)                          # 让场景稳定几帧

	# ---------- 1) Idle（正侧视看站姿呼吸）----------
	_set_cam(Vector3(0, 0.95, 3.8), Vector3(0, 0.60, 0))
	_stop()
	_seg("idle")
	await _wait(0.6)
	_print_state("idle", "settle")
	await _wait(1.4)

	# ---------- 2) Walk 自然速（1.6226 m/s ⇒ want 1.000 < 1.45，正侧视看双足步态）----------
	_seg("walk_natural_1.62")
	_drive(SPEED_WALK_NAT)
	await _wait(0.5)                          # 起播并稳定（速度插值到位、动画名切完）
	_print_state("walk_natural_1.62", "settle")
	await _wait(2.5)

	# ---------- 3) 换挡段：1.5 → 2.6 m/s 连续升速，专抓 Walk → Run 的换挡瞬间 ----------
	# 【为什么单独拍一段】"从走切到跑"的价值全在**读感随速度变化**上：同一只鸟、
	#   同一个机位，脚步从双足小跑逐渐变成**大步腾空跑**。这件事**只在帧与帧之间**存在，
	#   子串匹配 / 档位阈值逻辑在**静态图**上完全读不出来 —— 非动图不可。
	#   速度扫过 2.3528 m/s 时 want 越过 1.45，日志里会打印 CAPTURE_SWITCH。
	_seg("ramp_walk_to_run")
	await _ramp_walk_to_run(RAMP_FROM, RAMP_TO, RAMP_TIME)

	# ---------- 4) Run 全速（2.6 m/s ⇒ want 1.602 ≥ 1.45，正侧视、镜头跟住）----------
	# 【证据】这一段**实播的是 Run 而不是 Walk**；β 之后 get_playing_speed() ≡ speed_scale，
	#   所以这里的 1.3424 是**真实**步频。Run 有腾空相（build_bird §②b），侧视一眼可见。
	_seg("run_full_2.6")
	_drive(SPEED_RUN_FULL)
	await _wait(0.5)
	_print_state("run_full_2.6", "settle")
	await _wait(2.5)
	_stop()
	await _wait(0.5)

	# ---------- 5) AttackWindup → Attack（斜前 45°，看"蹲伏蓄力 → 跃起前扑啄下"）----------
	_set_cam(Vector3(3.3, 1.3, 3.3), Vector3(0, 0.60, 0))
	_seg("attack")
	_bird.call("request_attack", Vector3(1, 0, 0))
	await _wait(0.4)                          # 仍处于蓄力相
	_print_state("attack_windup", "settle")
	await _wait(2.0)

	# ---------- 6) Hit（受击硬直：看被打退）----------
	_seg("hit")
	_bird.call("take_damage", 10, _bird.global_position + Vector3(-1, 0, 0))
	await _wait(0.3)
	_print_state("hit", "settle")
	await _wait(0.7)

	# ---------- 7) Death + 尸体停留（看侧扑倒地是否自然）----------
	_seg("death")
	_bird.call("take_damage", 999, _bird.global_position + Vector3(-1, 0, 0))
	await _wait(0.4)
	_print_state("death", "settle")
	await _wait(2.8)

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

	# 地面：足够大（鸟全速会跑出 ~15m），并给个中性色方便看"脚有没有打滑"
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
	if _bird == null or _cam == null or not is_instance_valid(_bird):
		return
	var p: Vector3 = _bird.global_position
	_cam.global_position = p + _cam_offset
	_cam.look_at(p + _cam_look_at, Vector3.UP)


# ------------------------------------------------------------------ 驱动

func _set_cam(offset: Vector3, look: Vector3) -> void:
	_cam_offset = offset
	_cam_look_at = look


func _drive(speed: float) -> void:
	_bird.set("move_speed", speed)
	_bird.set("manual_wish_dir", Vector3(1, 0, 0))


func _stop() -> void:
	_bird.set("manual_wish_dir", Vector3.ZERO)


func _seg(name: String) -> void:
	# PNG 序号 = frames_drawn − 1（见项目 README 抓帧坑①），这里如实打印 frames_drawn
	print("CAPTURE_SEG %s frame=%d" % [name, Engine.get_frames_drawn()])
	_print_state(name, "start")


## 连续把鸟的**指令速度**从 from_spd 升到 to_spd（时长 dur 秒），并在每一帧记录
## "播放中的动画名是否发生了变化"。Walk→Run 换挡点因此会在日志里留下一行
## `CAPTURE_SWITCH`（带当时的指令速度、**实际速度**、动画名与实播倍速）—— 这是
## "换挡确实发生过、发生在哪个速度上"的当场证据。
func _ramp_walk_to_run(from_spd: float, to_spd: float, dur: float) -> void:
	_last_anim = ""
	var steps := maxi(1, int(round(dur * 30.0)))   # 抓帧固定 30fps
	for i in range(steps + 1):
		var spd := lerpf(from_spd, to_spd, float(i) / float(steps))
		_drive(spd)
		await get_tree().process_frame
		_log_switch(spd)
	_print_state("ramp_walk_to_run", "end")


## 按**真实（固定步长）时间**等待 —— --fixed-fps 下 timer 走的是固定 dt，切段因此可复现。
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


# ------------------------------------------------------------------ 播放状态取证

## 读取鸟此刻**真实的播放状态**。返回 [current_animation, get_playing_speed(), speed_scale]。
## β 之后 `get_playing_speed() ≡ speed_scale`，两个数应当一致 —— 打印出来就是当场验证它。
func _anim_state() -> Array:
	var ap: AnimationPlayer = null
	if _bird != null and is_instance_valid(_bird):
		ap = _bird.get("_anim_player") as AnimationPlayer
	if ap == null:
		return ["<none>", 0.0, 0.0]
	return [String(ap.current_animation), ap.get_playing_speed(), ap.speed_scale]


func _print_state(tag: String, when: String) -> void:
	var st := _anim_state()
	print("CAPTURE_STATE %s[%s] anim=%s playing=%.4f speed_scale=%.4f" % [
		tag, when, st[0], st[1], st[2]])


## ramp 段用：动画名一变就打一行，附上当时的**指令速度**与**实际速度**（velocity）。
func _log_switch(cmd_spd: float) -> void:
	var st := _anim_state()
	if st[0] == _last_anim:
		return
	_last_anim = st[0]
	var vel := Vector3.ZERO
	if _bird != null and is_instance_valid(_bird):
		vel = _bird.get("velocity") as Vector3
	var actual := Vector2(vel.x, vel.z).length()
	print("CAPTURE_SWITCH frame=%d cmd=%.3f vel=%.3f anim=%s playing=%.4f speed_scale=%.4f" % [
		Engine.get_frames_drawn(), cmd_spd, actual, st[0], st[1], st[2]])
