# FirstGame 设计文档

第三人称 3D 动作游戏（方向草案，随开发迭代更新）。

## 核心愿景

- 主打**近战手感**：攻击/翻滚/受击的帧级反馈优先，再谈内容量
- 设计参考：黑魂（节奏与翻滚）、鬼泣（连段爽感）、战神（镜头表现）
- 美术路线：M1 原语占位 → M2 起 Blender 低多边形风格（E:\blender\blender.exe）

## M1 垂直切片（已完成，待试玩反馈）

范围：移动 + 追尾镜头 + 翻滚(无敌帧) + 单段攻击 + 1 个敌人 + 竞技场 + 血条/死亡重生。
验证目标：**移动镜头手感、攻击命中感、翻滚躲攻击的可行性**。

## M2 手感打磨（候选清单，待反馈后取舍）

- [ ] 连击（最多 3 段，带节奏窗口）与攻击后摇取消
- [ ] 攻击命中：顿帧(hitstop)、屏幕震动、受击闪白已有、飘字伤害
- [ ] 翻滚无敌帧精确化 + 闪避音效
- [ ] 敌人 AI：攻击多样化（挥击/跳劈）、受击不打断预警但可被破招
- [ ] 音效（走路/挥剑/受击/环境）
- [ ] 输入映射迁移进 project.godot 并支持改键

## M3 内容扩展（构思）

多敌人类型 / Boss 战 / 技能与成长 / 更多场景 / Blender 正式角色替换占位模型

## M4 打磨上线

UI/设置存档 / 演出 / 发布构建

## 手感调参速查

- 玩家移动/翻滚：`scripts/player/player.gd` 顶部 `@export`
- 敌人 AI：`scripts/enemy/enemy.gd` 顶部 `@export`
- 镜头：`scripts/camera/third_person_camera.gd` 顶部 `@export`
在 Godot 编辑器里选中节点即可实时调整这些参数试手感。

## 美术资产管线（Blender）

- **建模源文件目录（唯一来源）**：`E:\blender\blenderproject\<模型名>\`
  - 每个模型一个子目录，内含 `.blend` 源文件、`export\*.glb`、`previews\*.png` 和 `README.md`（说明每个文件用途与改法）
  - 已有：`E:\blender\blenderproject\player_knight\` —— 玩家低模蓝甲骑士
    - 主文件 `knight-player.blend`：模型 + **21 根骨骼**（刚性蒙皮）+ **剑 `GEO-sword_01`**（绑在 `weapon.R`）+ **5 段动画**：`Walk`（行走 1.0s 循环）、`RollLeap`（原地翻滚 0.417s）、`Slash`（挥砍 0.5s）、`JumpStart`（起跳 0.333s）、`JumpAir`（悬空 0.5s 循环）
    - 引擎用导出：`export\player_knight_rigged.glb`（骨架 + 5 段动画）
    - 动画与代码对应：`roll_time=0.42` ≈ RollLeap；`attack_total=0.5`、命中窗 `0.17–0.28s`（游戏时间）= Slash 剑刃最快段 `0.18–0.30s`（动画时间，实测角速度峰值 496°/s @0.26s）；跳跃 = 起跳瞬间 `JumpStart` → 离地后循环 `JumpAir`；移动 = `Walk`（按当前速度调播放倍速，站住停播）
    - 所有水平位移（含跳跃弧线）都由代码的速度逻辑决定；`JumpStart` 的 root 高度是"双脚贴地"约束自动反解出来的
  - **注意**：动画不烘焙前向位移，切换动画不会残留位置偏移
- **Blender**：`E:\blender\blender.exe`（5.2.1 LTS）；dsh-blender 插件已配置指向该路径
- **游戏项目内的资产按类型分类存放**（源文件不放项目里，避免两处版本不一致）：
  ```
  assets/characters/player_knight/
    ├─ player_knight.glb   角色：5 网格 + 21 骨骼 + 5 段动画（**不含武器**）
    ├─ animations/         从 GLB 抽出的独立动画 .tres（tools/split_player_animations.gd 生成）
    ├─ previews/           各动画代表帧
    └─ README.md           角色使用说明（骨骼名/动画表/改法）
  assets/weapons/sword_01/
    └─ sword_01.glb        武器：独立资产（原点=握把中心，刀身沿局部 -Z）
  tools/                   资产工具（动画抽取 / 动画轨道检查 / 武器挂点验证）
  ```
- **武器与角色分离**：角色只带挂点骨骼 `weapon.R`，武器在 Godot 里用 `BoneAttachment3D` 附加。
  换武器只需导出新武器资产并调用 `player.equip_weapon(...)`，**角色模型与全部动画不用动**。
- **武器对齐（实测修正）**：武器资产的原点 = 握把中心、**刀身沿局部 -Z**。
  挂点骨骼 `weapon.R` 的静止基是 +Z≈模型上方、+Y≈模型前方，所以**不能单位变换直挂**——
  那样刀身会朝下（实测整把剑掉到 y≈-0.4、中心偏差 0.955 m）。
  现用固定对齐变换 `WEAPON_ALIGN_MODEL`（绕 X +90° 让刀身立起 + 平移到"分离前"的旧握柄中心）修正，
  **实测中心偏差 0.034 m**；回归方式：`tools/check_weapon.tscn` + 自动测试的武器断言。
- **改模型流程**：用 Blender 打开 blenderproject 里的源文件 → 修改 → 导出 GLB（勾选 Animation）→ 覆盖 `assets/characters/player_knight/player_knight.glb` → Godot 自动重新导入
- **Godot 接入状态**：`scripts/player/player.gd` 已接线——自动识别模型动画并按状态播放（MOVE→Walk / ROLL→RollLeap / ATTACK→Slash / JUMP→JumpStart→JumpAir）；未识别到动画时退回原语"小蓝人"与脚本姿态兜底
- 想让 AI 改模型时，直接说"改 `E:\blender\blenderproject\player_knight` 里的模型"即可
