extends Node
class_name CinematicDirector
## ============================================================
## 电影化分镜导演（CinematicDirector）
## ============================================================
## 【它解决什么问题】处决只有"动画演完就结束"，没有任何运镜 —— 玩家按完左键，
##   镜头还是那个平平的第三人称追尾，高光时刻被浪费掉了。
##   本节点是一个**自包含**的"导演"：处决开始时接管相机，按一张"分镜表"逐帧
##   写入相机位姿与 fov，同时拉出上下两条电影遮幅黑边；处决结束时把相机交还追尾。
##
## 【它为什么"自包含"】不依赖 HUD、也不依赖玩家脚本：
##   · 相机：运行时从 "camera" 组里找（找不到就整段降级为"只放遮幅、不动相机"）；
##   · 遮幅：自己 new 一个 CanvasLayer + 两条 ColorRect，不占用 HUD 的层级。
##   这样它既能塞进主场景，也能塞进任意测试场景，不需要任何外部接线。
##
## 【★ 核心思想：相对取景（relative framing）】
##   绝对坐标的电影机位在这个游戏里是行不通的：敌人会被击退、玩家会前冲贴近，
##   演员一动，钉死的机位就失焦了。所以本导演**每帧重新采样两个"锚点演员"的世界坐标**：
##     取景轴 = 玩家胸口 → 敌人胸口 的水平方向；
##     相机位置 = 锚点 + 由 (方位角 azimuth / 仰角 elev / 距离 dist) 描述的方向 × 距离。
##   于是"从玩家侧后方 4.2m、抬高 22° 俯视"这句话，无论演员怎么动都成立 —— 机位跟着人走。
##
## 【★ 时间轴用"归一化时间 0..1"】
##   分镜表里的 t 不是秒，而是"相对整段时长 execute_time 的比例"。
##   好处：以后把 execute_time 从 1.0 调到 1.2，三段分镜自动等比伸缩，
##   不用去重排每一刀的秒数，也不会因为改了时长而让"命中切镜"落后于动画。
##
## 【★ 切镜 = 硬切，不插值】
##   真实的电影剪接里，"切一刀"就是画面瞬间跳到一个全新机位，中间没有运镜。
##   本导演只在**进入特写**（前 INTRO_TIME 秒）和**退出特写**（交还相机）两端做平滑，
##   中间三个机位之间是硬切 —— 这正是分镜的"节奏感"来源。
##   ⚠️ 唯一需要"随演员动而连续变化"的，是每帧重采样的锚点坐标（那是取景，不是切镜）。
##
## 【★ 时间推进必须用被 time_scale 缩放过的 delta】
##   处决命中会触发慢动作（player.gd 的子弹时间，0.35 倍）。如果这里用真实时间推进，
##   慢动作期间"画面的时间"走得很慢、而"机位的时间"走得很快，镜头就会滑得比人物快 ——
##   一眼穿帮。用传入 _process 的 delta（已被缩放）推进，机位与画面天然同步。
## ============================================================


## ── 遮幅黑边 ──────────────────────────────────────────────
## 单条黑边占视口高度的比例。0.12 = 上下各 12% → 有效画面 76%，是常见的 2.35:1 电影感区间。
const LETTERBOX_RATIO: float = 0.12
## 入场滑入时长（真实秒）。用真实时间（补间 set_ignore_time_scale）→ 慢动作不会把滑入也拖慢。
const LETTERBOX_IN_TIME: float = 0.15
## 退场滑出时长（真实秒）。
const LETTERBOX_OUT_TIME: float = 0.15
## 纯黑，不透明。淡入淡出用尺寸变化做，不改 alpha（免得和 HUD 的半透明层混在一起）。
const LETTERBOX_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)

## ── 进场平滑接管 ──────────────────────────────────────────
## 进入特写时，从"接管瞬间的相机位姿"平滑过渡到分镜第一位机位所用的时长（秒，缩放时间）。
## ⚠️ 不用 0：玩家一按左键就"啪"地把镜头从追尾瞬移到全景机位，会有一帧的硬跳。
const INTRO_TIME: float = 0.15
## 计算注视方向时，"沿视线多远放一个注视点"。look_at 只关心方向、不关心距离，
## 所以这里只是一个足够远的整数值，用于把"方向"表达成"点"喂给 apply_driven_pose。
const LOOK_AHEAD: float = 10.0

