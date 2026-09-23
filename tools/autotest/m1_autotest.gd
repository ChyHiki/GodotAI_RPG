extends Node
## M1 战斗闭环自动化测试（headless 运行）：
##   闪避无敌帧+完美闪避(虚影/子弹时间) / 敌人挥击扣血 / 玩家挥砍扣血 / 击杀→重生 / 玩家死亡遮罩
## 运行：Godot --headless --path . res://tools/autotest/m1_autotest.tscn
## 退出码 0 = 全部通过；1 = 存在失败项。

var failures: Array[String] = []


func _ready() -> void:
    await _run()
    if failures.is_empty():
        print("AUTOTEST RESULT: ALL PASS")
        get_tree().quit(0)
    else:
        for f in failures:
            push_error("AUTOTEST FAIL: " + f)
        print("AUTOTEST RESULT: %d FAILED" % failures.size())
        get_tree().quit(1)


func _run() -> void:
    await _wait(0.6)  # 让主场景生成并落地

    var main: Node = load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    await _wait(0.8)  # 等待玩家/敌人出生与落地

    var player := get_tree().get_first_node_in_group("player")
    var enemy := get_tree().get_first_node_in_group("enemy")
    var hud := get_tree().get_first_node_in_group("hud")
    _expect(player != null, "玩家已生成")
    _expect(enemy != null, "敌人已生成")
    if player == null or enemy == null:
        return
    _expect(player.is_alive(), "玩家初始存活")
    _expect(enemy.is_alive(), "敌人初始存活")
    _expect(player.health.current_hp == 100, "玩家初始 HP=100，实际 %d" % player.health.current_hp)
    _expect(enemy.health.current_hp == 100, "敌人初始 HP=100，实际 %d" % enemy.health.current_hp)

    # ---- 0) 玩家外观：应加载骑士模型（KnightModel 挂在 VisualPivot 下）----
    var pivot = player.get_node_or_null("VisualPivot")
    var has_knight: bool = pivot != null and pivot.has_node("KnightModel")
    _expect(has_knight, "玩家使用外部模型 KnightModel")
    # 模型是骨骼版，含 12 段动画，应被自动识别（名字大小写/下划线无关）
    _expect(player._anim_player != null, "模型含 AnimationPlayer")
    _expect(player._skeleton != null, "模型含 Skeleton3D")
    if player._skeleton != null:
        _expect(player._skeleton.get_bone_count() >= 15,
            "骨骼数量正常(%d 根)" % player._skeleton.get_bone_count())
    _expect(player._dodge_fwd_anim == "DodgeForward", "识别前冲动画: %s" % player._dodge_fwd_anim)
    _expect(player._dodge_back_anim == "DodgeBack", "识别后撤动画: %s" % player._dodge_back_anim)
    _expect(player._walk_anim == "Walk", "识别行走动画: %s" % player._walk_anim)
    _expect(player._slash_anim == "Slash", "识别挥砍动画: %s" % player._slash_anim)
    # ---- 0-连击) 三段连击的 2/3 段动画（Slash2 / Slash3）----
    # 【识别顺序陷阱 · 与 walkstrafe 同源的坑】Slash2 / Slash3 的名字里都含 "slash"，
    #   识别时必须先判 slash2 / slash3 再判裸 slash。上面那条 `_slash_anim == "Slash"`
    #   本身就是这道顺序的守门断言 —— 一旦写反，遍历到最后的 Slash3 会覆盖 _slash_anim，
    #   这条立刻变红（症状：三段连击全长一个样，且第 1 段播的是第 3 段的动画）。
    _expect(player._slash2_anim == "Slash2", "识别连击②横斩动画: %s" % player._slash2_anim)
    _expect(player._slash3_anim == "Slash3", "识别连击③回旋收尾动画: %s" % player._slash3_anim)
    # 连击 2/3 段的设计时长同样要符合"length = N/24"的项目约定：
    #   Slash2 1..11 帧 → 11/24 = 0.4583s（内容 0.417s，对应 combo2_total）
    #   Slash3 1..15 帧 → 15/24 = 0.6250s（内容 0.583s，对应 combo3_total）
    for pair in [["Slash2", 11.0], ["Slash3", 15.0]]:
        var ca: Animation = (player._anim_player.get_animation(pair[0])
            if player._anim_player.has_animation(pair[0]) else null)
        if ca == null:
            _expect(false, "模型缺少连击动画 %s" % pair[0])
        else:
            _expect(absf(ca.length - float(pair[1]) / 24.0) < 0.01,
                "%s 时长 = %d/24(实际 %.4f，期望 %.4f)"
                    % [pair[0], int(pair[1]), ca.length, float(pair[1]) / 24.0])
            _expect(not _loop_ok(player, pair[0]), "%s 保持单次播放(不循环)" % pair[0])
    # ★★ 最后再兜一道最外层的防线：三段必须是**三段不同的动画**。
    #   这是"识别被裸 slash 规则覆盖"最直观的症状（三段连击全长一个样），
    #   单独钉一条比三条 equal 断言更难被"改断言凑过"。
    _expect(player._slash_anim != player._slash2_anim
        and player._slash2_anim != player._slash3_anim
        and player._slash_anim != player._slash3_anim,
        "★★ 三段连击用的是三段不同动画（识别未被裸 slash 规则覆盖）")
    # ⚠️ 下面两条仍要成立：**起跳动画已取消，但资产与识别都保留着**（为的是"调回 0.18 可恢复"）。
    #    识别保留 ≠ 会播放 —— "整段跳跃全程不播它"由 1d) 那条断言单独钉住。
    _expect(player._jump_start_anim == "JumpStart", "识别起跳动画: %s（已取消播放，仅保留识别）" % player._jump_start_anim)
    _expect(player._jump_air_anim == "JumpAir", "识别滞空动画: %s" % player._jump_air_anim)
    # 生活三段（Idle / Hurt / Death）：这三个状态以前是"骨骼复位 + 整体姿态"的权宜做法
    _expect(player._idle_anim == "Idle", "识别待机动画: %s" % player._idle_anim)
    _expect(player._hurt_anim == "Hurt", "识别受击动画: %s" % player._hurt_anim)
    _expect(player._death_anim == "Death", "识别倒地动画: %s" % player._death_anim)
    # 两段闪避的时长必须符合"帧偏移约定"：Animation.length = N/24 = 内容时长 + 1/24
    #   （Blender 的 Action 帧范围是 1..N → 首帧不在 0；Godot 导入时平移到 t=0）
    #   DodgeForward 1..10 帧 → 10/24 = 0.4167 s（内容 0.375 s）
    #   DodgeBack    1..12 帧 → 12/24 = 0.5000 s（内容 0.458 s）
    # ⚠ 这两条一旦因"改动画帧区间"而红，连带要改的是 player.gd 的
    #   dodge_forward_time / dodge_back_time（倍速 = length ÷ 时长 是现算的）。
    var dfwd: Animation = (player._anim_player.get_animation("DodgeForward")
        if player._anim_player.has_animation("DodgeForward") else null)
    var dback: Animation = (player._anim_player.get_animation("DodgeBack")
        if player._anim_player.has_animation("DodgeBack") else null)
    _expect(dfwd != null, "模型含 DodgeForward 动画")
    _expect(dback != null, "模型含 DodgeBack 动画")
    if dfwd != null:
        _expect(absf(dfwd.length - 10.0 / 24.0) < 0.01,
            "DodgeForward 时长 = 10/24(实际 %.3f，期望 %.3f)" % [dfwd.length, 10.0 / 24.0])
    if dback != null:
        _expect(absf(dback.length - 12.0 / 24.0) < 0.01,
            "DodgeBack 时长 = 12/24(实际 %.3f，期望 %.3f)" % [dback.length, 12.0 / 24.0])
    # 循环类动画必须开循环，否则只播一次就定住
    _expect(_loop_ok(player, "Walk"), "Walk 已设为循环播放")
    _expect(_loop_ok(player, "JumpAir"), "JumpAir 已设为循环播放")
    _expect(_loop_ok(player, "Idle"), "Idle 已设为循环播放")
    # 生活三段里只有 Idle 是循环；Hurt / Death 必须单次（Death 靠"播完冻末帧"让尸体躺着）
    _expect(not _loop_ok(player, "Hurt"), "Hurt 保持单次播放(不循环)")
    _expect(not _loop_ok(player, "Death"), "Death 保持单次播放(不循环，冻在末帧)")
    # ---- 0a) 格挡三段动画：识别正确 + 时长符合项目约定的 1/24 帧偏移 ----
    # 【识别顺序陷阱】BlockHold / BlockImpact 的名字里都含 "block"，
    #   识别时必须先判 hold / impact 再判裸 block，否则两段都会被吃成"格挡起手"。
    _expect(player._block_anim == "Block", "识别格挡起手动画: %s" % player._block_anim)
    _expect(player._block_hold_anim == "BlockHold", "识别格挡循环动画: %s" % player._block_hold_anim)
    _expect(player._block_impact_anim == "BlockImpact", "识别格挡顿挫动画: %s" % player._block_impact_anim)
    _expect(_loop_ok(player, "BlockHold"), "BlockHold 已设为循环播放")
    _expect(not _loop_ok(player, "Block"), "Block 保持单次播放(不循环)")
    _expect(not _loop_ok(player, "BlockImpact"), "BlockImpact 保持单次播放(不循环)")
    # 【时间轴约定】Blender 导出的 GLB 首帧在 1/24 而非 0，Godot 导入后
    #   Animation.length = 设计时长 + 1/24（详见 docs/GAME_DESIGN.md 的时间轴约定）。
    #   所以校验时必须减掉 1/24，别拿 length 直接和设计时长比。
    for pair in [["Block", 0.250], ["BlockHold", 1.000], ["BlockImpact", 0.333],
                 ["Idle", 2.000], ["Hurt", 0.333], ["Death", 0.542]]:
        var ba: Animation = player._anim_player.get_animation(pair[0])
        if ba == null:
            _expect(false, "缺少动画 %s" % pair[0])
        else:
            var design: float = ba.length - 1.0 / 24.0
            _expect(absf(design - float(pair[1])) < 0.01,
                "%s 设计时长 %.3fs 符合约定(实际 %.4fs)" % [pair[0], pair[1], design])
    # 命中判定窗应与"剑刃最快段"对齐（实测 Slash 动画 0.19~0.30s 为劈砍段）
    if player._anim_player != null and player._slash_anim != "":
        var slash_anim: Animation = player._anim_player.get_animation(player._slash_anim)
        var atk_spd: float = slash_anim.length / player.attack_total
        var win0: float = player.attack_active_start * atk_spd
        var win1: float = player.attack_active_end * atk_spd
        _expect(win0 > 0.14 and win1 < 0.33,
            "命中判定窗落在剑刃最快段(动画时间 %.2f~%.2fs)" % [win0, win1])
    # 模型应被自动缩放到约 1.8m 站高、脚底贴地（换模型时的回归保护）
    if pivot != null and pivot.has_node("KnightModel"):
        var model = pivot.get_node("KnightModel")
        var meshes: Array = []
        player._collect_meshes(model, Transform3D.IDENTITY, meshes)
        var mn := Vector3.INF
        var mx := -Vector3.INF
        for info in meshes:
            var mi: MeshInstance3D = info["node"]
            var aabb: AABB = mi.get_aabb()
            for corner in player._aabb_corners(aabb):
                var p: Vector3 = model.transform * ((info["xform"] as Transform3D) * corner)
                mn = mn.min(p)
                mx = mx.max(p)
        var height: float = mx.y - mn.y
        _expect(absf(height - 1.8) < 0.35, "模型站高被缩放到 1.8m 附近，实际 %.3f" % height)
        _expect(absf(mn.y) < 0.12, "模型脚底贴地(y≈0)，实际 %.3f" % mn.y)
        # ---- 0a-2) 角色 GLB 里**不能有剑**：剑是独立资产 assets/weapons/sword_01/，
        #   运行时由 player.gd 挂到 weapon.R 骨骼上。曾经踩过坑：导出脚本在导 GLB
        #   之前先把预览用的剑 import 进场景，结果剑被烘进角色 GLB（网格数 +1）。
        #   这里的算法是"从模型里收集到的网格数 − 挂点子树里的网格数"= 身体网格数。
        var all_meshes: Array = []
        player._collect_meshes(model, Transform3D.IDENTITY, all_meshes)
        var wpn_meshes: Array = []
        if player._weapon_socket != null:
            player._collect_meshes(player._weapon_socket, Transform3D.IDENTITY, wpn_meshes)
        var body_meshes: int = all_meshes.size() - wpn_meshes.size()
        _expect(body_meshes == 5,
            "角色 GLB 含 5 个身体网格(剑未烘进角色)，实际 %d" % body_meshes)

    # ---- 0b) 武器：独立武器应挂在 weapon.R 骨骼上，静止位置与"分离前"一致 ----
    var socket = player._weapon_socket
    var weapon = player._weapon
    _expect(socket != null, "武器挂点已创建(BoneAttachment3D)")
    _expect(weapon != null, "武器已装备")
    if socket != null:
        _expect(String(socket.bone_name) == "weapon.R",
            "武器挂在骨骼 weapon.R 上(实际 %s)" % socket.bone_name)
    if weapon != null and pivot != null and pivot.has_node("KnightModel"):
        var wmodel = pivot.get_node("KnightModel")
        var winv: Transform3D = wmodel.global_transform.affine_inverse()
        # ① 握柄应落在拳心（= 挂点骨骼原点）
        var grip: Vector3 = winv * weapon.global_position
        var socket_idx: int = player._skeleton.find_bone("weapon.R")
        var bone_pos: Vector3 = player._skeleton.get_bone_global_pose(socket_idx).origin
        var grip_off: float = grip.distance_to(bone_pos)
        _expect(grip_off < 0.06, "握柄位于拳心(偏差 %.3fm)" % grip_off)
        # ② 刀身应朝向身前(模型 -Z)，而不是贴在手臂上
        var blade: Vector3 = ((winv.basis * weapon.global_basis) * Vector3(0, 0, -1)).normalized()
        var blade_ang: float = rad_to_deg(blade.angle_to(Vector3(0, 0, -1)))
        _expect(blade_ang < 25.0, "刀身朝身前(与前方夹角 %.1f°)" % blade_ang)
        # ③ 剑刃应伸到身体前方（不再和手臂叠在一起）
        var wbounds: Array = [Vector3.INF, -Vector3.INF]
        _accumulate_bounds(weapon, winv, wbounds)
        var wmn: Vector3 = wbounds[0]
        _expect(wmn.z < -0.6, "剑刃伸向身体前方(最前端 z=%.2f)" % wmn.z)
        # ④ 挥砍时剑应随手臂骨骼大幅移动（证明是骨骼挂载，不是钉死在原地）
        var rel_before: Vector3 = winv * weapon.global_position
        player._try_start_attack()
        await _wait(0.3)                       # 劈砍段
        var rel_mid: Vector3 = winv * weapon.global_position
        _expect(rel_mid.distance_to(rel_before) > 0.25,
            "挥砍时剑跟随手臂骨骼(相对位移 %.2fm)" % rel_mid.distance_to(rel_before))
        await _wait(0.5)                       # 等攻击结束

    # ---- 1) 闪避·前闪（有方向输入）：转身 + DodgeForward + 无敌 + 距离 ----
    # 【方向规则 2026-09-20 改】`_try_start_dodge()` 现在按"有没有移动输入"选段：
    #   **任意方向键 + Shift = 前闪**（并且身体**先转向那个方向**），**单按 Shift = 后闪**（朝背后、不改朝向）。
    #   初版是"有 W 才前冲"，A/S/D+Shift 一律变成后撤 —— 想往左拉开得先转镜头，很反直觉。
    #   ⚠ 前闪会改朝向，所以"起手前的朝向"和"起手后的朝向"必须分开取，别拿同一个变量前后对比。
    var pos_before: Vector3 = player.global_position
    Input.action_press("move_forward")
    await get_tree().physics_frame          # 让 just_pressed 之外的状态先落到 Input 上
    player._try_start_dodge()
    Input.action_release("move_forward")
    await _wait(0.06)
    _expect(player.state == PlayerCharacter.State.DODGE,
        "[前闪] 已进入 DODGE 状态(实际 %d)" % player.state)
    _expect(player._dodge_is_forward, "[前闪] 有方向输入时应判为前闪")
    _expect(player._anim_player.current_animation == player._dodge_fwd_anim,
        "[前闪] 播放 %s(实际 %s)" % [player._dodge_fwd_anim, player._anim_player.current_animation])
    # ★★ 前闪必须真的转身到闪避方向（初版那条"闪避不改朝向"的规则对前闪已作废）
    var face_fwd: Vector3 = -player._pivot.global_basis.z
    face_fwd.y = 0.0
    var dot_face_dir: float = face_fwd.normalized().dot(player._dodge_dir.normalized())
    _expect(dot_face_dir > 0.95,
        "[前闪] 身体应已转向闪避方向(朝向·位移点积 %.3f)" % dot_face_dir)
    # ★ 倍速必须用 get_playing_speed() 读，不能读 speed_scale：
    #   实播速度 = 属性 speed_scale × play(name, -1, custom_speed) 两者相乘，
    #   只读 speed_scale 会漏掉 play() 传进去的那一半（本工程实测差 2 倍）。
    _expect(absf(player._anim_player.get_playing_speed() - player._dodge_anim_speed) < 0.05,
        "[前冲] 实播倍速 = length/时长 = %.3f(实际 %.3f)" % [
            player._dodge_anim_speed, player._anim_player.get_playing_speed()])
    player.take_damage(15, player.global_position + Vector3(0, 0, 1))
    _expect(player.health.current_hp == 100,
        "[闪避无敌] 闪避期间扣血了: %d" % player.health.current_hp)
    await _wait(0.45)          # 等整段前冲播完(dodge_forward_time=0.375s)
    # ★ 补齐 Idle 之后，"收招"不再是"动画停播 + 骨骼复位"，而是**切到 Idle 呼吸循环**。
    #   Idle 是循环动画 → is_playing() 恒为 true，所以断言要看"当前在播 Idle"。
    _expect(_idling(player),
        "[前闪] 结束后切到 Idle 待机(实际 %s)" % player._anim_player.current_animation)
    var moved: float = Vector2(player.global_position.x - pos_before.x,
        player.global_position.z - pos_before.z).length()
    # ★ 距离是**用户明确要求的** 4m（旧值只有 1.8m，反馈太短）。
    #   位移 = 速度 × 速度曲线均值(0.725) × 时长 = 14.7 × 0.725 × 0.375 ≈ 4.0m。
    #   容差给 ±20%：撞到台阶/斜坡会有损耗，但差到 3m 以下一定是参数被改回去了。
    _expect(moved > 3.2 and moved < 4.8,
        "[前闪] 位移应约 4.0m(实际 %.2fm)" % moved)

    # ---- 1a-1.5) 前闪靠方向键定方向：按 A 也应该是前闪，且转向 A 的方向 ----
    # 【这一条为什么必须有】初版规则下 A+Shift 会被判成**后撤**，正是用户反馈要改掉的行为。
    #   这里用"自己先算一遍 wish 方向"来写断言：不依赖镜头当前朝哪，任何机位下都成立。
    await _wait(0.2)
    Input.action_press("move_left")
    await get_tree().physics_frame
    player._update_wish_dir()
    var wish_left: Vector3 = player._wish_dir
    wish_left.y = 0.0
    wish_left = wish_left.normalized()
    player._try_start_dodge()
    Input.action_release("move_left")
    await _wait(0.05)
    _expect(player._dodge_is_forward,
        "[前闪·按A] 侧向输入也应判为前闪（旧规则会误判成后撤）")
    var face_side: Vector3 = -player._pivot.global_basis.z
    face_side.y = 0.0
    var dot_side: float = face_side.normalized().dot(wish_left)
    _expect(dot_side > 0.95,
        "[前闪·按A] 身体应转向方向键指向的方向(点积 %.3f)" % dot_side)
    _expect(player._anim_player.current_animation == player._dodge_fwd_anim,
        "[前闪·按A] 仍播 %s(实际 %s)" % [
            player._dodge_fwd_anim, player._anim_player.current_animation])
    await _wait(0.45)          # 等这段前闪播完

    # ---- 1a-2) 闪避·后撤：不按方向 → 判为后撤；位移方向应朝身体正后方 ----
    var pos_b2: Vector3 = player.global_position
    var facing_b: Vector3 = -player._pivot.global_basis.z      # 位移应按身体正后方发生
    player._try_start_dodge()                                   # 没按任何方向键
    await _wait(0.05)
    _expect(not player._dodge_is_forward, "[后撤] 没按方向时应判为后撤")
    _expect(player._anim_player.current_animation == player._dodge_back_anim,
        "[后撤] 播放 %s(实际 %s)" % [player._dodge_back_anim, player._anim_player.current_animation])
    var yaw_before: float = player._pivot.rotation.y
    await _wait(0.5)          # 等整段后撤播完(dodge_back_time=0.458s)
    var delta_b := Vector2(player.global_position.x - pos_b2.x,
        player.global_position.z - pos_b2.z)
    var fwd_flat := Vector2(facing_b.x, facing_b.z).normalized()
    _expect(delta_b.length() > 2.2 and delta_b.length() < 3.8,
        "[后撤] 位移应约 3.0m(实际 %.2fm)" % delta_b.length())
    _expect(delta_b.normalized().dot(fwd_flat) < -0.5,
        "[后撤] 位移应朝身体正后方(点积 %.2f)" % delta_b.normalized().dot(fwd_flat))
    # ★ **后闪**不改朝向（这条规则只对后闪成立；前闪现在已经会转向方向键了）：
    #   后撤若转身，锁定视角下会当场把敌人甩出画面、玩家瞬间失去方向感。
    _expect(absf(player._pivot.rotation.y - yaw_before) < 0.05,
        "[后撤] 不应改变身体朝向(Δyaw %.3f rad)" % (player._pivot.rotation.y - yaw_before))

    # ---- 1a-3) 完美闪避：闪避无敌帧里被"敌人挥击判定盒"扫中 → 虚影 + 子弹时间 ----
    # 【怎么造出"敌人这一下本来会打中"】敌人命中盒触发时调用的就是 take_damage()，
    #   所以直接调 take_damage 等价于"被判定盒扫到" —— 与完美格挡的测法同一个思路。
    #   ⚠ 这里必须**先确保不在受击无敌帧里**（_iframes > 0 时 take_damage 会提前 return，
    #     连完美判定都走不到），所以先等一段把 _iframes 耗干。
    await _wait(0.8)
    var slows_before: float = Engine.time_scale
    player._try_start_dodge()
    await _wait(0.05)
    _expect(player._perfect_dodge_armed, "[完美闪避] 进入闪避时应带着一次完美判定")
    var hp_before_pd: int = player.health.current_hp
    player.take_damage(15, player.global_position + Vector3(0, 0, 1.5))
    _expect(player.health.current_hp == hp_before_pd,
        "[完美闪避] 不掉血(实际 %d → %d)" % [hp_before_pd, player.health.current_hp])
    _expect(not player._perfect_dodge_armed, "[完美闪避] 一次闪避只给一次判定（应已用掉）")
    _expect(Engine.time_scale < slows_before - 0.01,
        "[完美闪避] 应触发子弹时间(%.2f → %.2f)" % [slows_before, Engine.time_scale])
    # 虚影是"常驻一小会儿再自毁"的节点，触发后当场就应该能找到
    # 虚影挂在玩家名下（host = player），所以从玩家往下数
    var ghosts: int = _count_ghost_trail(player)
    _expect(ghosts >= 1, "[完美闪避] 应留下虚影(找到 %d 个)" % ghosts)
    # ★ "看得见"类的特效不能只断"节点在" —— 锁定标记那一节踩过一模一样的坑：
    #   节点数、状态、生命周期全对，材质写错（不透明 / 混合模式不对 / 被自己挡住）
    #   屏幕上照样什么都看不见。所以这里把观感的四条硬指标也钉住。
    var gmat := _first_ghost_material(player)
    if gmat == null:
        _expect(false, "[完美闪避] 虚影上应盖有残影材质")
    else:
        _expect(gmat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
            "虚影材质应为半透明")
        _expect(gmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "虚影用加法混合发光")
        _expect(gmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
            "虚影不受场景光照影响")
        _expect(gmat.no_depth_test,
            "★ 虚影已关闭深度测试(否则会被自己/场景网格挡住)")
        # ★★ 起始不透明度必须 <1.0：叠加混合是"亮度相加"，三张 1.0 叠一起会被裁成纯白，
        #    三道残影糊成一团光（抓帧对比后收到 0.82 起步，这条断言就是防止被改回去）。
        _expect(gmat.albedo_color.a > 0.0 and gmat.albedo_color.a < 1.0,
            "★ 虚影起始不透明度应在 (0,1)(叠加混合会裁成纯白，实际 %.2f)"
                % gmat.albedo_color.a)
    # 再打一次：这一次 _perfect_dodge_armed 已用掉 → 不该重复触发（也不掉血）
    var ts_after: float = Engine.time_scale
    player.take_damage(15, player.global_position + Vector3(0, 0, 1.5))
    _expect(is_equal_approx(Engine.time_scale, ts_after),
        "[完美闪避] 同一次闪避内不应重复触发慢动作")
    _expect(player.health.current_hp == hp_before_pd, "[完美闪避] 第二下也不该掉血")
    # ★ 子弹时间"短"也是用户明确要求的：`bullet_time_duration`(0.25) + `bullet_time_fade`(0.25)
    #   = 0.5 真实秒内必须自行回到常速 —— 这条断言防止它被改回 0.6s 那种"拖到能喘口气"的长度。
    #   ⚠ 必须放在"不重复触发"那两条**之后**：那两条依赖玩家还在 DODGE 无敌帧里，
    #     这里一 await 整段闪避就走完了，再打第二下会真掉血。
    #   （SceneTreeTimer 按缩放时间走、实际等待更久；但恢复补间是 ignore_time_scale 的，
    #     按真实秒执行 —— 到点必然已经恢复）
    await _wait(0.8)
    _expect(is_equal_approx(Engine.time_scale, 1.0),
        "[完美闪避] 子弹时间应已自行结束并回到常速(实际 %.2f)" % Engine.time_scale)
    # ★★ 子弹时间是**全局单例**，测完必须复位：不复位会让后面所有 await 全被拖慢，
    #    表现为"测试莫名其妙卡住/超时"，而不是某一条断言变红 —— 极难排查。
    await _wait(1.2)
    Engine.time_scale = 1.0
    _expect(is_equal_approx(Engine.time_scale, 1.0), "[完美闪避] 时间倍率已复位为 1.0")
    # 等这一轮闪避走完 + 虚影全部淡出自毁。★ 这一条同样必要：虚影是"生成后自毁"的节点，
    # 另一个坏掉的方式是**只生不灭**（每闪一次留一堆半透明模型，越玩越卡）。
    await _wait(0.9)
    var ghosts_left: int = _count_ghost_trail(player)
    _expect(ghosts_left == 0, "[完美闪避] 虚影应已全部自毁(还剩 %d 个)" % ghosts_left)

    # ---- 1b) 行走动画：移动时播放并按速度调倍速；停下复位骨骼 ----
    Input.action_press("move_forward")
    await _wait(0.4)
    _expect(player._anim_player.current_animation == player._walk_anim,
        "移动时播放行走动画(实际 %s)" % player._anim_player.current_animation)
    _expect(player._anim_player.speed_scale > 0.6,
        "行走动画倍速随速度调整(%.2f)" % player._anim_player.speed_scale)
    Input.action_release("move_forward")
    await _wait(0.5)
    _expect(_idling(player),
        "停下后切到 Idle 待机(实际 %s)" % player._anim_player.current_animation)

    # ---- 1c) 挥砍动画：攻击播放 Slash，结束复位 ----
    _face_player_to(player, Vector3(0, 0, -1))
    player._try_start_attack()
    await _wait(0.1)
    _expect(player._anim_player.current_animation == player._slash_anim,
        "攻击时播放 %s(实际 %s)" % [player._slash_anim, player._anim_player.current_animation])
    await _wait(0.75)
    _expect(_idling(player),
        "攻击结束后切到 Idle 待机(实际 %s)" % player._anim_player.current_animation)

    # ---- 1d) 跳跃：按一下就离地(全程只播滞空 JumpAir) → 落地复位 ----
    # ★ 2026-09-21 起跳动画已取消：jump_prep_time = 0 → 按跳跃键**立刻**给向上初速度进 JUMP，
    #   不再有"先在地面播 JumpStart 蹬地、0.18s 后才离地"的蓄力段（该段代码保留、默认进不去）。
    _expect(player.jump_prep_time <= 0.01,
        "起跳蓄力已关闭(jump_prep_time=%.2f → 按跳跃键立即离地)" % player.jump_prep_time)
    var gy_before: float = player.global_position.y
    var vy_ground: float = player.velocity.y
    Input.action_press("jump")                       # 模拟"按住跳跃键"
    player._try_start_jump()
    # 「取消蓄力」最直接的证据：**调用的同一帧内**就已经在 JUMP 里、且拿到了向上初速度
    _expect(player.state == PlayerCharacter.State.JUMP,
        "按跳跃键立刻进入 JUMP(实际状态 %d —— 说明没有再走 JUMP_PREP 蓄力段)" % player.state)
    _expect(player.velocity.y > vy_ground + 1.0,
        "按跳跃键立刻获得向上初速度(vy=%.2f)" % player.velocity.y)

    # 采样整段：离地 → 滞空 → 落地；同时验证最高点 / 滞空动画 / 无二段跳 / **全程不播起跳动画**
    var full_peak: float = player.global_position.y
    var saw_air_anim := false
    var launched := false
    var double_jump_blocked := true
    var saw_jump_start := false                      # ★ 全程有没有漏播过一次起跳动画
    for i in 55:                                     # 约 1.1s（已无 0.18s 蓄力）
        await _wait(0.02)
        full_peak = maxf(full_peak, player.global_position.y)
        if player.global_position.y > gy_before + 0.12:
            launched = true
        if player._anim_player.current_animation == player._jump_air_anim:
            saw_air_anim = true
        if player._jump_start_anim != "" and player._anim_player.current_animation == player._jump_start_anim:
            saw_jump_start = true
        if i == 25:                                  # 约 0.5s：人在空中
            var vy_air: float = player.velocity.y
            player._try_start_jump()                 # 空中再按 → 不应生效
            await _wait(0.02)
            double_jump_blocked = player.velocity.y <= vy_air + 0.01
    Input.action_release("jump")
    _expect(launched, "按跳跃键后确实离地升空")
    _expect(saw_air_anim, "滞空阶段播放 %s" % player._jump_air_anim)
    _expect(not saw_jump_start,
        "★ 整段跳跃全程没有播放起跳动画 %s（起跳动画已取消）" % player._jump_start_anim)
    _expect(double_jump_blocked, "空中不能二段跳")
    var full_h: float = full_peak - gy_before
    _expect(full_h > 0.9 and full_h < 1.6, "按住跳跃的高度约 1.1m，实际 %.2fm" % full_h)
    await _wait(0.7)                                 # 等落地
    _expect(player.is_on_floor(), "跳跃后已落地")
    _expect(absf(player.global_position.y - gy_before) < 0.15,
        "落地后回到地面高度(%.2f)" % player.global_position.y)
    _expect(_idling(player),
        "落地后切到 Idle 待机(实际 %s)" % player._anim_player.current_animation)

    # 轻点跳跃(不按住) → 可变跳跃高度应该明显更低
    var hop_base: float = player.global_position.y
    player._try_start_jump()
    var hop_peak: float = hop_base
    for i in 30:                                     # 采样约 0.6s
        await _wait(0.02)
        hop_peak = maxf(hop_peak, player.global_position.y)
    var hop_h: float = hop_peak - hop_base
    _expect(hop_h < full_h - 0.15, "轻点跳跃更矮(轻点 %.2fm < 按住 %.2fm)" % [hop_h, full_h])
    await _wait(0.6)

    # ---- 1d-2) 「起跳蓄力」是**开关**不是残骸：调回 0.18 后蓄力段必须复活 ----
    # 这条专守 jump_prep_time 声明处的那句承诺（"想找回两段式起跳，调回 0.18 即可"）——
    # 免得以后有人把 State.JUMP_PREP 那套分支当成死代码顺手删掉，把"可逆"变成"不可逆"。
    await _wait(0.6)                                 # 确保已落地、回到 MOVE
    player.jump_prep_time = 0.18
    var gy_prep: float = player.global_position.y
    Input.action_press("jump")
    player._try_start_jump()
    await _wait(0.06)
    _expect(player.state == PlayerCharacter.State.JUMP_PREP,
        "把 jump_prep_time 调回 0.18 → 蓄力段复活(实际状态 %d)" % player.state)
    _expect(player._anim_player.current_animation == player._jump_start_anim,
        "蓄力段重新播放 %s(实际 %s)" % [player._jump_start_anim, player._anim_player.current_animation])
    _expect(player.global_position.y <= gy_prep + 0.05,
        "蓄力段仍留在地面(未提前离地, y=%.2f)" % player.global_position.y)
    Input.action_release("jump")
    player.jump_prep_time = 0.0                      # ★ 立刻还原默认值，别污染后面的用例
    await _wait(0.9)                                 # 让它正常起跳并落地
    _expect(player.jump_prep_time <= 0.01, "已还原 jump_prep_time = 0(默认值)")

    # ---- 1e) 格挡：进入/退出 + 普通减伤 + 方向限制 + 完美格挡 ----
    # 先把敌人挪远：它在仇恨半径(11m)内会一直追过来乱入打人，破坏血量的精确断言。
    enemy.global_position = player.global_position + Vector3(40, 0, 0)
    enemy.velocity = Vector3.ZERO
    await _wait(0.1)

    var facing := Vector3(0, 0, -1)          # 玩家默认朝 -Z
    _face_player_to(player, facing)

    # ① 按住右键 → 进入 BLOCK，播放 Block 起手
    Input.action_press("block")
    player._try_start_block()
    await _wait(0.05)
    _expect(player.state == PlayerCharacter.State.BLOCK,
        "按住右键进入格挡状态(实际状态 %d)" % player.state)
    _expect(player._anim_player.current_animation == player._block_anim,
        "格挡起手播放 %s(实际 %s)" % [player._block_anim, player._anim_player.current_animation])

    # ② 格挡中禁止攻击/闪避（防止"边挡边输出"、也防止"举着剑闪出去"）
    player._try_start_attack()
    player._try_start_dodge()
    _expect(player.state == PlayerCharacter.State.BLOCK,
        "格挡中不能攻击/闪避(实际状态 %d)" % player.state)

    # ③ 起手播完 → 自动切到 BlockHold 循环（Block 起手约 0.29s = 0.25 + 1/24）
    await _wait(0.45)
    _expect(player._anim_player.current_animation == player._block_hold_anim,
        "格挡起手后切到 %s 循环(实际 %s)" % [player._block_hold_anim, player._anim_player.current_animation])

    # ④ 普通格挡：完美窗口(0.15s)已过 → 按比例减伤，且不硬直
    var hp0: int = player.health.current_hp
    var chip: int = maxi(1, int(round(15.0 * (1.0 - player.block_damage_reduction))))
    player.take_damage(15, player.global_position + facing * 1.5)
    _expect(player.health.current_hp == hp0 - chip,
        "[普通格挡] 期望扣 %d 点(15×%.0f%%)，实际扣 %d" % [
            chip, (1.0 - player.block_damage_reduction) * 100.0, hp0 - player.health.current_hp])
    _expect(player.state == PlayerCharacter.State.BLOCK,
        "[普通格挡] 挡下后不硬直，仍保持格挡(实际状态 %d)" % player.state)
    _expect(player._anim_player.current_animation == player._block_impact_anim,
        "挡下瞬间插播 %s 顿挫(实际 %s)" % [player._block_impact_anim, player._anim_player.current_animation])
    await _wait(0.35)                        # 等顿挫演完，回到格挡循环

    # ⑤ 方向限制：只有正面锥形(默认 120°)内的攻击能被挡住，背后偷袭吃满伤害
    var hp2: int = player.health.current_hp
    player.take_damage(15, player.global_position - facing * 1.5)   # 攻击来自背后
    _expect(player.health.current_hp == hp2 - 15,
        "[方向限制] 背后攻击应吃满 15 伤害(实际扣 %d)" % (hp2 - player.health.current_hp))
    _expect(player.state == PlayerCharacter.State.HURT,
        "[方向限制] 背后攻击应打进受击硬直(实际状态 %d)" % player.state)

    # ⑥ 硬直结束时右键还按着 → 自动重新举剑（不白送完美窗口）
    await _wait(0.45)                        # HURT 硬直 0.32s
    _expect(player.state == PlayerCharacter.State.BLOCK,
        "硬直结束且右键仍按住 → 自动重新举剑(实际状态 %d)" % player.state)
    _expect(player._perfect_parried, "自动重举不白送完美格挡窗口")

    # ⑦ 松开右键 → 收招回 MOVE，并切回 Idle 待机
    Input.action_release("block")
    await _wait(0.25)
    _expect(player.state == PlayerCharacter.State.MOVE,
        "松开右键退出格挡(实际状态 %d)" % player.state)
    _expect(_idling(player),
        "退出格挡后回到 Idle 待机(实际 %s)" % player._anim_player.current_animation)

    # ⑧ 完美格挡：重新按下（新窗口）→ 0.15s 内挡下 → 0 伤害 + 敌人长硬直 0.8s
    _place_enemy_in_front_of(enemy, player, 1.3)
    await _wait(0.05)
    var enemy_hp0: int = enemy.health.current_hp
    var hp1: int = player.health.current_hp
    Input.action_press("block")
    player._try_start_block()
    await _wait(0.05)                        # 仍在 0.15s 完美窗口内
    _expect(player._state_time <= player.perfect_parry_window,
        "取样时刻仍在完美窗口内(%.3fs ≤ %.3fs)" % [player._state_time, player.perfect_parry_window])
    player.take_damage(15, enemy.global_position)
    _expect(player.health.current_hp == hp1,
        "[完美格挡] 应 0 伤害，实际 %d → %d" % [hp1, player.health.current_hp])
    _expect(enemy.health.current_hp == enemy_hp0,
        "[完美格挡] 敌人不该掉血(%d → %d)" % [enemy_hp0, enemy.health.current_hp])
    _expect(enemy.state == EnemyBrute.State.STAGGER,
        "[完美格挡] 敌人应被弹进硬直(实际状态 %d)" % enemy.state)
    _expect(absf(enemy._stagger_time - player.block_parry_stagger) < 0.001,
        "[完美格挡] 敌人硬直时长 = 玩家设置的 %.2fs(实际 %.2fs)" % [
            player.block_parry_stagger, enemy._stagger_time])
    _expect(enemy._stagger_time > 0.4,
        "[完美格挡] 硬直明显长于普通受击 0.4s(实际 %.2fs)" % enemy._stagger_time)
    # ⑧-2 完美格挡的**黄光特效**：应立刻迸出一个 HitFlash（核心亮球+扩散光环+点光源），
    #      并且真的在放大（防止 tween 没跑起来 —— 那样节点会"杵"在那里直到自毁）
    var fx := _first_hit_flash(get_tree().current_scene)
    _expect(fx != null, "完美格挡迸出黄色闪光特效(HitFlash)")
    if fx != null:
        await _wait(0.06)                   # 等 tween 把起始值(0.35)应用上
        var s0: float = fx.scale.x
        await _wait(0.12)
        _expect(fx.scale.x > s0, "闪光特效在放大(%.2f → %.2f)" % [s0, fx.scale.x])
        _expect(fx.get_child_count() >= 3, "闪光特效含核心/光环/点光源三个部件(实际 %d)" % fx.get_child_count())
    _expect(hud.get("_parry_flash") != null, "HUD 具备全屏金光层(_parry_flash)")

    # ⑨ 收尾：把敌人挪远、玩家血量与无敌帧复位，交给后面的"敌人挥击"测试
    Input.action_release("block")
    enemy.global_position = player.global_position + Vector3(40, 0, 0)
    enemy.velocity = Vector3.ZERO
    player.health.reset()
    await _wait(0.9)                         # 等 _iframes(0.6s) 走完
    _face_player_to(player, facing)
    _expect(player.health.current_hp == 100, "格挡测试收尾：玩家血量已复位")
    # 闪光特效(0.36s)应已播完并自毁 —— 验证 tween 的收尾回调没漏（否则节点会越积越多）
    _expect(_count_hit_flash(get_tree().current_scene) == 0,
        "闪光特效播完自动销毁(无残留节点)")

    # ---- 1f) 失衡(Poise) 与处决：完美格挡攒失衡 → 满则 BROKEN → 可被处决 ----
    # 【为什么要另造一只"木桩怪"】主场景那只怪是全场景唯一的真怪：
    #   它一旦被处决/打死就会触发主场景的重生计时、把 enemy 换成新实例，
    #   后面所有血量断言都会失准。所以这里用一个独立实例做隔离测试。
    var probe_scene: PackedScene = load("res://scenes/enemy/enemy.tscn")
    var probe: EnemyBrute = probe_scene.instantiate()
    main.add_child(probe)
    probe.global_position = player.global_position + Vector3(0, 0, -30)  # 远远放着，别来捣乱
    # 把它变成完全被动的木桩：不追、不攻击（否则它自己冲上来会打乱断言）
    probe.aggro_range = 0.0
    probe.attack_range = 0.0
    probe.move_speed = 0.0
    await _wait(0.15)

    # ① 组件与默认参数
    _expect(probe.poise != null, "敌人挂了 Poise(失衡)组件")
    _expect(probe.poise.max_poise > 0.0 and probe.poise.current_poise == 0.0,
        "失衡条初始为空(0/%.0f)" % probe.poise.max_poise)
    _expect(not probe.poise.is_broken(), "初始未处于失衡")
    _expect(absf(probe.parry_poise_percent - 34.0) < 0.001,
        "守卫默认每次完美格挡加 %.0f%%（3 次失衡）" % probe.parry_poise_percent)
    _expect(probe.execute_damage_scale > 0.0,
        "敌人具备处决伤害系数(%.2f)" % probe.execute_damage_scale)

    # ② 每次完美格挡 = 按**百分比**加失衡值（百分比可调 → 各类敌人加得不一样多）
    probe.poise.reset()
    probe.parry_poise_percent = 50.0           # 模拟"小怪"档：2 次就能顶满
    probe.deflect(0.2, probe.global_position + Vector3(0, 0, 1))
    _expect(absf(probe.poise.current_poise - probe.poise.max_poise * 0.5) < 0.001,
        "[失衡累积] 50%% 档加完 = 上限的一半(%.1f)" % probe.poise.current_poise)
    _expect(not probe.poise.is_broken(), "只挨 1 次完美格挡还不够失衡")
    probe.deflect(0.2, probe.global_position + Vector3(0, 0, 1))
    _expect(probe.poise.is_broken(), "[失衡] 第 2 次完美格挡顶满 → 进入失衡")
    _expect(probe.state == EnemyBrute.State.BROKEN,
        "[失衡] 状态切到 BROKEN(实际 %d)" % probe.state)
    await _wait(0.15)
    _expect(not probe._hitbox.monitoring, "[失衡] 失衡期间命中盒关闭(打不到人)")

    # ③ 失衡窗口不会被"多余的格挡"取消（deflect 在 broken 时必须保持 BROKEN）
    probe.deflect(0.2, probe.global_position + Vector3(0, 0, 1))
    await _wait(0.05)
    _expect(probe.state == EnemyBrute.State.BROKEN,
        "[失衡] 失衡期间再被弹开仍保持 BROKEN(实际 %d)" % probe.state)
    _expect(probe.poise.is_broken(), "[失衡] 失衡窗口没有被多余的格挡取消")

    # ④ HUD：黄色失衡条随数值变化；失衡时变亮金 + 弹出"按左键处决"提示
    enemy.poise.reset()
    await _wait(0.1)
    var poise_fill = hud.get("_poise_fill")
    var enemy_label = hud.get("_enemy_label")
    _expect(poise_fill != null and enemy_label != null, "HUD 具备黄色失衡条控件")
    enemy.poise.percent(50.0)
    await _wait(0.1)
    _expect(absf(poise_fill.size.x - 296.0 * 0.5) < 2.0,
        "[HUD] 黄条宽度跟随失衡值(%.0fpx ≈ 一半)" % poise_fill.size.x)
    enemy.poise.percent(50.0)
    await _wait(0.1)
    _expect(poise_fill.color.g > 0.9, "[HUD] 失衡时黄条变成亮金色")
    _expect(String(enemy_label.text).contains("处决"), "[HUD] 失衡时敌人标题提示可按左键处决")
    _expect(String(hud.get("_message_label").text).contains("失衡"),
        "[HUD] 顶部弹出失衡提示")
    # 恢复主场景那只怪的状态，免得影响后面的血量断言
    enemy.poise.reset()
    enemy.state = EnemyBrute.State.CHASE
    enemy.global_position = player.global_position + Vector3(40, 0, 0)
    enemy.velocity = Vector3.ZERO
    await _wait(0.15)

    # ⑤ 处决接口：只掉血 + 刷新失衡倒计时，**不打断 BROKEN 姿势**（非致命，木桩不会死）
    probe.poise.reset()
    probe.parry_poise_percent = 100.0          # 一次完美格挡直接顶满（测试提速）
    probe.deflect(0.2, probe.global_position + Vector3(0, 0, 1))
    probe.health.reset()
    await _wait(0.4)                            # 让失衡倒计时先走掉一点
    var break_left_before: float = probe.poise._break_left
    var probe_hp_before: int = probe.health.current_hp
    probe.execute(10, player.global_position)
    _expect(probe.health.current_hp == probe_hp_before - 10,
        "[处决接口] 按伤害系数结算(%.0f × 10 = %d)" % [probe.execute_damage_scale, probe_hp_before - probe.health.current_hp])
    _expect(probe.poise._break_left > break_left_before,
        "[处决接口] 处决会重置失衡倒计时(%.2fs > %.2fs)" % [probe.poise._break_left, break_left_before])
    _expect(probe.state == EnemyBrute.State.BROKEN,
        "[处决接口] 处决期间敌人保持 BROKEN 姿势(实际 %d)" % probe.state)

    # ⑥ 玩家处决全流程：走近失衡敌人按左键 → EXECUTE（而不是普通挥剑）→ 大量伤害
    _place_enemy_in_front_of(probe, player, 1.3)
    _face_player_to(player, Vector3(0, 0, -1))
    probe.health.reset()
    player.health.reset()
    player.health.invincible = false
    await _wait(0.15)
    var flash_before: int = _count_hit_flash(get_tree().current_scene)
    var exec_hp0: int = probe.health.current_hp
    player._attack_cooldown = 0.0
    player._try_start_attack()
    _expect(player.state == PlayerCharacter.State.EXECUTE,
        "[处决] 面前有失衡敌人时左键进入 EXECUTE(实际 %d)" % player.state)
    _expect(player.health.invincible, "[处决] 处决全程无敌")
    _expect(_count_hit_flash(get_tree().current_scene) > flash_before, "[处决] 起手迸出金色闪光")

    # ⑦ 专属处决动画（举剑→前刺→上划）：模型里要有 Execute 段，且此刻真的在播它
    #    【时长约定】Execute 关键帧 1..25（24fps）→ 内容时长 1.0s；
    #    导入后 Animation.length = 25/24 ≈ 1.0417s（本工程"首帧平移到 0"的既定约定）。
    #    这 1/24 是**约定不是 bug**，别去"修"它 —— 详情见 docs/GAME_DESIGN.md。
    _expect(player._execute_anim == "Execute",
        "[处决动画] 识别到专属处决动画(实际 '%s')" % player._execute_anim)
    var exec_clip: Animation = null
    if player._anim_player != null:
        exec_clip = player._anim_player.get_animation("Execute")
    _expect(exec_clip != null, "[处决动画] 模型里有 Execute 段")
    if exec_clip != null:
        _expect(absf(exec_clip.length - 25.0 / 24.0) < 0.005,
            "[处决动画] 时长 %.4fs = 25/24(1.0s 内容 + 1/24 约定)" % exec_clip.length)
    _expect(player._anim_player != null and player._anim_player.current_animation == "Execute",
        "[处决动画] 正在播放 Execute(实际 '%s')"
            % (player._anim_player.current_animation if player._anim_player != null else "<无播放器>"))
    # 前刺命中帧 = 动画第 9 帧 → 相对进度 (9-1)/25 = 0.32 × execute_time；
    # 这条断言把"参数"和"动画内容"钉在一起：改动画命中帧忘了改参数就会红。
    _expect(absf(player.execute_hit_time - 0.32 * player.execute_time) < 0.02,
        "[处决动画] 判定时刻对齐前刺帧(%.2fs ≈ 0.32 × %.2fs)"
            % [player.execute_hit_time, player.execute_time])

    await _wait(player.execute_hit_time + 0.12)   # 越过判定帧（execute_hit_time 0.32s）
    var exec_dealt: int = exec_hp0 - probe.health.current_hp
    _expect(probe.health.current_hp == maxi(0, exec_hp0 - player.execute_damage),
        "[处决] 造成 %d 点伤害(实际扣 %d)" % [player.execute_damage, exec_dealt])
    # ★ 需求原话："处决造成大量伤害，但不是直接秒杀" —— 下面两条把这句话变成可执行的约束
    _expect(player.execute_damage >= player.attack_damage * 2,
        "[处决] 伤害远高于普通挥砍(%.1f 倍：%d vs %d)" % [
            float(player.execute_damage) / maxf(1.0, float(player.attack_damage)),
            player.execute_damage, player.attack_damage])
    _expect(probe.is_alive(),
        "[处决] **不是秒杀**：满血守卫挨完还活着(剩 %d 血)" % probe.health.current_hp)
    _expect(probe.state == EnemyBrute.State.BROKEN,
        "[处决] 命中瞬间敌人仍保持 BROKEN 姿势(实际 %d)" % probe.state)

    await _wait(player.execute_time)              # 等整段处决演完
    _expect(player.state == PlayerCharacter.State.MOVE,
        "[处决] 演完后回到移动状态(实际 %d)" % player.state)
    _expect(not player.health.invincible, "[处决] 结束后解除无敌")
    # ★ 存活下来的敌人这时才"爬起来"：处决**消耗掉**这次失衡。
    #   否则玩家能原地连按左键无限连处决（且全程无敌），处决会退化成刷伤害的循环。
    _expect(not probe.poise.is_broken(),
        "[处决] 演出结束后收掉失衡(敌人爬起来) → 无法无限连处决")
    await _wait(0.1)
    _expect(probe.state != EnemyBrute.State.BROKEN,
        "[处决] 敌人已离开 BROKEN(实际 %d)" % probe.state)
    # ★ 收尾节奏：处决留下的残血应该"一刀就能补掉"（execute_damage + attack_damage ≥ 满血），
    #   这就是把伤害定成 75 而不是 70/80 的理由 —— 处决重创 + 补刀收人头，两段都有戏。
    _expect(probe.health.current_hp <= player.attack_damage,
        "[处决] 残血 %d ≤ 一刀(%d) → 处决+补刀=击杀" % [probe.health.current_hp, player.attack_damage])

    _expect(player.perfect_parry_window >= 0.2 and player.perfect_parry_window <= 0.6,
        "完美格挡窗口已放宽到 0.2~0.6s(实际 %.2fs)" % player.perfect_parry_window)
    # 清理木桩，避免影响后续断言
    probe.queue_free()
    player.health.reset()
    player._iframes = 0.0
    await _wait(0.2)

    # ---- 1g) 生活三段（Idle / Hurt / Death）：站住有呼吸、挨打有甩身、倒地有扑倒 ----
    # 【为什么值得单独测】这三段以前是"骨骼复位 + 整体姿态"的权宜做法：站住时是绑定姿势
    #   （像塑料模特），倒地是把整个 VisualPivot 转 90°（像根棍子翻过去）。补齐动画后要钉住：
    #   ① Idle 的循环真的闭合 ② Hurt/Death 是单次 ③ 对应状态真的会播它们。

    # ① Idle 循环闭合：Blender 里 f1 与 f49 取自同一正弦相位 → 首尾姿势必须严丝合缝。
    #   【为什么用 seek 取样而不是看 is_playing】循环动画永远在播，"在播"证明不了接缝没问题。
    var idle_anim: Animation = player._anim_player.get_animation(player._idle_anim)
    if idle_anim == null:
        _expect(false, "缺少 Idle 动画资源")
    else:
        var idle_loop_mode: int = idle_anim.loop_mode
        idle_anim.loop_mode = Animation.LOOP_NONE   # ⚠ 临时关循环，否则 seek(length) 会绕回 0
        player._anim_player.play(player._idle_anim)
        player._anim_player.seek(0.0, true)
        var pose_head := _sample_bone_rotations(player)
        player._anim_player.seek(idle_anim.length, true)
        var pose_tail := _sample_bone_rotations(player)
        var worst: float = 0.0
        for i in mini(pose_head.size(), pose_tail.size()):
            worst = maxf(worst, (pose_head[i] as Quaternion).angle_to(pose_tail[i] as Quaternion))
        _expect(worst < 0.02,
            "Idle 首尾帧姿势一致(最大差 %.5f rad) → 呼吸循环无缝" % worst)
        idle_anim.loop_mode = idle_loop_mode
        # 取样期间循环是关的 → 动画可能已停在末帧，显式重播一次，别让后面看到"冻住"
        player._anim_player.stop()
        player._anim_player.play(player._idle_anim, -1.0, 1.0)

    # ② 站住 → 播 Idle（而不是停在绑定姿势）
    await _wait(0.3)
    _expect(_idling(player),
        "站住时播放 Idle(实际 %s)" % player._anim_player.current_animation)

    # ③ 挨打 → 播 Hurt；倍速必须把动画恰好铺满 hurt_time（改动画或改时长都不脱节）
    player.health.reset()
    player._iframes = 0.0
    player._enter_hurt(player.global_position + Vector3(0, 0, 1.5))
    await _wait(0.06)
    _expect(player._anim_player.current_animation == player._hurt_anim,
        "受击时播放 %s(实际 %s)" % [player._hurt_anim, player._anim_player.current_animation])
    var hurt_anim: Animation = player._anim_player.get_animation(player._hurt_anim)
    if hurt_anim != null:
        var want_spd: float = hurt_anim.length / player.hurt_time
        # ⚠ 必须用 get_playing_speed() 而不是 speed_scale：
        #   本项目里 speed_scale(属性) 与 play(custom_speed) 是**相乘**的两层
        #   （实测：属性 3.0 × play 2.0 → 实际 6.0），只读属性会得到 1.0 而误判。
        _expect(absf(player._anim_player.get_playing_speed() - want_spd) < 0.01,
            "受击动画实际倍速 = length ÷ hurt_time = %.3f(实际 %.3f)"
                % [want_spd, player._anim_player.get_playing_speed()])
    await _wait(player.hurt_time + 0.2)              # 等硬直结束
    _expect(player.state == PlayerCharacter.State.MOVE,
        "受击硬直结束后恢复行动(状态 %d)" % player.state)
    _expect(_idling(player), "受击结束后回到 Idle")

    # ④ 兜底机制仍在：_anim_to_rest() 必须能把骨骼整体复位（翻滚收招 / 落地 / 老资产路径都靠它）。
    #   ⚠ 不能 await：只要玩家还在 MOVE 状态，下一帧 _animate_model 就会重新播 Idle 覆盖掉复位结果。
    player._anim_to_rest()
    _expect(_bones_at_rest(player), "_anim_to_rest() 能把骨骼复位到绑定姿势")

    player.health.reset()
    player._iframes = 0.0
    await _wait(0.3)

    # ---- 1h) 锁定敌人（鼠标中键**点击切换**）：面朝敌人 + A/S/D 侧移后撤 + 整体降速 ----
    # 【headless 里怎么"点击鼠标中键"】中键已从"按住"改成"点击切换"：按下 → 跨过物理帧 → 松开，
    #   只让 is_action_just_pressed 在"按下"那一帧被读到一次。统一用 _tap_lock() 辅助（见文件末尾）。
    #   ★ 新语义的守卫：松开按键本身不再有任何解锁含义 —— 这一点由后面的"仅松开不点击仍保持锁定"钉住。
    _expect(InputMap.has_action("lock_on"), "已注册锁定动作 lock_on")
    var bind_middle := false
    for ev in InputMap.action_get_events("lock_on"):
        if ev is InputEventMouseButton \
                and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
            bind_middle = true
    _expect(bind_middle, "lock_on 绑定在鼠标中键上")

    # ① 三段动画识别正确，且**不能把 Walk 顶掉**（识别链里必须排在裸 "walk" 之前）
    _expect(player._strafe_left_anim == "WalkStrafeLeft",
        "识别左移动画: %s" % player._strafe_left_anim)
    _expect(player._strafe_right_anim == "WalkStrafeRight",
        "识别右移动画: %s" % player._strafe_right_anim)
    _expect(player._walk_back_anim == "WalkBack",
        "识别后撤动画: %s" % player._walk_back_anim)
    _expect(player._walk_anim == "Walk",
        "★ WalkStrafe*/WalkBack 没有覆盖掉 _walk_anim(实际 %s)" % player._walk_anim)

    # ② 三段都是设计时长 1.000s 的循环
    #   ⚠ 与 0a 节同一套约定：Animation.length = 设计时长 + 1/24，必须先减掉 1/24 再比，
    #     直接拿 length(1.042) 跟 1.0 比会误报。
    for lock_anim in ["WalkStrafeLeft", "WalkStrafeRight", "WalkBack"]:
        _expect(_loop_ok(player, lock_anim), "%s 已设为循环播放" % lock_anim)
        var la: Animation = player._anim_player.get_animation(lock_anim)
        if la == null:
            _expect(false, "模型里缺少动画 %s" % lock_anim)
        else:
            var lock_design: float = la.length - 1.0 / 24.0
            _expect(absf(lock_design - 1.0) < 0.01,
                "%s 设计时长 1.000s 符合约定(实际 %.4fs)" % [lock_anim, lock_design])

    # ③ 不按中键时不该有任何锁定
    _expect(not player.is_locked_on(), "未按中键时没有锁定")
    _expect(player.get_lock_target() == null, "未锁定时取目标返回 null")
    _expect(player._locomotion_clip() == player._walk_anim,
        "自由模式的位移段是 Walk(实际 %s)" % player._locomotion_clip())

    # ④ 造一只被动木桩当锁定目标。
    #   ⚠ 必须先把主场景那只真怪**临时移出 enemy 组**：锁定取的是"范围内最近的敌人"，
    #     不挪走它就可能锁到它而不是木桩（它是随机位置的，断言会飘）。
    var lock_scene: PackedScene = load("res://scenes/enemy/enemy.tscn")
    var dummy: EnemyBrute = lock_scene.instantiate()
    main.add_child(dummy)
    dummy.aggro_range = 0.0
    dummy.attack_range = 0.0
    dummy.move_speed = 0.0            # 纯木桩：不追不打，免得打断断言
    var enemy_was_in_group: bool = enemy.is_in_group("enemy")
    enemy.remove_from_group("enemy")
    _expect(not enemy.is_in_group("enemy"), "主怪已临时移出 enemy 组(避免抢锁定)")

    player._wish_dir = Vector3.ZERO
    var p_fwd: Vector3 = player._get_facing_flat()
    dummy.global_position = player.global_position + p_fwd * 3.0
    await _wait(0.2)
    _expect(player._find_lock_target() == dummy, "范围内最近的敌人被选为锁定候选")

    await _tap_lock()
    _expect(player.is_locked_on(), "点一次中键 → 进入锁定")
    _expect(player.get_lock_target() == dummy, "锁定目标就是那只木桩")

    # ★ 本次改造核心守卫：把按键**松开**这一步本身不再有任何解锁含义。
    #   （改造前是"按住型"，松开即解除；这条专门钉住新语义，防止日后有人又改回按住语义。）
    Input.action_release("lock_on")          # 确保没有残留的"按下"状态
    await _wait(0.25)
    _expect(player.is_locked_on(), "★ 仅松开中键（不再点击）→ 仍然处于锁定（切换语义守卫）")
    _expect(player.get_lock_target() == dummy, "松开后锁定目标不变")

    # ⑤ 锁定后身体转过去面朝敌人：把木桩挪到玩家**左侧**，看他会不会转身
    var p_left: Vector3 = -player._pivot.global_basis.x
    p_left.y = 0.0
    dummy.global_position = player.global_position + p_left.normalized() * 3.0
    await _wait(1.0)                  # lock_turn_speed=18 → 1s 足够转到位
    var to_dummy: Vector3 = dummy.global_position - player.global_position
    to_dummy.y = 0.0
    var want_yaw := atan2(-to_dummy.x, -to_dummy.z)
    var yaw_err := rad_to_deg(absf(angle_difference(player._pivot.rotation.y, want_yaw)))
    _expect(yaw_err < 12.0, "锁定后身体转向敌人(角度误差 %.1f°)" % yaw_err)

    # ⑤b 锁定标记：敌人**身体中心**要有一颗白色亮点（LockMarker），挂在目标身上、水平居中。
    #   为什么这些点必须钉住：标记在敌人身体**内部**，靠 no_depth_test 才看得见；
    #   一旦有人"顺手"关掉它，节点还在、断言还过，但画面上什么都看不见 → 所以要断材质。
    var marker: LockMarker = player._lock_marker
    _expect(marker != null and is_instance_valid(marker), "锁定后生成了锁定标记(LockMarker)")
    _expect(marker != null and marker.get_target() == dummy, "标记跟随的就是锁定目标")
    _expect(marker != null and marker.get_parent() == dummy,
        "标记挂在目标节点下(跟随移动是引擎免费做的)")
    _expect(_count_lock_marker(get_tree().current_scene) == 1,
        "场景里同时只有一个锁定标记(实际 %d)" % _count_lock_marker(get_tree().current_scene))
    if marker != null:
        # 高度 = 敌人站高 × lock_marker_body_ratio（0.5 = 身体中心）
        var want_y: float = LockMarker.body_height(dummy) * float(player.lock_marker_body_ratio)
        _expect(absf(marker.position.y - want_y) < 0.02,
            "标记在身体中心高度(局部 y=%.3f，期望 %.3f)" % [marker.position.y, want_y])
        _expect(absf(marker.position.x) < 0.001 and absf(marker.position.z) < 0.001,
            "标记在身体中心线上(水平不偏移)")
        # 世界坐标也要落在躯干范围里（防止"局部对了但整体错位"）
        var above_feet: float = marker.global_position.y - dummy.global_position.y
        _expect(above_feet > 0.6 and above_feet < LockMarker.body_height(dummy) * 0.9,
            "标记世界高度落在躯干范围(脚往上 %.2fm)" % above_feet)
        # 竖直方向必须无视朝向（挂点用敌人根节点而不是会摇晃的 VisualPivot）
        var off_axis := Vector2(marker.position.x, marker.position.z).length()
        _expect(off_axis < 0.001, "标记在竖直轴线上(不受朝向/重心摇晃影响)")
        var core: MeshInstance3D = marker.get_node_or_null("Core") as MeshInstance3D
        _expect(core != null, "标记含发光球体 Core")
        if core != null:
            var mat := core.material_override as StandardMaterial3D
            _expect(mat != null, "标记用 StandardMaterial3D")
            if mat != null:
                _expect(mat.albedo_color.r > 0.99 and mat.albedo_color.g > 0.99
                        and mat.albedo_color.b > 0.99,
                    "标记是白色(%.2f,%.2f,%.2f)"
                        % [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b])
                _expect(mat.no_depth_test,
                    "★ 标记已关闭深度测试(否则被躯干网格挡死、等于看不见)")
                _expect(mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "标记用加法混合发光")
                _expect(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
                    "标记不受场景光照影响")

    # ⑥ 位移段选择：把移动方向投到自身轴上，看挑的是哪一段（纯函数，直接读 _wish_dir）
    var axis_fwd: Vector3 = -player._pivot.global_basis.z     # 角色正前
    var axis_right: Vector3 = player._pivot.global_basis.x    # 角色正右
    player._wish_dir = -axis_right
    _expect(player._locomotion_clip() == player._strafe_left_anim,
        "锁定 + 往左 → %s" % player._locomotion_clip())
    player._wish_dir = axis_right
    _expect(player._locomotion_clip() == player._strafe_right_anim,
        "锁定 + 往右 → %s" % player._locomotion_clip())
    player._wish_dir = axis_fwd
    _expect(player._locomotion_clip() == player._walk_anim,
        "锁定 + 往前 → %s" % player._locomotion_clip())
    player._wish_dir = -axis_fwd
    _expect(player._locomotion_clip() == player._walk_back_anim,
        "锁定 + 往后 → %s" % player._locomotion_clip())
    player._wish_dir = Vector3.ZERO

    # ⑦ 端到端：真的横移起来，看播的是三段之一（而不是 Walk）
    var pos_before_strafe: Vector3 = player.global_position
    Input.action_press("move_left")
    await _wait(0.55)
    var lock_clip: String = String(player._anim_player.current_animation)
    _expect(lock_clip == player._strafe_left_anim or lock_clip == player._strafe_right_anim
            or lock_clip == player._walk_back_anim,
        "锁定横移时播放侧移/后撤段(实际 %s)" % lock_clip)
    _expect(player.global_position.distance_to(pos_before_strafe) > 0.5,
        "锁定横移有实际位移(%.2fm)" % player.global_position.distance_to(pos_before_strafe))
    Input.action_release("move_left")

    # ⑧ 整体降速：同样的前进输入，锁定下的稳定速度要明显低于自由模式
    #   ⚠ 中键改成"点击切换"后，量"自由模式"那一组前必须**再点一次**中键来解除锁定 ——
    #     松开是没用的（切换语义里松开没有含义），否则量到的两组都会是锁定速度。
    await _tap_lock()                        # 再点一次 → 解除锁定（切到自由模式量速）
    await _wait(0.5)
    _expect(not player.is_locked_on(), "再点一次中键 → 解除锁定（自由模式量速前置）")
    Input.action_press("move_forward")
    await _wait(0.7)
    var fast_spd := Vector2(player.velocity.x, player.velocity.z).length()
    await _tap_lock()                        # 再点一次 → 重新锁定
    await _wait(0.7)
    var lock_spd := Vector2(player.velocity.x, player.velocity.z).length()
    Input.action_release("move_forward")
    _expect(fast_spd > 4.0, "自由模式前进速度接近 move_speed(%.2f)" % fast_spd)
    _expect(lock_spd < fast_spd * 0.75,
        "锁定移动明显更慢(%.2f < %.2f × 0.75)" % [lock_spd, fast_spd])
    await _wait(0.35)

    # ⑨ 受击：**不改面朝向**，只把人往后推（用户的明确要求）
    player._face_instant(Vector3(0, 0, -1))          # 先摆一个确定朝向（模型正面 = -Z）
    await _wait(0.05)
    var yaw_before_hurt: float = player._pivot.rotation.y
    var pos_before_hurt: Vector3 = player.global_position
    player.health.reset()
    player._iframes = 0.0
    # 伤害来自正前方(-Z) → 应给一个朝 +Z(远离来源)的击退速度，且**不转身**
    player._enter_hurt(player.global_position + Vector3(0, 0, -1.5))
    # ★ 立刻断言（中间不 await）：这一帧还没跑 _physics_process/move_and_slide，
    #   velocity 就是 _enter_hurt 刚赋的初值，**与"玩家是不是正好顶墙"无关**。
    #   【为什么不用位移当判据】前面几节把玩家挪到了场地边角，顶墙时击退被吃掉，
    #   位移只有 0.06m、残速 0.65m/s（实测），拿它判会误报成"没被击退"。
    _expect(player.velocity.z > 8.0,
        "受击瞬间获得朝后的击退速度(%.2f m/s ≈ knockback_strength %.1f)"
            % [player.velocity.z, player.knockback_strength])
    _expect(absf(player.velocity.x) < 0.001, "击退方向正对伤害来源的反向(无横向分量)")
    _expect(player.state == PlayerCharacter.State.HURT, "受击进入 HURT 硬直")
    var yaw_drift := absf(angle_difference(player._pivot.rotation.y, yaw_before_hurt))
    _expect(yaw_drift < 0.002, "受击不改变面朝向(转了 %.4f rad)" % yaw_drift)
    await _wait(player.hurt_time + 0.2)
    var pushed: Vector3 = player.global_position - pos_before_hurt
    _expect(pushed.z > -0.01, "受击不会被推向伤害来源(前后位移 %+.2fm)" % pushed.z)
    _expect(_idling(player), "受击硬直结束后回到 Idle")

    # ⑩ 解除锁定 / 目标消失，两条路径都要把标记收干净
    #   （标记是**常驻**节点，不像 HitFlash 会自毁 —— 漏收就会一直挂在敌人身上）
    await _tap_lock()
    await _wait(0.15)
    _expect(not player.is_locked_on(), "再点一次中键 → 解除锁定")
    _expect(player._lock_marker == null or not is_instance_valid(player._lock_marker),
        "解除锁定后玩家不再持有标记")
    _expect(_count_lock_marker(get_tree().current_scene) == 0, "解除锁定后标记已从场景移除")

    # ⑩-2 重新锁一次：同一个目标重锁应该只造回一个标记（防"每帧重造"式的漏收）
    await _tap_lock()
    _expect(player.is_locked_on(), "再点一次中键 → 重新锁定")
    _expect(_count_lock_marker(get_tree().current_scene) == 1,
        "重锁后场景里仍然只有一个标记(实际 %d，防重复生成)"
            % _count_lock_marker(get_tree().current_scene))

    # ⑩-4 ★ 奇偶性/幂等：连续点击多次，锁定状态按次数正确翻转（奇=锁定、偶数=解锁），
    #   且任意时刻场景里的锁定标记数量 ≤ 1。防两种回归：①一次点击被当成"开+关"两次（松开被误读）；
    #   ②标记"每帧重造"导致越积越多。进入本段时玩家为"已锁定"（dummy 仍有效）。
    var parity_ok: bool = true
    var marker_ok: bool = true
    for i in range(6):
        await _tap_lock()
        var expect_locked: bool = (i % 2 == 1)     # 第 1 次点击→解锁，第 2 次→锁定，交替
        if player.is_locked_on() != expect_locked:
            parity_ok = false
        if _count_lock_marker(get_tree().current_scene) > 1:
            marker_ok = false
    _expect(parity_ok, "★ 连续点击 6 次：锁定状态按奇偶正确翻转（奇=锁定/偶=解锁）")
    _expect(marker_ok, "★ 连续点击期间锁定标记数量始终 ≤ 1")
    _expect(player.is_locked_on(), "连续点击偶数次后回到进入本段时的锁定状态")

    # ⑩-3 目标消失 → 锁定自动退化（锁定期间也不能锁着一个悬空引用），标记随目标一起消失
    dummy.queue_free()
    await _wait(0.2)
    _expect(not player.is_locked_on(), "目标被销毁后自动退化为未锁定")
    _expect(_count_lock_marker(get_tree().current_scene) == 0, "目标销毁后标记已消失")
    _expect(player._locomotion_clip() == player._walk_anim, "退化后位移段回到 Walk")

    Input.action_release("lock_on")
    await _wait(0.1)
    _expect(not player.is_locked_on(), "解除锁定后状态保持未锁定")
    if enemy_was_in_group:
        enemy.add_to_group("enemy")      # 还原主怪的 enemy 组身份（后面几节要用）
    _expect(enemy.is_in_group("enemy"), "主怪已还原进 enemy 组")
    # ★ 还原镜头 yaw：锁定期间镜头被自动转到"玩家背后"，解除后 yaw 就停在那个角度
    #   （游戏里这是正常的 —— 玩家自己用鼠标找回手感）。但后面几节依赖
    #   "镜头 forward = -Z"（_try_start_attack 会用 _get_camera_forward() 决定出手方向），
    #   不摆回去玩家就会朝错方向挥空。这里 yaw 归零 + 立刻重摆镜头。
    var lock_cam: Node3D = get_tree().get_first_node_in_group("camera")
    if lock_cam != null:
        lock_cam.set("yaw", 0.0)
        lock_cam.call("_snap_to_target")
    await _wait(0.1)
    player.health.reset()
    player._iframes = 0.0
    await _wait(0.3)

    # ---- 2) 敌人挥击命中玩家：扣 15 ----
    _place_enemy_in_front_of(enemy, player, 1.3)
    await _wait(0.2)
    enemy._begin_strike(player)
    await _wait(0.35)  # 覆盖 strike 窗口
    _expect(player.health.current_hp == 85, "[敌人攻击] 期望 85，实际 %d" % player.health.current_hp)

    # ---- 3) 玩家挥砍命中敌人：扣 25 ----
    _place_enemy_in_front_of(enemy, player, 1.3)
    enemy.health.reset()
    var enemy_before: int = enemy.health.current_hp
    _face_player_to(player, Vector3(0, 0, -1))
    player._try_start_attack()
    await _wait(0.65)  # 覆盖整个攻击状态
    _expect(enemy.health.current_hp == enemy_before - 25,
        "[玩家攻击] 期望 %d，实际 %d（玩家状态=%d 攻击冷却=%.2f 相距=%.2fm）"
            % [enemy_before - 25, enemy.health.current_hp, player.state,
               player._attack_cooldown, player.global_position.distance_to(enemy.global_position)])

    # ---- 3b) 近战朝向修正（软锁定）：附近有敌人时，攻击自动朝向它 ----
    # ★ 场景刻意刁难：**按住 S 后退**（移动方向背离敌人），敌人摆在侧前方 45°。
    #   没有修正 → 一刀朝身后砍空；有修正 → 自动转向并砍中。
    # 本段把主怪临时变成木桩（它会追人/挥棒，玩家一旦被打进 HURT，
    # _try_start_attack 就会被拒绝，断言会莫名其妙地失败）。
    var foe_aggro: float = enemy.aggro_range
    var foe_range: float = enemy.attack_range
    var foe_speed: float = enemy.move_speed
    enemy.aggro_range = 0.0
    enemy.attack_range = 0.0
    enemy.move_speed = 0.0

    # ★ 让镜头确定性回到玩家正后方(yaw=0 → 镜头前方=-Z)，避免 3a 锁定残留的镜头角度
    #   干扰"敌人相对镜头/身体朝向"的判定。
    var soft_cam: Node3D = get_tree().get_first_node_in_group("camera")
    if soft_cam != null:
        soft_cam.yaw = 0.0
        soft_cam._snap_to_target()
    await _wait(0.05)

    player.global_position = Vector3(0.0, player.global_position.y, 9.0)
    player.velocity = Vector3.ZERO
    await _wait(0.25)
    _expect(player.soft_lock_enabled, "[近战修正] 总开关默认开启")
    _expect(player.soft_lock_range > 0.0 and player.soft_lock_angle > 0.0,
        "[近战修正] 参数已就位（半径 %.1fm / 半角 %.0f°）"
            % [player.soft_lock_range, player.soft_lock_angle])

    enemy.health.reset()
    player._attack_cooldown = 0.0
    _place_enemy_at_angle(enemy, player, 1.5, 45.0)
    await _wait(0.25)
    var hp_soft_before: int = enemy.health.current_hp
    Input.action_press("move_back")                 # 移动方向 = 背离敌人
    await _wait(0.15)
    player._try_start_attack()
    # ⚠ 朝向必须**起手瞬间**就读：攻击一结束回到 MOVE，`_face_towards(_wish_dir)` 会
    #   立刻把身体转回移动方向（仍按着 S → 转回背后），等 0.65s 再读就永远读到"没修正"。
    await _wait(0.06)
    var err_soft: float = _facing_error_deg(player, enemy)
    await _wait(0.6)
    _expect(err_soft < 8.0, "★ [近战修正] 边后退边攻击 → 自动朝向敌人（偏差 %.1f°）" % err_soft)
    _expect(enemy.health.current_hp == hp_soft_before - 25,
        "★ [近战修正] 修正后这一刀真的砍中（%d → %d）" % [hp_soft_before, enemy.health.current_hp])
    Input.action_release("move_back")
    await _wait(0.6)

    # 反证：关掉修正，同样的操作应该**砍空** —— 否则说明"命中"跟修正无关，
    # 上一条断言就是白过的。
    player.soft_lock_enabled = false
    enemy.health.reset()
    player._attack_cooldown = 0.0
    _place_enemy_at_angle(enemy, player, 1.5, 45.0)
    await _wait(0.25)
    var hp_manual_before: int = enemy.health.current_hp
    Input.action_press("move_back")
    await _wait(0.15)
    player._try_start_attack()
    await _wait(0.06)                                # 同上：起手瞬间读朝向
    var err_manual: float = _facing_error_deg(player, enemy)
    await _wait(0.6)
    _expect(err_manual > 60.0, "★ [近战修正·反证] 关掉后朝的是移动方向（离敌人 %.1f°）" % err_manual)
    _expect(enemy.health.current_hp == hp_manual_before,
        "★ [近战修正·反证] 关掉后这一刀砍空（血量 %d 不变）" % enemy.health.current_hp)
    Input.action_release("move_back")
    player.soft_lock_enabled = true
    await _wait(0.6)

    # ★ 把身体朝向显式掰回 -Z(=默认镜头前方)，让下面两条"边界"的角度语义相对
    #   "玩家面朝方向"，而非残留的 move_back(+Z) 朝向。并集锥形修复后，135° 世界的敌人
    #   若身体仍朝 +Z 会变成"身体前方 45°"被吸住、误判通过 —— 这里先归位。
    player._face_instant(Vector3(0, 0, -1))
    player._facing_dir = Vector3(0, 0, -1)
    if soft_cam != null:
        soft_cam.yaw = 0.0
        soft_cam._snap_to_target()
    await _wait(0.05)

    # 边界 1：超出搜索半径 → 不修正（远处的怪不许抢朝向）
    player._attack_cooldown = 0.0
    _place_enemy_at_angle(enemy, player, 6.0, 45.0)
    await _wait(0.2)
    player._try_start_attack()
    await _wait(0.06)
    var err_far: float = _facing_error_deg(player, enemy)
    await _wait(0.6)
    _expect(err_far > 30.0,
        "[近战修正] 超出半径(6m > %.1fm)不修正（偏差 %.1f°）" % [player.soft_lock_range, err_far])

    # 边界 2：背后的敌人 → 绝不修正（把每一刀掰到身后是最难受的手感）
    player._attack_cooldown = 0.0
    _place_enemy_at_angle(enemy, player, 1.5, 135.0)
    await _wait(0.2)
    player._try_start_attack()
    await _wait(0.06)
    var err_behind: float = _facing_error_deg(player, enemy)
    await _wait(0.6)
    _expect(err_behind > 100.0,
        "★ [近战修正] 背后的敌人不抢朝向（偏差 %.1f°）" % err_behind)

    # ---- 3c) 回归：镜头被甩开、但玩家正脸对着敌人 → 这一刀仍须朝敌人 ----
    #   【复现用户反馈】旧逻辑只看镜头前方锥形：镜头没对准敌人时软锁定落空、这一刀朝镜头空挥。
    #   并集锥形修复后，玩家面朝的敌人(即便镜头甩到背后)也能被吸住。本段把镜头甩到 +Z、
    #   敌人摆在玩家正前方(-Z)，断言只能通过"身体前方锥形"命中 —— 旧代码会朝镜头 +Z 空挥(偏差≈180°)。
    player.soft_lock_enabled = true
    player._attack_cooldown = 0.0
    player.global_position = Vector3(0.0, player.global_position.y, 9.0)
    player.velocity = Vector3.ZERO
    player._face_instant(Vector3(0, 0, -1))     # 玩家面朝 -Z
    player._facing_dir = Vector3(0, 0, -1)
    enemy.health.reset()
    _place_enemy_at_angle(enemy, player, 1.5, 0.0)   # 敌人正前方(-Z)、贴合
    await _wait(0.2)
    # 把镜头甩到玩家背后(+Z 方向看)，镜头前方变为 +Z，与敌人(-Z)成 180°
    var repro_cam: Node3D = get_tree().get_first_node_in_group("camera")
    if repro_cam != null:
        repro_cam.yaw = PI
        repro_cam._snap_to_target()
    await _wait(0.05)
    var hp_repro_before: int = enemy.health.current_hp
    player._try_start_attack()
    await _wait(0.06)                            # 起手瞬间读朝向
    var err_repro: float = _facing_error_deg(player, enemy)
    await _wait(0.6)
    _expect(err_repro < 8.0,
        "★ [近战修正·回归] 镜头甩开但仍面朝敌人 → 自动转向敌人(偏差 %.1f°)" % err_repro)
    _expect(enemy.health.current_hp == hp_repro_before - 25,
        "★ [近战修正·回归] 这一刀砍中(镜头甩开也生效, %d → %d)" % [hp_repro_before, enemy.health.current_hp])
    # 还原镜头朝向，避免影响后续章节
    if repro_cam != null:
        repro_cam.yaw = 0.0
        repro_cam._snap_to_target()
    await _wait(0.05)

    # ---- 3d) 三段连击：Slash → Slash2 → Slash3（后摇取消 + 输入缓冲 + 顿帧/震动/音效）----
    # 【为什么接在 3b/3c 后面】此时主怪的 aggro/attack_range/move_speed 已被前面几节改成 0，
    #   正好是根合格的连击木桩；它的真身属性要到本节末尾（enemy.aggro_range = foe_aggro）才还原。
    # 【为什么"等时间"全用 _wait_until_attack_time 而不是 `_wait(x)`】取消点是相对人物自己的
    #   _state_time 定义的，而连击里每一段命中都会触发**顿帧**（全局时间被压慢）——
    #   任何"先算好该等几秒"的写法都会因为顿帧错位。直接盯 _state_time 最稳。
    player.soft_lock_enabled = true
    player._attack_cooldown = 0.0
    player._combo_queued = false
    player._combo_buffer_time = 0.0
    player.health.reset()
    player._iframes = 0.0
    var combo_cam: Node3D = get_tree().get_first_node_in_group("camera")
    if combo_cam != null:
        combo_cam.yaw = 0.0
        combo_cam.call("_snap_to_target")
    player._face_instant(Vector3(0, 0, -1))
    player._facing_dir = Vector3(0, 0, -1)
    await _wait(0.1)

    # 3d-0) 参数表：三段的时长来源正确，且**第 3 段不可取消**
    # 【为什么绕一道 get_script_constant_map 读 COMBO_STEPS】player 是无类型句柄，
    #   而"类的常量"在 GDScript 里只能通过类名访问；拿到脚本的常量表是最直白的写法。
    var combo_steps: int = int(player.get_script().get_script_constant_map()["COMBO_STEPS"])
    _expect(combo_steps == 3, "连击总段数 = 3")
    _expect(player._combo_total(0) == player.attack_total
        and player._combo_total(1) == player.combo2_total
        and player._combo_total(2) == player.combo3_total,
        "三段时长分别取自 attack_total / combo2_total / combo3_total")
    _expect(player._combo_cancel_at(0) > 0.0 and player._combo_cancel_at(1) > 0.0,
        "★ 第 1/2 段有后摇取消点（%.2f / %.2f）"
            % [player._combo_cancel_at(0), player._combo_cancel_at(1)])
    _expect(player._combo_cancel_at(2) == 0.0,
        "★★ 第 3 段没有取消点 → 收尾重击必须演完（这就是连击的代价）")
    var combo_sum: int = player.attack_damage + player.combo2_damage + player.combo3_damage
    _expect(combo_sum == 95 and combo_sum < 100,
        "三段总伤害 %d < 满血 100（完整连击打不死敌人，仍要补刀）" % combo_sum)

    # 3d-1) 完整三段连击：每段都在"取消点之前一点点"按下 → 考的是**输入缓冲**
    enemy.health.reset()
    _place_enemy_in_front_of(enemy, player, 1.3)
    await _wait(0.15)
    var combo_hp0: int = enemy.health.current_hp
    player._try_start_attack()
    await _wait(0.04)
    _expect(player.get_combo_step() == 0, "★ 起手是第 1 段")
    _expect(player._anim_player.current_animation == player._slash_anim,
        "第 1 段播 Slash（实际 %s）" % player._anim_player.current_animation)

    # ── 第 1 段 → 第 2 段：在取消点**之前**按下 ──
    var t_press1: float = maxf(0.05, player._combo_cancel_at(0) - 0.10)
    _expect(await _wait_until_attack_time(player, t_press1), "第 1 段按时推进（仍在 ATTACK）")
    _expect(player.get_combo_step() == 0, "★ 到了取消点之前，仍停在第 1 段（没有自动接续）")
    player._try_start_attack()
    _expect(player.is_combo_queued(),
        "★ 取消点之前按下去 → 只记进输入缓冲，**不立刻断招**")
    _expect(player.get_combo_step() == 0, "★ 缓冲期间不会越级接段")
    _place_enemy_in_front_of(enemy, player, 1.3)   # 第 1 段把它打退了，摆回身前
    _expect(await _wait_combo_step(player, 1), "★★ 到取消点缓冲兑现 → 自动接上第 2 段")
    _expect(player._anim_player.current_animation == player._slash2_anim,
        "第 2 段播 Slash2（实际 %s）" % player._anim_player.current_animation)
    _expect(not player.is_combo_queued(), "★ 缓冲兑现后即清空（不会连着接两段）")

    # ── 第 2 段 → 第 3 段：同样走缓冲 ──
    var t_press2: float = maxf(0.05, player._combo_cancel_at(1) - 0.10)
    _expect(await _wait_until_attack_time(player, t_press2), "第 2 段按时推进（仍在 ATTACK）")
    player._try_start_attack()
    _expect(player.is_combo_queued(), "第 2 段同样吃输入缓冲")
    _place_enemy_in_front_of(enemy, player, 1.3)
    _expect(await _wait_combo_step(player, 2), "★★ 接上第 3 段（收尾重击）")
    _expect(player._anim_player.current_animation == player._slash3_anim,
        "第 3 段播 Slash3（实际 %s）" % player._anim_player.current_animation)

    # ── 第 3 段不可取消：中途按左键也接不出第 4 段（记都不记）──
    player._try_start_attack()
    _expect(not player.is_combo_queued(),
        "★★ 第 3 段不可取消：中途按下**连缓冲都不记**（没有下一段可接）")
    await _wait_until_attack_time(player, player._combo_total(2) * 0.7)
    _expect(player.get_combo_step() == 2, "★ 第 3 段中途不会越级到第 4 段")

    # ── 收尾：演完回 MOVE，冷却用更长的 combo_finish_cd（连击的"重量"也在这里）──
    await _wait_attack_over(player)
    _expect(_is_move_state(player), "★ 第 3 段演完回到 MOVE")
    _expect(player.get_combo_step() == 2, "整套连击结束后段号停在 2（第 3 段）")
    _expect(player._attack_cooldown > player.attack_cd + 0.05,
        "★ 收尾第 3 段的冷却(%.2f) > 普通攻击冷却(%.2f)"
            % [player._attack_cooldown, player.attack_cd])

    # ── 伤害累计：三段各打中一次，总伤害 = 25+30+40 = 95 ──
    # （上面这一整串连击就是"完整一套"，敌人 100 → 5）
    _expect(enemy.health.current_hp == combo_hp0 - combo_sum,
        "★★ 完整三段连击打出 %d 点伤害（%d → %d，三段各命中一次）"
            % [combo_sum, combo_hp0, enemy.health.current_hp])

    # 3d-2) 不接续：只按一次 → 演完整段回 MOVE，冷却回到普通 attack_cd
    player._attack_cooldown = 0.0
    enemy.health.reset()
    _place_enemy_in_front_of(enemy, player, 1.3)
    await _wait(0.15)
    player._try_start_attack()
    await _wait_attack_over(player)
    _expect(_is_move_state(player), "只按一次 → 第 1 段演完回 MOVE（不会自动连下去）")
    _expect(absf(player._attack_cooldown - player.attack_cd) < 0.06,
        "未接续的第 1 段冷却 = attack_cd(%.2f，实际 %.2f)"
            % [player.attack_cd, player._attack_cooldown])

    # 3d-3) 缓冲会**过期**：按得太早（早于 combo_buffer_time）就不该替我接段
    var saved_buf: float = player.combo_buffer_time
    player.combo_buffer_time = 0.05
    player._attack_cooldown = 0.0
    await _wait(0.15)
    player._try_start_attack()          # 第 1 段起手
    await _wait(0.02)
    player._try_start_attack()          # 立刻再按一下 → 缓冲只有 0.05s 寿命
    await _wait_attack_over(player)
    _expect(player.get_combo_step() == 0,
        "★ 缓冲过期后不接段（早于取消点 0.05s 就失效，仍停在第 1 段）")
    player.combo_buffer_time = saved_buf
    await _wait(0.2)

    # 3d-4) 命中反馈三件套：顿帧 / 镜头震动 / 音效
    # 【为什么直接调 _on_hit_landed，而不是真去打一刀】这三样是"命中之后"的副作用，
    #   与挥砍本身是两件事。直接调能把"顿帧真的压慢了全局时间""镜头真的抖了"独立钉死，
    #   不必再摆位对齐判定帧（命中本身已被 3d-1 的伤害累计覆盖）。
    Engine.time_scale = 1.0
    player._bt_factor = 1.0
    player._hs_factor = 1.0
    player._on_hit_landed(0)
    _expect(Engine.time_scale < 1.0,
        "★ 命中触发顿帧（全局时间倍率 %.3f < 1）" % Engine.time_scale)
    _expect(absf(Engine.time_scale - player.hitstop_scale) < 0.01,
        "顿帧把时间压到 hitstop_scale（实际 %.3f，期望 %.3f）"
            % [Engine.time_scale, player.hitstop_scale])
    var shake_amt: float = 0.0
    if combo_cam != null and combo_cam.has_method("get_shake_amount"):
        shake_amt = float(combo_cam.call("get_shake_amount"))
        _expect(shake_amt > 0.0, "★ 命中触发镜头震动（振幅 %.3f）" % shake_amt)
    # 震动是相机在**自己的 _process 里**逐帧施加到子节点 Camera3D 的局部偏移上的，
    # 刚调完 shake() 的那一帧offset 还是 0 —— 必须先过几帧真实时间再读。
    await _wait_real(0.06)
    if combo_cam != null:
        var cam_eye: Camera3D = combo_cam.get("_cam") as Camera3D
        if cam_eye != null:
            _expect(absf(cam_eye.h_offset) > 0.0 or absf(cam_eye.v_offset) > 0.0,
                "★ 震动真的作用到了相机上（h=%.4f v=%.4f）"
                    % [cam_eye.h_offset, cam_eye.v_offset])
        else:
            _expect(false, "镜头脚本里应持有子节点 Camera3D 的引用(_cam)")
    _expect(player._sfx_swing != null and player._sfx_hit != null,
        "挥剑 / 命中两个 3D 音效播放器已挂载")
    _expect(player._stream_swing_light != null and player._stream_swing_heavy != null
        and player._stream_hit != null,
        "轻挥 / 重挥 / 命中三个音效资源已加载")
    # 顿帧按**真实时间**计时 → 用真实时间的钟等它自己结束（普通 _wait 会被慢动作拖长）
    await _wait_real(player.hitstop_normal + 0.20)
    _expect(is_equal_approx(Engine.time_scale, 1.0),
        "★ 顿帧自行结束并回到常速（实际 %.3f）" % Engine.time_scale)
    # 收尾重击的顿帧更久：等过"普通时长"时它仍在顿帧
    player._on_hit_landed(2)
    await _wait_real(player.hitstop_normal + 0.03)
    _expect(Engine.time_scale < 1.0,
        "★ 收尾重击的顿帧比普通命中更久（普通 %.3f 已过、它仍在顿帧）" % player.hitstop_normal)
    await _wait_real(player.hitstop_finisher + 0.20)
    _expect(is_equal_approx(Engine.time_scale, 1.0),
        "★ 收尾顿帧也自行结束并回到常速（实际 %.3f）" % Engine.time_scale)

    # 3d-5) 顿帧与子弹时间**互不抢占**：两个因子取更慢者
    player._bt_factor = 0.45            # 假装子弹时间正压着时间
    player._hs_factor = 0.05
    player._push_time_scale()
    _expect(absf(Engine.time_scale - 0.05) < 0.001, "顿帧比子弹时间更慢 → 取顿帧")
    player._hs_factor = 1.0             # 顿帧结束，子弹时间还应继续压着（不能被拉回常速）
    player._push_time_scale()
    _expect(absf(Engine.time_scale - 0.45) < 0.001,
        "★ 顿帧结束后子弹时间仍在（不会被拉回 1.0 —— 这颗「各写一个因子再取更慢者」要解决的问题）")
    player._bt_factor = 1.0
    player._push_time_scale()
    _expect(is_equal_approx(Engine.time_scale, 1.0), "两个因子复位后回到常速")
    player.health.reset()
    player._iframes = 0.0
    await _wait(0.2)

    enemy.aggro_range = foe_aggro
    enemy.attack_range = foe_range
    enemy.move_speed = foe_speed

    # ---- 4) 连续攻击击杀敌人 → 触发重生 ----
    var killed_id := enemy.get_instance_id()
    enemy.take_damage(1000, player.global_position)
    await _wait(0.1)
    _expect(not enemy.is_alive(), "敌人已被击杀")
    await _wait(4.0)  # 等待重生计时
    var alive_enemies := _alive_nodes_in_group("enemy")
    var respawned := false
    for e in alive_enemies:
        if e.get_instance_id() != killed_id:
            respawned = true
    _expect(respawned, "敌人已重生为新实例")
    var new_enemy := get_tree().get_first_node_in_group("enemy")
    if new_enemy != null:
        _expect(new_enemy.health.current_hp == 100, "重生敌人 HP 满值")

    # ---- 5) 玩家死亡 → 死亡遮罩出现 + 播 Death 倒地动画 ----
    player.health.reset()
    await _wait(0.1)
    player.take_damage(1000, player.global_position + Vector3(0, 0, 1))
    await _wait(0.05)
    _expect(not player.is_alive(), "玩家已死亡")
    _expect(player._anim_player.current_animation == player._death_anim,
        "死亡时播放 %s(实际 %s)" % [player._death_anim, player._anim_player.current_animation])
    var death_anim: Animation = player._anim_player.get_animation(player._death_anim)
    if death_anim != null:
        var want_dspd: float = death_anim.length / player.death_time
        _expect(absf(player._anim_player.get_playing_speed() - want_dspd) < 0.01,
            "倒地动画实际倍速 = length ÷ death_time = %.3f(实际 %.3f)"
                % [want_dspd, player._anim_player.get_playing_speed()])
    if hud != null:
        var overlay = hud.get("_death_overlay")
        _expect(overlay != null and overlay.visible, "死亡遮罩已显示")

    # 演满 death_time 之后：动画停下，但**尸体不许复位**（骨骼冻在倒地末帧）。
    # 【为什么钉这条】以前是脚本把整个 VisualPivot 转 90°，一旦有人加回"演完 _anim_to_rest()"，
    #   尸体会"啪"地站起来 —— 这条断言就是防它。
    await _wait(player.death_time + 0.3)
    _expect(not player._anim_player.is_playing(), "倒地动画播完后停止(冻在末帧)")
    _expect(not _bones_at_rest(player), "死亡后骨骼**没有**复位(尸体保持倒地姿势)")
    var root_idx: int = player._skeleton.find_bone("root")
    if root_idx >= 0:
        var root_q: Quaternion = player._skeleton.get_bone_pose_rotation(root_idx)
        var root_rest: Transform3D = player._skeleton.get_bone_rest(root_idx)
        var root_rest_q: Quaternion = root_rest.basis.get_rotation_quaternion()
        var pitched: float = rad_to_deg(root_rest_q.angle_to(root_q))
        _expect(pitched > 60.0, "倒地末帧 root 骨骼已前倾 %.1f°(整体扑倒)" % pitched)


