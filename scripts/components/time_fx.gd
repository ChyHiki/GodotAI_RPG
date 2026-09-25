class_name TimeFx
extends Node
## ============================================================
## 通用"时间特效"组件（子弹时间 / 顿帧）
## ============================================================
## 【作用】管理**全局时间倍率**（`Engine.time_scale`）的两类减速效果：
##   - 子弹时间 bullet time：奖励玩家的表演时间（完美闪避 / 处决慢动作）
##   - 顿帧 hitstop：命中瞬间的打击感（几乎定格零点零几秒）
##
## 【挂载方式】与 Health / Poise 一样作为战斗单位的子节点：
##     Player(CharacterBody3D)
##       ├─ Health   (scripts/components/health.gd)
##       ├─ Poise    (scripts/components/poise.gd)
##       └─ TimeFx   (本脚本)
##   ⚠️ `Engine.time_scale` 是**全局单例**，不区分是谁在减速 —— 所以场上**同一时刻只应
##      有一个生效的 TimeFx**（本作只有玩家挂它）。敌人要慢动作就喊玩家的 TimeFx，
##      不要给每只怪都挂一个，否则它们会互相覆盖。
##
## 【为什么拆成组件（而不是留在 player.gd 里）】
##   它是"只管时间、不碰角色"的独立机制：谁都可以调，且和角色的状态机毫无耦合。
##   拆出来之后 enemy.gd / 陷阱 / 剧情脚本都能直接复用同一套语义，
##   不用各自再写一遍"两个因子取更慢者"的坑。
##
## 【核心设计：两个因子 + 取更慢者】
##   两类减速**各写一个因子**（`_bt_factor` / `_hs_factor`），
##   最终 `Engine.time_scale = min(两者)`。
##   【为什么不直接写 Engine.time_scale】两个补间抢同一个变量时"谁后写谁赢"，
##     先到点的那个还会把对方的减速一起拉回 1.0 —— 画面会突然"抽一下"。
##   【为什么是 min 而不是乘】相乘会让"子弹时间里的命中"慢到 0.45×0.05 = 0.0225
##     （几乎静止两秒），表现上像卡死。取 min = "最深的效果说了算"。
## ============================================================

## 信号：全局时间倍率发生变化（HUD / 调试面板可监听；1.0 = 常速）
signal time_scale_changed(scale: float)

## 顿帧收尾时的极短淡出时长(秒)。不用硬跳回 1.0 —— 硬跳会有一下可闻的"顿挫感"。
const HITSTOP_RELEASE: float = 0.03

## —— 子弹时间默认参数（完美闪避那一组）——
## 【多快褪色】保持 `bullet_time_duration` 真实秒后立刻开始回升 —— "瞥一眼"就够。
##   倍率 0.45（不是更狠的 0.35）：太慢会让玩家把子弹时间当成"停下来喘气"，打断战斗连贯感。
@export var bullet_time_scale: float = 0.45    # 全局时间倍率(1.0=常速，越小越慢)
@export var bullet_time_duration: float = 0.25 # 减速保持多久（**真实秒**，不受减速本身影响）
@export var bullet_time_fade: float = 0.25     # 从减速平滑回到常速的过渡时长（真实秒）

## —— 顿帧默认参数 ——
## 【为什么要设上限取最狠的一次】重叠命中（一刀扫到两个敌人）会连着调两次，
##   若每次都从头计时，顿帧会被叠成"两倍长" —— kill 掉上一次反而更稳。
@export var hitstop_scale: float = 0.05        # 顿帧期间的时间倍率(0.05 ≈ 几乎定格)
@export var hitstop_release: float = HITSTOP_RELEASE  # 收尾淡出时长(真实秒)

## 子弹时间对全局时间倍率的贡献值（1.0 = 不减速）。由补间直接驱动。
var _bt_factor: float = 1.0
## 顿帧对全局时间倍率的贡献值（1.0 = 不减速）。同上，由补间驱动。
var _hs_factor: float = 1.0

## 子弹时间的补间（用 set_ignore_time_scale 让它**不受自己造成的减速影响**）
var _bullet_time_tween: Tween = null
## 顿帧的补间（同样 set_ignore_time_scale —— 否则"顿帧自己的计时"会被自己压慢，
## 0.055s 的顿帧会实际持续 0.055/0.05 = 1.1s，整个节奏就毁了）
var _hitstop_tween: Tween = null


func _ready() -> void:
	# ★ 兜底把全局时间倍率复位：Engine.time_scale 是全局单例，若上一次运行/上一个场景
	#   是在减速状态里退出的（比如直接关窗），它会把 0.35 带去下一次运行 —— 症状极隐蔽
	#   （整个游戏慢动作、但没有任何报错）。这里每次进场景都强制拉回常速。
	reset()


