extends Node
## ============================================================
## 尸体不穿地守门项（T12c 根修配套；覆盖 enemy.gd 的"死亡重力"缺陷）
## ============================================================
## 【它守的是什么 bug】
##   enemy.gd 的 _die() 把 collision_layer/mask 一并归零（"尸体不挡玩家/镜头"的有意设计）。
##   但 _physics_process 里的重力旧写法是 `if not is_on_floor(): velocity.y -= GRAVITY*delta`——
##   无碰撞 ⇒ is_on_floor() **永远为假** ⇒ 重力在尸体上**无界积分** ⇒ 尸体加速下坠穿地。
##   （实测过：1.2 s 内 y 从 0 → −20 m；狼/守卫/鸟/章鱼**全部**中招。）
##   根修：重力行加死亡守卫 + _die() 里 velocity.y 归零。本探针把这条行为钉成回归门。
##
## 【为什么要跑"真实入口"】必须经由 take_damage() → Health 扣血 → _die() 这条**正常死亡路径**，
##   不允许直接赋 state=DEAD —— 否则测的不是玩家真能触发的代码路径。
##
## 【运行（★ 必须跑场景，不是 --script）】
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> \
##       res://tools/verify_corpse_no_sink.tscn
##   （enemy.gd 以标识符引用 autoload EventBus，--script 下不在编译期注册会挂。）
##
## 【判定（对 wolf / brute / bird / octopus 各一遍）】
##   ✓ 落地后再击杀（基准稳定）
##   ✓ take_damage 触发死亡（_dead==true）——**非空洞前置**：怪没死的话下面两条会被白送
##   ✓ 模型敌人的 Death 动画确实在播且 get_playing_speed() > 0.1 ——**非空洞**第二道
##   ✓ 采样窗口 ≥ 0.9 s（覆盖整个死亡演出；节点 queue_free 后自然停止）
##   ★ max(y) − min(y) ≤ 0.05 m（尸体不漂不沉）
##   ★ y_min ≥ −0.05 m（尸体不穿地）
## ============================================================

const ENEMY_CASES := [
	{ "id": "wolf",    "path": "res://scenes/enemy/wolf.tscn"    },
	{ "id": "brute",   "path": "res://scenes/enemy/enemy.tscn"   },
	{ "id": "bird",    "path": "res://scenes/enemy/bird.tscn"    },
	{ "id": "octopus", "path": "res://scenes/enemy/octopus.tscn" },
]
const SINK_SPAN_TOL := 0.05    # max(y)-min(y) 上限（米）
const Y_MIN_TOL := -0.05       # 允许的最低 y（米）——低于此即"穿地"
const SAMPLE_CAP := 3.0        # 采样时长上限（秒）；尸体 queue_free 后循环自然结束
const MIN_COVER := 0.9         # 最少要覆盖的采样时长（秒）
const LOG_EVERY := 0.2         # y 轨迹打印间隔（秒）

var _fail := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== 尸体不穿地守门项（T12c）===")
	_build_ground()
	await get_tree().process_frame
	for c in ENEMY_CASES:
		await _run_case(String(c["id"]), String(c["path"]))

	print("")
	if _fail == 0:
		print("结论：全部通过 ✓")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


## 一块 400×400 的静态地面（尸体要从"能落地"的状态开始）。
func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	add_child(ground)


func _run_case(id: String, path: String) -> void:
	print("")
	print("[%s] %s" % [id, path])

	var ps := load(path) as PackedScene
	if ps == null:
		_check(false, "场景加载", path)
		return
	var e := ps.instantiate() as Node3D
	if e == null:
		_check(false, "实例化（Node3D）", path)
		return
	e.set("ai_enabled", false)                 # 关 AI：Stand 原地，别追不存在的玩家
	e.position = Vector3(0, 0.05, 0)           # 略高于地，等它自己落地
	add_child(e)

	# ---- 1) 等落地（最多 ~2 s）----
	var body := e as CharacterBody3D
	var landed := false
	for i in range(120):
		await get_tree().physics_frame
		if body != null and is_instance_valid(body) and body.is_on_floor():
			landed = true
			break
	_check(landed, "落地后再击杀（基准稳定）",
		"is_on_floor=%s y=%.4f" % [str(body != null and body.is_on_floor()), e.global_position.y])

	# ---- 2) 真实入口击杀：take_damage → Health.damage → _die() ----
	e.call("take_damage", 999999, e.global_position + Vector3(0, 0, -1))
	await get_tree().physics_frame

	var dead: bool = e.get("_dead") == true
	_check(dead, "take_damage 触发死亡（非空洞前置）", "_dead=%s" % str(dead))
	if not dead:
		e.queue_free()
		await get_tree().process_frame
		return

	var ap := e.get("_anim_player") as AnimationPlayer
	var want_death_anim: bool = e.get("_use_model") == true and String(e.get("_death_anim")) != ""

	# ---- 3) 逐物理帧采样根节点 y，直到 queue_free 或超时 ----
	var dt := 1.0 / float(maxi(1, Engine.physics_ticks_per_second))
	var ys: Array[float] = []
	var trace: Array[String] = []
	var death_anim_seen := false
	var playing_speed_ok := false
	var playing_speed := 0.0
	var t := 0.0
	var next_log := 0.0
	while is_instance_valid(e) and t < SAMPLE_CAP:
		await get_tree().physics_frame
		t += dt
		if not is_instance_valid(e):
			break
		ys.append(e.global_position.y)
		if t >= next_log:
			trace.append("%.2f:%.4f" % [t, e.global_position.y])
			next_log += LOG_EVERY
		if is_instance_valid(ap):
			if String(ap.current_animation).contains("Death"):
				death_anim_seen = true
				playing_speed = ap.get_playing_speed()
				if playing_speed > 0.1:
					playing_speed_ok = true

	var covered := float(ys.size()) * dt
	print("  y 轨迹(t:y)： %s" % " ".join(trace))
	print("  采样 n=%d 覆盖=%.2f s" % [ys.size(), covered])

	# ---- 非空洞：确实死透（动画在播）----
	if want_death_anim:
		_check(death_anim_seen, "Death 动画确实在播（非空洞）", "anim_seen=%s" % str(death_anim_seen))
		_check(playing_speed_ok, "死亡中 get_playing_speed() > 0.1", "playing=%.4f" % playing_speed)
	else:
		print("  · 非模型敌人（_use_model=false）：跳过动画非空洞项")

	# ---- 采样窗口非平凡 ----
	_check(covered >= MIN_COVER, "采样窗口 ≥ %.1f s" % MIN_COVER, "covered=%.2f s" % covered)

	# ---- ★ 主判定：不漂不沉、不穿地 ----
	if ys.is_empty():
		_check(false, "采样非空", "n=0")
	else:
		var ymax: float = ys.max()
		var ymin: float = ys.min()
		var span: float = ymax - ymin
		_check(span <= SINK_SPAN_TOL,
			"尸体不漂不沉： max(y)-min(y) ≤ %.2f m" % SINK_SPAN_TOL,
			"span=%.4f（y %.4f .. %.4f）" % [span, ymin, ymax])
		_check(ymin >= Y_MIN_TOL,
			"尸体不穿地： y_min ≥ %.2f m" % Y_MIN_TOL,
			"y_min=%.4f" % ymin)