# ------------------------------------------------------------------ 工具

func _alive_nodes_in_group(group: StringName) -> Array:
    var out: Array = []
    for n in get_tree().get_nodes_in_group(group):
        if n.has_method("is_alive") and n.is_alive():
            out.append(n)
    return out


func _place_enemy_in_front_of(enemy: Node3D, player: Node3D, dist: float) -> void:
    var f := Vector3(0, 0, -1) # 玩家默认朝 -Z
    enemy.global_position = player.global_position + f * dist
    enemy.velocity = Vector3.ZERO


func _face_player_to(player: Node3D, dir: Vector3) -> void:
    if player.has_method("_face_instant"):
        player._face_instant(dir)


## 把敌人摆到玩家"镜头正前方偏 deg 度"的位置（水平距离 dist 米）。
## deg=0 = 正前方(-Z)；正数 = 往右偏(+X)。用来造"目标不在正前方"的刁难场景。
func _place_enemy_at_angle(enemy: Node3D, player: Node3D, dist: float, deg: float) -> void:
    var rad := deg_to_rad(deg)
    var dir := Vector3(sin(rad), 0.0, -cos(rad))
    enemy.global_position = player.global_position + dir * dist
    enemy.velocity = Vector3.ZERO


## 玩家当前正面 与 "玩家→目标" 方向的水平夹角(度)。
## 近战修正的断言全靠它：吸住了应该 ≈0°，没吸住就是目标所在的那个偏角。
func _facing_error_deg(player: Node3D, target: Node3D) -> float:
    var to_t := target.global_position - player.global_position
    to_t.y = 0.0
    if to_t.length() < 0.05:
        return 0.0
    var facing: Vector3 = player._get_facing_flat()
    return rad_to_deg(acos(clampf(facing.dot(to_t.normalized()), -1.0, 1.0)))


