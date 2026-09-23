extends Node
class_name CharacterSwitcher
## ============================================================
## 【调试工具】角色切换器 —— 把场上任意角色变成"当前可操作角色"
## ============================================================
## 【为什么需要它】
##   调动作游戏时，"敌人 AI 打我"和"我操控敌人打玩家"看到的完全是两种东西：
##   站在玩家位只能被动挨打，敌人的出手节奏、判定距离、击退力度全靠猜。
##   把敌人也做成可操作角色后，就能主动去撞判定、量距离、验证"这一棒到底
##   够不够得着"—— 调一只怪的效率差一个量级。
##
## 【核心思路：不去复制一套玩家控制器】
##   玩家那套 WASD→状态机→15 段动画的逻辑与 PlayerCharacter 深度耦合，
##   复制给敌人等于再养一份双胞胎代码（改一处要改两处，还会互相长歪）。
##   这里改成**给现有角色补一个"是否听玩家指令"的开关**：
##     · PlayerCharacter.control_enabled = false → 站桩（物理/动画照常，只是不读输入）
##     · EnemyBrute.ai_enabled = false + manual_wish_dir → 由本切换器喂指令
##   切换器只做三件事：读输入、发给当前角色、把镜头和 HUD 挪过去。
##   角色自己的状态机/动画/命中盒**全部原样复用**，所以"操控敌人打玩家"
##   与"敌人 AI 打玩家"是同一套代码路径 —— 测出来的结论才可信。
##
## 【按键】Tab 或 F 循环切换（见 input_setup.gd）；操控敌人时：
##        WASD = 移动（相对镜头）、左键 = 挥一棒（含 0.5s 蓄力预警，与 AI 完全一致）
## ============================================================

## 收集顺序：玩家优先（第一个受控），敌人其次。
## 【为什么按组收集而不是写死名单】敌人会死、会重生（主场景 3 秒后换新实例），
##   写死引用很快就会指向已销毁的节点 → 报一堆"对已释放实例操作"。
const CAST_GROUPS := ["player", "enemy"]

## 切换时广播：主场景拿它弹提示语。
signal controlled_changed(actor: Node3D)


# ------------------------------------------------------------------
# 运行时状态
# ------------------------------------------------------------------

## 当前可操控名单（按 CAST_GROUPS 顺序收集）
var _cast: Array[Node3D] = []
## 当前受控角色在 _cast 里的下标
var _index: int = 0
## HUD / 镜头引用（由 setup() 传入）
var _hud: Hud = null
var _camera: ThirdPersonCamera = null
## 上一轮接过信号的角色（重绑 HUD 时要先按它把旧连接断干净）
var _bound: Array[Node] = []


# ------------------------------------------------------------------
# 对外接口
# ------------------------------------------------------------------

## 初始化：记住 HUD 与镜头，收集名单，立即把操控交给第一个角色（玩家）。
func setup(hud: Hud, camera: ThirdPersonCamera) -> void:
	_hud = hud
	_camera = camera
	# ★ 比场上所有角色先跑：本帧的指令必须赶在角色自己的 _physics_process 之前写进去，
	#   否则敌人会用上一帧的方向先走一步（表现为"起步慢半拍、松手多滑一米"）。
	process_priority = -10
	refresh_cast()


## 重新收集名单（主场景敌人重生后要调一次，新实例才会进名单）。
func refresh_cast() -> void:
	_cast.clear()
	for group_name in CAST_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			var a := node as Node3D
			if a == null or not _is_playable(a):
				continue
			if _cast.has(a):
				continue
			_cast.append(a)
	if _index >= _cast.size():
		_index = 0
	_apply_control()
	_rebind_hud()


## 当前受控角色（空名单时返回 null）。
func current() -> Node3D:
	if _cast.is_empty() or _index >= _cast.size():
		return null
	return _cast[_index]


## 当前受控角色的显示名（HUD 提示语用）。
func current_name() -> String:
	var a := current()
	if a == null:
		return "（无）"
	return "玩家骑士" if a.is_in_group("player") else "红甲守卫"


# ------------------------------------------------------------------
# 主循环
# ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	# 1) 清理失效/死亡的角色；正在操控的那只没了就自动回落到玩家
	if _prune_cast():
		_apply_control()
		_rebind_hud()
	# 2) 切换键（边沿触发：一次按下只翻一格，不会连跳）
	if Input.is_action_just_pressed("switch_character"):
		_switch_next()
	# 3) 每帧把"谁听指令"这件事落实下去，并给受控角色喂指令
	_apply_control()