## ── 锚点高度（米）────────────────────────────────────────
## 取景时把演员的"世界坐标"抬到胸口再看，否则机位会对着脚踝构图。
##   player = 1.15：与 player.gd::_effect_point() 一致（胸口高度）。
##   enemy  = 1.50：敌人模型总高 2.66m，1.50 约等于胸口/锁骨一线。
const PIVOT_HEIGHT := {"player": 1.15, "enemy": 1.50}

## ============================================================
## ★★ 分镜表（新增演出就在这里加表）
## ============================================================
## 处决特写分镜（execute_time = 1.0s，切 3 刀）
##   t        ：归一化时间 0..1（相对 execute_time）。
##   pivot    ：注视锚点。"player" / "enemy" / "mid"（两者中点）。
##   azimuth  ：方位角(度)。0 = 相机在"玩家背后"（正对敌人）；正角 = 往角色右侧绕。
##   elev     ：仰角(度)。正角 = 相机更高（俯视）；负角 = 仰拍。
##   dist     ：相机到锚点的直线距离(米)。
##   fov      ：该刀使用的视野角度(度)。小 fov = 长焦特写（压缩空间、突出主体）。
## 三个切点：0.00 全景交代 → 0.32 命中（= execute_hit_time，硬切近景｜过肩 3.6m / fov50；原 1.9m/fov36 会穿过玩家身体糊屏）→ 0.62 拉回收招。
const EXECUTE_SHOTS := [
	{"t": 0.00, "pivot": "mid",    "azimuth": 58.0, "elev":  22.0, "dist": 4.2, "fov": 62.0},
	{"t": 0.32, "pivot": "enemy",  "azimuth": 18.0, "elev":   8.0, "dist": 3.6, "fov": 50.0},
	{"t": 0.62, "pivot": "player", "azimuth": 18.0, "elev":  20.0, "dist": 4.6, "fov": 58.0},
]

## 正在播出（= 导演此刻拥有相机控制权）。stop() 后立即为 false。
var _active: bool = false
## 当前分镜表（play 时传入，之后不再改）。
var _shots: Array = []
## 整段时长（秒，= execute_time）。归一化时间 = _elapsed / _duration。
var _duration: float = 1.0
## 已推进的**缩放后**时间(秒)。★ 用 delta 累加，见文件头说明。
var _elapsed: float = 0.0
## 进场平滑已经走了多久(秒)。只在前 INTRO_TIME 秒内用于混合。
var _intro_elapsed: float = 0.0

## 两个锚点演员。player.gd 会传 (self, target)。
var _actor_a: Node3D = null
var _actor_b: Node3D = null
## 接管中的相机（ThirdPersonCamera）。取不到就为 null（降级：只放遮幅）。
var _cam: ThirdPersonCamera = null

## 进场基准位姿：play() 那一刻记下相机的当前状态，作为"第 0 刀"。
var _entry_pos: Vector3 = Vector3.ZERO
var _entry_dir: Vector3 = Vector3.FORWARD
var _entry_fov: float = 70.0

## —— 遮幅节点 ——
var _layer: CanvasLayer = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
## 遮幅当前进度 0..1（0 = 收起，1 = 全开）。
var _bar_k: float = 0.0
var _bar_tween: Tween = null


func _ready() -> void:
	# 让 player.gd 能用 get_first_node_in_group("cinematic") 找到本导演。
	add_to_group("cinematic")
	_build_overlay()


## 交还控制权 / 被销毁时的兜底：把补间杀掉、相机放回去，别让画面卡在特写黑边里。
func _exit_tree() -> void:
	_bar_kill_tween()
	if _cam != null and is_instance_valid(_cam):
		_cam.release_driven()
	_cam = null
	_active = false


## ============================================================
## 公开 API
## ============================================================