## 按节点名递归查找（用于定位模型内部的动画节点，如 EMT-RollPivot）。
func _find_by_name(root: Node, target: String) -> Node:
    if root.name == target:
        return root
    for c in root.get_children():
        var found := _find_by_name(c, target)
        if found != null:
            return found
    return null


## 把某个节点下的所有网格包围盒换算到指定空间并求并集（用于武器位置校验）。
func _accumulate_bounds(node: Node, inv: Transform3D, bounds: Array) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var aabb: AABB = mi.get_aabb()
        var xform: Transform3D = inv * mi.global_transform
        for i in 8:
            var off := Vector3.ZERO
            if (i & 1) != 0:
                off.x = aabb.size.x
            if (i & 2) != 0:
                off.y = aabb.size.y
            if (i & 4) != 0:
                off.z = aabb.size.z
            var p: Vector3 = xform * (aabb.position + off)
            bounds[0] = (bounds[0] as Vector3).min(p)
            bounds[1] = (bounds[1] as Vector3).max(p)
    for child in node.get_children():
        _accumulate_bounds(child, inv, bounds)


## 检查某段动画是否已设为循环播放（Walk / JumpAir 必须是循环）。
func _loop_ok(player, anim_name: String) -> bool:
    if player._anim_player == null:
        return false
    var a: Animation = player._anim_player.get_animation(anim_name)
    return a != null and a.loop_mode != Animation.LOOP_NONE


