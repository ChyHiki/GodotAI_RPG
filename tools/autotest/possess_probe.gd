extends Node
## ============================================================
## 回归探针：验证"把敌人也做成可操作角色"（角色切换器）确实成立
## ============================================================
## 【为什么单独写一份】
##   m1_autotest.gd 是工程师自己写的断言，跑它不算独立验证。本探针**主动证伪**
##   本次改造里最容易悄悄坏掉的几条：
##     · 切换后"只有一个角色在听指令"（两个都听 = 玩家和怪一起动，很难发现）
##     · 敌人被操控时 AI 真的关了（否则会变成"我按左键、它自己也在追人"）
##     · 手动出招走的是**原本那条** WINDUP→STRIKE 链路（蓄力/命中盒/伤害都在）
##     · 镜头与 HUD 跟着换人（切了视角还对着旧角色 = 完全没法操作）
##     · 操控中的角色死亡 → 自动把操控权交还玩家（不能卡在尸体上）
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       res://tools/autotest/possess_probe.tscn
## 退出码 0 = 全部通过；1 = 有失败（失败项以 "PROBE FAIL:" 打印，并 push_error）。
## ============================================================

var failures: Array[String] = []
var _rows: Array[String] = []
var _violations: int = 0

## 场上的三个关键引用（_run 里填好）
var _main: Node = null
var _switcher: CharacterSwitcher = null
var _player: PlayerCharacter = null
var _enemy: EnemyBrute = null
var _hud: Hud = null


func _ready() -> void:
	await _run()
	print("")
	print("=== PROBE TABLE ===")
	for r in _rows:
		print(r)
	print("")
	print("=== INVARIANT VIOLATIONS: %d ===" % _violations)
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


## 按下 → 跨过 1 个物理帧（让 is_action_just_pressed 被读到）→ 松开 → 再等 2 帧。
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame
	await get_tree().physics_frame


## 按住某个动作 hold_sec 秒（用于"持续移动"这类需要按住的输入）。
func _hold(action: String, hold_sec: float) -> void:
	Input.action_press(action)
	await _wait(hold_sec)
	Input.action_release(action)
	await get_tree().physics_frame


## 递归找 Hud（主场景是代码搭的，没有稳定路径，只能按类型找）。
func _find_hud(node: Node) -> Hud:
	if node is Hud:
		return node as Hud
	for c in node.get_children():
		var found := _find_hud(c)
		if found != null:
			return found
	return null


## 把角色摆到指定水平位置（清零速度，避免上一项的残余惯性干扰测量）。
func _place(a: Node3D, x: float, z: float) -> void:
	a.global_position = Vector3(x, 0.2, z)
	a.velocity = Vector3.ZERO
	if a is PlayerCharacter:
		(a as PlayerCharacter)._wish_dir = Vector3.ZERO
	else:
		(a as EnemyBrute).manual_wish_dir = Vector3.ZERO


## 角色当前正面 与 "角色→目标" 方向的水平夹角(度)（用来断言软锁定吸没吸住）。
func _facing_error_deg(actor: Node3D, target: Node3D) -> float:
	var to_t := target.global_position - actor.global_position
	to_t.y = 0.0
	if to_t.length() < 0.05:
		return 0.0
	var facing: Vector3 = actor._get_facing_flat()
	return rad_to_deg(acos(clampf(facing.dot(to_t.normalized()), -1.0, 1.0)))


## ★ 不变量：任何时刻**恰好一个**角色在听玩家指令。
##   两个都听 = 玩家和怪一起动；都没人听 = 这局没有任何东西可操作。
## 【为什么敌人要先判存活】死亡的角色会被切换器移出名单，它的 ai_enabled 不再被
##   每帧维护（尸体不需要听指令），所以不能拿它来数"谁在听指令"。
func _check_exactly_one_controlled(stage: String) -> void:
	var listening := 0
	if is_instance_valid(_player) and _player.control_enabled:
		listening += 1
	if is_instance_valid(_enemy) and _enemy.is_alive() and not _enemy.ai_enabled:
		listening += 1
	if listening != 1:
		_violations += 1
		_check(false, "★ 不变量[%s]：恰好一个角色在听指令" % stage, "实际在听指令的角色数 = %d" % listening)
		return
	_rows.append("[PASS] ★ 不变量[%s]：恰好一个角色在听指令" % stage)
	print("PROBE OK: ★ 不变量[%s]：恰好一个角色在听指令" % stage)


# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------