## 播放一段分镜。
## @param shots     分镜表（见 EXECUTE_SHOTS）
## @param duration  状态机时长（秒）；分镜里的 t 是相对它的归一化时间
## @param actor_a   锚点演员 A（玩家）
## @param actor_b   锚点演员 B（处决目标）
func play(shots: Array, duration: float, actor_a: Node3D, actor_b: Node3D) -> void:
	if shots == null or shots.is_empty():
		return
	_shots = shots
	_duration = maxf(0.0001, duration)   # 防 0 除
	_actor_a = actor_a
	_actor_b = actor_b
	_elapsed = 0.0
	_intro_elapsed = 0.0
	_active = true

	# 找相机并记下"接管瞬间的位姿"（进场平滑的起点）。
	# ★ 取不到相机不算错：降级成"只放遮幅"的纯 UI 演出，处决照常跑。
	_cam = get_tree().get_first_node_in_group("camera") as ThirdPersonCamera
	if _cam != null:
		_entry_pos = _cam.global_position
		# 相机的局部 -Z 就是它看向的方向（本工程的相机约定，见 third_person_camera.gd）。
		_entry_dir = -_cam.global_basis.z
		_entry_fov = _cam.get_fov()
		# ★ 先把追尾驱动关掉，避免"追尾写一帧、导演写一帧"互相打架。
		_cam.driven = true
	_show_letterbox()


## 中途停止并交还相机控制权。★ 必须随时可安全调用（目标失效时 player.gd 会提前收招）。
func stop() -> void:
	_active = false
	if _cam != null and is_instance_valid(_cam):
		# ★ release_driven 会从当前位姿反推 yaw/pitch，交还后追尾从当前位置无缝续上 —— 不弹回。
		_cam.release_driven()
	_cam = null
	_hide_letterbox()


## 导演此刻是否拥有相机控制权。
func is_active() -> bool:
	return _active


## 遮幅是否正在显示（测试用；也方便将来接别处的 UI 判断）。
func is_letterbox_visible() -> bool:
	return _bar_top != null and _bar_top.visible and _bar_top.size.y > 0.0


## 两个锚点演员是否都还活着。任一见 false → 导演该收手（见 _process 的防御分支）。
## 【为什么用 is_instance_valid 而不是 `!= null`】被 queue_free 的实例不是 null，但它已是"失效对象"，
##   直接访问其属性/传参会抛错。is_instance_valid 才是"这个对象还能不能用"的正确判据。
func _anchors_alive() -> bool:
	return is_instance_valid(_actor_a) and is_instance_valid(_actor_b)


# ============================================================
# 每帧驱动
# ============================================================

func _process(delta: float) -> void:
	if not _active:
		return
	# ★ 防御：两个锚点演员任一在演出中途被清场（queue_free / 换场景）就立刻收手。
	#   没有别的路径会在"玩家被单独销毁"时调 stop() —— 不这么做，相机会永久卡在 driven=true、
	#   遮幅永不合上、_chest 每帧报 "previously freed"。宁可提前收手，也绝不能永久卡住。
	if not _anchors_alive():
		stop()
		return
	# ★ 用传入的 delta（已被 time_scale 缩放）推进时间轴，见文件头"时间推进"一节。
	_elapsed += delta
	var nt := clampf(_elapsed / _duration, 0.0, 1.0)
	var shot := _shot_at(nt)
	var pose := _compute_shot_pose(shot)
	var pos: Vector3 = pose["pos"]
	var look: Vector3 = pose["look"]
	var fov: float = pose["fov"]

	# —— 进场前 INTRO_TIME 秒：从"第 0 刀（接管瞬间位姿）"平滑滑到分镜机位 ——
	# 用 smoothstep 让起收都有缓动（线性过渡会显得很"机械"）。
	_intro_elapsed += delta
	if _cam != null and _intro_elapsed < INTRO_TIME:
		var k := smoothstep(0.0, 1.0, _intro_elapsed / INTRO_TIME)
		pos = _entry_pos.lerp(pos, k)
		# 注视方向也一起混合：从"接管时看的方向"旋到"分镜要看的方向"，
		# 这样进场不会出现"位置在滑、视线却瞬间甩过去"的割裂感。
		var shot_dir := (look - pos).normalized()
		var dir := _entry_dir.slerp(shot_dir, k)
		look = pos + dir * LOOK_AHEAD
		fov = lerpf(_entry_fov, fov, k)

	if _cam != null:
		_cam.apply_driven_pose(pos, look, fov)


## 查表：返回"当前时间落在哪一刀上"。
## ★ 硬切：取最后一个 t <= nt 的机位，不和相邻那刀做任何混合（见文件头"切镜"一节）。
func _shot_at(nt: float) -> Dictionary:
	var cur: Dictionary = _shots[0]
	for s in _shots:
		if float(s["t"]) <= nt + 0.0001:
			cur = s
		else:
			break       # 表是按 t 升序排的，遇到更大的即可停
	return cur