## 检查所有骨骼是否都回到"绑定姿势"(rest pose)（容差内）。
## 用于验证"停下/落地/受击后骨骼没有僵在动画中途的姿势"。
func _bones_at_rest(player) -> bool:
    var skel = player._skeleton
    if skel == null:
        return false
    for i in skel.get_bone_count():
        var rest: Transform3D = skel.get_bone_rest(i)
        var q_rest: Quaternion = rest.basis.get_rotation_quaternion()
        var q_pose: Quaternion = skel.get_bone_pose_rotation(i)
        if absf(q_pose.angle_to(q_rest)) > 0.08:
            return false
        if skel.get_bone_pose_position(i).distance_to(rest.origin) > 0.02:
            return false
    return true


## 玩家是否正在播"站立待机"(Idle)。
## 【为什么需要它】补齐 Idle 之后，"停下 / 落地 / 收招"不再是"动画停播 + 骨骼复位到绑定姿势"，
##   而是切到 Idle 呼吸循环 —— Idle 是循环动画、`is_playing()` 恒为 true，
##   所以老写法 `not is_playing() and _bones_at_rest()` 全部失效，要换成判"当前在播 Idle"。
func _idling(player) -> bool:
    if player._anim_player == null or player._idle_anim == "":
        return false
    return player._anim_player.current_animation == player._idle_anim


