extends SceneTree
## ============================================================
## 一次性工具：生成 wolf.tscn（狼敌人场景）与 wolf_test.tscn（狼测试关卡）
## ============================================================
## 【为什么用脚本生成，而不是手写 .tscn 文本】
##   本项目的踩坑记录：手写 .tscn 时，只要 ext_resource 的 id、或某个 @export 的
##   类型化数组序列化写法有一处不对，Godot **不报错**，只会安静地把那个字段丢掉 ——
##   你会得到一个"看起来对、属性却全是默认值"的场景，排查起来极其痛苦。
##   ResourceSaver 写出来的格式一定是引擎自己认得的，所以场景也走"代码生成"。
##
## 【做法】instantiate 既有的 enemy.tscn / forest_clearing.tscn → 覆盖需要的 @export
##   → PackedScene.pack() → ResourceSaver.save()。
##   ⚠️ 本脚本必须**跑场景**（不是 --script）：enemy.gd 里引用了 autoload `EventBus`，
##      而 --script 模式下 autoload 不注册 → 加载 enemy.tscn 时会编译失败。
##      故本工具自带一个 .tscn 壳（gen_wolf_scenes.tscn），用跑场景的方式执行。
##
## 【已有的 .tscn 会被覆盖】想改数值请直接在编辑器里打开生成的 .tscn 编辑，
##   不要再跑本脚本 —— 本脚本只是"从零造一份正确的骨架"。
## ============================================================

const ENEMY_TSCN := "res://scenes/enemy/enemy.tscn"
const FOREST_TSCN := "res://maps/forest_clearing.tscn"
const WOLF_GLB := "res://assets/enemies/wolf_01/wolf_rigged.glb"
const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const WOLF_TEST_TSCN := "res://maps/wolf_test.tscn"


func _initialize() -> void:
	var ok := true
	ok = _gen_wolf() and ok
	ok = _gen_wolf_test() and ok
	if ok:
		print("[gen_wolf_scenes] 全部生成完成")
	else:
		push_error("[gen_wolf_scenes] 有步骤失败，请看上面的错误")
	quit(0 if ok else 1)


## 生成 wolf.tscn：以 enemy.tscn 为模板，覆盖全部物种相关 export。
func _gen_wolf() -> bool:
	var src := load(ENEMY_TSCN) as PackedScene
	if src == null:
		push_error("加载不到模板 %s" % ENEMY_TSCN)
		return false

	var root := src.instantiate()
	root.name = "EnemyWolf"

	# ---- 顶层 export（enemy.gd）----
	root.set("enemy_id", "wolf")
	root.set("enemy_model_path", WOLF_GLB)
	root.set("enemy_weapon_path", "")      # ★ 空串 = 无武器（徒手撕咬）
	root.set("drop_item_id", "")           # ★ 空串 = 不掉落（不参与 q_guards）
	root.set("drop_item_amount", 1)
	# ★ 3.4（原 4.2）：动画倍速根修（方案 β）之后实播倍速 ≡ speed_scale，
	#   4.2 会给出 3.58 步/秒（读感是模糊的"刨地"）；3.4 约 2.90 步/秒，
	#   落在真实狼小跑 2–3 Hz。★ 必须与 scenes/enemy/wolf.tscn 保持一致 ——
	#   否则重跑本生成器会把 move_speed 改回 4.2，verify_enemy_wolf 立刻变红。
	root.set("move_speed", 3.4)
	root.set("attack_damage", 12)
	root.set("parry_poise_percent", 50.0)  # 2 次完美格挡失衡
	root.set("aggro_range", 13.0)
	root.set("attack_range", 2.0)
	root.set("model_target_height", 1.20)
	root.set("walk_natural_speed", 1.1724) # 实测值（probe_stride_wolf）
	root.set("walk_max_speed_scale", 3.8)  # ★ 旧注释「保证 4.2/1.1724=3.58 不触发 clamp」已被证伪：
	#   它只约束**单帧** want=clamp(spd/1.1724, 0.4, 3.8)，而旧代码的实播倍速是
	#   speed_scale × 被 play() 冻结的 custom，稳态可达 3.58×1.74≈6.2 —— 完全越过了这个"上限"。
	#   数值 3.8 保持不动（改它会翻别的断言）；倍速真源改由 enemy.gd 的 β 修法保证。
	#   ★ 加 Run 之后 Walk 只在 want < run_switch_speed_scale(2.40) 时才被选中 ⇒ 3.8 已成死代码，
	#     但数值仍安全、且 verify_enemy_wolf.gd 把它钉在 3.8 ⇒ **不动**。
	# ---- ★ Run 段参数（T08）----
	# ⚠️ 本行必须与 scenes/enemy/wolf.tscn 里的 run_natural_speed 手工同步：
	#   两边各写一份（生成器 + 场景），是因为 .tscn 的既有数值允许在编辑器里手工微调，
	#   而重跑本生成器会**覆盖** .tscn（见文件头"已有的 .tscn 会被覆盖"）。
	#   若哪天只改了一边，verify_enemy_wolf.gd 的 run_natural_speed 断言会立刻变红。
	root.set("run_natural_speed", 2.7104)  # ★v4 实测值（probe_run_ground 口径；解析 2.7132）
	root.set("corpse_linger_time", 1.2)
	root.set("hitbox_size", Vector3(1.4, 1.1, 1.5))
	root.set("hitbox_offset", Vector3(0.0, 0.65, -1.2))

	# ---- 子组件 ----
	var health := root.get_node("Health")
	if health != null:
		health.set("max_hp", 70)
	var poise := root.get_node("Poise")
	if poise != null:
		poise.set("max_poise", 100.0)
		poise.set("break_time", 3.0)

	# ---- 碰撞胶囊：狼体型独立小胶囊（不是守卫那根 2.1m 大胶囊）----
	var col := root.get_node("CollisionShape3D")
	if col != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45
		cap.height = 0.95          # 总高（含两端半球）；须 >= 2*radius
		col.shape = cap
		col.position = Vector3(0.0, 0.5, 0.0)

	return _save_packed(root, WOLF_TSCN)


## 生成 wolf_test.tscn：复用森林环境，只把 enemy_scene 覆盖为 wolf.tscn。
func _gen_wolf_test() -> bool:
	var src := load(FOREST_TSCN) as PackedScene
	if src == null:
		push_error("加载不到模板 %s" % FOREST_TSCN)
		return false

	var wolf := load(WOLF_TSCN) as PackedScene
	if wolf == null:
		push_error("wolf.tscn 尚未生成，无法生成 wolf_test.tscn")
		return false

	var root := src.instantiate()
	root.name = "WolfTest"
	root.set("enemy_scene", wolf)

	return _save_packed(root, WOLF_TEST_TSCN)


## 把实例化的节点树打包写出，成功返回 true。
func _save_packed(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var perr := packed.pack(root)
	if perr != OK:
		push_error("pack 失败（错误码 %d）：%s" % [perr, path])
		root.free()
		return false
	var serr := ResourceSaver.save(packed, path)
	if serr != OK:
		push_error("写出 %s 失败（错误码 %d）" % [path, serr])
		root.free()
		return false
	print("[gen_wolf_scenes] 已写出 %s" % path)
	root.free()
	return true
