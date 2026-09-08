extends CanvasLayer
class_name Hud
## ============================================================
## HUD（游戏内 UI）
## ============================================================
## 【作用】玩家血条(左上)、敌人血条(右上)、屏幕中央准星、顶部提示消息、
##   死亡全屏遮罩。
## 【为什么全部用代码创建控件】
##   便于无美术资源起步、也便于随时调整颜色/尺寸。用 Control 节点 +
##   锚点(anchor)定位：血条钉在四个角、准星钉在屏幕中心，窗口缩放不跑位。
## 【对外接口（主场景调用）】
##   set_player_hp(cur,max) / set_enemy_hp(cur,max)  刷新血条
##   show_message(文本,秒数)                          顶部提示后淡出
##   show_death() / hide_death()                      死亡遮罩
## ============================================================

## ---- 各控件的引用（_build_hud 里创建后保存，供更新函数使用）----
var _player_fill: ColorRect    # 玩家血条里的"绿色填充条"
var _enemy_fill: ColorRect     # 敌人血条里的"红色填充条"
var _enemy_root: Control       # 敌人血条整组(背景+填充+标题)，血条为 0 时整组隐藏
var _message_label: Label      # 顶部提示消息文本
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


## 刷新敌人血条；血量为 0 时自动隐藏整条敌人血条。
func set_enemy_hp(current: int, max_hp: int) -> void:
    _set_bar(_enemy_fill, current, max_hp)
    _enemy_root.visible = current > 0


## 在屏幕顶部显示一条提示消息，停留 duration 秒后 0.5 秒内淡出。
## 实现：改 Label 文本 → 用 Tween 先等待再淡出透明度。
func show_message(text: String, duration: float = 2.5) -> void:
    _message_label.text = text
    _message_label.modulate.a = 1.0
    var tw := create_tween()
    tw.tween_interval(duration)                    # 先停留
    tw.tween_property(_message_label, "modulate:a", 0.0, 0.5)  # 再淡出


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
    var elabel := _make_label("ENEMY", Color(1, 0.6, 0.5, 0.9), 13, Vector2(0, -18))
    _enemy_root.add_child(elabel)
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