## 触发子弹时间：把全局时间压慢，持续 hold 真实秒后再平滑回升。
## 【为什么用 Tween 而不是自己数秒】自己数秒必须拿"真实时间"，而 _process 的 delta
##   恰恰是被 time_scale 缩放过的 —— 用它计时会让"减速期间"的计时也一起变慢，
##   实际减速时长会被拉长成 duration / time_scale（0.6s 变 1.7s），节奏完全失控。
##   Tween.set_ignore_time_scale(true) 就是官方提供的"这条补间不受 time_scale 影响"开关。
## 【为什么要 kill 上一条件】连续完美闪避时，旧补间到点会把新减速一起拉回 1.0。
## 【参数化】三个参数默认沿用**完美闪避**那组值 → 完美闪避的调用点一个字都不用改；
##   处决慢动作（更慢更久）与闪避共存于同一套机制，只是传不同的参数进来。
##   默认值引用实例成员，GDScript 会在**调用时**求值 —— 调用方不传就走当下的 @export 值。
## @param scale 减速倍率(1.0=常速)；hold 保持时长(真实秒)；fade 回升过渡时长(真实秒)
func start_bullet_time(scale: float = NAN, hold: float = NAN, fade: float = NAN) -> void:
	# NAN = "没传，用我自己的 @export 默认值"。这样调用方不传时读到的是场景里调好的值，
	# 而不是脚本里的字面量 —— 调参改场景即可生效（同 player 里 `:= bullet_time_scale` 的效果）。
	if is_nan(scale):
		scale = bullet_time_scale
	if is_nan(hold):
		hold = bullet_time_duration
	if is_nan(fade):
		fade = bullet_time_fade
	if _bullet_time_tween != null and _bullet_time_tween.is_valid():
		_bullet_time_tween.kill()
	_bt_factor = scale                      # 只改"自己这一份"因子 → 不会踩掉正在进行的顿帧
	_push_time_scale()
	_bullet_time_tween = create_tween()
	_bullet_time_tween.set_ignore_time_scale(true)      # ★ 关键：别被自己造成的减速拖慢
	_bullet_time_tween.tween_interval(hold)
	_bullet_time_tween.tween_method(_set_bullet_factor, scale, 1.0, fade)


## 顿帧(hitstop)：命中瞬间把全局时间压到几乎定格，持续 real_seconds **真实秒**后迅速弹回。
## 【为什么要设上限取最狠的一次】重叠命中（一刀扫到两个敌人）会连着调两次，
##   若每次都从头计时，顿帧会被叠成"两倍长" —— kill 掉上一次反而更稳。
## @param real_seconds 顿帧时长（真实秒）。<=0 直接忽略。
func start_hitstop(real_seconds: float) -> void:
	if real_seconds <= 0.0 or hitstop_scale >= 1.0:
		return
	if _hitstop_tween != null and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	_hs_factor = hitstop_scale
	_push_time_scale()
	_hitstop_tween = create_tween()
	_hitstop_tween.set_ignore_time_scale(true)          # ★ 同子弹时间：别被自己的减速拖长
	_hitstop_tween.tween_interval(real_seconds)
	# 收尾用一段极短的淡出而不是硬跳回 1.0：硬跳会有一下可闻的"顿挫感"
	_hitstop_tween.tween_method(_set_hitstop_factor, hitstop_scale, 1.0, hitstop_release)


## 临时压慢时间但不自动回升（处决分镜想自己控制何时恢复时用）。
## 与 start_bullet_time 共用同一个因子 —— 两者是"同一路效果的不同驱动方式"。
func set_bullet_factor(v: float) -> void:
	_set_bullet_factor(v)


## 立即停掉所有减速并复位（重开 / 传送 / 剧情打断时用）。
func reset() -> void:
	if _bullet_time_tween != null and _bullet_time_tween.is_valid():
		_bullet_time_tween.kill()
	if _hitstop_tween != null and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	_bt_factor = 1.0                 # 两个因子也一并复位，否则下次 _push_time_scale 会把旧值带回来
	_hs_factor = 1.0
	Engine.time_scale = 1.0
	time_scale_changed.emit(1.0)


## 当前全局时间倍率（= 两个因子中更慢的那个）。只读查询用。
func current_scale() -> float:
	return minf(_bt_factor, _hs_factor)


## 是否正在减速（子弹时间或顿帧任一生效）。
func is_slowed() -> bool:
	return current_scale() < 1.0


## 子弹时间因子的写入口（由上面的补间逐帧调用，也可外部直接调用）。
func _set_bullet_factor(v: float) -> void:
	_bt_factor = v
	_push_time_scale()


## 顿帧因子的写入口（由上面的补间逐帧调用）。
func _set_hitstop_factor(v: float) -> void:
	_hs_factor = v
	_push_time_scale()


## 把两个因子合成真正的全局时间倍率 —— 取**更慢的那个**。
## 【为什么是 min 而不是乘】见文件头"核心设计"。
func _push_time_scale() -> void:
	Engine.time_scale = minf(_bt_factor, _hs_factor)
	time_scale_changed.emit(Engine.time_scale)


## 被销毁（重开场景 / 退出）时把时间倍率复位。
## 【为什么必须兜底】Engine.time_scale 是**全局单例**，一旦在减速状态里被销毁，
##   补间随之消失 → 整个游戏（包括下一个场景）都会永远停留在 0.45 倍速。
func _exit_tree() -> void:
	reset()
