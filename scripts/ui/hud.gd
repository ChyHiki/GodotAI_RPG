extends CanvasLayer
class_name Hud
## ============================================================
## HUD（游戏内 UI）
## ============================================================
## 【作用】玩家血条(左上)、敌人血条+失衡条(右上)、屏幕中央准星、顶部提示消息、
##   死亡全屏遮罩、完美格挡的全屏金光、完美闪避的全屏青光。
## 【为什么全部用代码创建控件】
##   便于无美术资源起步、也便于随时调整颜色/尺寸。用 Control 节点 +
##   锚点(anchor)定位：血条钉在四个角、准星钉在屏幕中心，窗口缩放不跑位。
## 【对外接口（主场景调用）】
##   set_player_hp(cur,max) / set_enemy_hp(cur,max)  刷新血条
##   set_enemy_poise(cur,max,broken)                 刷新敌人下方的**黄色失衡条**
##   flash_parry()                                   完美格挡时全屏闪一下金光
##   flash_dodge()                                   完美闪避时全屏闪一下青光
##   show_message(文本,秒数)                          顶部提示后淡出
##   show_death() / hide_death()                      死亡遮罩
## ============================================================

## ---- 各控件的引用（_build_hud 里创建后保存，供更新函数使用）----
var _player_fill: ColorRect    # 玩家血条里的"绿色填充条"
var _enemy_fill: ColorRect     # 敌人血条里的"红色填充条"
var _enemy_root: Control       # 敌人血条整组(背景+填充+标题)，血条为 0 时整组隐藏
var _enemy_label: Label        # 敌人血条上方的小标题（失衡时会改成"按左键处决"）
var _poise_fill: ColorRect     # 敌人失衡条里的"黄色填充条"
var _poise_root: Control       # 失衡条整组（敌人未失衡时也常驻显示，让玩家看到进度）
var _parry_flash: ColorRect    # 完美格挡时的全屏金色闪光层（平时 alpha=0）
var _dodge_flash: ColorRect    # 完美闪避时的全屏青色闪光层（平时 alpha=0；与金光各占一层）
var _message_label: Label      # 顶部提示消息文本
var _message_tween: Tween      # 提示消息的"停留→淡出"补间（重发消息时要先 kill 掉旧的）
var _death_overlay: Control    # 死亡遮罩（半透明红底 + 文字）
var _crosshair: ColorRect      # 屏幕正中央的小白方块 = 准星


func _ready() -> void:
    add_to_group("hud")   # 注册进 "hud" 组，主场景用 get_first_node_in_group("hud") 找到它
    layer = 10            # CanvasLayer 层级：数字大者显示在上层（盖住 3D 世界）
    _build_hud()          # 一次性创建所有控件
    hide_death()          # 初始隐藏死亡遮罩


# ------------------------------------------------------------------
# 对外接口（主场景/角色信号回调）
# ------------------------------------------------------------------

## 刷新玩家血条（由玩家 Health 组件的 changed 信号驱动）。
func set_player_hp(current: int, max_hp: int) -> void:
    _set_bar(_player_fill, current, max_hp)


## 刷新敌人血条；血量为 0 时自动隐藏整条敌人血条（含失衡条）。
func set_enemy_hp(current: int, max_hp: int) -> void:
    _set_bar(_enemy_fill, current, max_hp)
    var alive := current > 0
    _enemy_root.visible = alive
    if _poise_root != null:
        _poise_root.visible = alive