## 采一份"当前所有骨骼的姿势旋转"，用于比较两个时刻的姿势差多少。
func _sample_bone_rotations(player) -> Array:
    var out: Array = []
    var skel = player._skeleton
    if skel == null:
        return out
    for i in skel.get_bone_count():
        out.append(skel.get_bone_pose_rotation(i))
    return out


## 递归统计场景里"还活着的"打击闪光特效数量（完美格挡 / 处决会生成 HitFlash）。
## 【为什么要递归】特效挂载点由 player._vfx_root() 决定（优先挂场景根，
##   取不到才退到父节点），所以不能假设它一定在哪一层，只能整棵树数。
func _count_hit_flash(node: Node) -> int:
    var n := 0
    for c in node.get_children():
        if c is HitFlash:
            n += 1
        n += _count_hit_flash(c)
    return n


## 递归找出场景里的第一个 HitFlash（要检查它的内部结构/动画曲线时用）。
func _first_hit_flash(node: Node) -> HitFlash:
    for c in node.get_children():
        if c is HitFlash:
            return c as HitFlash
        var found := _first_hit_flash(c)
        if found != null:
            return found
    return null


## 递归统计场景里"还活着"的锁定标记数量。
## 【为什么要数】锁定标记是**常驻**节点（不像 HitFlash 会自毁），
##   最怕的 bug 是"每帧重造一个"或"解除锁定忘了收"—— 节点会越积越多。
##   数一遍就能钉住"任意时刻至多一个"。
func _count_lock_marker(node: Node) -> int:
    var n := 0
    for c in node.get_children():
        if c is LockMarker:
            n += 1
        n += _count_lock_marker(c)
    return n