## 计算某一刀的位姿（相对取景）。返回 {"pos", "look", "fov"}。
## ★ 每帧现算：两个锚点的世界坐标每次都重新采样，演员移动时机位跟着走。
## ★ 本函数**在任何情况下都返回完整的字典**（pos/look/fov 齐全），绝不返回空字典 ——
##   否则 _process 里 pose["pos"] 会报 "Invalid access … on a base object of type 'Dictionary'"，
##   并连带让该帧 apply_driven_pose 不被调用（相机定格一帧）。
func _compute_shot_pose(shot: Dictionary) -> Dictionary:
	# —— 0) 防御性取锚点：先 is_instance_valid 再取 ——
	#   ⚠️ 为什么必须先判再取：_chest 的形参一旦带 `: Node3D` 注解，GDScript 会在**传参绑定阶段**
	#      就拒绝 "previously freed" 对象（抛 SCRIPT ERROR），函数体里的守卫根本执行不到。
	#      所以这里先判；失效的那个退化为"另一个锚点"，两个都失效则退回原点。
	var a_valid := is_instance_valid(_actor_a)
	var b_valid := is_instance_valid(_actor_b)
	var a_chest: Vector3
	var b_chest: Vector3
	if a_valid:
		a_chest = _chest(_actor_a, float(PIVOT_HEIGHT["player"]))
	elif b_valid:
		a_chest = _chest(_actor_b, float(PIVOT_HEIGHT["player"]))   # 玩家没了 → 借敌人位置当 A，别让取景轴崩
	else:
		a_chest = Vector3.UP * float(PIVOT_HEIGHT["player"])
	if b_valid:
		b_chest = _chest(_actor_b, float(PIVOT_HEIGHT["enemy"]))
	elif a_valid:
		b_chest = _chest(_actor_a, float(PIVOT_HEIGHT["enemy"]))
	else:
		b_chest = Vector3.UP * float(PIVOT_HEIGHT["enemy"])

	# —— 2) 基准轴：玩家 → 敌人（水平）。相机方位角以它为 0 度基准 ——
	var axis := b_chest - a_chest
	axis.y = 0.0
	if axis.length() > 0.01:
		axis = axis.normalized()
	else:
		# 两人重叠（退化情形）：退回用玩家自身朝向的水平分量，再不行给个兜底方向。
		axis = -(_actor_a as Node3D).global_basis.z if a_valid else Vector3(0.0, 0.0, -1.0)
		axis.y = 0.0
		axis = axis.normalized() if axis.length() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var back := -axis                                  # azimuth = 0 时相机在这个方向（玩家背后）

	# —— 3) 注视点（pivot）——
	var pivot: Vector3
	match String(shot["pivot"]):
		"player":
			pivot = a_chest
		"enemy":
			pivot = b_chest
		_:
			pivot = (a_chest + b_chest) * 0.5          # "mid"

	# —— 4) 水平方向绕 Y 旋转 azimuth（正角 = 往角色右侧绕）——
	var dir_h := back.rotated(Vector3.UP, deg_to_rad(float(shot["azimuth"])))
	# —— 5) 再绕"水平且垂直于它"的轴抬起 elev ——
	# 【为什么用 dir_h × UP 这根轴】绕轴 a 转 +φ 时，dir_h 的瞬时导数 = a × dir_h。
	#   取 a = dir_h × UP，则 a × dir_h = UP → dir_h 朝 +Y 抬起，
	#   于是"正角 = 相机更高 = 俯视"，与分镜表里的语义一致。
	var elev_axis := dir_h.cross(Vector3.UP)
	elev_axis = elev_axis.normalized() if elev_axis.length() > 0.001 else Vector3.RIGHT
	var dir := dir_h.rotated(elev_axis, deg_to_rad(float(shot["elev"])))

	var pos := pivot + dir * float(shot["dist"])
	return {"pos": pos, "look": pivot, "fov": float(shot["fov"])}


