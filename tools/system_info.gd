extends SceneTree
## 开发辅助：打印本机显示设备与渲染设备信息。
## 先通过 ClassDB 反射确认可用方法名（不同 Godot 版本命名不同），再安全调用。
## 用法（必须非 headless：headless 用假显示服务，读不到真实屏幕）：
##   godot --path . --script res://tools/system_info.gd

func _init() -> void:
    # ---- 1) 反射：列出 DisplayServer / RenderingServer 里与屏幕、显卡相关的方法 ----
    var ds_methods: Array[String] = []
    for m in ClassDB.class_get_method_list("DisplayServer"):
        var n: String = m["name"]
        if n.contains("screen") or n.contains("window_get_size") or n.contains("window_get_position"):
            ds_methods.append(n)
    ds_methods.sort()
    print("DisplayServer 可用方法: ", ds_methods)

    # ---- 2) 屏幕信息 ----
    var count_method := "get_screen_count" if _has_ds("get_screen_count") else "screen_get_count"
    var n: int = 1
    if _has_ds(count_method):
        n = int(DisplayServer.call(count_method))
    print("===== 屏幕 =====")
    print("屏幕数量: ", n)
    if _has_ds("get_primary_screen"):
        print("主屏索引: ", DisplayServer.call("get_primary_screen"))
    for i in n:
        print("--- 屏幕 %d ---" % i)
        for method in ["screen_get_name", "screen_get_size", "screen_get_usable_rect",
                "screen_get_position", "screen_get_refresh_rate", "screen_get_scale", "screen_get_dpi"]:
            if _has_ds(method):
                print("  %s = %s" % [method, str(DisplayServer.call(method, i))])
        if _has_ds("screen_get_max_scale"):
            print("  screen_get_max_scale = ", DisplayServer.call("screen_get_max_scale"))

    # ---- 3) 渲染设备 ----
    print("===== 渲染设备 =====")
    for method in ["get_video_adapter_name", "get_video_adapter_vendor", "get_video_adapter_type",
            "get_video_adapter_api_version"]:
        if ClassDB.class_has_method("RenderingServer", method):
            print("  RenderingServer.%s = %s" % [method, str(RenderingServer.call(method))])
    print("  DisplayServer.get_name() = ", DisplayServer.get_name())
    print("  游戏窗口尺寸 = ", DisplayServer.window_get_size())
    quit(0)


func _has_ds(method: String) -> bool:
    return ClassDB.class_has_method("DisplayServer", method)