## 递归统计场景里"还活着的"完美闪避虚影数量（GhostTrail）。
## 【为什么要数】虚影是"生成后淡出并自毁"的节点，最怕两种情况：
##   ① 完美闪避根本没生成（节点数 0）—— 玩家什么都看不到；
##   ② 生成后忘了销毁（越积越多）—— 每闪一次都留一堆半透明模型。
##   数它就能一次钉住这两端。
func _count_ghost_trail(node: Node) -> int:
    var n := 0
    if node is GhostTrail:
        n += 1
    for c in node.get_children():
        n += _count_ghost_trail(c)
    return n


## 取第一张虚影身上的残影材质（用于断"看不看得见"那几条硬指标）。
## 【为什么要单独写个取材质的】虚影的身体是 VisualPivot 的**裸拷贝**，
##   中间隔了 Skeleton3D / MeshInstance3D 好几层，且没有任何脚本能借道，
##   只能递归下去捞第一个带 material_override 的 MeshInstance3D。
func _first_ghost_material(node: Node) -> StandardMaterial3D:
    if node is GhostTrail:
        var mi := _first_mesh_override(node)
        if mi != null:
            return mi
    for c in node.get_children():
        var r := _first_ghost_material(c)
        if r != null:
            return r
    return null


func _first_mesh_override(node: Node) -> StandardMaterial3D:
    if node is MeshInstance3D:
        var m := (node as MeshInstance3D).material_override as StandardMaterial3D
        if m != null:
            return m
    for c in node.get_children():
        var r := _first_mesh_override(c)
        if r != null:
            return r
    return null


