extends SceneTree
## 开发辅助：逐帧比较抓取到的画面，输出"运动量"曲线，
## 用来证明某段动画（如翻滚）在运行时确实在播放。
## 用法：godot --headless --path . --script res://tools/anim_diff.gd -- <相对res的帧目录>

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var dir := ".tmp_anim" if args.is_empty() else args[0]
    var base := ProjectSettings.globalize_path("res://").trim_suffix("/")
    var dir_path := base + "/" + dir

    var frames: Array[String] = []
    var i := 0
    while true:
        var p := "%s/frame%08d.png" % [dir_path, i]
        if not FileAccess.file_exists(p):
            break
        frames.append(p)
        i += 1
    print("扫描到帧数: ", frames.size())
    if frames.size() < 3:
        quit(1)
        return

    var prev: Image = null
    var step := 4
    var peak := 0.0
    var peak_frame := -1
    for idx in frames.size():
        var img := Image.load_from_file(frames[idx])
        if img == null:
            continue
        img.convert(Image.FORMAT_RGB8)
        if prev != null:
            var diff := 0
            var total := 0
            for y in range(0, img.get_height(), step):
                for x in range(0, img.get_width(), step):
                    var a := prev.get_pixel(x, y)
                    var b := img.get_pixel(x, y)
                    total += 1
                    # 单通道差异阈值 0.05，超过即认为该点"动了"
                    if absf(a.r - b.r) > 0.05 or absf(a.g - b.g) > 0.05 or absf(a.b - b.b) > 0.05:
                        diff += 1
            var pct := float(diff) * 100.0 / float(maxi(1, total))
            if pct > peak:
                peak = pct
                peak_frame = idx
            if idx % 6 == 0 or pct > 5.0:
                var avg := _avg_color(img, step)
                print("帧 %3d: 运动量 %5.2f%%  平均色=(%3d,%3d,%3d)" % [
                    idx, pct, int(avg.r * 255), int(avg.g * 255), int(avg.b * 255)])
        prev = img
    print("=== 峰值运动量 %.2f%% 出现在帧 %d ===" % [peak, peak_frame])
    quit(0)


## 计算整幅图的平均颜色（用于判断该帧是否为"退出时的空/黑帧"）。
func _avg_color(img: Image, step: int) -> Color:
    var sum := Vector3.ZERO
    var n := 0
    for y in range(0, img.get_height(), step):
        for x in range(0, img.get_width(), step):
            var c := img.get_pixel(x, y)
            sum += Vector3(c.r, c.g, c.b)
            n += 1
    return Color(sum.x / n, sum.y / n, sum.z / n)