## 切到下一个角色（循环）。
func _switch_next() -> void:
	if _cast.size() <= 1:
		return
	_index = (_index + 1) % _cast.size()
	_apply_control()
	_rebind_hud()
	controlled_changed.emit(current())


# ------------------------------------------------------------------
# 名单维护
# ------------------------------------------------------------------

## 这个角色现在还能不能当"可操作角色"。
## 玩家那一档刻意放宽：玩家死了也留在名单里（死亡遮罩由主场景接管，
## 不做"强制跳到敌人"这种越权操作），等按 R 重开一切自然复位。
func _is_playable(a: Node3D) -> bool:
	if not is_instance_valid(a):
		return false
	if a.is_in_group("player"):
		return true
	return not (a.has_method("is_alive") and not a.is_alive())


## 剔除失效/已死的角色；剔除后若下标越界则归零。
## @return 名单是否发生变化（变化了才需要重绑 HUD）
func _prune_cast() -> bool:
	var changed := false
	for i in range(_cast.size() - 1, -1, -1):
		if not _is_playable(_cast[i]):
			# 退场时把"手动操控"标志还给它的 AI：名单外没人再每帧维护这个开关，
			# 留着 false 会让尸体/待销毁实例挂着"正在被操控"的假状态。
			if _cast[i] is EnemyBrute:
				(_cast[i] as EnemyBrute).ai_enabled = true
			_cast.remove_at(i)
			changed = true
	if changed and _index >= _cast.size():
		_index = 0
	return changed


# ------------------------------------------------------------------
# 指令下发：读输入 → 发给当前角色
# ------------------------------------------------------------------

## 落实"谁听指令"，并把本帧输入喂给受控角色。
func _apply_control() -> void:
	var wish := _read_wish()
	var attack_pressed := Input.is_action_just_pressed("attack")
	for i in _cast.size():
		var a := _cast[i]
		if not is_instance_valid(a):
			continue
		var active: bool = (i == _index)
		if a is PlayerCharacter:
			# 玩家自己会在 _physics_process 里读输入，这里只决定"它读不读"
			(a as PlayerCharacter).control_enabled = active
		elif a is EnemyBrute:
			var e := a as EnemyBrute
			e.ai_enabled = not active
			if not active:
				continue
			# ★ 敌人不会自己读输入 → 由这里代劳，把指令写进它的两个入口
			e.manual_wish_dir = wish
			if attack_pressed:
				# 有移动输入就朝移动方向打；站桩时朝镜头正前方打（与玩家的规则一致）
				e.request_attack(wish if wish.length() > 0.1 else _camera_forward())
	if _camera != null and is_instance_valid(_camera):
		var cur := current()
		if cur != null and _camera.target != cur:
			_camera.set_target(cur)   # 镜头跟着换人（内部会立刻 snap，不会拖影）


## WASD + 镜头朝向 → 世界系移动意图（与 player.gd 的 _update_wish_dir 同一套算法）。
func _read_wish() -> Vector3:
	var fwd_in := Input.get_axis("move_back", "move_forward")   # W=+1, S=-1
	var side_in := Input.get_axis("move_left", "move_right")    # D=+1, A=-1
	var f := Vector3.FORWARD
	var r := Vector3.RIGHT
	if _camera != null and is_instance_valid(_camera):
		f = -_camera.global_basis.z   # 镜头局部 -Z = 它看向的方向
		r = _camera.global_basis.x    # 镜头局部 X = 它的右边
	f.y = 0.0
	r.y = 0.0
	f = f.normalized()
	r = r.normalized()
	var wish := f * fwd_in + r * side_in
	if wish.length() > 1.0:
		wish = wish.normalized()      # 斜着走不比直走快
	return wish


## 镜头看向的水平单位向量（站桩出招时朝屏幕正前方打）。
func _camera_forward() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		var f := -_camera.global_basis.z
		f.y = 0.0
		if f.length() > 0.1:
			return f.normalized()
	return Vector3.FORWARD


# ------------------------------------------------------------------
# HUD 重绑：受控角色 → 自己的血条；对手 → 上方血条 + 失衡条
# ------------------------------------------------------------------