func _run() -> void:
	await _wait(0.6)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.8)

	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	_enemy = get_tree().get_first_node_in_group("enemy") as EnemyBrute
	_switcher = _main.get_node_or_null("CharacterSwitcher") as CharacterSwitcher
	_hud = _find_hud(_main)

	_check(_player != null, "前置：玩家已生成")
	_check(_enemy != null, "前置：敌人已生成")
	_check(_switcher != null, "前置：主场景挂了角色切换器")
	_check(_hud != null, "前置：HUD 已生成")
	if _player == null or _enemy == null or _switcher == null or _hud == null:
		return
	_check(InputMap.has_action("switch_character"), "前置：switch_character 动作已注册")

	# ---------------------------------------------------------------
	# T1 启动默认：操控玩家
	# ---------------------------------------------------------------
	_check(_switcher.current() == _player, "T1 启动默认操控玩家")
	_check(_player.control_enabled, "T1 玩家在听指令")
	_check(_enemy.ai_enabled, "T1 敌人仍由 AI 驱动")
	_check_exactly_one_controlled("T1")

	# ---------------------------------------------------------------
	# T2 按一次切换键 → 操控权移到敌人
	# ---------------------------------------------------------------
	await _tap("switch_character")
	_check(_switcher.current() == _enemy, "T2 ★ 按切换键后操控敌人",
			"current=%s" % _switcher.current_name())
	_check(not _player.control_enabled, "T2 玩家已停止听指令（站桩当陪练）")
	_check(not _enemy.ai_enabled, "T2 敌人已改为听指令")
	_check_exactly_one_controlled("T2")
	# 镜头必须跟着换人，否则"切了却还看着旧角色"根本没法操作
	_check(_switcher._camera != null and _switcher._camera.target == _enemy,
			"T2 镜头目标已切到敌人")
	# HUD：自己的血条绑到敌人、对手血条绑到玩家
	_check(_enemy.health.changed.is_connected(_hud.set_player_hp),
			"T2 ★ HUD 自身血条已改绑敌人")
	_check(not _player.health.changed.is_connected(_hud.set_player_hp),
			"T2 玩家不再占用自身血条")
	_check(_player.health.changed.is_connected(Callable(_switcher, "_on_foe_hp_changed")),
			"T2 HUD 对手血条已绑到玩家")

	# ---------------------------------------------------------------
	# T3 操控敌人：WASD 真的能走
	# ---------------------------------------------------------------
	_place(_enemy, 0.0, 0.0)
	_place(_player, 18.0, 18.0)     # 玩家挪远，免得挡路
	await _frames(4)
	var cam_fwd := _switcher._camera_forward()
	var p0 := _enemy.global_position
	await _hold("move_forward", 0.6)
	var moved := Vector2(_enemy.global_position.x - p0.x, _enemy.global_position.z - p0.z).length()
	_check(moved > 0.5, "T3 ★ 操控敌人时按 W 会移动", "位移 %.2fm" % moved)
	var dir := (_enemy.global_position - p0)
	dir.y = 0.0
	var dot := dir.normalized().dot(cam_fwd) if dir.length() > 0.05 else 0.0
	_check(dot > 0.8, "T3 移动方向 = 镜头前方", "点积 %.2f" % dot)

	# ---------------------------------------------------------------
	# T4 AI 已关：把它放在仇恨范围内也不该自己追人
	# ---------------------------------------------------------------
	_place(_enemy, 0.0, 0.0)
	_place(_player, 0.0, 6.0)       # 6m < aggro(11m)：AI 若还开着，这 1.2s 足够冲过来
	await _frames(4)
	var e0 := _enemy.global_position
	await _wait(1.2)
	var chase := Vector2(_enemy.global_position.x - e0.x, _enemy.global_position.z - e0.z).length()
	_check(chase < 0.3, "T4 ★ 被操控时 AI 不再自动追人", "1.2s 内自行移动 %.2fm" % chase)

	# ---------------------------------------------------------------
	# T5 手动出招：走的是原本那条 WINDUP→STRIKE 链路（不是另起一套）
	# ---------------------------------------------------------------
	_place(_enemy, 0.0, 10.6)       # 站到玩家（z=9）正后方 1.6m
	_place(_player, 0.0, 9.0)
	await _frames(6)
	var hp_before := _player.health.current_hp
	# 出手方向 = 镜头前方（-Z，正对玩家）
	# ⚠ 按下后要**跨过两个物理帧**再读状态：physics_frame 信号是在 _physics_process
	#   **之前**发出的，第一帧恢复时切换器还没读到这次按键（会误判成"左键没反应"）。
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await get_tree().physics_frame
	_check(_enemy.state == EnemyBrute.State.WINDUP, "T5 ★ 左键让敌人进入蓄力 WINDUP",
			"state=%d(期望 %d=WINDUP)" % [_enemy.state, EnemyBrute.State.WINDUP])
	await _wait(0.35)               # WINDUP 0.5s 还没结束
	_check(_enemy.state == EnemyBrute.State.WINDUP or _enemy.state == EnemyBrute.State.STRIKE,
			"T5 蓄力结束后才出手", "state=%d" % _enemy.state)
	await _wait(0.9)                # 等挥击判定与收招走完
	var hp_after := _player.health.current_hp
	_check(hp_after < hp_before, "T5 ★ 操控敌人挥棒能打中玩家",
			"玩家 %d → %d" % [hp_before, hp_after])

	# ---------------------------------------------------------------
	# T5b 近战朝向修正：操控敌人时，玩家站在**侧前方 60°**也该一棒砸中
	#   （守卫身上是同一套规则，基准换成它自己的正面）
	# ---------------------------------------------------------------
	_place(_enemy, 0.0, 10.6)
	_place(_player, 1.9, 9.5)          # 相对敌人正面偏 60°、2.2m：不修正就是抡空
	_enemy._pivot.rotation.y = 0.0     # 面朝 -Z（= 镜头正前方），与玩家差 60°
	_player.health.reset()
	_enemy._attack_cd = 0.0
	_enemy.state = EnemyBrute.State.IDLE
	_enemy._state_time = 0.0
	await _frames(4)
	var hp_p0 := _player.health.current_hp
	await _tap("attack")
	_check(_enemy.state == EnemyBrute.State.WINDUP, "T5b 前置：已进入蓄力")
	var err_aim := _facing_error_deg(_enemy, _player)
	_check(err_aim < 8.0, "T5b ★ 出招瞬间朝向被吸附到玩家（偏差 %.1f°）" % err_aim)
	await _wait(1.0)
	_check(_player.health.current_hp < hp_p0, "T5b ★ 侧前方的玩家也被砸中",
			"%d → %d" % [hp_p0, _player.health.current_hp])

	# 反证：把搜索半径设成 0（= 关掉修正）→ 朝镜头正前方挥空
	_enemy.soft_lock_range = 0.0
	_player.health.reset()
	_enemy._attack_cd = 0.0
	_enemy.state = EnemyBrute.State.IDLE
	_enemy._state_time = 0.0
	_place(_enemy, 0.0, 10.6)
	_place(_player, 1.9, 9.5)
	_enemy._pivot.rotation.y = 0.0
	await _frames(4)
	var hp_p1 := _player.health.current_hp
	await _tap("attack")
	var err_plain := _facing_error_deg(_enemy, _player)
	_check(err_plain > 40.0, "T5b ★ 关掉修正后朝的是镜头正前方（离玩家 %.1f°）" % err_plain)
	await _wait(1.0)
	_check(_player.health.current_hp == hp_p1, "T5b ★ 关掉修正后这一棒抡空（血量 %d 不变）" % hp_p1)
	_enemy.soft_lock_range = 3.0       # 还原，别影响后面的章节

	# ---------------------------------------------------------------
	# T6 再按一次 → 操控权交还玩家，敌人恢复 AI
	# ---------------------------------------------------------------
	await _tap("switch_character")
	_check(_switcher.current() == _player, "T6 再按一次切回玩家")
	_check(_player.control_enabled, "T6 玩家重新听指令")
	_check(_enemy.ai_enabled, "T6 敌人恢复 AI")
	_check_exactly_one_controlled("T6")

	# ---------------------------------------------------------------
	# T7 操控中的角色死亡 → 自动把操控权交还玩家（不能卡在尸体上）
	# ---------------------------------------------------------------
	await _tap("switch_character")
	_check(_switcher.current() == _enemy, "T7 前置：已切到敌人")
	_enemy.health.invincible = false
	_enemy.health.damage(1000)
	await _frames(6)
	_check(_switcher.current() == _player, "T7 ★ 操控中的敌人死亡 → 操控权自动交还玩家",
			"current=%s" % _switcher.current_name())
	_check(_player.control_enabled, "T7 玩家已重新听指令")
	_check_exactly_one_controlled("T7")