## ★ 刷新敌人的**黄色失衡条**（由敌人 Poise 组件的 changed 信号驱动）。
## 【为什么失衡条常驻显示】它是"完美格挡的进度条"——玩家必须看得见"还差几次"
##   才能规划下一次弹反。若只在失衡时才出现，玩家永远不知道自己攒到哪了。
## @param broken 是否已进入失衡：进入时整条变亮 + 标题改成"按左键处决"
func set_enemy_poise(current: float, max_poise: float, broken: bool) -> void:
    if _poise_fill == null:
        return
    var ratio := 0.0
    if max_poise > 0.0:
        ratio = clampf(current / max_poise, 0.0, 1.0)
    _poise_fill.size = Vector2(296.0 * ratio, 10.0)
    # 失衡中：把黄条拉到最亮的金黄；平时是偏暗的琥珀色（一眼区分"攒一半"和"满了"）
    _poise_fill.color = Color(1.0, 0.92, 0.25) if broken else Color(0.85, 0.68, 0.18)
    if _enemy_label != null:
        _enemy_label.text = "ENEMY  ——  已失衡！按左键处决" if broken else "ENEMY"
        _enemy_label.add_theme_color_override(
            "font_color", Color(1.0, 0.9, 0.3, 1.0) if broken else Color(1, 0.6, 0.5, 0.9))


## 显示/隐藏整条失衡条（对手**没有**失衡条时调用，比如"操控敌人"时对手是玩家）。
## 【为什么不能只把数值刷成 0】空黄条仍然占着位置，看起来像"进度条坏了"；
##   没有失衡机制就该整组收掉，别给玩家假信息。
func set_enemy_poise_visible(visible_: bool) -> void:
    if _poise_root != null:
        _poise_root.visible = visible_


## 完美格挡的全屏反馈：整屏泛一下金光后立刻淡掉。
## 【为什么用全屏色块而不是闪光贴图】纯代码、零资源，且"余光感"最强 ——
##   玩家视线在屏幕中央也能立刻感到"刚才那一下弹对了"。
## 用 set_deferred 之外的普通 tween：这里只是改 alpha，没有物理时序问题。
func flash_parry() -> void:
    if _parry_flash == null:
        return
    _parry_flash.color = Color(1.0, 0.86, 0.30, 0.30)   # 起手 30% 不透明的金
    var tw := create_tween()
    tw.tween_property(_parry_flash, "color:a", 0.0, 0.28)


## 完美闪避的全屏反馈：整屏泛一下青光后淡掉（青色 = 冷色 = "躲开了"，
## 与完美格挡的金色"顶回去了"一眼区分）。
## ⚠ 补间必须 set_ignore_time_scale(true)：完美闪避会**同时**触发子弹时间，
##   而 HUD 是 CanvasLayer（默认跟随 time_scale），不禁用的话这段淡出会被拖慢
##   到 0.28 / 0.35 = 0.8 秒，闪光变成"糊在屏幕上不走"。
func flash_dodge() -> void:
    if _dodge_flash == null:
        return
    _dodge_flash.color = Color(0.45, 0.85, 1.0, 0.34)
    var tw := create_tween()
    tw.set_ignore_time_scale(true)
    tw.tween_property(_dodge_flash, "color:a", 0.0, 0.28)


## 在屏幕顶部显示一条提示消息，停留 duration 秒后 0.5 秒内淡出。
## 实现：改 Label 文本 → 用 Tween 先等待再淡出透明度。
## 【为什么要 kill 掉上一条的 Tween】两条消息在时间上重叠时（例如开场提示还没淡完
##   就弹出"敌人失衡了"），上一条的淡出 Tween 到点后会把**新消息**的透明度也拉成 0，
##   表现为"新提示一闪就没了"。所以每次先杀掉旧的，保证同一时刻只有一条在管这个 Label。
func show_message(text: String, duration: float = 2.5) -> void:
    if _message_tween != null and _message_tween.is_valid():
        _message_tween.kill()
    _message_label.text = text
    _message_label.modulate.a = 1.0
    _message_tween = create_tween()
    _message_tween.tween_interval(duration)                    # 先停留
    _message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.5)  # 再淡出


## 显示死亡遮罩（玩家死亡时由主场景调用）。
func show_death() -> void:
    _death_overlay.visible = true


## 隐藏死亡遮罩（游戏重开/重载后默认隐藏）。
func hide_death() -> void:
    _death_overlay.visible = false


# ------------------------------------------------------------------
# UI 构建
# ------------------------------------------------------------------

