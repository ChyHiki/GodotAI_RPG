extends CanvasLayer
class_name Hud
## M1 HUD：玩家血条、敌人血条、准星、提示消息、死亡遮罩。
## 全部由代码构建，无 UI 美术依赖。

var _player_fill: ColorRect
var _enemy_fill: ColorRect
var _enemy_root: Control
var _message_label: Label
var _death_overlay: Control
var _crosshair: ColorRect


func _ready() -> void:
    add_to_group("hud")
    layer = 10
    _build_hud()
    hide_death()


# ------------------------------------------------------------------ 对外接口

func set_player_hp(current: int, max_hp: int) -> void:
    _set_bar(_player_fill, current, max_hp)


func set_enemy_hp(current: int, max_hp: int) -> void:
    _set_bar(_enemy_fill, current, max_hp)
    _enemy_root.visible = current > 0


func show_message(text: String, duration: float = 2.5) -> void:
    _message_label.text = text
    _message_label.modulate.a = 1.0
    var tw := create_tween()
    tw.tween_interval(duration)
    tw.tween_property(_message_label, "modulate:a", 0.0, 0.5)


func show_death() -> void:
    _death_overlay.visible = true


func hide_death() -> void:
    _death_overlay.visible = false


# ------------------------------------------------------------------ 构建 UI

func _build_hud() -> void:
    # 玩家血条（左上）
    var pcont := Control.new()
    pcont.set_anchors_preset(Control.PRESET_TOP_LEFT)
    pcont.position = Vector2(20, 20)
    add_child(pcont)
    var pbar := _make_bar(Color(0.3, 0.95, 0.42))
    pcont.add_child(pbar)
    _player_fill = pbar.get_child(1) as ColorRect
    var plabel := _make_label("HP", Color(1, 1, 1, 0.9), 14, Vector2(-32, 3))
    pcont.add_child(plabel)

    # 敌人血条（右上）
    _enemy_root = Control.new()
    _enemy_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _enemy_root.position = Vector2(-320, 20)
    _enemy_root.size = Vector2(300, 20)
    add_child(_enemy_root)
    var ebar := _make_bar(Color(0.95, 0.3, 0.25))
    ebar.size = Vector2(300, 20)
    ebar.position = Vector2.ZERO
    _enemy_root.add_child(ebar)
    _enemy_fill = ebar.get_child(1) as ColorRect
    var elabel := _make_label("ENEMY", Color(1, 0.6, 0.5, 0.9), 13, Vector2(0, -18))
    _enemy_root.add_child(elabel)
    _enemy_root.visible = false

    # 准星
    _crosshair = ColorRect.new()
    _crosshair.color = Color(1, 1, 1, 0.85)
    _crosshair.size = Vector2(6, 6)
    _crosshair.set_anchors_preset(Control.PRESET_CENTER)
    _crosshair.position = Vector2(-3, -3)
    add_child(_crosshair)

    # 顶部提示消息
    _message_label = Label.new()
    _message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _message_label.position = Vector2(0, 70)
    _message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message_label.add_theme_font_size_override("font_size", 22)
    _message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
    _message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    _message_label.add_theme_constant_override("shadow_offset_x", 2)
    _message_label.add_theme_constant_override("shadow_offset_y", 2)
    add_child(_message_label)

    # 死亡遮罩
    _death_overlay = Control.new()
    _death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    var dim := ColorRect.new()
    dim.color = Color(0.35, 0.02, 0.02, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _death_overlay.add_child(dim)
    var title := Label.new()
    title.text = "你 阵 亡 了"
    title.set_anchors_preset(Control.PRESET_CENTER)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 56)
    title.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    title.add_theme_constant_override("shadow_offset_x", 3)
    title.add_theme_constant_override("shadow_offset_y", 3)
    title.position = Vector2(-120, -80)
    title.size = Vector2(240, 90)
    _death_overlay.add_child(title)
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


func _make_bar(fill_color: Color) -> Control:
    var bar := Control.new()
    bar.size = Vector2(300, 20)
    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.55)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bar.add_child(bg)
    var fill := ColorRect.new()
    fill.color = fill_color
    fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
    fill.position = Vector2(2, 2)
    fill.size = Vector2(296, 16)
    bar.add_child(fill)
    return bar


func _make_label(text: String, color: Color, font_size: int, pos: Vector2) -> Label:
    var lb := Label.new()
    lb.text = text
    lb.position = pos
    lb.add_theme_font_size_override("font_size", font_size)
    lb.add_theme_color_override("font_color", color)
    return lb


func _set_bar(fill: ColorRect, current: int, max_hp: int) -> void:
    if fill == null or max_hp <= 0:
        return
    var ratio := clampf(float(current) / float(max_hp), 0.0, 1.0)
    var full_width: float = 296.0
    fill.size = Vector2(full_width * ratio, 16.0)
