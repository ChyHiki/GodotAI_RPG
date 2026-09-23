extends Node
## ============================================================
## 对抗性回归探针：验证"鼠标中键点击切换锁定"的行为语义。
## ============================================================
## 为什么单独写一份（而不是复用 m1_autotest.gd）：
##   m1_autotest.gd 是工程师自写的断言，跑它不能算独立验证。本探针**主动证伪**本次
##   "按住 → 点击切换"的行为变更，重点钉住几个最容易出错的点：
##     · 长按中键不得每帧翻转（若误用 is_action_pressed 必挂）
##     · 松开本身不得有任何解锁含义（本次变更的核心）
##     · 范围外点击不得出现"已锁定但无目标"的假状态
##     · 目标销毁/死亡时自动退化或重找，且标记收干净
##     · 不点中键时绝不自动锁定（工程师提到的"每帧重找导致自锁"坑）
##     · 死亡强制解除
##     · 状态不变量：flag == 有效锁定，且"有目标 ⇔ 已锁定"
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       res://tools/autotest/lock_toggle_probe.tscn
## 退出码 0 = 全部通过；1 = 有失败（失败项以 "PROBE FAIL:" 打印，并 push_error）。
##
## 【构造约定】主场景那只真怪会被临时移出 "enemy" 组并静默（否则随机位置会抢锁定、
##   打架会打断断言）；锁定目标一律用另造的被动木桩。
## ============================================================

var failures: Array[String] = []
var _rows: Array[String] = []
var _invariant_violations: int = 0