## 一次性创建所有 HUD 控件。
## 布局：玩家血条钉左上角(20,20)，敌人血条钉右上角，消息居中偏上，
##       准星居中，死亡遮罩铺满全屏。
func _build_hud() -> void:
    # ---------- 玩家血条（左上角） ----------
    # pcont：一个锚定在左上角的空容器，用来整体定位
    var pcont := Control.new()
    pcont.set_anchors_preset(Control.PRESET_TOP_LEFT)  # 锚点=左上角
    pcont.position = Vector2(20, 20)                   # 离角 20px
    add_child(pcont)
    var pbar := _make_bar(Color(0.3, 0.95, 0.42))      # 绿色血条
    pcont.add_child(pbar)
    _player_fill = pbar.get_child(1) as ColorRect      # 保存"填充条"(第 2 个孩子)
    var plabel := _make_label("HP", Color(1, 1, 1, 0.9), 14, Vector2(-32, 3))
    pcont.add_child(plabel)

    # ---------- 敌人血条（右上角，锚定右上向左伸展） ----------
    _enemy_root = Control.new()
    _enemy_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _enemy_root.position = Vector2(-320, 20)  # 相对右上角往左 320px
    _enemy_root.size = Vector2(300, 20)
    add_child(_enemy_root)
    var ebar := _make_bar(Color(0.95, 0.3, 0.25))      # 红色血条
    ebar.size = Vector2(300, 20)
    ebar.position = Vector2.ZERO
    _enemy_root.add_child(ebar)
    _enemy_fill = ebar.get_child(1) as ColorRect
    _enemy_label = _make_label("ENEMY", Color(1, 0.6, 0.5, 0.9), 13, Vector2(0, -18))
    _enemy_root.add_child(_enemy_label)

    # ---------- 敌人失衡条（紧贴血条下方的细黄条） ----------
    # 【为什么放在血条正下方】失衡是"下一次处决的进度"，和血量是同一条视线上的信息，
    #   上下并排看最省眼球移动。细一点(10px)是为了不抢血条的视觉权重。
    _poise_root = Control.new()
    _poise_root.position = Vector2(0, 24)      # 血条(20高)下面留 4px 缝
    _poise_root.size = Vector2(300, 10)
    _enemy_root.add_child(_poise_root)
    var poise_bg := ColorRect.new()
    poise_bg.color = Color(0, 0, 0, 0.55)
    poise_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    _poise_root.add_child(poise_bg)
    var poise_fill := ColorRect.new()
    poise_fill.color = Color(0.85, 0.68, 0.18)   # 琥珀黄（未满）
    poise_fill.position = Vector2(2, 2)
    poise_fill.size = Vector2(0, 6)              # 初始空条，宽度由 set_enemy_poise 给
    _poise_root.add_child(poise_fill)
    _poise_fill = poise_fill

    _enemy_root.visible = false                        # 默认隐藏（敌人未在场）

    # ---------- 中央准星（屏幕正中央的小白点） ----------
    _crosshair = ColorRect.new()
    _crosshair.color = Color(1, 1, 1, 0.85)
    _crosshair.size = Vector2(6, 6)
    _crosshair.set_anchors_preset(Control.PRESET_CENTER)  # 锚点=屏幕中心
    _crosshair.position = Vector2(-3, -3)                  # 让 6x6 方块居中(偏移一半)
    add_child(_crosshair)

    # ---------- 顶部提示消息 ----------
    _message_label = Label.new()
    _message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)  # 顶部通栏
    _message_label.position = Vector2(0, 70)
    _message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message_label.add_theme_font_size_override("font_size", 22)
    _message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
    # 给文字加阴影提高可读性
    _message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    _message_label.add_theme_constant_override("shadow_offset_x", 2)
    _message_label.add_theme_constant_override("shadow_offset_y", 2)
    add_child(_message_label)

    # ---------- 完美格挡的全屏金光层 ----------
    # 【为什么放在死亡遮罩前面】CanvasLayer 里后加的孩子画在上面；
    #   金光应该盖住 3D 世界与血条，但不能盖住死亡遮罩，所以插在遮罩之前。
    _parry_flash = ColorRect.new()
    _parry_flash.set_anchors_preset(Control.PRESET_FULL_RECT)   # 铺满窗口
    _parry_flash.color = Color(1.0, 0.86, 0.30, 0.0)            # 平时完全透明
    add_child(_parry_flash)

    # ---------- 完美闪避的全屏青光层 ----------
    # 【为什么要跟金光是**两个独立控件**】两者可能在极短时间内先后触发
    #   （挡一下、紧接着闪一下），共用一个 ColorRect 时后一个 tween 会把前一个的
    #   淡出进度也拉走（同 show_message 踩过的坑）。各管各的，颜色也不会互相污染。
    _dodge_flash = ColorRect.new()
    _dodge_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
    _dodge_flash.color = Color(0.45, 0.85, 1.0, 0.0)
    add_child(_dodge_flash)

    # ---------- 死亡遮罩（全屏半透明红 + 标题 + 提示） ----------
    _death_overlay = Control.new()
    _death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)  # 铺满窗口
    var dim := ColorRect.new()
    dim.color = Color(0.35, 0.02, 0.02, 0.55)  # 半透明暗红
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _death_overlay.add_child(dim)
    # "你阵亡了"大标题（居中）
    var title := Label.new()
    title.text = "你 阵 亡 了"
    title.set_anchors_preset(Control.PRESET_CENTER)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 56)
    title.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    title.add_theme_constant_override("shadow_offset_x", 3)
    title.add_theme_constant_override("shadow_offset_y", 3)
    title.position = Vector2(-120, -80)   # 居中后再上移一点
    title.size = Vector2(240, 90)
    _death_overlay.add_child(title)
    # 下方小字提示
    var hint := Label.new()
    hint.text = "按  R  重新开始"
    hint.set_anchors_preset(Control.PRESET_CENTER)
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.add_theme_font_size_override("font_size", 24)
    hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    hint.position = Vector2(-160, 10)
    hint.size = Vector2(320, 40)
    _death_overlay.add_child(hint)
    add_child(_death_overlay)

    # 关键：让所有 HUD 控件"不拦截鼠标事件"。
    # Control 默认会吃掉落在自己范围内的点击/移动事件，导致
    # 血条/准星/文字下方的鼠标点击到不了游戏（镜头环绕、攻击都会失灵）。
    _set_mouse_ignore(self)


