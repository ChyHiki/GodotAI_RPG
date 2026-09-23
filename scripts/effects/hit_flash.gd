class_name HitFlash
extends Node3D
## ============================================================
## 一次性"打击闪光"特效（纯原语，零美术资源）
## ============================================================
## 【长什么样】三个东西叠在一起，0.3 秒左右放大 + 淡出，然后自毁：
##   · Core  核心闪光：一个小球，快速放大（"亮一下"）
##   · Ring  扩散光环：一个扁平圆环，向外扩成冲击波（"弹开"的感觉）
##   · Light 点光源：短促的彩色补光，把周围角色也照亮（"真的有光"）
##
## 【为什么不用粒子 / 贴图】
##   本作是纯原语低模风格（角色以外的美术都是 BoxMesh/CapsuleMesh 拼的），
##   程序化网格最一致，也不需要引入 .png 与导入配置。
##   以后要做正式美术特效再换成 GPUParticles3D + 贴图即可（调用方接口不变）。
##
## 【怎么用】
##   HitFlash.spawn(父节点, 世界坐标, 颜色, 半径, 时长, 光强)
##   节点是 top_level 的（不跟随父节点的旋转/缩放），所以直接传世界坐标。
##   返回的实例不用管，播完自己 queue_free()。
## ============================================================

## 生成并播放一次闪光。
## @param parent       挂到谁下面（一般传触发者本身；只影响生命周期，不影响位置）
## @param at           世界坐标（闪光中心）
## @param color        主色（完美格挡 = 黄；处决 = 更亮的黄）
## @param radius       基准半径(米)：环的最大半径 ≈ radius×2.6
## @param duration     总时长(秒)
## @param light_energy 点光源初始强度（0 = 不要光源，纯做运动特效时可用）
static func spawn(parent: Node, at: Vector3, color: Color = Color(1.0, 0.85, 0.25),
		radius: float = 0.9, duration: float = 0.34, light_energy: float = 7.0) -> HitFlash:
	var fx := HitFlash.new()
	fx._color = color
	fx._radius = radius
	fx._duration = duration
	fx._light_energy = light_energy
	parent.add_child(fx)              # 先进树 → 子节点在 _ready 里建好
	# 【顺序讲究】top_level 要在进树之后再开：进树前设可能不生效（引擎要重新计算全局变换）
	fx.top_level = true               # 不跟随父节点的旋转/缩放/落地压缩
	fx.global_position = at           # 进树后才能安全写"世界坐标"
	fx._animate()                     # 子节点建好了，起动画
	return fx

## 主色
var _color: Color = Color(1.0, 0.85, 0.25)
## 基准半径(米)
var _radius: float = 0.9
## 总时长(秒)
var _duration: float = 0.34
## 点光源初始强度
var _light_energy: float = 7.0
## 所有自发光材质（淡出时要逐个改）
var _mats: Array[StandardMaterial3D] = []
var _light: OmniLight3D = null


func _ready() -> void:
	_build_core()
	_build_ring()
	if _light_energy > 0.0:
		_build_light()


## 核心闪光：一个小球。
func _build_core() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.22 * _radius
	mesh.height = 0.44 * _radius          # SphereMesh 的 height 是总高(=半径×2)，不是半径
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.name = "Core"
	mi.mesh = mesh
	mi.material_override = _make_glow_mat(_color, 1.0)
	add_child(mi)


## 扩散光环：一个躺在水平面上的圆环（像冲击波那样向外推）。
## 【为什么用圆环而不是第二个球】球放大只是"变大"，圆环放大读起来像"炸开一圈"。
func _build_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.30 * _radius
	mesh.outer_radius = 0.44 * _radius
	mesh.rings = 20                       # 沿环一周的分段
	mesh.ring_segments = 8                # 管截面的分段
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = mesh
	mi.material_override = _make_glow_mat(_color, 0.8)
	add_child(mi)


## 点光源：短促的彩色补光。没有它，闪光只是"贴在屏幕上的亮片"，
## 有了它周围的地面/角色会被照亮，才像真的爆了一下光。
func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "FlashLight"
	_light.light_color = _color
	_light.light_energy = _light_energy
	_light.omni_range = 4.5 * _radius
	_light.shadow_enabled = false         # 短促闪光，不值得为它算阴影
	add_child(_light)


## 造一个"发光"材质：不受光照影响(unshaded) + 加法混合，所以亮度可以超过 1 白到发光。
func _make_glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 不受场景光照影响
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD            # 加法混合 → 叠在背景上"发亮"
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED              # 双面可见(环的内侧也看得到)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy * 4.0
	_mats.append(mat)
	return mat


## 播放：整体从 0.35 倍放大到 2.6 倍，同时把"亮度"和"透明度"淡到 0，最后自毁。
## 【为什么 alhpa 和 emission 都要淡】只淡 alpha 的话，自发光项仍然会亮着不走样；
##   两个一起淡才干净（加法混合下 alpha 与自发光都会被乘进去）。
func _animate() -> void:
	var tw := create_tween()
	tw.set_parallel(true)                                   # 下面的动画同时进行
	tw.tween_property(self, "scale", Vector3.ONE * 2.6, _duration) \
		.from(Vector3.ONE * 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for mat in _mats:
		var m := mat                                        # 捕获当前这一个材质（lambda 按值捕获）
		tw.tween_method(
			func(a: float) -> void:
				m.albedo_color.a = a
				m.emission_energy_multiplier = a * 4.0,
			1.0, 0.0, _duration)
	if _light != null:
		tw.tween_property(_light, "light_energy", 0.0, _duration)
	# chain() = 等上面这一批全部结束，再执行下一个：销毁自己
	tw.chain().tween_callback(queue_free)