func _ready() -> void:
	await _run()
	print("")
	print("=== PROBE TABLE ===")
	for r in _rows:
		print(r)
	print("")
	print("=== INVARIANT VIOLATIONS: %d ===" % _invariant_violations)
	print("")
	if failures.is_empty():
		print("PROBE RESULT: ALL PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("PROBE FAIL: " + f)
		print("PROBE RESULT: %d FAILED" % failures.size())
		get_tree().quit(1)


# ------------------------------------------------------------------
# 断言 / 工具
# ------------------------------------------------------------------

func _check(ok: bool, label: String, detail: String = "") -> void:
	var tag := "PASS" if ok else "FAIL"
	_rows.append("[%s] %s%s" % [tag, label, ("  | " + detail) if detail != "" else ""])
	if ok:
		print("PROBE OK: " + label + (("  [" + detail + "]") if detail != "" else ""))
	else:
		failures.append(label)
		print("PROBE FAIL: " + label + (("  [" + detail + "]") if detail != "" else ""))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## 模拟"点击一次鼠标中键"：按下 → 跨过 1 个物理帧（让 just_pressed 被读到）→ 松开 → 再等 2 帧。
func _tap_lock() -> void:
	Input.action_press("lock_on")
	await get_tree().physics_frame
	Input.action_release("lock_on")
	await get_tree().physics_frame
	await get_tree().physics_frame


## 递归数场景树里的 LockMarker（锁定标记是常驻节点，最怕"每帧重造/漏收"）。
func _count_markers(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is LockMarker:
			n += 1
		n += _count_markers(c)
	return n


## 状态不变量：显式开关 _lock_on 与有效锁定一致；"有目标 ⇔ 已锁定"。
func _invariants_hold(player: PlayerCharacter) -> bool:
	var effective: bool = player.is_locked_on()
	var flag: bool = player._lock_on
	var tgt: Node3D = player.get_lock_target()
	return (flag == effective) and ((tgt != null) == effective)


func _check_invariants(player: PlayerCharacter) -> void:
	if not _invariants_hold(player):
		_invariant_violations += 1
		print("PROBE FAIL: 状态不变量被破坏  flag=%s  effective=%s  target=%s"
			% [player._lock_on, player.is_locked_on(), str(player.get_lock_target())])


## 把木桩摆到玩家正前方 dist 米处（水平距离 = dist，用于范围内/外切换）。
func _set_dist(d: Node3D, player: Node3D, dist: float) -> void:
	d.global_position = player.global_position + Vector3(0.0, 0.0, -dist)


## 造一只不会追、不会打的被动木桩，摆在玩家正前方 dist 米处。
func _spawn_dummy(parent: Node, player: Node3D, dist: float) -> EnemyBrute:
	var scene: PackedScene = load("res://scenes/enemy/enemy.tscn")
	var d := scene.instantiate() as EnemyBrute
	parent.add_child(d)
	d.aggro_range = 0.0
	d.attack_range = 0.0
	d.move_speed = 0.0
	d.global_position = player.global_position + Vector3(0.0, 0.0, -dist)
	await _frames(4)
	return d


# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------

func _run() -> void:
	await _wait(0.6)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _wait(0.8)

	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	var enemy := get_tree().get_first_node_in_group("enemy") as EnemyBrute
	_check(player != null, "前置：玩家已生成")
	_check(enemy != null, "前置：主敌人已生成")
	if player == null or enemy == null:
		return
	_check(InputMap.has_action("lock_on"), "前置：lock_on 动作已注册")

	# 主怪退场：移出 enemy 组 + 静默，避免抢锁定 / 攻击玩家打断断言
	enemy.remove_from_group("enemy")
	enemy.aggro_range = 0.0
	enemy.attack_range = 0.0
	enemy.move_speed = 0.0
	_check(not enemy.is_in_group("enemy"), "前置：主怪已临时移出 enemy 组")

	# 玩家摆到出生点、清零运动与朝向
	player.global_position = Vector3(0.0, 0.2, 9.0)
	player.velocity = Vector3.ZERO
	player._wish_dir = Vector3.ZERO
	player._pivot.rotation.y = 0.0
	await _frames(6)
	_check(not player.is_locked_on(), "前置：初始未锁定")
	_check(main != null, "前置：主场景已挂载")

	# ---- 一根贯穿 T1~T4 的木桩 ----
	var dummy := await _spawn_dummy(main, player, 3.0)

	await _t1t2_hold_and_release(player, dummy)
	await _t3_parity(player)
	await _t4_out_of_range(player, dummy)
	await _t5_destroy_degrade(player, main)
	await _t6a_death_degrade(player, main)
	await _t6b_death_refind(player, main)
	await _t7_no_self_lock(player, main)
	await _t8_invariants_locked(player, main)
	await _t10_locked_dodge_turn(player, main)
	await _t9_death_force_unlock(player, main)   # ⚠ 这条会把玩家打死，必须排在最后

	# T8/T7 的不变量汇总
	_check(_invariant_violations == 0,
		"★ 状态不变量全程成立(flag==effective 且 有目标==已锁定)",
		"违规 %d 次" % _invariant_violations)

	Input.action_release("lock_on")


# ---- T1：长按 2 秒不重复翻转；T2：松手不解锁 ----
func _t1t2_hold_and_release(player: PlayerCharacter, dummy: EnemyBrute) -> void:
	Input.action_release("lock_on")
	await _frames(3)
	_check(not player.is_locked_on(), "T1 前置：未锁定")

	var transitions := 0
	var prev: bool = player.is_locked_on()
	var max_markers := 0
	Input.action_press("lock_on")
	for i in range(120):                       # 2 秒 @ 60Hz
		await get_tree().physics_frame
		var cur: bool = player.is_locked_on()
		if cur != prev:
			transitions += 1
			prev = cur
		max_markers = maxi(max_markers, _count_markers(get_tree().current_scene))
		_check_invariants(player)
	_check(transitions == 1, "T1 ★ 长按中键 2s 只翻转一次",
		"实际 %d 次(>1 = 每次按下都翻/误用 is_action_pressed)" % transitions)
	_check(player.is_locked_on(), "T1 长按期间保持锁定")
	_check(player.get_lock_target() == dummy, "T1 长按锁定目标正确")
	_check(max_markers <= 1, "T1 长按期间标记数量 ≤1", "峰值 %d" % max_markers)

	# 松开 = T2（本次变更核心：松开无解锁含义）
	Input.action_release("lock_on")
	await _wait(0.5)
	_check(player.is_locked_on(), "T2 ★ 松开中键 ≥0.5s 后仍锁定(松开无解锁含义)")
	_check(player.get_lock_target() == dummy, "T2 松开后目标不变")
	_check(_count_markers(get_tree().current_scene) == 1, "T2 松开后标记仍在且仅 1 个",
		"实际 %d" % _count_markers(get_tree().current_scene))
	_check_invariants(player)


# ---- T3：连续 6 次点击严格奇偶交替 ----
func _t3_parity(player: PlayerCharacter) -> void:
	var seq: Array[bool] = []
	var max_markers := 0
	for i in range(6):
		await _tap_lock()
		seq.append(player.is_locked_on())
		max_markers = maxi(max_markers, _count_markers(get_tree().current_scene))
		_check_invariants(player)
	var ok_alt := true
	for i in range(1, seq.size()):
		if seq[i] == seq[i - 1]:
			ok_alt = false
	_check(ok_alt, "T3 ★ 连续 6 次点击严格交替(奇偶翻转)", "序列 %s" % str(seq))
	_check(max_markers <= 1, "T3 连续点击期间标记 ≤1", "峰值 %d" % max_markers)


# ---- T4：范围外点一次 → 保持未锁定，且无残留标记 ----
func _t4_out_of_range(player: PlayerCharacter, dummy: EnemyBrute) -> void:
	if player.is_locked_on():
		await _tap_lock()
	_check(not player.is_locked_on(), "T4 前置：已解锁")
	_set_dist(dummy, player, 30.0)             # 移出 lock_on_range(9m)
	await _frames(4)
	_check(not player.is_locked_on(), "T4 目标移出范围后未锁定")
	await _tap_lock()
	_check(not player.is_locked_on(),
		"T4 ★ 范围外点一次 → 保持未锁定(不得出现锁定态无目标)",
		"实际锁定=%s" % player.is_locked_on())
	_check(player.get_lock_target() == null, "T4 范围外点击后无锁定目标")
	_check(_count_markers(get_tree().current_scene) == 0, "T4 范围外点击后无残留标记",
		"实际 %d" % _count_markers(get_tree().current_scene))
	_check_invariants(player)
	# ★ 清场：把 T1~T4 共用木桩彻底移出场景。否则它会留在范围内，
	#   与后续测试新建的木桩**距离相同** → _find_lock_target 的最近邻出现并列，
	#   后续测试可能锁到这只旧木桩而不是自己新建的那只（本探针初版就踩了这个坑）。
	dummy.queue_free()
	await _frames(4)


# ---- T5：锁定中目标被销毁 → 自动退化 + 收标记 ----
func _t5_destroy_degrade(player: PlayerCharacter, parent: Node) -> void:
	var d := await _spawn_dummy(parent, player, 3.0)
	await _tap_lock()
	_check(player.is_locked_on() and player.get_lock_target() == d, "T5 前置：已锁定木桩")
	_check(_count_markers(get_tree().current_scene) == 1, "T5 前置：标记=1")
	d.queue_free()
	await _frames(6)
	_check(not player.is_locked_on(), "T5 ★ 目标销毁 → 自动退化为未锁定")
	_check(player.get_lock_target() == null, "T5 目标销毁后无目标")
	_check(_count_markers(get_tree().current_scene) == 0, "T5 目标销毁后标记收掉",
		"实际 %d" % _count_markers(get_tree().current_scene))


# ---- T6a：锁定中目标死亡(is_alive=false) → 自动退化 + 收标记 ----
func _t6a_death_degrade(player: PlayerCharacter, parent: Node) -> void:
	if player.is_locked_on():
		await _tap_lock()
	var d := await _spawn_dummy(parent, player, 3.0)
	await _tap_lock()
	_check(player.is_locked_on() and player.get_lock_target() == d, "T6a 前置：已锁定木桩")
	d.health.damage(9999)                      # 合法入口：扣光血 → died → _die
	await _frames(6)
	_check(not d.is_alive(), "T6a 木桩已死亡(is_alive=false)")
	_check(not player.is_locked_on(), "T6a ★ 目标死亡 → 自动退化为未锁定")
	_check(_count_markers(get_tree().current_scene) == 0, "T6a 目标死亡后标记收掉",
		"实际 %d" % _count_markers(get_tree().current_scene))
	d.queue_free()
	await _frames(2)


# ---- T6b：锁定中目标死亡 → 当场重找最近存活目标 ----
func _t6b_death_refind(player: PlayerCharacter, parent: Node) -> void:
	if player.is_locked_on():
		await _tap_lock()
	var a := await _spawn_dummy(parent, player, 3.0)
	var b := await _spawn_dummy(parent, player, 5.0)
	_set_dist(a, player, 3.0)
	_set_dist(b, player, 5.0)
	await _frames(4)
	await _tap_lock()
	_check(player.is_locked_on() and player.get_lock_target() == a,
		"T6b 前置：锁定最近目标 A(3m)")
	a.health.damage(9999)
	await _frames(8)
	_check(not a.is_alive(), "T6b A 已死亡")
	_check(player.is_locked_on(), "T6b ★ 目标 A 死亡 → 仍保持锁定(重找)")
	var tgt := player.get_lock_target()
	_check(tgt == b, "T6b ★ 已改锁到最近的存活目标 B(5m)",
		"实际 %s" % (tgt.name if tgt != null else "<null>"))
	_check(_count_markers(get_tree().current_scene) == 1, "T6b 标记仍只有 1 个(已迁移到 B)",
		"实际 %d" % _count_markers(get_tree().current_scene))
	await _tap_lock()
	_check(_count_markers(get_tree().current_scene) == 0, "T6b 解锁后标记清零")
	a.queue_free()
	b.queue_free()
	await _frames(3)


# ---- T7：不点中键时绝不自动锁定 ----
func _t7_no_self_lock(player: PlayerCharacter, parent: Node) -> void:
	var e := await _spawn_dummy(parent, player, 4.0)
	if player.is_locked_on():
		await _tap_lock()
	Input.action_release("lock_on")
	await _frames(3)
	_check(not player.is_locked_on(), "T7 前置：未锁定")
	var ever_locked := false
	var any_marker := false
	for i in range(60):                        # 1 秒不碰中键
		await get_tree().physics_frame
		if player.is_locked_on():
			ever_locked = true
		if _count_markers(get_tree().current_scene) != 0:
			any_marker = true
		_check_invariants(player)
	_check(not ever_locked, "T7 ★ 不点中键 1s 全程未锁定(无每帧重找自锁)")
	_check(not any_marker, "T7 不点中键全程无标记")
	e.queue_free()
	await _frames(3)


# ---- T8：锁定态下的状态不变量采样 ----
func _t8_invariants_locked(player: PlayerCharacter, parent: Node) -> void:
	var e := await _spawn_dummy(parent, player, 4.0)
	await _tap_lock()
	_check(player.is_locked_on(), "T8 前置：已锁定")
	for i in range(30):
		await get_tree().physics_frame
		_check_invariants(player)
	_check(_invariants_hold(player), "T8 锁定态不变量成立")
	await _tap_lock()
	_check(not player.is_locked_on(), "T8 解锁后未锁定")
	_check(_count_markers(get_tree().current_scene) == 0, "T8 解锁后标记清零")
	e.queue_free()
	await _frames(3)


# ---- T9：死亡强制解除；死后点击/长按也不锁定 ----
func _t9_death_force_unlock(player: PlayerCharacter, parent: Node) -> void:
	var e := await _spawn_dummy(parent, player, 4.0)
	await _tap_lock()
	_check(player.is_locked_on() and player.get_lock_target() == e, "T9 前置：已锁定木桩")
	_check(_count_markers(get_tree().current_scene) == 1, "T9 前置：标记=1")
	player._die()                              # 玩家死亡入口
	await _frames(6)
	_check(not player.is_alive(), "T9 玩家已死亡")
	_check(not player.is_locked_on(), "T9 ★ 死亡 → 强制解除锁定")
	_check(player.get_lock_target() == null, "T9 死亡后无锁定目标")
	_check(_count_markers(get_tree().current_scene) == 0, "T9 死亡后标记收掉",
		"实际 %d" % _count_markers(get_tree().current_scene))
	# 死后即使点按中键也不应进入锁定
	var locked_after_death := false
	Input.action_press("lock_on")
	for i in range(30):
		await get_tree().physics_frame
		if player.is_locked_on():
			locked_after_death = true
	Input.action_release("lock_on")
	_check(not locked_after_death, "T9 死亡后点击/长按中键不会锁定")
	e.queue_free()
	await _frames(2)


# ---- T10：锁定中「方向键 + 闪避」必须跟着转向（用户 2026-09-20 明确选的行为）----
# 【为什么这一条要放进锁定探针】它与锁定的核心承诺（"身体恒面向敌人"）直接冲突，
#   是**唯一被允许临时破坏该承诺**的动作 —— 放在这里才能和 T8 的不变量检查互为照应：
#   允许"朝向被借走几帧"，但绝不允许"借着借着把锁定也弄丢了"。
func _t10_locked_dodge_turn(player: PlayerCharacter, parent: Node) -> void:
	var e := await _spawn_dummy(parent, player, 3.0)
	await _tap_lock()
	_check(player.is_locked_on() and player.get_lock_target() == e, "T10 前置：已锁定木桩")
	# 按 A（侧向）+ Shift → 前闪
	Input.action_press("move_left")
	await _frames(2)
	player._update_wish_dir()
	var wish_left: Vector3 = player._wish_dir
	wish_left.y = 0.0
	wish_left = wish_left.normalized()
	player._try_start_dodge()
	Input.action_release("move_left")
	await _frames(2)
	_check(player.state == PlayerCharacter.State.DODGE, "T10 锁定中仍可起手闪避")
	_check(player._dodge_is_forward, "T10 方向键 + 闪避判为前闪（不是后撤）")
	var face: Vector3 = -player._pivot.global_basis.z
	face.y = 0.0
	var dot_side: float = face.normalized().dot(wish_left)
	_check(dot_side > 0.95, "T10 ★ 锁定中也跟着转向方向键的方向", "点积 %.3f" % dot_side)
	_check(player.is_locked_on(), "T10 ★ 闪避期间锁定不被解除（借走的只是朝向）")
	_check(_count_markers(get_tree().current_scene) == 1, "T10 闪避期间标记仍在")
	# 整段闪避里每一帧都要守不变量（朝向被借走 ≠ 状态失控）
	for i in range(45):
		await get_tree().physics_frame
		_check_invariants(player)
	# 闪避结束回 MOVE → 锁定应把朝向重新拉回敌人
	await _wait(0.7)
	_check(player.state == PlayerCharacter.State.MOVE, "T10 闪避结束已回到 MOVE")
	_check(player.is_locked_on(), "T10 收招后仍然锁定")
	# ⚠ 朝向要跟"此刻"的敌人方向比：这段闪避挪了 4m，事前的方向已经作废
	var to_enemy: Vector3 = e.global_position - player.global_position
	to_enemy.y = 0.0
	var face_back: Vector3 = -player._pivot.global_basis.z
	face_back.y = 0.0
	var dot_back: float = face_back.normalized().dot(to_enemy.normalized())
	_check(dot_back > 0.9, "T10 ★ 收招后朝向被锁定拉回敌人", "点积 %.3f" % dot_back)
	await _tap_lock()
	_check(not player.is_locked_on(), "T10 解锁")
	_check(_count_markers(get_tree().current_scene) == 0, "T10 解锁后标记清零")
	e.queue_free()
	await _frames(3)
