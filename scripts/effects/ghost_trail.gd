extends Node3D
class_name GhostTrail
## ============================================================
## GhostTrail —— 完美闪避留下的"角色残影"（一道青蓝色的虚影拖尾）
## ============================================================
## 【它是什么 / 什么时候出现】
##   完美闪避（敌人挥击判定盒扫到你的那一瞬间，你正好在闪避无敌帧里）时，
##   在玩家身后拖出 N 个**定格的角色快照**，各自淡出后自毁。
##   —— 和 HitFlash（一亮就散）、LockMarker（常驻跟随）一样，都是"纯原语、零美术资源"的做法，
##      区别只在这一个要**复制角色当前的姿势**，是三者里唯一"照着活物克隆"的。
##
## 【节点结构】一个虚影 = 两层：
##     GhostTrail(本脚本，空容器，负责定位/淡出/自毁)
##       └─ body(VisualPivot 的裸拷贝，只带姿势，transform 归零)
##   为什么要多这一层容器：拷贝出来的东西**没有脚本**，若不加壳，外部就"按类型找得到虚影"
##   这件事根本无从谈起（自动测试靠数 GhostTrail 来钉"该生成时生成了、淡出后清干净了"）。
##   ⚠ 踩过的坑：最初直接把裸拷贝挂进场景，结果 `_count_ghost_trail()` 永远返回 0 ——
##     表现是"画面里明明有虚影，断言却说没有"。
##
## 【核心难点：怎么把"当前这一帧的姿势"冻下来】
##   直接 `visual.duplicate()` 只能复制**节点属性**，而 Skeleton3D 的骨骼姿势是存在
##   节点内部状态里的（不是可序列化属性）→ 复制出来的骨架会回到**绑定姿势(T-pose)**，
##   虚影就成了一群"摊开手脚的假人"。所以复制完必须**逐根骨骼把姿势搬过去**
##   （见 _copy_bone_poses）—— 这一步是整份实现里唯一"不写就绝对不对"的地方。
##   姿势搬完还要**把复制体里的 AnimationPlayer 全部删掉**：
##   否则它会继续驱动新骨架，虚影就跟着本体一起做后续动作，看不出是"快照"。
##
## 【为什么用 material_override 而不是换 Skin】
##   同一份 MeshInstance3D 的蒙皮资源是共享的，改材质最省：给每个 MeshInstance3D
##   盖一份自己的自发光青蓝材质（透明 + 不受光 + 叠加混合），就能得到"残影"的观感。
##   ⚠ 每个虚影要**独立的材质实例** —— 三个虚影各自淡出的进度不同，
##     共用一份材质会让它们同时变透明（看起来就是一个虚影忽明忽暗）。
##
## 【和 HitFlash 的相同约束】跟事件实时触发的视觉**只能引擎内做**：
##   云侧的 3D/视频生成只产离线素材，做不了"玩家这一刻正好在哪、什么姿势"。
## ============================================================

## 头/尾虚影的起始不透明度。
## 【为什么不能是 1.0】虚影用的是**叠加混合**（ADD，见 _paint），而 ADD 是"亮度相加"：
##   三个虚影只要有一点重叠，1.0 + 1.0 立刻被裁剪到纯白 —— 观感就成了"一团发光的雾"，
##   而不是"三道能看出手脚的残影"。压到 0.82 起步、尾端 0.42，重叠处才留得住轮廓。
##   （2026-09-20 抓帧对比调出来的：改前触发瞬间整屏白成一团，改后同帧能数出三道残影）
const ALPHA_HEAD := 0.82
const ALPHA_TAIL := 0.42

## 生成一道虚影拖尾。
## @param host      挂载点（一般是玩家自己；虚影跟着它一起被销毁）
## @param visual    要复制的可视子树（一般是玩家身上的 VisualPivot）
## @param dir       本次闪避的位移方向（虚影沿它的**反方向**拖尾，落在"刚经过的地方"）
## @param color     虚影颜色（完美闪避用青蓝，与完美格挡的金色区分）
## @param count     虚影个数（3 个就够连成一道拖尾；再多肉眼也分不出来）
## @param life      单个虚影的淡出时长(秒)
static func burst(host: Node, visual: Node3D, dir: Vector3, color: Color,
		count: int = 3, life: float = 0.45) -> void:
	if host == null or visual == null or not is_instance_valid(visual):
		return
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	d = d.normalized()
	var n := maxi(1, count)
	for i in n:
		# 越靠后的虚影离本体越远、越淡 —— 0 号紧贴本体（刚闪出去的那一格）
		var k := float(i) / float(maxi(1, n - 1)) if n > 1 else 0.0
		var a := lerpf(ALPHA_HEAD, ALPHA_TAIL, k)
		var body := _make_body(visual, color, a)
		if body == null:
			continue
		# ★ 结构：GhostTrail(容器) ── body(VisualPivot 的拷贝，只带姿势)
		#   为什么要有这层容器：拷贝出来的东西是**没有脚本的裸 Node3D**，
		#   直接数"场景里有多少个 GhostTrail"会永远数到 0（自动测试就踩过这一下）。
		#   容器还顺带承担两件事：自毁的生命周期、以及被外部按类型检索。
		var ghost := GhostTrail.new()
		host.add_child(ghost)
		# ★★ 必须 top_level：虚影是**留在原地**的快照，不能跟着本体继续跑。
		#   挂到 host（玩家）名下只是为了"玩家被销毁时一起消失"；
		#   不脱钩的话变换会继承自玩家 → 虚影一路跟着玩家移动，完全不像残影。
		ghost.top_level = true
		ghost.global_transform = visual.global_transform
		# 沿来路依次后退。首尾拉开到 1.05m：太挤会糊成一团（同上"叠加混合"的原因）
		ghost.global_position += -d * (0.15 + 0.45 * k)
		body.transform = Transform3D.IDENTITY             # 位置/朝向由容器给，拷贝体只保留姿势
		ghost.add_child(body)
		_fade_out(ghost, color, life + 0.12 * k, a)