## 【为什么每次切换都要"全断再全连"】
##   血量信号是"谁扣血谁广播"，绑定关系不跟着操控权走的话，
##   操控敌人时会看到"我打玩家，掉的确是上面那条红血"——读不懂。
##   所以这里把 HUD 的两条血条定义成**角色关系**而不是**固定身份**：
##     自己 → 下方绿条；对手 → 上方红条（+ 黄条，有失衡条才显示）。
func _rebind_hud() -> void:
	if _hud == null:
		return
	for a in _bound:
		_unbind(a)
	_bound.clear()

	var me := current()
	_bind_self(me)
	_bind_foe(_opponent())


## 对手 = 名单里第一个不是自己的角色（没有对手时上方血条整组隐藏）。
func _opponent() -> Node3D:
	var me := current()
	for a in _cast:
		if a != me and is_instance_valid(a):
			return a
	return null


func _bind_self(a: Node3D) -> void:
	if a == null:
		return
	var hp := _health_of(a)
	if hp == null:
		return
	if not hp.changed.is_connected(_hud.set_player_hp):
		hp.changed.connect(_hud.set_player_hp)
	_hud.set_player_hp(hp.current_hp, hp.max_hp)   # 立刻同步一次初值
	_bound.append(a)


func _bind_foe(a: Node3D) -> void:
	if a == null:
		_hud.set_enemy_hp(0, 1)            # 传 0 → HUD 自己把整组隐藏
		_hud.set_enemy_poise_visible(false)
		return
	var hp := _health_of(a)
	if hp != null:
		if not hp.changed.is_connected(_on_foe_hp_changed):
			hp.changed.connect(_on_foe_hp_changed)
		_hud.set_enemy_hp(hp.current_hp, hp.max_hp)
		_bound.append(a)
	# 失衡条只有带 Poise 组件的角色才有（玩家没有 → 整组隐藏，不留空黄条）
	var po := _poise_of(a)
	if po != null:
		if not po.changed.is_connected(_on_foe_poise_changed):
			po.changed.connect(_on_foe_poise_changed)
		if not po.broken_started.is_connected(_on_foe_broken):
			po.broken_started.connect(_on_foe_broken)
		_on_foe_poise_changed(po.current_poise, po.max_poise, po.is_broken())
		_hud.set_enemy_poise_visible(true)
	else:
		_hud.set_enemy_poise_visible(false)


## 断开某角色在 HUD 上的所有连接（改绑前必须做，否则一条血被两个角色同时刷）。
func _unbind(a: Node) -> void:
	if not is_instance_valid(a):
		return
	var hp := _health_of(a)
	if hp != null:
		if hp.changed.is_connected(_hud.set_player_hp):
			hp.changed.disconnect(_hud.set_player_hp)
		if hp.changed.is_connected(_on_foe_hp_changed):
			hp.changed.disconnect(_on_foe_hp_changed)
	var po := _poise_of(a)
	if po != null:
		if po.changed.is_connected(_on_foe_poise_changed):
			po.changed.disconnect(_on_foe_poise_changed)
		if po.broken_started.is_connected(_on_foe_broken):
			po.broken_started.disconnect(_on_foe_broken)


func _on_foe_hp_changed(current_hp: int, max_hp: int) -> void:
	if _hud != null:
		_hud.set_enemy_hp(current_hp, max_hp)


func _on_foe_poise_changed(current: float, max_poise: float, broken: bool) -> void:
	if _hud != null:
		_hud.set_enemy_poise(current, max_poise, broken)


## 对手刚进入失衡 → 提示可以处决（与原来"敌人失衡"的提示是同一句，只是对象换了）。
func _on_foe_broken() -> void:
	if _hud != null:
		_hud.show_message("对手失衡了！走近按【左键】处决", 2.5)


# ------------------------------------------------------------------
# 小工具：按名字取组件（不同角色挂的组件不一样，用 get 避免硬类型）
# ------------------------------------------------------------------

func _health_of(a: Node) -> Health:
	if a == null or not is_instance_valid(a):
		return null
	return a.get("health") as Health


func _poise_of(a: Node) -> Poise:
	if a == null or not is_instance_valid(a):
		return null
	# 玩家没有 poise 属性 → get 返回 null，正好走"不显示失衡条"那一支
	return a.get("poise") as Poise
