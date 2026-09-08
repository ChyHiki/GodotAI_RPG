# FirstGame — 第三人称 3D 动作游戏（M1 垂直切片）

用 Godot 4.7 开发的第三人称动作游戏。当前为 **M1 可玩垂直切片**：移动/翻滚/近战攻击手感验证阶段，全部美术为引擎原语占位。

## 环境

- Godot **4.7.2 stable**：`D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
  （编辑器也可直接双击 `Godot.lnk` 或用该 exe 打开本目录的 `project.godot`）
- Blender 5.2.1 LTS（`E:\blender\blender.exe`）：预留的建模管线，M2 起用于正式角色/场景

## 如何运行

1. 用 Godot 打开 `D:\GodotProject\first-game\project.godot`
2. 打开场景 `scenes/main/main.tscn`（或直接按 **F6** 运行当前工程的主场景）
3. 试玩

### 操作

| 输入 | 动作 |
|---|---|
| WASD / 方向键 | 移动（相对镜头方向） |
| 鼠标 | 环绕视角（点击窗口可重新捕获鼠标） |
| 左键 | 近战挥砍 |
| Shift | 翻滚（全程无敌帧） |
| Esc | 释放/捕获鼠标 |
| R | 重新开始（死亡后也可用） |

## M1 包含

- ✅ 第三人称自由追尾镜头（鼠标环绕、平滑跟随、墙体避让）
- ✅ 角色状态机：移动 / 翻滚(无敌) / 攻击 / 受击硬直 / 死亡
- ✅ 敌人"红甲守卫"AI：索敌 → 追击 → 蓄力预警 → 挥击 → 恢复（可打断）
- ✅ 战斗循环：攻击判定、受击闪白、击退硬直、击杀
- ✅ 有边界竞技场（围墙 + 立柱）、天空光照
- ✅ HUD：玩家血条、敌人血条、准星、提示消息、死亡遮罩
- ✅ 敌人 3 秒重生、玩家 R 重开

## 目录结构

```
project.godot            # 引擎配置（3D 渲染 / Jolt 物理 / 主场景 / autoload）
scenes/
  main/main.tscn         # 主场景（程序化构建环境 + 生成管理）
  player/player.tscn     # 玩家（胶囊碰撞 + Health）
  enemy/enemy.tscn       # 红甲守卫
  camera/camera.tscn     # 追尾镜头
  ui/hud.tscn            # HUD
scripts/
  autoload/input_setup.gd      # 运行时输入映射（WASD/攻击/翻滚…）
  components/health.gd         # 通用生命值组件
  player/player.gd             # 玩家状态机 + 程序化原语角色
  enemy/enemy.gd               # 敌人 AI 状态机
  camera/third_person_camera.gd# 镜头
  ui/hud.gd                    # HUD 构建与更新
  main/main.gd                 # 主场景逻辑
docs/GAME_DESIGN.md       # 设计文档与后续方向
```

## 已知限制（M1 有意为之）

- 角色视觉在运行时用原语网格拼装（编辑器场景预览看不到模型，运行即可见）
- 输入动作用代码注册（Input Map 面板不可见），M2 迁移为正式项目配置以支持改键
- 无音效 / 打击特效 / 锁定 / 连击——属于 M2 打磨内容

## 验证方式（命令行冒烟测试）

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\GodotProject\first-game --quit-after 240
# exit=0 且无 SCRIPT ERROR 即通过
```