## 复制一份"定格的外观"（残影的**身体**），并把它的材质全部换成残影材质。
## 返回的是 VisualPivot 的裸拷贝，外面还会被套进一个 GhostTrail 容器（见 burst）。
static func _make_body(visual: Node3D, color: Color, alpha: float) -> Node3D:
	var dup := visual.duplicate() as Node3D
	if dup == null:
		return null
	_strip_non_visual(dup)                    # 去掉动画器与碰撞体（见函数注释，这一步不能省）
	_copy_bone_poses(visual, dup)             # 再把当前这一帧的骨骼姿势搬过去（关键步骤）
	_paint(dup, color, alpha)
	return dup


## 剥掉复制体里所有"不是外观"的东西：AnimationPlayer 与碰撞体。
## 【为什么必须剥】
##   ① AnimationPlayer：不剥的话它会继续驱动新骨架，虚影跟着本体做后续动作，
##      完全看不出是"快照"。（不能只 stop()：任何一次 play 都可能让它复活，直接删干净。）
##   ② Area3D / CollisionShape3D：玩家的攻击命中盒 AttackHitbox **就挂在 VisualPivot 下**
##      （见 player.gd 的 _create_attack_hitbox）→ 整棵子树一复制，
##      每个虚影都会自带一个"幽灵命中盒"。虽然复制体 monitoring=false 不会真的打人，
##      但这属于"凭运气不出事"：改成别的检测方式、或哪天有人打开了它，就会莫名其妙多出伤害。
static func _strip_non_visual(root: Node) -> void:
	var doomed: Array[Node] = []
	for klass in ["AnimationPlayer", "CollisionObject3D", "CollisionShape3D"]:
		_collect_of_class(root, klass, doomed)
	for n in doomed:
		if not is_instance_valid(n) or n == root:
			continue
		var p := n.get_parent()
		if p != null:
			p.remove_child(n)
		n.free()                  # 已经脱离父节点，free() 是确定性的（queue_free 要等帧末）


## 把源骨架**当前这一帧**的姿势逐根搬到目标骨架上。
## 【为什么必须显式搬】Skeleton3D 的骨骼姿势存在节点内部状态里，duplicate() 不会带走 →
##   不搬的话虚影显示的是绑定姿势（T-pose），看起来是"另一个人"而不是"刚才的你"。
## 【为什么只搬 position/rotation/scale】rest 变换两边完全相同（同一份模型资源），
##   所以只要局部姿势一致，算出来的全局姿势就一定一致，不用碰 rest。
static func _copy_bone_poses(src_root: Node, dst_root: Node) -> void:
	var src_skels: Array[Node] = []
	var dst_skels: Array[Node] = []
	_collect_of_class(src_root, "Skeleton3D", src_skels)
	_collect_of_class(dst_root, "Skeleton3D", dst_skels)
	for i in mini(src_skels.size(), dst_skels.size()):
		var s := src_skels[i] as Skeleton3D
		var t := dst_skels[i] as Skeleton3D
		if s == null or t == null or s.get_bone_count() != t.get_bone_count():
			continue
		for b in s.get_bone_count():
			t.set_bone_pose_position(b, s.get_bone_pose_position(b))
			t.set_bone_pose_rotation(b, s.get_bone_pose_rotation(b))
			t.set_bone_pose_scale(b, s.get_bone_pose_scale(b))


## 给复制体里的每个 MeshInstance3D 盖一份独立的自发光半透明材质。
static func _paint(root: Node, color: Color, alpha: float) -> void:
	var meshes: Array[Node] = []
	_collect_of_class(root, "MeshInstance3D", meshes)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, alpha)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 不受光 → 像"光做的人"
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD            # 叠加：亮处更亮，暗处透明
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED              # 两面都画，剪影更完整
		mat.no_depth_test = true                                  # 虚影应"盖"在场景上，不被自己挡
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 让虚影一边淡出一边整体轻微上浮（一点点"灵魂往上飘"的味道），结束后自毁。
static func _fade_out(ghost: Node3D, color: Color, life: float, alpha: float) -> void:
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	# 材质是逐个 MeshInstance3D 的 material_override，用 tween_method 统一推进 alpha
	tw.tween_method(func(a: float) -> void: _set_alpha(ghost, color, a), alpha, 0.0, life)
	tw.tween_property(ghost, "position:y", ghost.position.y + 0.12, life)
	tw.chain().tween_callback(ghost.queue_free)


static func _set_alpha(ghost: Node3D, color: Color, a: float) -> void:
	if not is_instance_valid(ghost):
		return
	# ⚠ 这里**不复用 _paint()**：_paint 会 new 一份新材质，每帧 new 一次会把内存打爆。
	#   只改已有材质的 alpha 通道即可。
	var meshes: Array[Node] = []
	_collect_of_class(ghost, "MeshInstance3D", meshes)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(color.r, color.g, color.b, maxf(0.0, a))


## 递归收集某一类节点（Godot 没有内置的"按类型找全部子节点"）。
static func _collect_of_class(node: Node, klass: String, out: Array[Node]) -> void:
	if node.is_class(klass):
		out.append(node)
	for c in node.get_children():
		_collect_of_class(c, klass, out)