func _expect(cond: bool, msg: String) -> void:
    if cond:
        print("AUTOTEST OK: " + msg)
    else:
        failures.append(msg)
        print("AUTOTEST FAIL: " + msg)


func _wait(sec: float) -> void:
    await get_tree().create_timer(sec).timeout


## 按**真实时间**等待（不受 Engine.time_scale 影响）。
## 【为什么需要它】普通 `_wait` 用的是被缩放过的计时器：顿帧把时间压到 0.05 倍时，
##   "等 0.08 秒"会被拉成 1.6 秒真实时间 —— 而顿帧本身是**按真实时间**计时的（补间
##   set_ignore_time_scale）。想验证"0.055 秒真实时间后顿帧自己结束"，就必须用真实时间的钟。
func _wait_real(sec: float) -> void:
    await get_tree().create_timer(sec, true, false, true).timeout


## 等玩家当前这一段攻击的 _state_time 走到 t 秒（游戏时间），或提前离开 ATTACK 就返回。
## 【为什么要这么等，而不是 `await _wait(t)`】取消点/判定窗都是相对**人物自己的状态计时**
##   (_state_time) 定义的，而顿帧会在中途把时间压慢 —— 自己算"该等多久"迟早会错位。
##   直接盯 _state_time，帧帧问"到了没"，无论中间发生多少次顿帧都精确。
## @return 是否"走到 t 时仍处于 ATTACK"（false = 中途就离开攻击状态了）
func _wait_until_attack_time(player, t: float) -> bool:
    var guard := 0
    while player.is_attacking() and float(player._state_time) < t and guard < 1200:
        await get_tree().physics_frame
        guard += 1
    return player.is_attacking()