## 取某演员的"胸口"世界坐标（演员可能已失效 → 退回"原点上方"的占位点，避免崩）。
## ⚠️ 形参**故意不加 `: Node3D` 类型注解**：一旦带注解，GDScript 会在传参绑定阶段就拒绝
##    freed 对象（抛 "previously freed … is not a subclass of the expected argument class"），
##    函数体里这句 is_instance_valid 守卫就永远跑不到 —— 文档承诺的"失效守卫"会变成摆设。
##    调用方也应先自行 is_instance_valid 判断（见 _compute_shot_pose），这里只是第二道防线。
func _chest(actor, height: float) -> Vector3:
	if actor == null or not is_instance_valid(actor):
		return Vector3.UP * height
	return (actor as Node3D).global_position + Vector3.UP * height


# ============================================================
# 遮幅黑边（自建 CanvasLayer，layer=0：3D 世界之上、HUD 之下）
# ============================================================

func _build_overlay() -> void:
	# ★ layer = 0：HUD 的 CanvasLayer 在 hud.gd 里显式设为 **layer = 10**，所以遮幅(0)压在 HUD(10) 之下
	#   （不挡血条），但仍盖在 3D 世界之上（Godot 的 canvas 层整体在 3D 之后合成）。
	_layer = CanvasLayer.new()
	_layer.name = "CinematicOverlay"
	_layer.layer = 0
	add_child(_layer)

	_bar_top = _make_bar("BarTop")
	_bar_bottom = _make_bar("BarBottom")
	# 初始收起（高度 0）。
	_layout_bars()
	# ★ 视口尺寸变化时重算黑边尺寸：不然拉伸窗口后黑边就"变高变矮"或对不上底边。
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_layout_bars)


func _make_bar(node_name: String) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = node_name
	bar.color = LETTERBOX_COLOR
	# 遮幅只是画面装饰，不能吃掉鼠标点击（否则游戏内第一次点击会被它拦下）。
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	_layer.add_child(bar)
	return bar


## 按当前进度 _bar_k 与视口尺寸，重算两条黑边的位置与大小。
func _layout_bars() -> void:
	if _bar_top == null or _bar_bottom == null:
		return
	var vp := get_viewport()
	var vp_size := Vector2(1152.0, 648.0)          # 兜底：拿不到视口时给个常规分辨率
	if vp != null:
		vp_size = vp.get_visible_rect().size
		if vp_size.y < 1.0:
			vp_size.y = 648.0
		if vp_size.x < 1.0:
			vp_size.x = 1152.0
	var bar_h := vp_size.y * LETTERBOX_RATIO * _bar_k
	_bar_top.position = Vector2(0.0, 0.0)
	_bar_top.size = Vector2(vp_size.x, bar_h)
	_bar_bottom.position = Vector2(0.0, vp_size.y - bar_h)
	_bar_bottom.size = Vector2(vp_size.x, bar_h)


## 遮幅进度写入口（由补间逐帧调用）。同时把黑边排布刷新到对应高度。
func _set_bar_k(k: float) -> void:
	_bar_k = clampf(k, 0.0, 1.0)
	_layout_bars()


func _show_letterbox() -> void:
	_bar_kill_tween()
	_bar_top.visible = true
	_bar_bottom.visible = true
	# ★ set_ignore_time_scale(true)：滑入用真实时间 —— 处决后半段可能还在慢动作里，
	#   若用缩放时间，遮幅会"慢吞吞地"滑进来，节奏就散了。
	_bar_tween = create_tween()
	_bar_tween.set_ignore_time_scale(true)
	_bar_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_method(_set_bar_k, _bar_k, 1.0, LETTERBOX_IN_TIME)


func _hide_letterbox() -> void:
	_bar_kill_tween()
	if _bar_k <= 0.0:
		_bar_top.visible = false
		_bar_bottom.visible = false
		return
	_bar_tween = create_tween()
	_bar_tween.set_ignore_time_scale(true)
	_bar_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_bar_tween.tween_method(_set_bar_k, _bar_k, 0.0, LETTERBOX_OUT_TIME)
	# 滑出结束后把节点藏起来（不发 Update，省一点绘制）。
	_bar_tween.tween_callback(_on_letterbox_hidden)


func _on_letterbox_hidden() -> void:
	if _bar_top != null:
		_bar_top.visible = false
	if _bar_bottom != null:
		_bar_bottom.visible = false


func _bar_kill_tween() -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = null
