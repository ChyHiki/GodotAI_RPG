extends Node
## ============================================================
## QA 独立验证 · 负向断言（工程师只验了"正向会发生什么"，这里补"没发生什么"）
## ============================================================
## 运行（★ 跑场景，不是 --script；原因见 verify_wolf_hitbox.gd 顶部）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\GodotProject\first-game \
##       res://tools/verify_qa_negative.tscn
##   退出码 0 = 通过，1 = 有断言失败。
##
## 【本探针独立于工程师的 5 个验证器编写，用于证伪以下"应该不发生"的行为】
##   A. 狼 drop_item_id==""  → EventBus.item_collected 必须**一发都不发**
##   B. 守卫默认 drop_item_id=="guard_insignia" → 恰好发**一次** ("guard_insignia", 1)
##   C. 狼 enemy_weapon_path=="" → 子树里**不得**出现 WeaponSocket / BoneAttachment3D / _weapon
##   D. 守卫 enemy.tscn 未覆盖 export → 实例上的命中盒/尸体时序/掉落 走默认值
##      （默认值必须与"改造前硬编码字面量"逐字相同）
## ============================================================

const WOLF_TSCN := "res://scenes/enemy/wolf.tscn"
const BRUTE_TSCN := "res://scenes/enemy/enemy.tscn"

var _fail := 0

## 记录 EventBus 收到的信号（在 _ready 里连接，整个探针生命周期有效）
var _items: Array = []          # [ [item_id, amount], ... ]
var _deaths: Array = []         # [ enemy_id, ... ]


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("  ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _on_item(item_id: String, amount: int) -> void:
	_items.append([item_id, amount])


func _on_died(enemy_id: String) -> void:
	_deaths.append(enemy_id)


func _ready() -> void:
	print("=== QA 负向断言验证 ===")
	EventBus.item_collected.connect(_on_item)
	EventBus.enemy_died.connect(_on_died)

	# ---- 地面：让尸体有地方站/躺，避免无谓的下坠噪声 ----
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(40.0, 1.0, 40.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	await _case_wolf()
	await _case_brute()

	# ---------- 结论 ----------
	print("")
	if _fail == 0:
		print("结论：负向断言全部通过 ✓")
		get_tree().quit(0)
	else:
		print("结论：%d 项未通过 ✗" % _fail)
		get_tree().quit(1)


## A + C：狼不掉落、无武器挂点
func _case_wolf() -> void:
	print("\n[A/C] 狼：不掉落 + 无武器挂点")
	var wolf := (load(WOLF_TSCN) as PackedScene).instantiate() as EnemyBrute
	wolf.position = Vector3(0, 0.1, 0)
	add_child(wolf)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- C：树结构扫描（不看 _weapon_socket 变量，直接找节点，避免"变量对但节点在"）---
	var socket_node := _find_named(wolf, "WeaponSocket")
	var any_attach := _find_bone_attachment(wolf)
	_check(socket_node == null, "子树里没有名为 WeaponSocket 的节点")
	_check(any_attach == null, "子树里没有任何 BoneAttachment3D")
	_check(wolf.get("_weapon") == null, "_weapon == null（狼无武器）")
	_check(wolf.get("_weapon_socket") == null, "_weapon_socket == null")

	# --- A：死亡掉落必须静默 ---
	_items.clear()
	_deaths.clear()
	wolf._die()
	await get_tree().process_frame
	_check(_items.is_empty(),
		"★ 狼死亡**没有**发出任何 item_collected", "收到 %d 条：%s" % [_items.size(), str(_items)])
	_check(_deaths.size() == 1 and _deaths[0] == "wolf",
		"狼死亡恰好发出一次 enemy_died(\"wolf\")", str(_deaths))

	if is_instance_valid(wolf):
		wolf.free()


## B + D：守卫默认掉落一次徽记 + 默认几何逐字核对
func _case_brute() -> void:
	print("\n[B/D] 守卫：默认掉落一次徽记 + 默认 export 逐字核对")
	var brute := (load(BRUTE_TSCN) as PackedScene).instantiate() as EnemyBrute
	brute.position = Vector3(0, 0.1, 0)
	add_child(brute)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- D：实例上的最终取值（= 默认值，因为 enemy.tscn 不覆盖）---
	_check(brute.get("enemy_id") == "brute", "enemy_id == \"brute\"", str(brute.get("enemy_id")))
	_check(brute.get("drop_item_id") == "guard_insignia", "drop_item_id == \"guard_insignia\"")
	_check(int(brute.get("drop_item_amount")) == 1, "drop_item_amount == 1")
	var hs: Vector3 = brute.get("hitbox_size")
	var ho: Vector3 = brute.get("hitbox_offset")
	_check(hs.is_equal_approx(Vector3(2.2, 1.5, 1.5)),
		"hitbox_size == (2.2, 1.5, 1.5)（改造前原值）", str(hs))
	_check(ho.is_equal_approx(Vector3(0.0, 1.15, -1.7)),
		"hitbox_offset == (0, 1.15, -1.7)（改造前原值）", str(ho))
	_check(absf(float(brute.get("corpse_linger_time")) - 1.2) < 0.0001,
		"corpse_linger_time == 1.2（改造前原值）", str(brute.get("corpse_linger_time")))
	# 命中盒真节点上的几何也应与 export 一致
	var hb: Node = brute.get("_hitbox")
	if hb != null:
		var shape_node: Node = hb.get_node_or_null("HitboxShape")
		_check(shape_node != null and (shape_node.shape as BoxShape3D).size.is_equal_approx(Vector3(2.2, 1.5, 1.5)),
			"守卫命中盒实际尺寸 = (2.2, 1.5, 1.5)")
		_check(shape_node != null and shape_node.position.is_equal_approx(Vector3(0.0, 1.15, -1.7)),
			"守卫命中盒实际偏移 = (0, 1.15, -1.7)")
	# 守卫应有武器挂点（与狼形成对照）
	_check(brute.get("_weapon_socket") != null, "守卫**有** WeaponSocket（对照）")
	_check(_find_named(brute, "WeaponSocket") != null, "守卫子树里能找到 WeaponSocket 节点")

	# --- B：死亡掉落恰好一次 ---
	_items.clear()
	_deaths.clear()
	brute._die()
	await get_tree().process_frame
	_check(_items.size() == 1, "★ 守卫死亡发出 item_collected 的次数 = 1", "实际 %d 次" % _items.size())
	if _items.size() >= 1:
		_check(_items[0][0] == "guard_insignia" and int(_items[0][1]) == 1,
			"掉落物 = (\"guard_insignia\", 1)", str(_items[0]))
	_check(_deaths.size() == 1 and _deaths[0] == "brute",
		"守卫死亡恰好发出一次 enemy_died(\"brute\")", str(_deaths))

	if is_instance_valid(brute):
		brute.free()


# ------------------------------------------------------------------
# 工具
# ------------------------------------------------------------------

func _find_named(root: Node, want: String) -> Node:
	if root.name == want:
		return root
	for c in root.get_children():
		var f := _find_named(c, want)
		if f != null:
			return f
	return null


func _find_bone_attachment(root: Node) -> BoneAttachment3D:
	if root is BoneAttachment3D:
		return root as BoneAttachment3D
	for c in root.get_children():
		var f := _find_bone_attachment(c)
		if f != null:
			return f
	return null
