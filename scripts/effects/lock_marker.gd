class_name LockMarker
extends Node3D
## ============================================================
## 锁定标记：贴在敌人"身体中心"的一颗白色亮点（纯原语，零美术资源）
## ============================================================
## 【要解决的问题】锁定敌人会同时改变面相/位移动画/镜头/移速，但**画面上没有任何
##   东西指出"我锁的是哪一只"**。怪一多（或者锁定目标被自动重找换了一只）玩家只能靠
##   镜头角度去猜。于是在敌人身体中心放一颗白色亮点：位置稳定、始终可见、随敌人移动。
##
## 【为什么挂成敌人的子节点】挂上去之后"跟随移动"是引擎免费做的，不需要每帧写
##   global_position；敌人被释放时标记也跟着消失，不会留下悬空节点。
##   ⚠ 挂点是敌人的**根节点**（脚底 y=0）而不是 VisualPivot：
##     根节点不旋转；pivot 在挨打时 position.y 会上下弹、失衡时会左右摇，
##     把标记挂到 pivot 上会跟着一起抖，锁定点看起来就"不稳"了。
##
## 【为什么必须关掉深度测试】亮点在**身体内部**。不关深度测试的话它会被躯干网格挡死，
##   等于什么都看不见（这是本效果唯一容易踩的坑）。关掉后它总画在最上层 ——
##   与 UI 准星同理，正是"锁定标记"该有的观感。代价是被墙挡住时也能看到，
##   但锁定距离只有 lock_on_range(9m)，实战里可接受。
##
## 【为什么用加法混合】加法混合叠在角色身上会"发亮"，亮度可以超过纯白，
##   比一个普通不透明小球更像"亮点"；与项目既有的 HitFlash 同一套做法。
##
## 【怎么用】
##   LockMarker.attach(敌人节点, 身体中心比例, 半径)
##   返回的实例由调用方持有；解除锁定/敌人死亡时由调用方 free()。
##   标记自己也会在目标失效时自毁（双保险，见 _process）。
## ============================================================

## 目标没有 model_target_height 时的兜底站高(米)
const DEFAULT_BODY_HEIGHT := 1.8
## 脉动频率(Hz)：静止的亮点容易被误看成"卡住的白点"
const PULSE_HZ := 3.2
## 脉动幅度：缩放 = 1 ± 这个值
const PULSE_AMOUNT := 0.16


## 生成并挂上一个锁定标记。
## @param target     锁定的敌人（挂成它的子节点）
## @param body_ratio 标记高度 = 敌人站高 × 这个比例（0.5 ≈ 身体中心）
## @param radius     亮点半径(米)
## @return 标记实例；target 无效时返回 null
static func attach(target: Node3D, body_ratio: float = 0.5,
		radius: float = 0.16) -> LockMarker:
	if not is_instance_valid(target):
		return null
	var m := LockMarker.new()
	m.name = "LockMarker"
	m._target = target
	m._radius = maxf(0.01, radius)
	# 本地坐标 = 敌人根节点上方 body_ratio×站高 处。脚底在 y=0（模型已对齐），
	# 所以这个高度就是"从脚往上算的身体中心"。
	m.position = Vector3(0.0, body_height(target) * body_ratio, 0.0)
	target.add_child(m)          # 进树 → _ready 里建网格
	return m


## 取"目标站高(米)"：优先读敌人自己的 model_target_height，没有再用兜底值。
## 【为什么要读敌人的属性而不是写死】不同敌人（2.66 的壮汉 / 以后的小怪）身高差很多，
##   写死一个高度会让小怪身上的标记飘到头顶、大怪身上的陷进肚子。
static func body_height(target: Node3D) -> float:
	if is_instance_valid(target):
		var h: Variant = target.get("model_target_height")
		if (typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT) and float(h) > 0.1:
			return float(h)
	return DEFAULT_BODY_HEIGHT


## 当前跟随的目标（调用方用它判断"要不要重造标记"）。
func get_target() -> Node3D:
	return _target


## 跟随的目标
var _target: Node3D = null
## 亮点半径
var _radius: float = 0.16
## 已累计时间（脉动用）
var _t: float = 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	# 目标没了（敌人被释放）或不值得锁了（死了）→ 自己收掉，不留悬空亮点。
	# 正常情况下玩家侧的 _sync_lock_marker 也会 free 它，这里是双保险。
	if not is_instance_valid(_target) \
			or (_target.has_method("is_alive") and not _target.is_alive()):
		queue_free()
		return
	_t += delta
	scale = Vector3.ONE * (1.0 + PULSE_AMOUNT * sin(_t * TAU * PULSE_HZ))


## 建一个白色发光球。一个球就够 —— 用户要的是"一个白色亮点"，
## 加光环/准星框反而会把它变成另一个东西（要改的话在这里加子节点即可）。
func _build() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = _radius
	mesh.height = _radius * 2.0      # SphereMesh 的 height 是总高(=直径)，不是半径
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.name = "Core"
	mi.mesh = mesh
	mi.material_override = _make_white_glow()
	add_child(mi)


## 白色发光材质：不受光照 + 加法混合 + 关闭深度测试（见文件头说明）。
func _make_white_glow() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 不受场景光照影响
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD            # 加法混合 → 叠在角色上"发亮"
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED              # 双面可见
	mat.no_depth_test = true                                  # ★ 否则被躯干网格挡死
	mat.render_priority = 2                                   # 排在普通不透明物体之后
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 3.0
	return mat