## 等当前这段攻击**演完**（离开 ATTACK 状态），或超时返回。
func _wait_attack_over(player) -> void:
    var guard := 0
    while player.is_attacking() and guard < 1200:
        await get_tree().physics_frame
        guard += 1


## 等连击段号变成 expected（最多等 timeout_sec 游戏时间）。@return 是否等到
## 【为什么不能只等"时间"】切段会把 _state_time **归零**，于是"等到 _state_time ≥ 0.31"
##   这种条件在切换后会重新成立（0 < 0.31），循环根本不会退出 —— 更糟的是它会在切换
##   发生之前就提前满足退出（比如按下时 _state_time 已经超过目标），断言便跑在切换之前。
##   直接盯"段号变了没"才是这件事的本来语义，也不会被顿帧打乱。
func _wait_combo_step(player, expected: int, timeout_sec: float = 2.0) -> bool:
    var guard := 0
    var limit := int(timeout_sec * 240.0)
    while int(player.get_combo_step()) != expected and guard < limit:
        await get_tree().physics_frame
        guard += 1
    return int(player.get_combo_step()) == expected


## 玩家是否处于"可自由行动"的移动/待机状态（= State.MOVE = 0）。
## 【为什么用数字 0】GDScript 不允许通过实例访问枚举（player.State.MOVE 不合法），
##   而这里拿到的是无类型的 player 句柄 —— 用枚举首项的下标最直接，注释说明它是什么。
func _is_move_state(player) -> bool:
    return int(player.state) == 0


## 模拟"点击一次鼠标中键"（lock_on 现在是**切换型**输入：点一次锁定、再点一次解除）。
## 【为什么必须跨物理帧】点击 = 按下 → **至少跨过一个物理帧**（让 _physics_process 里的
##   is_action_just_pressed 有机会被读到）→ 松开。绝对不能"同一帧 press 完立刻 release 且中间不 await"，
##   那样这一次按下可能一次都没被观察到、点击被吞掉（切换型比按住型更怕漏 —— 漏一次就少翻转一次）。
## 【为什么 release 后再等两帧】press 后留 1 帧让 just_pressed 生效；release 后再留 1~2 帧让状态稳定落定，
##   避免"上一次点击的余波"混进下一次点击的判定。
func _tap_lock() -> void:
    Input.action_press("lock_on")
    await get_tree().physics_frame
    Input.action_release("lock_on")
    await get_tree().physics_frame
    await get_tree().physics_frame