## 递归把本 HUD 下所有 Control 的 mouse_filter 设为 IGNORE（完全透明给鼠标）。
func _set_mouse_ignore(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _set_mouse_ignore(child)


## 制作一根"血条"：返回一个 300x20 的 Control，
## 内含两个 ColorRect：孩子[0]=深色底，孩子[1]=彩色填充(调用方需保存)。
func _make_bar(fill_color: Color) -> Control:
    var bar := Control.new()
    bar.size = Vector2(300, 20)
    # 底色（半透明黑，让血条在任意背景上都看得清）
    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.55)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bar.add_child(bg)
    # 彩色填充条（默认撑满，宽度由 _set_bar 按血量比例改）
    var fill := ColorRect.new()
    fill.color = fill_color
    fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
    fill.position = Vector2(2, 2)
    fill.size = Vector2(296, 16)
    bar.add_child(fill)
    return bar


## 快速创建带指定文字/颜色/字号/位置的 Label（纯代码 UI 的简写工具）。
func _make_label(text: String, color: Color, font_size: int, pos: Vector2) -> Label:
    var lb := Label.new()
    lb.text = text
    lb.position = pos
    lb.add_theme_font_size_override("font_size", font_size)
    lb.add_theme_color_override("font_color", color)
    return lb


## 按"当前/最大"比例设置填充条的宽度（血条核心逻辑）。
## 实现：比例 = clamp(cur/max, 0, 1)，宽度 = 296 * 比例（296=300-2*2边距）。
func _set_bar(fill: ColorRect, current: int, max_hp: int) -> void:
    if fill == null or max_hp <= 0:
        return
    var ratio := clampf(float(current) / float(max_hp), 0.0, 1.0)
    var full_width: float = 296.0
    fill.size = Vector2(full_width * ratio, 16.0)
