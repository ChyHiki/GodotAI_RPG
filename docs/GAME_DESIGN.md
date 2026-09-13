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
  - 已有：`E:\blender\blenderproject\player_knight\` —— 玩家低模蓝甲骑士（静态模型 + `RollLeap` 翻滚动画）
- **Blender**：`E:\blender\blender.exe`（5.2.1 LTS）；dsh-blender 插件已配置指向该路径
- **游戏项目内只保留引擎需要的产物**：`artifacts/models/<模型名>/*.glb` 与预览图；模型源文件不放项目里，避免两处版本不一致
- **改模型流程**：用 Blender 打开 blenderproject 里的源文件 → 修改 → 导出 GLB（勾选 Animation）→ 覆盖 `artifacts/models/player_knight/` 下的同名 GLB → Godot 自动重新导入
- 想让 AI 改模型时，直接说"改 `E:\blender\blenderproject\player_knight` 里的模型"即可
