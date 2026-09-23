extends CharacterBody3D
class_name PlayerCharacter
## ============================================================
## 玩家角色：状态机 + 外观（支持外部模型 / 原语兜底）
## ============================================================
## 【这个脚本做了什么】
##   第三人称动作游戏的主角控制：
##     - 移动：WASD 相对镜头方向平移（视角朝向哪，W 就往哪走）
##     - 翻滚：Shift，带位移与全程无敌帧（用来躲敌人攻击）
##     - 攻击：鼠标左键挥剑，命中面前敌人造成伤害
##     - 格挡：鼠标右键**按住**举剑横挡在身前（减伤 70%），
##             按下的**前 0.22s** 内挡住攻击 = 完美格挡
##             （0 伤害 + 敌人长硬直 + 往敌人失衡条里顶一截 + 迸出黄色闪光）
##     - 处决：把敌人顶到**失衡**后走近按左键 = 处决（全程无敌 + 成吨伤害）
##     - 受击/死亡：被打会硬直+击退+闪白；血空倒地死亡
##
## 【外观两种形态】
##   1) 外部模型（默认）：加载 assets/characters/player_knight/player_knight.glb，
##      自动测量模型高度缩放到 1.8m 并落到脚底 y=0。
##      该 GLB 是"带 21 根骨骼的绑定模型"，内含 19 段骨骼动画（按名字自动识别）：
##        Idle       2.000s 循环  站立呼吸（站住时播；膝盖微张合带动身体极轻微起伏）
##        Walk       1.00s  循环  行走（原地，位移由本脚本负责）
##        DodgeForward 0.417s 单次  闪避·前冲（低姿突进：压腿→蹬伸前压→前腿承重→回正）
##        DodgeBack    0.500s 单次  闪避·后撤（向后跳步：下沉→蹬伸→腾空收腿→落地→回正）
##        （RollLeap 0.417s 旧"前滚翻"，Shift 改为闪避后已不再引用，动画仍留在资源里）
##        Slash      0.50s  单次  连击①举剑过顶→前下劈（剑刃最快段即命中窗）
##        Slash2     0.417s 单次  连击②右手横斩：由右向左扫过身前（接在①后摇里）
##        Slash3     0.583s 单次  连击③转身回旋 + 举剑过顶下劈（收招最重、不可取消）
##        JumpStart  0.333s 单次  蹲身→蹬地→踮脚离地 —— ★ **2026-09-21 起跳动画已取消，本段不再播放**：
##                                 资产与识别都保留（把 jump_prep_time 调回 0.18 即可恢复两段式起跳）
##        JumpAir    0.50s  循环  空中收腿+展臂平衡（离地后循环播）
##        Block/Hold/Impact  格挡三段（起手 0.25s / 举剑待机循环 1.0s / 挡下顿挫 0.333s）
##        Execute    1.00s  单次  处决三段：举剑→前刺(命中)→上划→收招
##        Hurt       0.333s 单次  挨打一甩：2 帧内后仰到位，再缓回来
##        Death      0.542s 单次  前扑倒地（整体绕 root 转 -90° 扑倒，播完冻在末帧）
##      识别到的动画会在对应状态自动播放；缺失的动画仍由本脚本做"整体姿态"
##      （奔跑起伏/攻击前倾/受击后仰/死亡倒地）与受击闪光兜底。
##   2) 原语兜底：找不到模型时用胶囊/球/方块拼装的"小蓝人"，
##      支持更细的肢体动画（摆腿/挥剑），逻辑保持不变。
##
## 【状态机设计（核心）】
##   state 变量保存当前状态，_physics_process 里按状态算速度，
##   _process 里按状态摆姿势(动画)。状态切换都是"改 state + 归零计时"：
##
##     MOVE(移动/待机) ──攻击键──▶ ATTACK(挥剑)
##     MOVE            ──Shift───▶ DODGE(无敌闪避：有方向键=朝那个方向前闪 / 无方向=朝背后撤)
##     MOVE            ──跳跃键──▶ JUMP(滞空) ──落地──▶ MOVE
##     MOVE            ──右键按住─▶ BLOCK(格挡) ──松开右键──▶ MOVE
##     MOVE            ──攻击键(且面前有失衡的敌人)──▶ EXECUTE(处决)
##     MOVE            ◀──超时── ATTACK / DODGE / HURT / EXECUTE
##     ATTACK(第1/2段) ──取消点后再按攻击键──▶ ATTACK(下一段)  ← 三段连击
##     BLOCK           ──踩空──▶ JUMP(下落)
##     HURT(受击硬直)  ──被打死──▶ DEAD(倒地)
##
##   （旧的 JUMP_PREP「起跳蓄力段」仍在代码里、但默认**进不去**：起跳动画已取消，
##     `jump_prep_time = 0` 时按跳跃键直接进 JUMP；把它调回 0.18 就恢复"先蹲身蹬地再离地"。）
##
## 【ATTACK 内部的"三段连击"】ATTACK 不是"一种动作"，而是**同一条链上的第 1/2/3 段**：
##   进入 ATTACK 时记住"现在是第几段"(_combo_step)，每一段有自己的时长 / 命中窗 / 伤害，
##   以及一个**后摇取消点**(cancel)。玩家在后摇里再按一次左键就提前掐掉剩余收招、
##   直接接上下一段 —— 这就是"连击"；按不出来就演完整段回 MOVE 并进冷却。
##   · 输入缓冲：在取消点**之前**按的那一下不会被丢掉，会记进 _combo_buffer_time 秒的缓冲，
##     一到取消点立刻兑现 —— 玩家不必掐着帧去按（没有缓冲就没法"预输入"，手感很硬）。
##   · 第 3 段**不可取消**：它是整套连段的收尾重击，必须站着把长后摇演完 —— 这就是连击的代价。
##   · 三段各有专属动画(Slash / Slash2 / Slash3)，第 1 段与老版本完全一致（老断言不受影响）。
##
## 【DODGE(闪避) 是什么 / 为什么不是"翻滚"】
##   2026-09-20 起，Shift 由"翻滚(RollLeap 前滚翻)"改成"闪避"。
##   ★ 方向规则当天又改了一版：**按着任意方向键 + Shift = 前闪**（并且身体先转向那个方向、
##   再顺着它冲出去；锁定时也照转），**单按 Shift = 后闪**（朝背后跳开、不改朝向）。
##   【为什么要这一版】初版是"有 W 才前冲"，于是 A/S/D+Shift 一律判成后撤 ——
##   想往左边拉开必须先转镜头，闪避最核心的诉求（"我要去那边"）被规则吃掉了。
##   原因是手感 —— 被敌人挥击锁定时，玩家要的是"往后一撤"或"往前一钻"这种**方向明确、
##   起手快、位移短**的动作；前滚翻是"往任意方向滚"，读起来既不快也不指向明确。
##   闪避全程无敌帧，并且**在敌人挥击判定盒扫到你的那一瞬间仍处于闪避中 = 完美闪避**：
##   留一道虚影 + 触发子弹时间（见 _trigger_perfect_dodge）。判据与完美格挡同源 ——
##   都是"这一下本来打得中你，而你化解掉了"，区别只在化解方式（格挡 vs 闪避）。
##   ⚠ RollLeap 这段动画仍留在模型资源里（未删），只是不再有任何代码引用它。
##
## 【格挡状态的特殊之处】它是唯一"由输入按住与否决定存续"的状态：
##   不是靠 _state_time 超时结束，而是每帧检查 Input.is_action_pressed("block")。
##
## 【EXECUTE(处决) 是什么】完美格挡攒满敌人的失衡条后，敌人进入 BROKEN(失衡)，
##   此时走近 + 按左键 = 处决：锁住移动、全程无敌，打出一记"举剑→前刺→上划"的
##   大量伤害（**刻意留活口，不秒杀** —— 理由见 execute_damage 的注释）。
##   攻击键在"面前没有失衡敌人"时仍然是普通挥剑 —— 判定顺序见 _try_start_attack。
##
## 【输入读取方式】
##   攻击/翻滚/跳跃在 _physics_process 里用 Input.is_action_just_pressed 轮询，
##   而不是靠 _unhandled_input 事件回调 —— 轮询不依赖事件是否被 UI 吃掉，
##   更稳定。镜头鼠标环绕在 camera 脚本里用 _input 读取。
##
## 【节点结构】
##   Player(CharacterBody3D，本脚本)
##   ├─ CollisionShape3D   胶囊碰撞(决定"身体"占多大)
##   ├─ Health             通用血量组件(scripts/components/health.gd)
##   └─ VisualPivot(代码生成) 外观根节点：只转它=转身，碰撞体不受影响
##       ├─ KnightModel 或 原语各部件
##       └─ AttackHitbox 攻击命中盒(Area3D)
## ============================================================

## 信号：玩家死亡（主场景收到后显示死亡遮罩）
signal player_died

## 信号：发生了一次完美格挡（主场景收到后让 HUD 闪一下全屏金光）
signal perfect_parry

## 信号：发生了一次完美闪避（主场景收到后让 HUD 闪一下全屏青光 + 提示子弹时间）
signal perfect_dodge

## 状态枚举：一次只能处于一种状态（详见文件头状态机图）
## ⚠️ `JUMP_PREP`（起跳蓄力）默认**进不去**：起跳动画已取消、`jump_prep_time = 0`，
##    所以 `_try_start_jump()` 直接走 `_launch_jump()`。留着它是为了"调回 0.18 即可恢复"。
enum State { MOVE, DODGE, ATTACK, HURT, JUMP_PREP, JUMP, BLOCK, EXECUTE, DEAD }

## 连击总段数。第 3 段**不可取消**（它没有取消点）—— 这是连击的代价，见 combo3_* 声明处。
const COMBO_STEPS: int = 3

## 顿帧结束时的"弹回"过渡时长(真实秒)。极短，只为消掉硬跳变，别当成"慢慢恢复"。
const HITSTOP_RELEASE: float = 0.03

## 挥砍 / 命中音效的资源路径（由 tools/gen_sfx.py 程序化合成，见 assets/audio/sfx/README.md）。
## 【为什么用常量路径 + 运行时 load 而不是 preload】preload 在"文件还不存在"时会直接让
##   脚本编译失败 —— 音频是可缺的美术资产，缺了游戏也得能跑（_play_sfx 会静默跳过）。
const SFX_SWING_LIGHT := "res://assets/audio/sfx/swing_light.wav"
const SFX_SWING_HEAVY := "res://assets/audio/sfx/swing_heavy.wav"
const SFX_HIT := "res://assets/audio/sfx/hit_impact.wav"


# ------------------------------------------------------------------
# 手感参数（@export → 在编辑器选中 Player 节点即可实时调整试手感）
# ------------------------------------------------------------------

@export var move_speed: float = 6.2          # 走路/跑步最大速度(米/秒)
@export var accel: float = 22.0              # 加速度：越大起步/急停越快(更跟手)
@export var turn_speed: float = 14.0         # 转身速率：角色模型追移动方向的速度
## ── 闪避（Shift）──────────────────────────────────────────────
## 【为什么前冲/后撤各有自己的时长与速度】两者手感诉求相反：
##   前冲要"快、远、压上去"（0.375s / 14.7 m/s ≈ **4.0m**），后撤要"干脆、留出反应距离"
##   （0.458s / 9.0 m/s ≈ **3.0m**）。用同一组数值的话，要么前冲不够远、要么后撤太飘。
## 【选段规则见 `_try_start_dodge()`】有方向输入 = 前闪（**并转身朝那个方向**）；
##   单按 Shift = 后闪（朝背后、不改朝向）。
## 【时长 = 动画的"内容时长"】与既有约定一致（同 execute_time/hurt_time）：
##   单次动画的播放倍速一律现算 `length ÷ 时长`，让动画恰好铺满这段时间。
##   DodgeForward 的 length 是 0.417s（= 10/24），0.417/0.375 ≈ 1.111 倍速。
## ★★ **距离 = 速度 × 0.725 × 时长**，别只看 speed 的数字：
##   速度曲线是"起步满速 → 末段衰减到 45%"，时间均值 = (1.0 + 0.45) / 2 = **0.725**。
##   想挪 X 米就填 `X ÷ 时长 ÷ 0.725` —— 前冲 4m：4÷0.375÷0.725 ≈ **14.7**；后撤 3m：3÷0.458÷0.725 ≈ **9.0**。
##   （旧值 6.6 / 4.8 实际只能挪 1.8 / 1.6 m —— 用户试玩后反馈"闪避距离太小"，一算才发现是这里吃了暗亏）
@export var dodge_forward_time: float = 0.375  # 前冲持续时间(秒)，期间无敌。⚠️ 改它要同步换算上面那个速度
@export var dodge_back_time: float = 0.458     # 后撤持续时间(秒)，期间无敌。同上
@export var dodge_forward_speed: float = 14.0  # 前冲位移速度(米/秒) → 实测位移 **4.0 m**
@export var dodge_back_speed: float = 8.7      # 后撤位移速度(米/秒) → 实测位移 **3.0 m**
## （按上面公式算是 14.7 / 9.0，实测却多出 5% → 4.20 / 3.11 m。
##   差在第一帧：`_state_time` 还没推进时速度已被用到满值，且 resize；不必深究，按实测反推即可）
## ── 完美闪避（闪避无敌帧里被敌人挥击判定盒扫中）──────────────
## 【多快褪色】保持 0.25 真实秒后立刻开始回升 —— "瞥一眼"就够，不拖到"干等"。
##   倍率 0.45（不是更狠的 0.35）：太慢会让玩家把子弹时间当成"停下来喘气"，打断战斗连贯感。
@export var bullet_time_scale: float = 0.45    # 子弹时间：全局时间倍率(1.0=常速，越小越慢)
@export var bullet_time_duration: float = 0.25 # 减速保持多久（**真实秒**，不受减速本身影响）
@export var bullet_time_fade: float = 0.25     # 从减速平滑回到常速的过渡时长（真实秒）
@export var ghost_count: int = 3               # 完美闪避留下的虚影个数（沿闪避路径拖出的一道残影）
@export var ghost_life: float = 0.45           # 单个虚影淡出时长(秒)
@export var ghost_color: Color = Color(0.45, 0.85, 1.0)  # 虚影颜色：青蓝，与完美格挡的金色区分开
## 完美闪避那颗"青蓝亮球"的尺寸。
## 【为什么单独给三个参数、还比完美格挡小一号】格挡的黄光是在**空地上**炸的，
##   再亮也只是自己亮；闪避的亮球是**炸在角色身上**的，而同时还有三道叠加混合的虚影。
##   抓帧对比过：沿用格挡那套（半径 0.9 / 强度 7.0）会让触发瞬间整屏泛白、
##   虚影和本人都被吃掉 —— 玩家看到的是"一团光"而不是"我刚闪开了"。
##   收小到 0.55 / 3.2 之后同帧能一眼数出三道残影，闪光反而更像"擦身而过的火花"。
@export var dodge_flash_radius: float = 0.55     # 亮球半径(米)
@export var dodge_flash_time: float = 0.30       # 亮球存在时长(秒)
@export var dodge_flash_energy: float = 3.2      # 点光源强度（照亮周围地面的程度）
## ── 三段连击（左键）──────────────────────────────────────────
## 【一句话】左键点一下 = 第 1 段；在**第 1 段后摇里再点一下** = 提前掐掉收招接第 2 段；
##   第 2 段后摇里再点 = 第 3 段（收尾重击，不可取消）。三段的时长/判定窗/伤害/取消点各自独立。
## 【为什么第 1 段的参数**不并进数组**、而是继续留成 attack_* 四个标量】
##   它们是老版本的参数，自动化测试与调参注释都直接读 `player.attack_total` 这些名字；
##   把它们挪进数组=凭空制造一次"改参数就得改测试"的重构。第 1 段就沿用原名，
##   第 2/3 段另起 combo2_* / combo3_* —— 命名代价换来的是"老东西一行不动"。
@export var attack_damage: int = 25          # 第1段伤害（敌人100血→4刀）
@export var attack_cd: float = 0.42          # 普通攻击冷却：两段之间(未接续)的最小间隔
@export var attack_total: float = 0.5        # 第1段总时长(起手+挥砍+收招)
## 命中判定窗（判定帧期间攻击命中盒开启）。
## 【数值按动画实测】采样 Slash 动画里 hand.R/weapon.R 的角速度曲线：
##   举剑段 0~0.16s(≤90°/s) → 劈砍最快段 0.18~0.30s(峰值 496°/s @0.26s) → 收招段。
##   换算到游戏时间（动画 0.542s ÷ attack_total 0.5s ≈ 1.083 倍速）：
##   0.19s/1.083 ≈ 0.17、0.30s/1.083 ≈ 0.28。
## 所以取 0.17~0.28：只有"剑刃真正划过"时才判定，避免举剑阶段就打出伤害。
## 复现方式：godot --headless --path . --script res://tools/inspect_rig.gd -- <骑士glb> Slash
@export var attack_active_start: float = 0.17 # 第1段判定帧开始(游戏时间，秒)
@export var attack_active_end: float = 0.28   # 第1段判定帧结束(游戏时间，秒)
## 第1段的后摇取消点(秒)：走到这一刻起，缓冲里的那次左键立刻兑现 → 接第 2 段。
## 取值比判定窗结束(0.28)再晚一点点 → "打到就能接"，而不是"抬剑就能接"。
@export var combo_cancel_1: float = 0.30

## —— 第 2 段（Slash2 右手横斩）——
## 【判定窗怎么来的】同第 1 段的做法：采样 Slash2 里剑刃的角速度曲线，
##   取"超过峰值一半"的那段（0.042~0.375s，动画自身时间轴），峰值在 0.167s；
##   动画 length 0.458s ÷ 本段时长 0.417s ≈ 1.10 倍速 → 除以 1.10 换算成游戏时间：
##   0.038~0.341s、峰值 0.152s。再往里收一点（去掉起手与收尾的肉），取 **0.12~0.30**。
## 【为什么本段比第 1 段短(0.417 < 0.5)】连击的节奏要"越接越快"：第 1 段是完整的起手→劈→收，
##   第 2 段是"顺着力"甩出去的横斩，本来就该更短更干脆。三段 0.500 / 0.417 / 0.583 形成了
##   "长—短—长"的重音，第 3 段才显得是收尾。
@export var combo2_total: float = 0.417
@export var combo2_active_start: float = 0.12
@export var combo2_active_end: float = 0.30
@export var combo2_damage: int = 30
## 第2段的取消点(秒)：与判定窗末端对齐 —— 剑扫过之后马上就能接收尾。
@export var combo_cancel_2: float = 0.28

## —— 第 3 段（Slash3 转身回旋 + 过顶下劈）——
## 【判定窗】Blade 角速度 >峰值一半的段为 0.167~0.458s(动画时间轴)，峰值 0.25s；
##   length 0.625 ÷ 本段时长 0.583 ≈ 1.07 倍速 → 游戏时间 0.156~0.428、峰值 0.233。
##   取 **0.16~0.42**：这一段的判定窗刻意开得比前两段都宽 —— 它是转身横扫，剑刃在横向
##   停留时间长，收得太紧会"看着明明扫到了却不掉血"。
@export var combo3_total: float = 0.583
@export var combo3_active_start: float = 0.16
@export var combo3_active_end: float = 0.42
@export var combo3_damage: int = 40
## 【第 3 段没有 combo_cancel_3，这是刻意的】它是整套连段的收尾重击：
##   演完 0.583s 的长后摇才能动，就是"连击"的代价 —— 若也能取消，连击就变成
##   "只有收益没有风险"，玩家会无脑一直按。三个伤害 25/30/40 = 满连段 95（敌人100血
##   剩 5）→ 一次完整连击打不死任何敌人，最后仍要补一刀，与"处决重创＋补刀收人头"的
##   既有节奏一致（处决 75 之后也是留一刀的量）。
@export var combo_finish_cd: float = 0.62    # 第3段演完后的冷却(比普通攻击更长 = 收尾的"重量")
## 输入缓冲时长(秒)：在后摇取消点**之前**按的那一下左键不会丢，最多记住这么久，
## 到取消点立刻兑现。0.3s 的依据：连击链里"提前按"最多也就早 0.1~0.2s，
## 给到 0.3 足够宽容；再长会让"随手乱按"也被当成连击意图。
@export var combo_buffer_time: float = 0.30

## —— 命中反馈（顿帧 / 镜头震动 / 音效）——
## 【顿帧 hitstop】命中瞬间把**全局时间**压到几乎停住 hitstop_* 秒(真实秒)，
##   让"这一刀打实了"有物理上的重量感。第 3 段(收尾)给得更长更狠。
## 【和子弹时间的关系】两者都是"压慢全局时间"，但用途/时长/深度完全不同：
##   子弹时间是奖励玩家的表演时间，顿帧是打击感。它们**各写一个因子**（_bt_factor/_hs_factor），
##   最终 Engine.time_scale 取两者中更慢的那个 → 谁也不用抢谁，完美闪避里打命中也表现正常。
@export var hitstop_normal: float = 0.055    # 普通命中的顿帧时长(真实秒)
@export var hitstop_finisher: float = 0.11   # 第3段命中的顿帧时长(真实秒，更重)
@export var hitstop_scale: float = 0.05      # 顿帧期间的时间倍率(0.05 ≈ 几乎定格)
## 镜头震动：命中时抖一下，收尾重击抖得更猛。数值是"偏移振幅(米)"与"持续(秒)"。
@export var shake_normal: float = 0.035
@export var shake_finisher: float = 0.085
@export var shake_time: float = 0.16

@export var knockback_strength: float = 9.0  # 受击时的击退初速度

## —— 受击 / 倒地 ——
## 【为什么要单独给时长】Hurt / Death 动画的内容时长是 0.333s / 0.542s，
##   而"硬直多久""倒地演多久"是两条独立的手感参数，不该和动画长度绑死：
##   播放倍速按 **length ÷ 时长 现算**（同 Execute / Hurt 的做法）→
##   以后改动画帧数或改这个时长，两边都不会脱节。
@export var hurt_time: float = 0.32          # 受击硬直时长(秒)：被打后多久恢复行动
@export var death_time: float = 0.55         # 倒地演出时长(秒)：从挨打到躺平

## —— 格挡手感（鼠标右键按住）——
## 【机制】按住右键 = 举剑横挡：受击时只吃 (1 - block_damage_reduction) 的伤害，
##   并且**不硬直、不击退**（可以边挡边小碎步挪）。松开右键立刻收招。
## 【完美格挡】按下右键后的 perfect_parry_window 秒内挡下攻击 = 完美格挡：
##   0 伤害 + 把攻击者打进 block_parry_stagger 秒的长硬直（这就是玩家的反击窗口）。
##   一次按住只给一次完美判定，窗口过了之后继续按住就只是普通格挡。
## 【方向】只有来自"正面 block_guard_angle 度锥形内"的攻击才能被挡住；
##   背后/侧后挨打照样吃满伤害 —— 逼玩家把敌人放在视野里。
@export var block_damage_reduction: float = 0.7  # 普通格挡的减伤比例（0.7 = 只吃 30% 伤害）
## 按下后多少秒内挡下算"完美格挡"(秒)。
## 【取值沿革】0.15（初版，偏硬：得掐准敌人 0.5s 的蓄力帧）→ 0.22（放宽到"看到棒子
##   举起来就按右键"也能吃到）→ **0.45（当前值，再放宽到"看到敌人抬手就按"）**。
## 【为什么放这么宽界还不失衡】靠的是"**一次按住只给一次完美判定**"
##   （_perfect_parried，见 _resolve_block）：窗口内挡下即刻用掉这次机会，
##   之后继续按住就只是普通格挡。所以调宽窗口只是降低搓招门槛，
##   不会变成"按住右键无敌"——真正的代价是"这次没挡中就没有第二次"。
## 【调参】>0.6 会明显感觉"随便按都完美"，失衡条会失去挑战性；想回到硬核手感调回 0.22。
@export var perfect_parry_window: float = 0.45   # 按下后多少秒内挡下算"完美格挡"(秒)
@export var block_guard_angle: float = 120.0     # 正面格挡锥形的张角(度)
@export var block_move_scale: float = 0.3        # 格挡时的移动速度倍率（举着剑走不快）
@export var block_parry_stagger: float = 0.8     # 完美格挡让对方硬直的时长(秒)
@export var block_anim_speed: float = 1.0        # 格挡三段动画的播放倍速
@export var block_impact_hold: float = 0.22      # 挡下攻击后"顿挫动画"占用的时长(秒)

## —— 处决手感（走近失衡的敌人按左键）——
## 【机制】敌人失衡(BROKEN)期间，玩家在 execute_range 内按左键 = 处决：
##   锁住方向自动贴近 → 在 execute_hit_time 时刻打出 execute_damage 伤害 →
##   演完 execute_time 收招。全程无敌(health.invincible=true)，不会被杂兵打断。
##
## 【伤害量级：大量，但**刻意不致命**】
##   execute_damage 默认 75 → 满血(100)的普通守卫挨完还剩 25。
##   【为什么不做成秒杀】处决是"用 3 次完美格挡换来的高光"。若一击必杀，
##     玩家的最优解就退化成"格挡→秒杀→格挡→秒杀"，普通挥砍(25/刀)直接被架空；
##     而且处决强在"全程无敌"，能秒杀就等于无敌+秒杀，强度失控。
##   留 25 血 = **正好一刀 attack_damage 的量** → 处决负责"重创"、补刀负责"收人头"，
##     两段都有演出，也给了敌人一次"反扑"的窗口（它爬起来还能打你一下）。
##   差异化仍交给敌人自己的 execute_damage_scale（见 enemy.gd），精英/Boss 调低。
##   ⚠ 敌人扛住这一击后**必须收掉失衡**（否则玩家可以原地无限连处决），
##     见 enemy.gd::end_break_after_execution()。
@export var execute_damage: int = 75            # 处决伤害（满血守卫 100 → 剩 25，补一刀收尾）
@export var execute_range: float = 2.6           # 触发处决所需的水平距离(米)
## 整段处决动作时长(秒)。默认 1.0 = Execute 动画的内容时长 → 动画 1.0 倍速播放
## （不慢放也不加速，姿势最干净；改这个值动画会自动换算倍速去适配）。
@export var execute_time: float = 1.0
## 判定时刻(秒)：动作走到这时打出伤害。
## 【怎么算的】Execute 动画的"前刺命中"定在第 9 帧，相对进度 = (9-1)/25 = 0.32
##   （分母 25 = 总帧数，本工程 root 关键帧为 1..25）；再乘 execute_time → 0.32s。
##   改动画命中帧或改 execute_time 时，这个值要跟着重算（autotest 有断言盯着）。
@export var execute_hit_time: float = 0.32
@export var execute_approach_speed: float = 7.0  # 处决时自动贴近目标的移动速度(米/秒)
## 处决动画播放倍速：**0 = 自动**（按"动画时长 ÷ execute_time"换算，推荐）；
## >0 = 手动固定倍速（只在想手动微调演出快慢时才填）。
@export var execute_anim_speed: float = 0.0

## —— 跳跃手感（数值都在编辑器里可调）——
@export var jump_velocity: float = 7.4            # 起跳初速度(米/秒)；最高点 ≈ v²/(2g) ≈ 1.1m
@export var jump_cut_multiplier: float = 2.0      # 上升中松开跳跃键时的额外重力倍数 → 轻点=小跳
@export var fall_gravity_multiplier: float = 1.35 # 下落阶段的额外重力倍数 → 落地更干脆
@export var air_accel: float = 9.0                # 空中水平操控加速度(小于地面 accel → 跳跃有承诺感)
@export var coyote_time: float = 0.12             # 土狼时间：刚离开地面仍可起跳的宽限(秒)
@export var jump_buffer_time: float = 0.15        # 跳跃缓冲：落地前提前按跳跃也算数(秒)
@export var land_squash_time: float = 0.18        # 落地压缩(视觉)持续时间(秒)
## 起跳蓄力(预备)时长(秒)：按跳跃键后**先在地面**播完 JumpStart 的蹬地段，才真正离地。
##
## 【2026-09-21 起跳动画已取消 → 默认 0.0，按跳跃键**立刻**离地，全程只播滞空 JumpAir】
##   当初引入这段蓄力的理由，是 JumpStart 本身是"蹲身→蹬地→踮脚离地"的**地面**动作：
##   若一按就给向上速度，人已经飞到空中了还在播蹬地动画（动画与位移不同步）。
##   现在连**这段动画本身**都不要了，那层"动画与位移同步"的理由自然一起消失 ——
##   于是直接瞬间起跳，响应更干脆，也少了一段"按了没反应"的 0.18s。
##
## ★★ 这里**只把参数置 0，没有删掉 JUMP_PREP 那一整套机器**：
##   想找回两段式起跳，把这个数调回 0.18 就行 —— JumpStart 的动画、识别、以及
##   `State.JUMP_PREP` 的所有分支都完整保留，只是默认进不去。
##   所以这个 0 是**功能开关**，不是"没人用的残骸"：**改代码时别顺手把这个参数删掉**。
## 【取值】0 = 立即起跳（当前默认）；0.15~0.22 = 有重量感但起跳偏钝（原值 0.18）。
@export var jump_prep_time: float = 0.0

## —— 行走动画对齐 ——
## Walk 动画的"自然前进速度"(米/秒) = 一个周期的步幅 ÷ 周期时长。
## 本模型 Walk：0.5m × 2 步 ÷ 1.0s ≈ 1.0 m/s。
## 播放倍速 = 当前移动速度 ÷ 这个值（这样脚步与地面基本同步、不打滑）。
@export var walk_natural_speed: float = 1.0
## 行走动画的播放倍速上限。move_speed(6.2) 远高于自然步速(1.0)，
## 不设上限腿会快成"电风扇"；设上限的代价是跑动时仍有轻微滑步。
## 想彻底消除滑步，需要美术侧再出一段 Run（步幅更大的循环动画）。
@export var walk_max_speed_scale: float = 2.0

## —— 锁定敌人（鼠标中键点击切换：点一次锁定、再点一次解除）——
## 【锁定做了什么】① 身体始终面朝敌人（移动方向不再参与转身）→ A/S/D 变成"相对敌人的横移/后撤"；
##   ② 位移动画换成侧移三段 WalkStrafeLeft / WalkStrafeRight / WalkBack（不然身体朝向会和移动方向打架）；
##   ③ 镜头绕到玩家背后、正对敌人；④ 移动整体降速（更稳、更容易看清敌人起手）；
##   ⑤ 在**敌人身体中心**放一颗白色亮点（LockMarker），让玩家一眼看出"锁的是哪一只"。
@export var lock_on_range: float = 9.0        # 能锁到敌人的最大水平距离(米)
@export var lock_move_scale: float = 0.6      # 锁定时的移动速度倍率（整体降速）
@export var lock_turn_speed: float = 18.0     # 锁定时的转身速率：要比自由模式(14)快，敌人在绕后才能跟得住
## 侧移/后撤动画的自然速度(米/秒) —— 与 walk_natural_speed 同理，决定播放倍速。
## 侧移一个周期脚只横向挪 ~0.29m（比 Walk 的 0.52m 步幅小），用同一个 1.0 会让脚步偏快，
## 所以单独给一个可调值。
@export var strafe_natural_speed: float = 1.0
## 锁定标记（敌人身体中心的白点）半径(米)。
## 太小会在远处看不见（锁定时距离可达 9m），太大就变成一个盖住敌人的白球了。
@export var lock_marker_radius: float = 0.16
## 锁定标记的高度 = 敌人站高 × 这个比例。0.5 = 身体中心（对 2.66m 的壮汉正好是胸腹之间）。
@export var lock_marker_body_ratio: float = 0.5

# ------------------------------------------------------------------
# —— 近战朝向修正（攻击"软锁定"）——
# 【它解决什么问题】第三人称下，攻击朝向原本 = 移动输入方向（没有输入时 = 镜头方向）。
#   贴脸近战时玩家的手指在 WASD 上、视线在屏幕中央，很难每一刀都精确对准 ——
#   表现就是"明明站在怪面前，一刀砍在空气里"。所以攻击**起手的瞬间**把朝向
#   吸到附近敌人身上（只在近距离生效，远距离仍听玩家的）。
# 【和"锁定"的区别】锁定是玩家显式按中键、全程生效、还改镜头与位移动画；
#   近战修正是**自动的、只在攻击起手那一瞬生效、其余一切照旧**。
# ------------------------------------------------------------------

## 近战修正总开关（想体验"完全手动瞄准"的手感就关掉它）
@export var soft_lock_enabled: bool = true
## 搜索半径(米)：水平距离超过这个值的敌人**不参与**修正。
## 【为什么取 3.5】比攻击判定(约 1.9m)略大、明显小于锁定距离(9m)：
##   只在"已经贴身、理应打得着"的范围内帮玩家对焦，远了就不抢朝向。
@export var soft_lock_range: float = 3.5
## 相对"镜头正前方"的最大偏角(度)：偏得比这更远的敌人不抢朝向。
## 【为什么以镜头为准而不是只比距离】屏幕中心才是玩家"我在打谁"的意图。
##   只看距离的话，背后的怪会把每一刀都掰到身后去 —— 那是最难受的手感。
@export var soft_lock_angle: float = 70.0

## 重力加速度(米/秒²)。动作游戏常用比现实重力略大，手感更"沉"
const GRAVITY := 24.0

## ★ 调试开关：本角色是否接受玩家输入（角色切换器会把它置 false 来"夺走操控"）。
##   false 时角色只是**不读键盘鼠标**，物理、重力、状态机、动画全部照常 →
##   表现为原地站桩的陪练木桩。
## 【为什么不用 set_physics_process(false)】那样 move_and_slide 也停了：
##   角色会卡在空中不落地、状态计时冻结，看上去像"游戏崩了"，而不是"换成别人在操控"。
@export var control_enabled: bool = true


# ------------------------------------------------------------------
# 玩家模型（可选）。要换角色模型时，替换这里的路径即可
# 模型资产按类型分类存放：assets/characters/player_knight/
#   ├─ player_knight.glb   （模型+骨骼+9 段动画）
#   ├─ animations/         （从 GLB 抽出的独立动画 .tres，由 tools/split_player_animations.gd 生成）
#   └─ previews/           （各动画代表帧，仅供参考）
# 源文件（.blend）在 E:\blender\blenderproject\player_knight\，不在 Godot 项目内
# ------------------------------------------------------------------

## 玩家外观模型（.glb/.tscn 均可）。带骨骼动画的模型会自动识别并播放其中的动作。
const PLAYER_MODEL := preload("res://assets/characters/player_knight/player_knight.glb")
## 模型应缩放到的"站高"(米)。碰撞胶囊高 1.8，默认让模型与之匹配
const MODEL_TARGET_HEIGHT := 1.8

## 武器资产：与角色**分离**存放 —— 换武器只换这个文件，角色与全部动画都不用动。
## 资产约定（本资产实测）：原点 = 握把中心；刀身沿局部 **-Z**（护手 z≈±0.14、刀身 z -0.145~-1.0）
const PLAYER_WEAPON := preload("res://assets/weapons/sword_01/sword_01.glb")
## 武器挂点骨骼名（角色模型里的空骨骼）。换手/背挂只需改这里，或再建挂点骨骼。
const WEAPON_SOCKET := "weapon.R"
## 挂点对齐变换（相对挂点骨骼）：让**握柄停在骨骼原点(拳心)、刀身沿骨骼 +Y 朝向身前**。
## 【为什么沿 +Y】挂点骨骼 weapon.R 的静止基实测为：
##   +Y ≈ 模型前方(-Z)、+Z ≈ 模型上方、+X ≈ 模型右侧 —— 骨骼本身就是"沿 +Y 指向前方"的持械轴。
##   而武器刀身沿自身 -Z，所以绕骨骼 X 轴 +90°（-Z → +Y）即可把刀身扳到身前。
## 【为什么不沿用旧位置】武器分离前旧模型里剑是**竖直朝上**贴在手臂外侧的，
##   照抄那个位置会让刀身陷在手臂网格里（实测剑与手臂包围盒重叠），视觉上像"嵌在手臂中"。
##   朝前握持才是正常姿态。
## 【怎么验证】tools/check_weapon.tscn 会打印"握柄到拳心距离"和"刀身指向与模型前方的夹角"；
##   自动测试也有对应断言（握柄≈拳心、刀身朝前、挥砍时跟随手臂）。
const WEAPON_ALIGN_LOCAL := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)

## 是否正在使用外部模型（true=用模型；false=用原语小蓝人兜底）
var _use_model: bool = false
## 模型自带的动画播放器（GLB 内嵌动画时存在；静态模型则为 null）
var _anim_player: AnimationPlayer = null
## 识别到的两段闪避动画名（按名字含 dodgeforward / dodgeback 自动识别；
## 空字符串 = 该段缺失，走脚本整体姿态兜底）
var _dodge_fwd_anim: String = ""      # DodgeForward：前冲（压上、低姿突进）
var _dodge_back_anim: String = ""     # DodgeBack：后撤（向后跳步拉开）
## 本次闪避实际播放的那一段（进入 DODGE 时按方向选定，供 _end_dodge / _animate_model 读）
var _dodge_anim: String = ""
## 本次闪避的播放倍速：让动画恰好铺满 _dodge_time 秒，与位移/无敌帧同步
var _dodge_anim_speed: float = 1.0
## 本次闪避是否朝前（true=前冲 / false=后撤）。位移方向、动画、时长三样都由它决定。
var _dodge_is_forward: bool = false
## 其余识别到的骨骼动画名（空字符串 = 该动作没有动画资源，走脚本姿态兜底）
var _walk_anim: String = ""
# 锁定模式专用的三段位移（身体保持朝前、脚步往侧/往后走）
var _strafe_left_anim: String = ""    # WalkStrafeLeft：向左侧移（循环）
var _strafe_right_anim: String = ""   # WalkStrafeRight：向右侧移（循环）
var _walk_back_anim: String = ""      # WalkBack：后撤（循环）
var _slash_anim: String = ""           # Slash：连击①举剑过顶→前下劈
var _slash2_anim: String = ""          # Slash2：连击②右手横斩（由右向左扫）
var _slash3_anim: String = ""          # Slash3：连击③转身回旋+过顶下劈（收尾）
var _jump_start_anim: String = ""
var _jump_air_anim: String = ""
## 格挡三段动画（空字符串 = 该段缺失，走脚本姿态兜底）
var _block_anim: String = ""          # Block：从站姿举剑进入防护架势（单次）
var _block_hold_anim: String = ""     # BlockHold：举着剑待机（循环）
var _block_impact_anim: String = ""   # BlockImpact：挡下攻击的顿挫（单次）
## 处决专用动画（空字符串 = 该段缺失，退回"慢放挥砍"或脚本姿态兜底）
var _execute_anim: String = ""        # Execute：举剑→前刺→上划→收招（单次）
## 生活三段动画（空字符串 = 该段缺失，退回脚本整体姿态兜底）
var _idle_anim: String = ""           # Idle：呼吸待机（循环，站住时播）
var _hurt_anim: String = ""           # Hurt：挨打一甩（单次）
var _death_anim: String = ""          # Death：前扑倒地（单次，播完冻在末帧）
## 武器挂点（BoneAttachment3D，挂在模型的 weapon.R 骨骼上）
var _weapon_socket: BoneAttachment3D = null
## 当前装备的武器节点（徒手时为 null）
var _weapon: Node3D = null
## 武器相对挂点的对齐偏移（= WEAPON_ALIGN_LOCAL，设在武器子节点上，见 _attach_weapon）
var _weapon_align_local: Transform3D = Transform3D.IDENTITY
## 模型的骨骼节点：用于"没有动画时"把骨骼复位成绑定姿势（见 _anim_to_rest）。
## 为什么需要：骨骼动画一停播，骨骼会冻在停播那一帧的姿势上。
var _skeleton: Skeleton3D = null


# ------------------------------------------------------------------
# 运行时状态变量
# ------------------------------------------------------------------

var state: State = State.MOVE      # 当前状态（见 State 枚举）
var _state_time: float = 0.0       # 当前状态已持续的时间(秒)，用于判定"该切换到下一个状态了"
var _attack_cooldown: float = 0.0  # 攻击冷却倒计时(秒)，>0 时不能攻击
## 当前在第几段连击（0=第1段 Slash / 1=第2段 Slash2 / 2=第3段 Slash3）。
## 只在 state == ATTACK 时有意义；每次 _start_combo_step() 显式写入。
var _combo_step: int = 0
## 输入缓冲：后摇取消点**之前**按下的那次左键是否还记着（到取消点就兑现成下一段）。
var _combo_queued: bool = false
## 上述缓冲的剩余寿命(秒)。归零后即使还没到取消点也不再兑现 —— 防止"很久以前乱按的一下"
## 在零点几秒后突然替我接了一段（玩家会完全无法理解这一刀从哪来的）。
var _combo_buffer_time: float = 0.0
var _iframes: float = 0.0          # 受击后的短暂无敌倒计时(秒)，>0 时伤害无效
var _dead: bool = false            # 是否已死亡（死亡后忽略一切输入/伤害）
var _perfect_parried: bool = false # 本次格挡是否已用掉"完美"判定（一次按住只给一次）
## 本次闪避是否还留着"完美闪避"判定（一次闪避只给一次，同 _perfect_parried 的道理：
## 否则在敌人判定盒里连挨两下会连着触发两次慢动作，画面会花）
var _perfect_dodge_armed: bool = false
## 子弹时间的补间（用 set_ignore_time_scale 让它**不受自己造成的减速影响**）
var _bullet_time_tween: Tween = null
## 子弹时间对"全局时间倍率"的贡献值（1.0 = 不减速）。由补间直接驱动，
## 最终 Engine.time_scale = min(_bt_factor, _hs_factor)（见 _push_time_scale）。
var _bt_factor: float = 1.0
## 顿帧(hitstop)对全局时间倍率的贡献值（1.0 = 不减速）。同上，由补间驱动。
var _hs_factor: float = 1.0
## 顿帧的补间（同样 set_ignore_time_scale —— 否则"顿帧自己的计时"会被自己压慢，
## 0.055s 的顿帧会实际持续 0.055/0.05 = 1.1s，整个节奏就毁了）
var _hitstop_tween: Tween = null
## 本次闪避的持续时间(秒)：进入 DODGE 时按前冲/后撤选定，速度/收招都读它
var _dodge_time: float = 0.375
var _block_impact_time: float = 0.0 # 挡下顿挫的剩余时长(秒)，>0 时正在演 BlockImpact
var _execute_target: Node3D = null  # 处决目标（进入 EXECUTE 时锁定；失效则提前收招）
var _execute_hit_done: bool = false # 本次处决是否已经打出伤害（防重复结算）
var _lock_on: bool = false          # 锁定开关（切换型：点一次 true、再点一次 false；与 _lock_target 同步维护）
var _lock_target: Node3D = null     # 锁定中的敌人（点一次中键开启、再点一次关闭；null = 未锁定）
var _lock_marker: LockMarker = null # 锁定标记（敌人身体中心的白点）；未锁定时为 null


# ------------------------------------------------------------------
# 外观引用
# ------------------------------------------------------------------

var _pivot: Node3D                 # VisualPivot：外观根节点，旋转=转身
## —— 仅"原语小蓝人"模式用 ——
var _shoulder_r: Node3D            # 右肩节点（剑挂在它下面，挥剑=转它）
var _shoulder_l: Node3D            # 左肩节点
var _leg_r: Node3D                 # 右腿节点（走路时摆腿）
var _leg_l: Node3D                 # 左腿节点
## —— 通用 ——
var _hitbox: Area3D                # 攻击命中盒（面前的长方体感应区）
var _hit_targets: Array = []       # 本刀已经打中的敌人（防止一刀多次伤害）
var _mats: Array[StandardMaterial3D] = []  # 外观材质（受击闪白要批量改它们）
## —— 音效（缺资源时为 null，_play_sfx 会静默跳过）——
var _sfx_swing: AudioStreamPlayer3D = null   # 挥剑破空声：每一段起手播一次
var _sfx_hit: AudioStreamPlayer3D = null     # 命中声：真打到敌人才播
var _stream_swing_light: AudioStream = null  # 轻挥（第 1/2 段）
var _stream_swing_heavy: AudioStream = null  # 重挥（第 3 段收尾）
var _stream_hit: AudioStream = null          # 命中


# ------------------------------------------------------------------
# 运动缓冲变量
# ------------------------------------------------------------------

var _wish_dir: Vector3 = Vector3.ZERO  # 本帧"想要的移动方向"(由输入+镜头换算)
var _facing_dir: Vector3 = Vector3.FORWARD  # 朝攻击方向（默认朝 -Z）
var _dodge_dir: Vector3 = Vector3.ZERO  # 闪避的位移方向（进入 DODGE 时按前/后锁定）
var _bob_phase: float = 0.0            # 跑步摆腿/起伏的相位(累加时间产生循环)
var _hurt_from: Vector3 = Vector3.ZERO # 受击来源位置（决定击退方向）
var _coyote: float = 0.0               # 土狼时间剩余(秒)：离地后仍允许起跳的宽限
var _jump_buffer: float = 0.0          # 跳跃缓冲剩余(秒)：落地前提前按也算数
var _squash: float = 0.0               # 落地压缩计时(秒，纯视觉)

## Health 组件的引用（场景里的子节点，onready=子节点就绪后自动取）
@onready var health: Health = $Health


# ------------------------------------------------------------------
# 引擎回调
# ------------------------------------------------------------------

## 进入场景：注册组、拼装外观、接通命中盒信号、监听血量归零。
func _ready() -> void:
	add_to_group("player")         # 让敌人AI/镜头/主场景能按组找到玩家
	# ★ 兜底把全局时间倍率复位：Engine.time_scale 是全局单例，若上一次运行/上一个场景
	#   是在子弹时间里退出的（比如直接关窗），它会把 0.35 带去下一次运行 —— 症状极隐蔽
	#   （整个游戏慢动作、但没有任何报错）。这里每次进场景都强制拉回常速。
	Engine.time_scale = 1.0
	_build_body()                  # 优先用骑士模型，失败则回退原语小蓝人
	_setup_audio()                 # 挂挥剑/命中两个 3D 音效播放器（缺资源时静默跳过）
	_connect_hitbox_signals()      # 命中盒的"有东西进入"信号接好
	health.died.connect(_on_health_died)


## 供外部(AI/主场景)查询：还活着吗？
func is_alive() -> bool:
	return not _dead


## 物理帧主循环：推进计时 → 轮询攻击/翻滚/跳跃键 → 更新方向/速度 → 移动 → 检查状态切换
func _physics_process(delta: float) -> void:
	_state_time += delta                           # 状态计时
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_iframes = maxf(0.0, _iframes - delta)         # 无敌倒计时递减
	_coyote = maxf(0.0, _coyote - delta)           # 土狼时间递减
	_jump_buffer = maxf(0.0, _jump_buffer - delta) # 跳跃缓冲递减
	_squash = maxf(0.0, _squash - delta)           # 落地压缩递减
	_block_impact_time = maxf(0.0, _block_impact_time - delta)  # 格挡顿挫递减
	# 连击输入缓冲递减：寿命走到 0 就连"记着有个待兑现的左键"这个标记一起撤掉。
	# ★ 必须在这一步撤标记（而不是只在读取处比较 >0），否则 _combo_queued 会长期停在 true，
	#   下次进 ATTACK 时（_start_combo_step 会重置它，倒不至于出错）语义上已经骗人了。
	if _combo_buffer_time > 0.0:
		_combo_buffer_time = maxf(0.0, _combo_buffer_time - delta)
		if _combo_buffer_time <= 0.0:
			_combo_queued = false
	if is_on_floor():
		_coyote = coyote_time                      # 站在地面上就刷新土狼时间
	# ★ 攻击/闪避/跳跃都用"轮询"读取：不依赖事件是否被 UI 吞掉，稳定可靠
	if control_enabled:
		if Input.is_action_just_pressed("attack"):
			_try_start_attack()
		if Input.is_action_just_pressed("dodge"):
			_try_start_dodge()
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = jump_buffer_time        # 先记进缓冲，落地瞬间会自动补跳
		if _jump_buffer > 0.0:
			_try_start_jump()                      # 不满足条件时(如已在空中)会被函数自己拒绝
		# ★ 格挡是"按住"型输入：这里只管起手，松开由 _update_state 的 BLOCK 分支负责收招
		if Input.is_action_just_pressed("block"):
			_try_start_block()
		# ★ 锁定状态必须在"算移动意图 / 算速度 / 切状态"之前更新：
		#   后面三步全都要读它（选哪段位移动画、速度乘多少、面朝谁）。
		_update_lock_on()
		_update_wish_dir()                         # 读输入算出移动意图
	else:
		# 操控被夺走：清掉"待处理输入"与"正在按住"的状态，别让它变成暗开关。
		#   · BLOCK 是靠 `按住右键` 维持的（见 _update_state），没人按了就必须手动收招，
		#     否则这个角色会永远举着剑站下去；
		#   · 锁定是中键"切换型"的，同理要显式解除，否则锁定白点会一直挂在敌人身上。
		_jump_buffer = 0.0
		_wish_dir = Vector3.ZERO
		if state == State.BLOCK:
			_end_block()
		if _lock_on:
			_lock_on = false
			_lock_target = null
		_sync_lock_marker()
	_update_velocity(delta)                        # 按状态给 velocity 赋值
	move_and_slide()                               # 让引擎真正移动+碰撞+落地
	_update_state(delta)                           # 状态超时→切换


# ------------------------------------------------------------------
# 输入 → 移动意图 / 状态启动
# ------------------------------------------------------------------

## 把 WASD + 镜头朝向换算成世界系移动方向(_wish_dir)。
## 实现：镜头"前进方向"和"右方向"做基向量，W=前进、D=右移，
##       组合后若长度>1(斜向)则归一化，保证斜走不比直走快。
func _update_wish_dir() -> void:
	if _dead or state == State.DEAD:
		_wish_dir = Vector3.ZERO
		return
	if state == State.DODGE or state == State.EXECUTE:  # 闪避/处决期间不接受方向输入(方向已锁定)
		return
	var fwd_in := Input.get_axis("move_back", "move_forward")  # W→+1, S→-1
	var side_in := Input.get_axis("move_left", "move_right")   # D→+1, A→-1
	var cam := _get_camera()
	var f := Vector3.ZERO
	var r := Vector3.RIGHT
	if cam != null:
		f = -cam.global_basis.z      # 镜头局部 -Z = 它看向的方向
		r = cam.global_basis.x       # 镜头局部 X = 它的右边
	f.y = 0.0                        # 只看水平分量(角色不会飞)
	r.y = 0.0
	f = f.normalized()
	r = r.normalized()
	_wish_dir = (f * fwd_in + r * side_in)
	if _wish_dir.length() > 1.0:
		_wish_dir = _wish_dir.normalized()


## 尝试开始攻击（只有站立/移动状态且冷却结束才允许）。
## 一进入就把命中盒关闭；真正能打人的时刻由 _animate_model 按时间窗开启。
## ★ 攻击键有双重语义：
##   ① **面前站着失衡(BROKEN)的敌人** → 这一次按下变成处决；
##   ② **自己正在 ATTACK** → 这一次按下是"连击意图"，记进输入缓冲（见 _queue_combo）。
func _try_start_attack() -> void:
	if _dead:
		return
	# ② 连击中再按 —— 不在这里真的接段，只"记下来"：
	#   什么时候兑现由 _update_state 的 ATTACK 分支按"后摇取消点"决定。
	#   【为什么不在按键当下就接】那样等于"一按就断招"，取消点形同虚设：
	#   连击的节奏感恰恰来自"挥到位了再按下一刀"。
	if state == State.ATTACK:
		_queue_combo()
		return
	if state != State.MOVE:
		return
	# 【为什么把处决判定放在最前面】处决与普通攻击共用左键：
	#   玩家不用为处决额外记一个键，且失衡窗口只有几秒，优先响应处决更符合直觉。
	#   注意处决不受攻击冷却限制 —— 否则"刚挥完一刀就能处决"会莫名被卡住。
	var victim := _find_execute_target()
	if victim != null:
		_try_start_execute(victim)
		return
	if _attack_cooldown > 0.0:
		return
	_start_combo_step(0)             # 从第 1 段起手


## 起手/接续第 idx 段连击：切状态、清已命中记录、软锁定转向、播对应动画。
## 【为什么把"第 1 段"和"接续段"走同一个函数】两边的操作除动画名外**完全一样**
##   （归零计时、清 _hit_targets、重新吸附朝向）—— 分开写迟早会漂移成两套行为。
## @param idx 0/1/2（越界会被夹到合法范围）
func _start_combo_step(idx: int) -> void:
	_combo_step = clampi(idx, 0, COMBO_STEPS - 1)
	_combo_queued = false            # 缓冲已兑现（或全新起手）→ 清掉，别让它连着接两段
	_combo_buffer_time = 0.0
	state = State.ATTACK
	_state_time = 0.0
	_hit_targets.clear()             # 新的一刀，清空"已命中"记录（所以连击能对同一个敌人三段都生效）
	# 朝哪打：见 _aim_direction 的优先级说明（锁定目标 > 附近敌人 > 移动输入 > 镜头方向）
	# ★ 每一段都重新吸附一次：敌人被前一段打退了，第 2/3 段要跟着转向，
	#   否则会出现"对着空气连挥三刀"（软锁定的意义就在这）。
	var aim := _aim_direction()
	if aim.length() > 0.1:
		_face_instant(aim)           # 瞬间转身(攻击要跟手，不能慢慢转)
		_facing_dir = aim
	_set_hitbox_active(false)
	_play_combo_anim(_combo_step)
	# 破空声：每一段起手都来一发（第 3 段用更沉的重挥音，听感上就把"收尾"讲清楚了）
	_play_sfx(_sfx_swing, _stream_swing_heavy if _combo_step >= COMBO_STEPS - 1 else _stream_swing_light)


## 播放第 idx 段的挥砍动画。倍速按"动画时长 ÷ 该段时长"现算，让收招与状态切换对齐。
## ★ 缺段兜底：没有 Slash2/Slash3 资产时退回第 1 段的 Slash ——
##   宁可三段打起来一模一样，也不要"第 2 段直接没动作"。
func _play_combo_anim(idx: int) -> void:
	if _anim_player == null:
		return
	var anim_name := _combo_anim(idx)
	if anim_name == "":
		return
	var a := _anim_player.get_animation(anim_name)
	var spd := 1.0
	if a != null and a.length > 0.01:
		spd = a.length / maxf(0.05, _combo_total(idx))
	_anim_player.speed_scale = 1.0
	_anim_player.stop()
	_anim_player.play(anim_name, -1.0, spd)


## 第 idx 段该播哪段动画（1→Slash2、2→Slash3，缺失则退回 Slash）。
func _combo_anim(idx: int) -> String:
	match idx:
		1:
			return _slash2_anim if _slash2_anim != "" else _slash_anim
		2:
			return _slash3_anim if _slash3_anim != "" else _slash_anim
		_:
			return _slash_anim


## 记下"玩家想接下一段"这个意图（输入缓冲）。
## 【为什么第 3 段直接忽略】它是不可取消的收尾重击（没有取消点），
##   记下来也永远不会被兑现；不记反而更诚实 —— 也让自动测试能断言"第3段按了没用"。
func _queue_combo() -> void:
	if _combo_step >= COMBO_STEPS - 1:
		return
	_combo_queued = true
	_combo_buffer_time = combo_buffer_time


# ------------------------------------------------------------------
# 连击参数速查（三段各一套：时长 / 判定窗 / 取消点 / 伤害）
# ------------------------------------------------------------------

## 对外查询：当前连击段号（0 起算；非 ATTACK 时返回上一次的段号，仅供调试/测试观察）。
func get_combo_step() -> int:
	return _combo_step


## 对外查询：当前是否正在挥砍（自动测试/敌人AI 判断"这人攻击中"用）。
func is_attacking() -> bool:
	return state == State.ATTACK


## 对外查询：第 idx 段的输入缓冲是否还记着待兑现的左键。
func is_combo_queued() -> bool:
	return _combo_queued


## 第 idx 段的整段时长(秒)。
func _combo_total(idx: int) -> float:
	match idx:
		1: return combo2_total
		2: return combo3_total
		_: return attack_total


## 第 idx 段的命中判定窗起点(秒)。
func _combo_active_start(idx: int) -> float:
	match idx:
		1: return combo2_active_start
		2: return combo3_active_start
		_: return attack_active_start


## 第 idx 段的命中判定窗终点(秒)。
func _combo_active_end(idx: int) -> float:
	match idx:
		1: return combo2_active_end
		2: return combo3_active_end
		_: return attack_active_end


## 第 idx 段的后摇取消点(秒)。**返回 0 = 该段不可取消**（第 3 段，见 combo3_* 说明）。
func _combo_cancel_at(idx: int) -> float:
	match idx:
		0: return combo_cancel_1
		1: return combo_cancel_2
		_: return 0.0


## 第 idx 段的伤害。
func _combo_damage(idx: int) -> int:
	match idx:
		1: return combo2_damage
		2: return combo3_damage
		_: return attack_damage


## ★ 攻击起手时"该朝哪打"（近战修正的落点）。
##
## 【优先级】锁定目标 > 附近的敌人(软锁定) > 移动输入方向 > 镜头正前方。
##   ① 锁定目标是玩家**显式**按中键指定的，任何自动修正都不能盖掉它；
##   ② 软锁定代表"我贴脸站着一个人"，比"我手指正按着 W"更能代表这一刀的意图 ——
##      这也是本次修正要解决的核心问题（边后退边砍却砍空的挫败感）；
##   ③ 都没有才退回老规则：有移动输入朝移动方向，站桩时朝屏幕中心。
func _aim_direction() -> Vector3:
	var locked := get_lock_target()
	if is_instance_valid(locked):
		var to_locked := locked.global_position - global_position
		to_locked.y = 0.0
		if to_locked.length() > 0.05:
			return to_locked.normalized()
	var soft := _find_soft_lock_dir()
	if soft.length() > 0.1:
		return soft
	if _wish_dir.length() > 0.1:
		return _wish_dir
	return _get_camera_forward()


## 找"近战修正"要吸附的敌人：镜头前方锥形内、**水平距离最近的**活敌人。
## @return 指向它的水平单位向量；没有合适的目标时返回零向量（调用方据此走回退逻辑）。
##
## 【为什么锥内取"最近"而不是"最对准准星"】用户要的是"**附近有**敌人时自动朝向它"：
##   贴身那只才是这一刀真正该打的。若按角度取，会出现"贴脸的怪偏 20°、远处 3m 的怪正对准星，
##   结果一刀甩向远处"的荒谬感 —— 那正是软锁定要消灭的手感。
## 【为什么只看水平距离/夹角】角色不会飞，高度差(比如敌人站在坡上)不该把修正弄失灵。
func _find_soft_lock_dir() -> Vector3:
	if not soft_lock_enabled:
		return Vector3.ZERO
	var cam_fwd := _get_camera_forward()
	var body_fwd := _get_facing_flat()
	var cos_limit := cos(deg_to_rad(soft_lock_angle))
	var best: Node3D = null
	var best_dist := soft_lock_range
	for e in get_tree().get_nodes_in_group("enemy"):
		var enemy := e as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		var to_e := enemy.global_position - global_position
		to_e.y = 0.0
		var dist := to_e.length()
		if dist > best_dist or dist < 0.05:      # 太远 / 几乎重合(方向无意义) → 跳过
			continue
		# ★ 锥形取"镜头前方 ∪ 身体前方"的并集：敌人在**任一个**朝向的锥形内即算 nearby。
		#   【为什么是并集、不是只看镜头】旧逻辑只认镜头前方，导致"我正脸对着敌人、
		#   但镜头刚被甩到别处/在侧翼"时软锁定落空、这一刀朝镜头空挥 —— 正是用户反馈的 bug。
		#   身体朝向(=_get_facing_flat)代表玩家此刻真正面朝谁，比镜头更贴出招意图，并入判定。
		#   【为什么不干脆去掉锥形】纯距离最近会把"背后贴脸的怪"也吸过来，违背
		#   3b 边界2"背后敌人不抢朝向"；并集在"朝镜头/朝身体"两种明确意图下都生效，
		#   背后(两朝向都够不到)依然不吸，手感最稳。
		var dir_e := to_e.normalized()
		if dir_e.dot(cam_fwd) < cos_limit and dir_e.dot(body_fwd) < cos_limit:
			continue
		best_dist = dist
		best = enemy
	if best == null:
		return Vector3.ZERO
	var to_best := best.global_position - global_position
	to_best.y = 0.0
	return to_best.normalized()


## 找"当前可以处决的敌人"：最近的、处于失衡(BROKEN)状态、且在 execute_range 内的敌人。
## 没找到返回 null。
## 【为什么按距离取最近】同时有两三只怪被弹失衡时，玩家想打的显然是脚下这只，
##   而不是隔了半个场地的那只。距离最近 = 最符合意图。
func _find_execute_target() -> Node3D:
	var best: Node3D = null
	var best_dist := execute_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("is_broken"):
			continue
		var enemy := e as Node3D
		if not e.is_broken():                 # 没失衡 → 不是处决目标
			continue
		var d := Vector2(enemy.global_position.x - global_position.x,
			enemy.global_position.z - global_position.z).length()
		if d <= best_dist:
			best_dist = d
			best = enemy
	return best


# ------------------------------------------------------------------
# 锁定敌人（鼠标中键点击切换）
# ------------------------------------------------------------------

## 对外查询：当前是否处于锁定状态（镜头/自动测试都要用）。
func is_locked_on() -> bool:
	# ⚠ 必须先 is_instance_valid 再往下传：目标可能是**已被释放**的节点，
	#   而把"已释放的对象"传进带 Node3D 类型标注的参数会直接抛类型错误
	#   （不是返回 false）—— 自动测试里销毁木桩那一节就是踩这个。
	return is_instance_valid(_lock_target) and _lock_target_valid(_lock_target)


## 对外查询：锁定目标的节点（未锁定返回 null）。镜头用它算"绕到背后"的角度。
func get_lock_target() -> Node3D:
	return _lock_target if is_locked_on() else null


## 目标是否还值得锁定：活着（不是尸体）。
## ⚠ 调用前请先用 is_instance_valid() 过滤（见 is_locked_on 的注释）。
func _lock_target_valid(t: Node3D) -> bool:
	if t.has_method("is_alive") and not t.is_alive():
		return false
	return true


## 找"最该锁定的敌人"：lock_on_range 内、活着、水平距离最近的。
## 与 _find_execute_target() 的区别：**不要求失衡** —— 锁定是常态操作，
## 失衡只是"恰好可以处决"的特例（处决目标同样被本函数覆盖）。
func _find_lock_target() -> Node3D:
	var best: Node3D = null
	var best_dist := lock_on_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		var enemy := e as Node3D
		if not is_instance_valid(enemy) or not _lock_target_valid(enemy):
			continue
		var d := Vector2(enemy.global_position.x - global_position.x,
			enemy.global_position.z - global_position.z).length()
		if d <= best_dist:
			best_dist = d
			best = enemy
	return best


## 每帧维护锁定状态（在 _physics_process 里推进）。
## 【为什么用手动"切换"而不是"按住"】按住型输入会把玩家的手指一直钉在中键上：长时间按着既累，
##   又没法腾出手做别的。改成"点一次开 / 再点一次关"后，玩家只在中键上花一瞬，其余时间手是自由的。
## 【那玩家怎么知道"我到底锁没锁"】不靠手指记忆，靠**敌人身体中心那颗白色亮点**（LockMarker）做
##   可视化：锁定期间它一直在、解除立刻收掉，所见即所得。所以"按住=状态与手指一一对应，不会有暗开关"
##   那条老理由不再成立 —— 用户要的就是"不必一直按着"。
## 【为什么不会重复触发】开启是**边沿事件**，只读 is_action_just_pressed（只在"按下"那一瞬返回 true），
##   一次点击只翻转一次。关键在于：**"松开"这一步在切换语义里没有任何含义**，绝对不能再去读它
##   （否则一次"按下+松开"会被当成开、关两次，等于白点）。这正是本次改造最要防的残留。
## 【目标失效怎么办】锁定期间目标死了/被销毁就**当场重找一只**：玩家锁定的意图是
##   "我要一直盯着打"，而不是"锁这一只直到它死"。找不到任何有效目标就退化为未锁定。
func _update_lock_on() -> void:
	if _dead or state == State.DEAD:
		_lock_on = false             # 死亡 = 强制解除（保留既有行为）
		_lock_target = null
	elif Input.is_action_just_pressed("lock_on"):
		# 边沿触发：只在"点击"那一帧翻转开关（读法与 attack/dodge/jump/block 一致，都在 _physics_process 轮询）
		_lock_on = not _lock_on
		if _lock_on:
			_lock_target = _find_lock_target()
			if _lock_target == null:
				_lock_on = false     # 范围内没有可锁定的敌人 → 不进"已锁定但没目标"的假状态，保持未锁定
		else:
			_lock_target = null      # 已锁定 → 再点一次 = 解除
	# 维持阶段（每帧都要跑）：已开启锁定、但目标死了/被销毁 → 当场重找一只；找不到就退化为未锁定。
	# ⚠ 必须用 _lock_on 跟着判断：若只看 _lock_target 是否为 null，未锁定时（null）也会被当成"目标失效"而
	#   每帧重找 → 变成"不点也自动锁定"。_lock_on 就是"玩家到底开没开锁定"的那一位记忆（切换型必须显式记）。
	if _lock_on and (not is_instance_valid(_lock_target) or not _lock_target_valid(_lock_target)):
		_lock_target = _find_lock_target()
		if _lock_target == null:
			_lock_on = false         # 找不到任何有效目标 → 退化为未锁定
	_sync_lock_marker()              # 每条路径都要走一遍：解除/死亡时靠它把标记收掉


## 让"身体中心白点"跟上当前锁定目标：换目标就重造、解除锁定就收掉。
## 【为什么每帧调用而不是只在进入/退出锁定那一刻调】目标会在锁定期间被**自动换掉**
##   （旧目标死了会当场重找一只，见 _update_lock_on），只有对比引用才发现得了。
## 【为什么不用每帧改标记位置】标记是目标的子节点，"跟随移动"是引擎免费做的；
##   这里只负责判断"该不该存在 / 该跟谁"（详见 LockMarker 文件头）。
func _sync_lock_marker() -> void:
	var want := get_lock_target()
	if _lock_marker != null and is_instance_valid(_lock_marker) \
			and _lock_marker.get_target() == want:
		return                       # 已有标记、且目标没变 → 什么都不用做
	_clear_lock_marker()
	if want != null:
		_lock_marker = LockMarker.attach(want, lock_marker_body_ratio, lock_marker_radius)


## 收掉锁定标记（解除锁定 / 换目标 / 死亡时调用）。
func _clear_lock_marker() -> void:
	if _lock_marker != null and is_instance_valid(_lock_marker):
		_lock_marker.queue_free()
	_lock_marker = null


## 锁定模式下的转身：始终面向锁定目标（移动方向不参与转身，这是"侧移"能成立的前提）。
func _face_lock_target(delta: float, speed: float = -1.0) -> bool:
	var tgt := get_lock_target()
	if tgt == null:
		return false
	var to_t := tgt.global_position - global_position
	to_t.y = 0.0
	if to_t.length() <= 0.05:
		return false
	_face_towards(to_t, delta, lock_turn_speed if speed < 0.0 else speed)
	return true


# ------------------------------------------------------------------
# 位移段选择（锁定 = 侧移/后撤三段；自由 = Walk）
# ------------------------------------------------------------------

## 选"当前该播的位移动画名"。
## 【怎么判断该播哪一段】把移动方向投影到**角色自身的两个水平轴**上：
##   前轴 = 模型正面(-Z)，右轴 = basis.x。
##   左右分量占优 → 侧移段；否则前后分量占优 → 前进(Walk) 或 后撤(WalkBack)。
## 【为什么不用输入轴(A/S/D)直接选】因为移动方向是镜头相对算出来的；
##   投影到自身轴才与"角色此刻朝哪"一致 —— 锁定期间角色面朝敌人，那 A 就是真的往左横移。
func _locomotion_clip() -> String:
	if not is_locked_on():
		return _walk_anim
	var fwd_axis := -_pivot.global_basis.z
	var right_axis := _pivot.global_basis.x
	fwd_axis.y = 0.0
	right_axis.y = 0.0
	if fwd_axis.length_squared() < 0.001 or right_axis.length_squared() < 0.001:
		return _walk_anim
	var f := _wish_dir.dot(fwd_axis.normalized())
	var r := _wish_dir.dot(right_axis.normalized())
	if absf(r) > absf(f):
		if r < 0.0 and _strafe_left_anim != "":
			return _strafe_left_anim
		if r > 0.0 and _strafe_right_anim != "":
			return _strafe_right_anim
	elif f < 0.0 and _walk_back_anim != "":
		return _walk_back_anim
	return _walk_anim


## 某段位移动画的"自然速度"（算播放倍速用）。侧移三段一个值、Walk 一个值。
func _natural_speed_for(clip: String) -> float:
	if clip == _strafe_left_anim or clip == _strafe_right_anim:
		return strafe_natural_speed
	return walk_natural_speed



## 发动处决：锁定目标、转身面向它、开无敌，并播专属的 Execute 动画
## （举剑 → 前刺 → 上划 → 收招）。
## 【为什么全程无敌】处决是"玩家主动交出的执行权"——动作期间不能翻滚也不能格挡，
##   如果不能被打断，就会被旁边的杂兵白嫖一顿；给无敌换来的是"处决值得用"。
##   代价（强度平衡）在于：处决动作比普通挥砍长（execute_time 1.0 > attack_total 0.5），
##   无敌结束后仍有一段收招，所以不该在怪堆里无脑处决。
func _try_start_execute(target: Node3D) -> void:
	state = State.EXECUTE
	_state_time = 0.0
	_execute_target = target
	_execute_hit_done = false
	health.invincible = true                 # 处决全程无敌
	_hit_targets.clear()
	_set_hitbox_active(false)                # 处决伤害走 enemy.execute()，不用命中盒
	# 转身面向目标（处决要"看着它砍"），并把前冲方向锁定成目标方向
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		to_target = to_target.normalized()
		_facing_dir = to_target
		_face_instant(to_target)
	# 动画：优先播专属的 Execute（举剑→前刺→上划）；万一模型里没有这段，
	# 就退回"慢放挥砍(Slash)"，保证任何资产状态下处决都有演出。
	# 【倍速怎么定】按"动画时长 ÷ execute_time"换算，让整段动画恰好铺满 EXECUTE 状态，
	#   而且动画的"前刺命中帧"会落在 execute_hit_time 上（改哪个值都不会脱节）。
	var clip := _execute_anim if _execute_anim != "" else _slash_anim
	if _anim_player != null and clip != "":
		var a := _anim_player.get_animation(clip)
		var spd := execute_anim_speed
		if spd <= 0.0:
			spd = 1.0
			if a != null and a.length > 0.01:
				spd = a.length / maxf(0.05, execute_time)
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(clip, -1.0, spd)
	# 起手就先迸一层金光，明确告诉玩家"这一下是处决"
	HitFlash.spawn(self, _effect_point(), Color(1.0, 0.86, 0.3), 1.1, 0.32, 6.0)


## 特效挂载点：优先挂在当前场景根下，取不到就退回自己的父节点。
## 【为什么不用 self】特效节点若挂在玩家身上，玩家被清场时特效会跟着消失；
##   挂到场景根更"独立"。但玩家本身可能就是场景根（例如自动化测试里直接
##   把 Player 当根节点跑），这时 get_parent() 为 null，add_child 会报错，
##   所以要逐级兜底，最终回退到自己。
func _vfx_root() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	var parent := get_parent()
	if parent != null:
		return parent
	return self


## 处决的伤害结算（在 execute_hit_time 时刻调用一次，对应动画的"前刺"帧）。
## 【注意这里只打一次伤害、不做"是否打死"的判断】无论目标死没死，演出都照演到底
##   （见 _process 里 EXECUTE 分支的注释）—— 半途收招会让处决看起来很廉价。
func _execute_strike() -> void:
	if _execute_hit_done:
		return
	_execute_hit_done = true
	var target := _execute_target
	# 目标可能在处决途中死掉/被清场 → 目标失效就只演动作不出伤害
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("execute"):
		target.execute(execute_damage, global_position)   # 敌人侧负责乘 execute_damage_scale
	elif target.has_method("take_damage"):
		target.take_damage(execute_damage, global_position)  # 没实现 execute 的敌人就按普通伤害打
	# 命中处的金色爆闪：比完美格挡更大更亮，作为"处决成立"的强反馈
	HitFlash.spawn(_vfx_root(), target.global_position + Vector3(0, 1.1, 0),
		Color(1.0, 0.8, 0.25), 1.4, 0.45, 9.0)


## 收招：解除无敌、回到移动状态、给一点攻击冷却（防止处决完立刻又挥一刀）。
func _end_execute() -> void:
	health.invincible = false
	state = State.MOVE
	_state_time = 0.0
	# ★ 通知目标"处决演出结束了"：扛住这一击的敌人这时才爬起来（收掉 BROKEN）。
	#   必须在清空 _execute_target 之前调用。
	# 【为什么不让敌人自己在 execute() 里收】那一刻演出才刚开始 —— 敌人当场站直
	#   会变成"在处决动画里复活"，非常出戏。
	# 【为什么非收不可】伤害改成"大量但非致命"之后，敌人会活着留在 BROKEN 里；
	#   不收失衡的话玩家能原地连按左键无限处决（还是全程无敌），
	#   处决就从"一次性的高光"退化成"刷伤害的循环"。
	var victim := _execute_target
	if victim != null and is_instance_valid(victim) and victim.has_method("end_break_after_execution"):
		victim.end_break_after_execution()
	_execute_target = null
	_execute_hit_done = false
	_attack_cooldown = maxf(_attack_cooldown, attack_cd)
	_pivot.rotation.x = 0.0


## 玩家身体中心（特效生成点）：胸口高度略偏前，让闪光看起来"从身上迸出来"。
func _effect_point() -> Vector3:
	return global_position + Vector3(0.0, 1.15, 0.0)


## 尝试开始闪避（只有站立状态允许）。
## ★ **方向规则（2026-09-20 改）**：
##   · **按着任意方向键 + Shift → 前闪**，并且**身体先转到那个方向**、再顺着它冲出去；
##   · **单按 Shift（没有方向输入）→ 后闪**，朝身体正后方跳开，**不改朝向**。
## 【为什么改成"有输入就前闪"】旧规则是"有 W 才前冲"，A/S/D+Shift 一律判成后撤 ——
##   想"往左边拉开"必须先转镜头或先走两步把身体转过去，闪避最核心的诉求被规则吃掉了。
## 【为什么前闪必须真转身】不转身会出现"身体朝前、人往旁边平移"的拧巴状态，
##   斜着走更像螃蟹横行；转身后再冲，读起来才始终是"整个人扑出去"。
##   ⚠️ **锁定时也照转**（用户明确要求）：`_face_lock_target()` 只在 MOVE / BLOCK 里被调用，
##   DODGE 期间不会被拉回去；闪避结束回到 MOVE 时，锁定会自己把朝向平滑转回敌人。
## health.invincible=true → 闪避全程免疫（无敌帧），这也是"完美闪避"的判定前提。
func _try_start_dodge() -> void:
	if state != State.MOVE or _dead:
		return
	# ⚠️ 必须**自己先刷新一次** wish 方向：平时 `_update_wish_dir()` 算在本函数**之后**
	#   （见 _physics_process 的轮询顺序），不补这一次读到的会是上一帧的方向 ——
	#   同帧按下"方向键 + Shift"时会漏判成"没有方向输入"，静默变成后撤。
	_update_wish_dir()
	var wish := _wish_dir
	wish.y = 0.0
	# 【为什么这里反而该读 _wish_dir】闪避要的正是"玩家按的是世界哪个方向"（相对镜头）。
	#   旧版刻意不读它，是因为那时要判"前 / 后"，会被"身体正在转身"的中间态污染；
	#   现在只判"有没有输入"，然后直接拿这个方向当位移方向 —— 中间态问题不复存在。
	if wish.length_squared() > 0.01:
		_dodge_is_forward = true
		_dodge_dir = wish.normalized()
		_face_instant(_dodge_dir)          # 瞬间转身 → 再顺着这个方向冲出去
		_facing_dir = _dodge_dir
	else:
		_dodge_is_forward = false
		_dodge_dir = -_get_facing_flat()   # 单按 Shift：朝背后跳开，刻意不改朝向
	state = State.DODGE
	_state_time = 0.0
	health.invincible = true
	_perfect_dodge_armed = true          # 这一次闪避还留着一次完美判定
	_dodge_time = dodge_forward_time if _dodge_is_forward else dodge_back_time
	_dodge_anim = _dodge_fwd_anim if _dodge_is_forward else _dodge_back_anim
	# 位移方向在前一步已经按输入定好（前闪=输入方向、后闪=身体正后方），这里只管播动画。
	# 倍速现算，让动画恰好铺满 _dodge_time 秒（与位移/无敌帧同步收尾）
	_dodge_anim_speed = 1.0
	if _anim_player != null and _dodge_anim != "":
		var a := _anim_player.get_animation(_dodge_anim)
		if a != null and a.length > 0.01:
			_dodge_anim_speed = a.length / maxf(0.05, _dodge_time)
		# stop() 先归零，避免残留上次播放的进度
		_anim_player.stop()
		_anim_player.play(_dodge_anim, -1.0, _dodge_anim_speed)


## 尝试进入格挡（只有站立/移动状态允许：翻滚、攻击、受击硬直中都不能起手格挡）。
## 进入瞬间把 _perfect_parried 清零 —— 接下来的 perfect_parry_window 秒就是完美格挡窗口。
## 这里只播 Block（举剑起手）；举剑待机的循环由 _block_play 在起手动画放完后接手。
func _try_start_block() -> void:
	if state != State.MOVE or _dead:
		return
	state = State.BLOCK
	_state_time = 0.0
	_perfect_parried = false        # 新的一次格挡 → 重新给一次完美判定
	_block_impact_time = 0.0        # 清掉上次残余的顿挫
	if _anim_player != null and _block_anim != "":
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_block_anim, -1.0, block_anim_speed)


## 结束格挡：回到移动状态并收掉格挡动画、复位骨骼。
## 【为什么要 _anim_to_rest】BlockHold 是循环动画，不收掉的话下一段动作（走路/攻击）
##   会从"举着剑"的姿势混进来，出招前会闪一下。
func _end_block() -> void:
	if _anim_player != null and _anim_player.is_playing():
		_anim_to_rest()
	state = State.MOVE
	_state_time = 0.0
	_perfect_parried = false
	_block_impact_time = 0.0
	_pivot.rotation.x = 0.0         # 兜底模式(无动画)的整体旋转复位


## 尝试起跳（由物理帧里的"跳跃缓冲"驱动调用）。
## 可以被接受的情况：
##   ① 正站在地面上；② 刚离开地面不久（还在 coyote_time 土狼时间内）。
## 会被拒绝的情况：翻滚/攻击/受击硬直/格挡/处决中、已经在跳跃流程里（不做二段跳）、已死亡。
## 【默认 = 瞬间起跳】起跳动画已取消（见 jump_prep_time 声明处）→ `jump_prep_time = 0`，
##   站在地面按跳跃键**立刻**给向上速度进入 JUMP，全程只播滞空动画，没有"按了没反应"的前摇。
##   ★ 下面那条"地面蓄力段"分支**仍然保留**：把 `jump_prep_time` 调回 > 0.01 就会重新走
##   JUMP_PREP（先在地面播完蹬地动作再离地）；空中按（走平台的土狼跳）两条路都直接进 JUMP。
func _try_start_jump() -> void:
	if _dead or state == State.DODGE or state == State.ATTACK or state == State.HURT or state == State.BLOCK or state == State.EXECUTE:
		return
	if state == State.JUMP or state == State.JUMP_PREP:
		return                                      # 已在跳跃流程中 → 不可二段跳
	if not is_on_floor() and _coyote <= 0.0:
		return                                      # 既不在地面、也不在土狼时间内
	_jump_buffer = 0.0
	_coyote = 0.0
	if is_on_floor() and _anim_player != null and _jump_start_anim != "" and jump_prep_time > 0.01:
		# —— 蓄力段（★ 默认关闭：起跳动画已取消，jump_prep_time = 0 时走 else 直接离地）——
		# 留在地面播蹬地预备动作，倍速按 jump_prep_time 换算。
		state = State.JUMP_PREP
		_state_time = 0.0
		var a := _anim_player.get_animation(_jump_start_anim)
		var spd := 1.0
		if a != null and a.length > 0.01:
			spd = a.length / jump_prep_time          # 例：0.375s ÷ 0.18s ≈ 2.08 倍速（仅蓄力开启时有意义）
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_jump_start_anim, -1.0, spd)
	else:
		_launch_jump(true)


## 真正起跳：给向上初速度并进入空中状态（JUMP），切换为滞空循环动画。
## @param with_impulse true=给跳跃初速度(正常起跳)；false=不给冲量(蓄力途中掉下平台)
## 实现要点：竖直速度"直接赋值"而不是插值——起跳要脆、要立刻响应；
##           水平速度不重置，跑动中跳跃能保留冲量(跳跃距离自然更远)。
func _launch_jump(with_impulse: bool) -> void:
	if with_impulse:
		velocity.y = jump_velocity
	state = State.JUMP
	_state_time = 0.0
	if _anim_player != null and _jump_air_anim != "":
		_anim_player.speed_scale = 1.0
		_anim_player.stop()
		_anim_player.play(_jump_air_anim, -1.0, 1.0)


## 状态超时检测：每个状态是否该结束/切换（被 _physics_process 每帧调用）。
func _update_state(_delta: float) -> void:
	match state:
		State.MOVE:
			# 锁定中：身体始终朝向敌人（移动方向不参与转身）——这是"侧移"能成立的前提，
			# 否则身体会扭向移动方向，侧移动画就失去意义了。
			if not _face_lock_target(_delta):
				_face_towards(_wish_dir, _delta)  # 走路时身体平滑转向移动方向
			if _wish_dir.length() > 0.1:
				_bob_phase += _delta * 10.0       # 在动才累计跑步相位
			# 走下台阶/跳下平台：过了土狼时间仍未落地 → 进入 JUMP(下落)状态
			if not is_on_floor() and _coyote <= 0.0:
				state = State.JUMP
				_state_time = 0.0
		State.DODGE:
			if _state_time >= _dodge_time:        # 闪避时间到 → 结束
				_end_dodge()
		State.BLOCK:
			# 格挡的存续完全由"右键是否按住"决定（不是靠 _state_time 超时）：
			#   松开右键 → 收招回 MOVE
			#   踩空掉下平台 → 也收招（不能在空中举着剑滑翔），转为下落
			#   按住 → 缓慢朝移动方向转身（举着剑挪步时身体还是会跟着走）
			if not Input.is_action_pressed("block"):
				_end_block()
			elif not is_on_floor() and _coyote <= 0.0:
				_end_block()
				state = State.JUMP
				_state_time = 0.0
			else:
				# 锁定中举着剑也要保持面朝敌人（不然绕后的敌人会让格挡锥形指错方向）
				if not _face_lock_target(_delta, lock_turn_speed * 0.5):
					_face_towards(_wish_dir, _delta, turn_speed * 0.5)
		State.EXECUTE:
			# 处决：自动贴近目标，到 execute_hit_time 结算一次伤害，演满 execute_time 收招。
			# 目标中途死掉/失效就直接收招，不空演动作。
			var tgt := _execute_target
			# 【注意只判"节点被销毁"】不判"目标死了" —— 处决一刀把敌人砍死是常态，
			# 若一死就收招，演出会在半途戛然而止。让它演完 execute_time 再收。
			if tgt == null or not is_instance_valid(tgt):
				_end_execute()
			else:
				# 一直盯着目标转身（处决要"对着它砍"，目标被击退时也跟着转）
				var to_t := tgt.global_position - global_position
				to_t.y = 0.0
				if to_t.length() > 0.05:
					_face_towards(to_t, _delta, turn_speed)
				if not _execute_hit_done and _state_time >= execute_hit_time:
					_execute_strike()
				if _state_time >= execute_time:
					_end_execute()
		State.ATTACK:
			# ★ 连击的两条出路，先判"后摇取消"：
			#   取消点(≤0.30)必然早于整段末尾，两条分支不会同时成立，先后只是可读性。
			var cancel_at := _combo_cancel_at(_combo_step)
			if cancel_at > 0.0 and _combo_queued and _state_time >= cancel_at:
				# 兑现输入缓冲 → 掐掉剩余收招、直接接下一段。
				# 【为什么不用等整段演完】这正是"后摇取消"：取消点在判定窗之后一点点，
				#   剑气刚扫过就能顺势甩出下一刀，连击才"顺"。
				_start_combo_step(_combo_step + 1)
			elif _state_time >= _combo_total(_combo_step):
				# 没人接 → 演完整段，回移动 + 进冷却。
				# 第 3 段用更长的 combo_finish_cd：收尾重击的"重量"也体现在这儿（多站一会儿）。
				var was_finisher := _combo_step >= COMBO_STEPS - 1
				state = State.MOVE
				_state_time = 0.0
				_attack_cooldown = combo_finish_cd if was_finisher else attack_cd
				_combo_queued = false
				_combo_buffer_time = 0.0
				_set_hitbox_active(false)
		State.HURT:
			if _state_time >= hurt_time:          # 受击硬直时间到 → 恢复行动（时长见 @export）
				state = State.MOVE
				_state_time = 0.0
				# 硬直结束时格挡键还按着 → 自动重新举剑。
				# 【为什么】设计承诺是"按住右键=持续格挡"；若被背后偷袭打破防后
				#   必须松开再按才能重新格挡，与这个承诺矛盾，手感也很别扭。
				# 【但要防白送】重举时把 _perfect_parried 标成已用过：
				#   只有"自己主动按下"的那一次才有完美格挡窗口，
				#   否则"按住不放 → 被打 → 自动重举 → 白拿一次完美窗口"会变成无脑套路。
				if control_enabled and Input.is_action_pressed("block") and not _dead:
					_try_start_block()
					_perfect_parried = true
		State.JUMP_PREP:
			# 蓄力段（仍在地面）：播蹬地预备动作；时间到 → 真正起跳。
			# 若中途掉下平台（不再是 on_floor 且过了土狼时间）→ 不给冲量直接进入空中。
			# ⚠️ 默认**进不来**（jump_prep_time = 0，起跳动画已取消）；调回 0.18 即恢复这条路径。
			if not is_on_floor() and _coyote <= 0.0:
				_launch_jump(false)
			elif _state_time >= jump_prep_time:
				_launch_jump(true)
		State.JUMP:
			# 落地判定：踩到地面且竖直速度已非上升 → 回移动状态 + 落地压缩 + 收掉滞空动画。
			# （起跳动画已取消，离地后就只剩滞空循环要处理了）
			if is_on_floor() and velocity.y <= 0.01:
				state = State.MOVE
				_state_time = 0.0
				_squash = land_squash_time
				if _anim_player != null and _anim_player.is_playing():
					_anim_to_rest()
		State.DEAD:
			pass                                  # 死亡状态保持，等主场景重开


## 结束闪避：解除无敌、回到移动状态、短暂冷却(防止"闪完立刻开打"粘在一起)。
## 【和老的 _end_roll 差在哪】老翻滚要把 RollLeap 自带的 1m 根位移"过继"给本体
##   （动画末帧停在身体前方 1m）；两段闪避动画**不含净位移**（root.location.x/y 恒 0），
##   位移完全由 _update_velocity 的 DODGE 分支给，所以这里不需要任何位置补偿 ——
##   只剩"收动画 + 复位骨骼 + 回 MOVE"三件事。
func _end_dodge() -> void:
	health.invincible = false
	# 收掉闪避动画并复位骨骼：两段动画的**末帧就是中立站架**（首尾同姿势，出片脚本有自检），
	# 所以在这里收掉不会跳变；不收的话下一段动作会从它停下的位置混进来。
	if _anim_player != null and _dodge_anim != "":
		_anim_to_rest()
	state = State.MOVE
	_state_time = 0.0
	_attack_cooldown = maxf(_attack_cooldown, 0.15)
	# ⚠ 刻意**不**清 _dodge_anim / _dodge_is_forward：它们只在 state==DODGE 时被读，
	#   留着能让"上一次闪的是哪一段"在闪避结束后仍可查（自动测试与排查都用得上）。
	_pivot.rotation.x = 0.0          # 兜底模式(无动画)的整体旋转复位


# ------------------------------------------------------------------
# 速度计算（每个状态对 velocity 的不同处理）
# ------------------------------------------------------------------

## 按状态设置水平速度，并始终应用重力。
## 平滑手法：velocity 向目标值做帧率无关插值 lerp(x, target, 1-exp(-rate*dt))，
##           数字越大越"贴"，越小越"滑"。
func _update_velocity(delta: float) -> void:
	if not is_on_floor():
		# 重力分三段，做出"起跳跟手、下落利落"的手感：
		#   ① 上升中且按住跳跃键 → 常规重力(跳满高度)
		#   ② 上升中但松开了跳跃键 → 重力×jump_cut_multiplier(轻点=小跳)
		#   ③ 下落中 → 重力×fall_gravity_multiplier(落地更干脆，不飘)
		var g := GRAVITY
		if velocity.y > 0.0:
			if not Input.is_action_pressed("jump"):
				g *= jump_cut_multiplier
		else:
			g *= fall_gravity_multiplier
		velocity.y -= g * delta
	match state:
		State.MOVE:
			# 锁定中整体降速：横移/后撤时脚是横着走的，按全速跑会显得"飘"，
			# 而且降速能让玩家更容易看清敌人的起手动作（锁定本来就是为了对刀）。
			var lock_scale := lock_move_scale if is_locked_on() else 1.0
			var target := _wish_dir * move_speed * lock_scale
			var t := 1.0 - exp(-accel * delta)   # accel 越大越跟手
			velocity.x = lerpf(velocity.x, target.x, t)
			velocity.z = lerpf(velocity.z, target.z, t)
		State.DODGE:
			# 闪避速度：开头最猛、随时间衰减到 45%（冲出去的爆发感，收尾自然刹住）。
			# 【为什么用衰减而不是匀速】匀速"闪"读起来像"滑过去"；前猛后收才像"整个人弹出去"。
			# 衰减终点给 0.45 而不是 0：留一点末速，收招回 MOVE 时不会顿一下。
			var t := clampf(1.0 - _state_time / _dodge_time, 0.0, 1.0)
			var base_spd := dodge_forward_speed if _dodge_is_forward else dodge_back_speed
			var spd := base_spd * lerpf(0.45, 1.0, t)
			velocity.x = _dodge_dir.x * spd
			velocity.z = _dodge_dir.z * spd
		State.BLOCK:
			# 格挡：能走但只能挪（乘 block_move_scale），加速度也压低一点，
			# 做出"举着盾牌/大剑移动"的迟滞感；松手时靠同一个 lerp 自然刹停。
			# 锁定中再乘一层 lock_move_scale —— 举剑 + 锁定是最慢的挪步，符合"稳守"的定位。
			var blk_lock_scale := lock_move_scale if is_locked_on() else 1.0
			var target := _wish_dir * move_speed * block_move_scale * blk_lock_scale
			var t := 1.0 - exp(-accel * 0.6 * delta)
			velocity.x = lerpf(velocity.x, target.x, t)
			velocity.z = lerpf(velocity.z, target.z, t)
		State.EXECUTE:
			# 处决：自动朝目标平推过去（不受方向输入影响），贴近到 1.4m 就停住，
			# 免得把身体挤进敌人模型里（视觉上会穿模）。
			var ex_tgt := _execute_target
			var want_ex := Vector3.ZERO
			if ex_tgt != null and is_instance_valid(ex_tgt):
				var to_ex := ex_tgt.global_position - global_position
				to_ex.y = 0.0
				if to_ex.length() > 1.4:
					want_ex = to_ex.normalized() * execute_approach_speed
			var te := 1.0 - exp(-14.0 * delta)
			velocity.x = lerpf(velocity.x, want_ex.x, te)
			velocity.z = lerpf(velocity.z, want_ex.z, te)
		State.ATTACK, State.HURT:
			# 攻击/受击硬直时快速刹停（不能一边走一边挥）
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-12.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-12.0 * delta))
		State.JUMP_PREP, State.JUMP:
			# 蓄力段与空中都用较小的水平加速度：保留起跳冲量，但很难在空中大幅变向
			var target := _wish_dir * move_speed
			var t := 1.0 - exp(-air_accel * delta)
			velocity.x = lerpf(velocity.x, target.x, t)
			velocity.z = lerpf(velocity.z, target.z, t)
		State.DEAD:
			# 死亡后慢慢停住（尸体不滑走）
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-8.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-8.0 * delta))


# ------------------------------------------------------------------
# 受击与死亡
# ------------------------------------------------------------------

## 对外伤害入口（敌人命中盒调用）。
## 顺序：死亡/闪避/短暂无敌 → 忽略（但闪避中要顺带判"完美闪避"）；
##       正在格挡且攻击来自正面锥形内 → 走格挡分支（完美格挡 / 普通减伤）；
##       否则扣血；血空→死亡；否则→受击硬直。
func take_damage(amount: int, from_pos: Vector3) -> void:
	if _dead or state == State.DODGE or state == State.EXECUTE or _iframes > 0.0:
		# ★★ 完美闪避的判定点就在这里。
		# 【为什么把判据挂在这个函数上，而不是另做一套"闪避窗口计时"】
		#   敌人命中盒（enemy.gd 的 AttackHitbox）只在挥击判定帧开门，
		#   `body_entered` 打在玩家身上的瞬间就会调到这里 —— 也就是说
		#   **"这里被调用"本身就等价于"敌人的这一下本来已经打中你了"**，
		#   敌人自己的 windup/strike 节奏就是最准确的窗口，不需要玩家侧再调任何秒数。
		#   玩家此刻正在闪避无敌帧里 → 这一下被你闪开了 = 完美闪避。
		# 【为什么要 _perfect_dodge_armed 这一位】一次闪避只给一次完美判定：
		#   否则站在敌人判定盒里被连续扫到会连着触发慢动作，画面会花、也不合理。
		# 【对比完美格挡】两者同源（都是"本来打得中、被你化解"），
		#   但格挡要额外判"是不是正面 120° 锥形内"，闪避不需要 —— 闪避本来就能往后躲。
		if state == State.DODGE and _perfect_dodge_armed:
			_perfect_dodge_armed = false
			_trigger_perfect_dodge(from_pos)
		return
	# ★ 格挡判定要在扣血之前：挡下来就完全不进受击流程（不硬直、不击退）
	if state == State.BLOCK and _is_blocking_from(from_pos):
		_resolve_block(amount, from_pos)
		return
	if not health.damage(amount):                # Health 组件自身也会挡无敌
		return
	if health.current_hp <= 0:
		_die()
		return
	_enter_hurt(from_pos)


## 判断来袭方向是否落在"正面格挡锥形"内。
## 【实现】比较 自己朝向 与 "指向攻击来源的方向" 的夹角：夹角越小 dot 越大，
##         dot >= cos(张角/2) 就算挡住。背后/侧后袭击 dot 很小 → 挡不住。
## 【为什么用锥形而不是"任意方向"】否则玩家可以背对敌人一直按着右键无脑挨打，
##        格挡就失去了"要看住敌人"的博弈价值。
func _is_blocking_from(from_pos: Vector3) -> bool:
	var to_src := from_pos - global_position
	to_src.y = 0.0
	if to_src.length_squared() < 0.0001:
		return true                              # 来源就在脚下（几乎不会发生），按"挡住"处理
	var facing := _get_facing_flat()
	var dot := facing.dot(to_src.normalized())
	return dot >= cos(deg_to_rad(block_guard_angle * 0.5))


## 结算一次"被挡下"的攻击。
##   · 完美格挡（按下后 perfect_parry_window 秒内 + 本次还没用掉）：
##       0 伤害，并把攻击者弹进长硬直（deflect）→ 玩家的反击窗口；闪金光提示。
##   · 普通格挡：只吃 (1 - block_damage_reduction) 的伤害；
##       不硬直、不击退、不进无敌帧，所以持续被砸依然会慢慢掉血
##       （避免"按住右键 = 无敌"），并播 BlockImpact 演一下顿挫。
## 两种情况都会插播顿挫动画（完美的更亮）。
func _resolve_block(amount: int, from_pos: Vector3) -> void:
	var perfect := _state_time <= perfect_parry_window and not _perfect_parried
	_perfect_parried = true                      # 一次按住只给一次完美判定
	_block_impact_time = block_impact_hold       # 插播顿挫，_animate_model 会在这段时间里播它
	# 插播顿挫动画：先 stop() 再 play，确保从头播（否则同名动画不会重播）
	if _anim_player != null and _block_impact_anim != "":
		_anim_player.stop()
		_anim_player.play(_block_impact_anim, -1.0, block_anim_speed)
	if perfect:
		# —— 完美格挡：不掉血，反手把攻击者打进长硬直 ——
		_flash(1.2)
		# 黄光特效：在格挡点（身前一点）迸一圈金色环 + 亮球，给"这一下弹对了"强反馈
		HitFlash.spawn(_vfx_root(), _effect_point() + _get_facing_flat() * 0.55,
			Color(1.0, 0.85, 0.22), 0.95, 0.36, 8.0)
		perfect_parry.emit()                 # 通知 HUD 闪一下屏幕金光
		_stagger_attacker(from_pos)
		return
	# —— 普通格挡：按比例减伤（至少吃 1 点，否则高减伤下就变成无敌了）——
	var reduced := maxi(1, int(round(float(amount) * (1.0 - block_damage_reduction))))
	if not health.damage(reduced):
		return
	if health.current_hp <= 0:
		_die()
		return
	_flash(0.45)


## 完美格挡的反馈：把"攻击者"打进长硬直。
## 【怎么找到攻击者】敌人命中盒调用 take_damage 时传进来的 from_pos 就是它自己的
##   位置，所以"离 from_pos 最近且站在 from_pos 上（<1.5m）的敌人"就是攻击者。
##   用容差而不是精确相等，是为了兜住"两只怪重叠在一起"的极端情况。
## 【为什么不用敌人回调】玩家的 take_damage 签名是 (amount, from_pos)，
##   拿不到攻击者节点；在这里按位置反查是代价最小、耦合最低的做法。
func _stagger_attacker(from_pos: Vector3) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("deflect"):
			continue
		if (e as Node3D).global_position.distance_to(from_pos) <= 1.5:
			e.deflect(block_parry_stagger, global_position)


## 完美闪避的结算：闪光 + 虚影 + 子弹时间。
## 【为什么三样一起给】缺一样，玩家都会"不知道自己刚刚做对了什么"：
##   · 闪光 = 瞬时确认（这一下闪对了）
##   · 虚影 = 空间残留（把"我在哪闪开的"画出来，也是唯一的"帅气"来源）
##   · 子弹时间 = 时间层面的奖励（接下来这零点几秒是你的表演时间）
## 与敌人侧无关 —— 完美闪避**不动敌人**（不像完美格挡会把敌人打进硬直）：
##   闪避是"我躲开了"，格挡是"我顶回去了"，前者不该反过来控制敌人。
## 【参数说明】_from_pos 现在用不上（闪避不控制敌人），保留形参是为了：
##   ① 与 take_damage 的调用点保持一致、将来要接"从敌人方向甩一道风痕"时不用改签名；
##   ② 让人一眼看出"这次完美闪避是被谁触发的"。
func _trigger_perfect_dodge(_from_pos: Vector3) -> void:
	_flash(1.2)                                  # 身上闪一下白（与被打/格挡共用同一套闪光）
	# 青蓝色的亮球 + 扩散环：故意用冷色，和完美格挡的金色一眼区分开。
	# 尺寸/强度单独给了一组更小的 @export（原因见参数声明处：它炸在角色身上，会吃掉虚影）
	HitFlash.spawn(_vfx_root(), _effect_point(), ghost_color,
		dodge_flash_radius, dodge_flash_time, dodge_flash_energy)
	GhostTrail.burst(self, _pivot, _dodge_dir, ghost_color, ghost_count, ghost_life)
	_start_bullet_time()
	perfect_dodge.emit()                         # 通知 HUD 闪屏 + 给提示


## 触发子弹时间：把全局时间压慢，持续 bullet_time_duration 真实秒后再平滑回升。
## 【为什么用 Tween 而不是自己数秒】自己数秒必须拿"真实时间"，而 _process 的 delta
##   恰恰是被 time_scale 缩放过的 —— 用它计时会让"减速期间"的计时也一起变慢，
##   实际减速时长会被拉长成 duration / time_scale（0.6s 变 1.7s），节奏完全失控。
##   Tween.set_ignore_time_scale(true) 就是官方提供的"这条件不受 time_scale 影响"开关。
## 【为什么要 kill 上一条件】连续完美闪避时，旧补间到点会把新减速一起拉回 1.0。
func _start_bullet_time() -> void:
	if _bullet_time_tween != null and _bullet_time_tween.is_valid():
		_bullet_time_tween.kill()
	_bt_factor = bullet_time_scale           # 只改"自己这一份"因子 → 不会踩掉正在进行的顿帧
	_push_time_scale()
	_bullet_time_tween = create_tween()
	_bullet_time_tween.set_ignore_time_scale(true)      # ★ 关键：别被自己造成的减速拖慢
	_bullet_time_tween.tween_interval(bullet_time_duration)
	_bullet_time_tween.tween_method(_set_bullet_factor, bullet_time_scale, 1.0, bullet_time_fade)


## 子弹时间因子的写入口（由上面的补间逐帧调用）。
func _set_bullet_factor(v: float) -> void:
	_bt_factor = v
	_push_time_scale()


## 顿帧(hitstop)：命中瞬间把全局时间压到几乎定格，持续 real_seconds **真实秒**后迅速弹回。
## 【为什么顿帧要单独一个因子、不直接写 Engine.time_scale】见 hitstop_* 参数声明处：
##   它和子弹时间都会压慢时间，两个补间直接抢同一个变量时，"谁后写谁赢"，
##   先前那个到点还会把对方的减速一起拉回 1.0（画面会突然"抽一下"）。
##   拆成两个因子 + 取更慢者，两边互不干扰。
## 【为什么要设上限取最狠的一次】重叠命中（一刀扫到两个敌人）会连着调两次，
##   若每次都从头计时，顿帧会被叠成"两倍长" —— 取 max 反而更稳。
func _start_hitstop(real_seconds: float) -> void:
	if real_seconds <= 0.0 or hitstop_scale >= 1.0:
		return
	if _hitstop_tween != null and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	_hs_factor = hitstop_scale
	_push_time_scale()
	_hitstop_tween = create_tween()
	_hitstop_tween.set_ignore_time_scale(true)          # ★ 同子弹时间：别被自己的减速拖长
	_hitstop_tween.tween_interval(real_seconds)
	# 收尾用一段极短的淡出（0.03s）而不是硬跳回 1.0：硬跳会有一下可闻的"顿挫感"
	_hitstop_tween.tween_method(_set_hitstop_factor, hitstop_scale, 1.0, HITSTOP_RELEASE)


## 顿帧因子的写入口（由上面的补间逐帧调用）。
func _set_hitstop_factor(v: float) -> void:
	_hs_factor = v
	_push_time_scale()


## 把两个因子合成真正的全局时间倍率 —— 取**更慢的那个**。
## 【为什么是 min 而不是乘】相乘会让"子弹时间里的命中"慢到 0.45×0.05 = 0.0225（几乎静止两秒），
##   表现上像卡死。取 min 则"最深的效果说了算"，两者叠在一起也不会失控。
func _push_time_scale() -> void:
	Engine.time_scale = minf(_bt_factor, _hs_factor)


## 玩家被销毁（重开场景 / 退出）时把时间倍率复位。
## 【为什么必须兜底】Engine.time_scale 是**全局单例**，一旦在减速状态里被销毁，
##   补间随之消失 → 整个游戏（包括下一个场景）都会永远停留在 0.35 倍速。
func _exit_tree() -> void:
	if _bullet_time_tween != null and _bullet_time_tween.is_valid():
		_bullet_time_tween.kill()
	if _hitstop_tween != null and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	_bt_factor = 1.0                 # 两个因子也一并复位，否则下次进场景 _push_time_scale 会把旧值带回来
	_hs_factor = 1.0
	Engine.time_scale = 1.0


## 进入受击状态：硬直 + 击退 + 0.6s 无敌(防连击) + 闪白。
## ★ **刻意不改面朝向**（用户的明确要求："受到攻击时不改变面朝向，只会后退"）。
##   HURT 状态全程不写 _pivot.rotation.y，所以身体保持挨打前的朝向被击退出去。
##   【为什么这样更好】被打就"扭头看偷袭者"会让玩家丢掉原本的方向感：
##     正面顶着敌人时被侧面杂兵擦一下，身体突然转向杂兵 —— 主目标就脱出视野了。
##     不改朝向则"后退"是纯位移，位置变了、朝哪没变，玩家更容易维持战斗节奏。
func _enter_hurt(from_pos: Vector3) -> void:
	state = State.HURT
	_state_time = 0.0
	_iframes = 0.6
	_hurt_from = from_pos
	var away := global_position - from_pos       # 远离伤害来源的方向=击退方向
	away.y = 0.0
	if away.length() < 0.01:
		away = -_get_camera_forward()            # 兜底：来源正下方时朝镜头反向飞
	away = away.normalized()
	velocity.x = away.x * knockback_strength
	velocity.z = away.z * knockback_strength
	# 受击动画：**进状态的第一时间就播**，不要放到 _animate_model 里每帧判 ——
	#   硬直中又被补一下时 _state_time 会归零，动画却不会重头播，两边就错位了。
	# 倍速按"动画时长 ÷ hurt_time"现算 → 动画恰好铺满硬直时间（同 Dodge / Execute）。
	if _anim_player != null and _hurt_anim != "":
		var a := _anim_player.get_animation(_hurt_anim)
		var spd := 1.0
		if a != null and a.length > 0.01:
			spd = a.length / maxf(0.05, hurt_time)
		_anim_player.speed_scale = 1.0
		_anim_player.play(_hurt_anim, 0.05, spd)   # 0.05s 混入：被打断的动作不会硬跳
	_flash(0.7)                                  # 白闪一下提示"被打到了"
	# ⚠ 这里**故意不调用 _face_instant(away)**：见上面的函数注释（不改朝向，只后退）。


## Health 组件血量归零信号的回调 → 进入死亡（与 take_damage 里的路径去重）
func _on_health_died() -> void:
	if _dead:
		return
	_die()


## 进入死亡：锁死一切行动、广播 player_died（主场景弹遮罩）。
func _die() -> void:
	if _dead:            # 防重复触发（damage 内部信号与外部调用可能双到）
		return
	_dead = true
	state = State.DEAD
	_state_time = 0.0
	health.invincible = true    # 死后不再受伤害(尸体不被打)
	_set_hitbox_active(false)
	# 倒地动画：Death 是**单次**动画，播完会冻在末帧 → 尸体就一直躺着。
	# 倍速按"动画时长 ÷ death_time"现算；没有这段动画的老资产走整体前栽兜底。
	if _anim_player != null and _death_anim != "":
		var a := _anim_player.get_animation(_death_anim)
		var spd := 1.0
		if a != null and a.length > 0.01:
			spd = a.length / maxf(0.05, death_time)
		_anim_player.speed_scale = 1.0
		_anim_player.play(_death_anim, 0.08, spd)
	player_died.emit()


# ------------------------------------------------------------------
# 朝向（转向）工具 —— 都基于"模型的 -Z 是正面"这个约定
# ------------------------------------------------------------------

## 平滑转向：让 VisualPivot 的 Y 轴旋转逐渐对准 dir。
## 公式 rotation.y = atan2(-dir.x, -dir.z) 是因为：绕 Y 转 θ 后，
## 模型正面(-Z)指向 (-sinθ, 0, -cosθ)，反解出 θ。
func _face_towards(dir: Vector3, delta: float, speed: float = -1.0) -> void:
	var flat := dir
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	var rate: float = turn_speed if speed < 0.0 else speed
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-rate * delta))


## 瞬间转身（攻击起手用，保证出手方向跟手）。
func _face_instant(dir: Vector3) -> void:
	var flat := dir
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_pivot.rotation.y = atan2(-flat.x, -flat.z)


## 当前模型朝向的水平单位向量（翻滚无输入时用它定方向）。
func _get_facing_flat() -> Vector3:
	var f := -_pivot.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


## 镜头看向的水平单位向量（静止攻击时朝屏幕中心打）。
func _get_camera_forward() -> Vector3:
	var cam := _get_camera()
	if cam == null:
		return _get_facing_flat()
	var f := -cam.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


## 按组名查找镜头（镜头的 ThirdPersonCamera 脚本把自己加进了 "camera" 组）
func _get_camera() -> Node3D:
	return get_tree().get_first_node_in_group("camera") as Node3D


# ------------------------------------------------------------------
# 攻击命中（Area3D 命中盒）
# ------------------------------------------------------------------

## 连接命中盒信号。Area3D 的 body_entered(撞进身体) / area_entered(撞进区域)
## 信号，在监控打开且目标重叠时触发。
func _connect_hitbox_signals() -> void:
	if _hitbox == null:
		return
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_hitbox.area_entered.connect(_on_hitbox_area_entered)


func _on_hitbox_body_entered(body: Node3D) -> void:
	_on_hitbox_target(body)


## 敌人是 CharacterBody3D(身体)，通常 body_entered 就够；
## 这条兜底处理"目标是个 Area(区域)"的情况，取它的父亲当目标。
func _on_hitbox_area_entered(area: Area3D) -> void:
	var hit_owner := area.get_parent()
	if hit_owner != null and hit_owner != self:
		_on_hitbox_target(hit_owner)


## 命中判定统一出口：
##   只在自己处于 ATTACK 且判定帧内生效；同一次挥砍对同一敌人只打一次
##   (_hit_targets 记录)；只打组别为 "enemy" 且有 take_damage 的活目标。
## ★ 伤害取自**当前连击段**：_hit_targets 每段开打就清空（见 _start_combo_step），
##   所以同一个敌人会被连击的三段各打中一次 —— 这正是连击的意义。
func _on_hitbox_target(node: Node) -> void:
	if state != State.ATTACK:
		return
	if node == null or _hit_targets.has(node):
		return
	if not node.is_in_group("enemy") or not node.has_method("take_damage"):
		return
	if not node.is_alive():
		return
	_hit_targets.append(node)
	node.take_damage(_combo_damage(_combo_step), global_position)
	_on_hit_landed(_combo_step)


## 命中反馈三件套：顿帧 + 镜头震动 + 音效。
## 【为什么单独抽一个函数】这三样永远是"一次命中一起来"的，散在 _on_hitbox_target 里会
##   把"判定命中"和"给出反馈"搅成一坨。抽出来还有个好处：自动测试可以直接调它来验证
##   "顿帧真的压慢了时间、镜头真的抖了"，不必真去场地里挥一刀打中敌人。
## @param step 命中时所在的连击段（0/1/2），决定反馈的量级
func _on_hit_landed(step: int) -> void:
	var finisher := step >= COMBO_STEPS - 1     # 第 3 段 = 收尾重击 → 反馈更狠
	_start_hitstop(hitstop_finisher if finisher else hitstop_normal)
	_shake_camera(shake_finisher if finisher else shake_normal)
	_play_sfx(_sfx_hit)


## 抖一下镜头（命中手感）。
## 【为什么先 has_method 再调】headless 自动测试里镜头可能没被主场景搭起来，
##   或者将来换了个不带震动的镜头 —— 缺了"震动"这个能力不该让整刀打空。
func _shake_camera(amount: float) -> void:
	if amount <= 0.0:
		return
	var cam := _get_camera()
	if cam != null and cam.has_method("shake"):
		cam.shake(amount, shake_time)


## 播一个 3D 音效（挂在角色身上，会随距离衰减、随朝向定位）。
## 【为什么容错】音频资源是"后加的美术资产"：在它缺席时（比如刚 clone 下来还没跑生成脚本）
##   游戏必须照常能玩，而不是因为 load 到 null 就报错 —— 所以这里静默跳过。
func _play_sfx(player: AudioStreamPlayer3D, stream: AudioStream = null) -> void:
	if player == null:
		return
	if stream != null:
		player.stream = stream
	if player.stream == null:
		return
	player.play()


## 挂两个 3D 音效播放器（挥剑 / 命中）。
## 【为什么是 AudioStreamPlayer3D 而不是 AudioStreamPlayer】3D 播放器是"世界里的声源"：
##   会随距离衰减、按镜头与声源的相对方位定位（左后方来的敌人挨打，声音就在左后）。
##   M1 之后要做的"听声辨位躲攻击"靠的就是它；2D 播放器只会平铺在耳朵里。
func _setup_audio() -> void:
	_stream_swing_light = _load_stream(SFX_SWING_LIGHT)
	_stream_swing_heavy = _load_stream(SFX_SWING_HEAVY)
	_stream_hit = _load_stream(SFX_HIT)
	# 挥剑给人耳偏小一点（它是每段都响的背景音），命中声给足（它是"打实了"的确认）
	_sfx_swing = _make_sfx_player("SfxSwing", -5.0)
	_sfx_hit = _make_sfx_player("SfxHit", -1.0)


## 造一个挂在角色身上的 3D 音效播放器。
func _make_sfx_player(node_name: String, volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.volume_db = volume_db
	p.max_distance = 22.0      # 超过这个距离就听不见了（避免全场音效叠成一锅粥）
	p.unit_size = 4.0          # 衰减曲线：越大传得越远。4 大约是"十来米内听得清"
	add_child(p)
	return p


## 载入一个音频资源；文件不存在 / 没导入成功 → 返回 null。
## 【为什么不直接 load】load 一个不存在的路径会 push_error 并返回 null，
##   这里先用 ResourceLoader.exists 挡一道，让"音频还没生成"这件事**安静地**被容忍。
func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## 开关命中盒：set_deferred 让修改在"安全时机"(物理步结束后)生效，
## 避免在物理回调里直接改监控状态导致报错。
func _set_hitbox_active(active: bool) -> void:
	if _hitbox != null:
		_hitbox.set_deferred("monitoring", active)


# ------------------------------------------------------------------
# 外观构建入口
# ------------------------------------------------------------------

## 搭外观：先尝试加载外部模型(PLAYER_MODEL)；失败则用原语小蓝人兜底。
## 无论哪种，都会创建攻击命中盒挂在 VisualPivot 下(随朝向转动)。
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "VisualPivot"
	add_child(_pivot)

	if PLAYER_MODEL != null:
		_use_model = _setup_model()      # 尝试把骑士模型装进 VisualPivot
	if not _use_model:
		_build_robot_visuals()           # 兜底：原语小蓝人
	_create_attack_hitbox()              # 共用命中盒


## 加载并安置外部模型。
## 实现三步：
##   1. 实例化 GLB；
##   2. 递归收集每个网格部件，用它们的包围盒+节点变换算出模型总包围盒；
##   3. 按 MODEL_TARGET_HEIGHT 统一缩放，并平移到脚底 y=0、水平居中。
## 同时把部件材质登记进 _mats（受击闪光用）。
func _setup_model() -> bool:
	var model := PLAYER_MODEL.instantiate() as Node3D
	_pivot.add_child(model)
	model.name = "KnightModel"

	# 递归收集所有 MeshInstance3D 及其"相对模型根"的变换
	var meshes: Array = []   # 每个元素 { "node": MeshInstance3D, "xform": Transform3D }
	_collect_meshes(model, Transform3D.IDENTITY, meshes)
	if meshes.is_empty():
		model.queue_free()   # 空模型 → 放弃使用
		return false

	# 计算总包围盒(模型局部坐标，未缩放)
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for info in meshes:
		var mi: MeshInstance3D = info["node"]
		var aabb: AABB = mi.get_aabb()
		for corner in _aabb_corners(aabb):
			var p := (info["xform"] as Transform3D) * corner
			mn = mn.min(p)
			mx = mx.max(p)
	if mx.y - mn.y <= 0.001:
		model.queue_free()
		return false

	# 统一缩放到目标身高，并让脚底对齐 y=0、水平居中
	var s := MODEL_TARGET_HEIGHT / (mx.y - mn.y)
	model.scale = Vector3.ONE * s
	model.position = Vector3(
		-(mn.x + mx.x) * 0.5 * s,
		-mn.y * s,
		-(mn.z + mx.z) * 0.5 * s
	)

	# 登记材质：GLTF 导入后通常是每个面一个 StandardMaterial3D
	for info in meshes:
		var mi: MeshInstance3D = info["node"]
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mi.get_active_material(surface)
			if mat is StandardMaterial3D and not _mats.has(mat):
				_mats.append(mat)
	# 识别模型自带动画（Walk/DodgeForward/DodgeBack/Slash/JumpStart/JumpAir）
	_setup_animations(model)
	# 把独立武器资产挂到骨骼挂点上（武器与角色分离 → 换武器不用改角色和动画）
	_attach_weapon(model)
	return true


## 递归收集模型下所有网格部件和它们相对根节点的累计变换。
## 注意：只递归 Node3D 子节点——模型里可能混有非 Node3D 的节点
## （例如 AnimationPlayer），强转会导致空引用报错。
func _collect_meshes(node: Node3D, parent_xform: Transform3D, out: Array) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D:
		out.append({ "node": node, "xform": xform })
	for child in node.get_children():
		if child is Node3D:
			_collect_meshes(child as Node3D, xform, out)


## 扫描模型自带的动画资源：找到 AnimationPlayer，并按名字识别 16 段动作。
## 识别规则（大小写无关、忽略下划线）：
##   含 exec            → 处决（Execute：举剑→前刺→上划→收招）
##   含 idle            → 待机呼吸（Idle，循环；站住时播）
##   含 hurt / damage   → 受击（Hurt，单次；倍速按 length ÷ hurt_time 现算）
##   含 death / die     → 倒地（Death，单次；倍速按 length ÷ death_time 现算）
##   含 dodgeforward    → 闪避·前冲（DodgeForward，单次）
##   含 dodgeback       → 闪避·后撤（DodgeBack，单次）
##   含 walk            → 行走（循环）
##   含 slash2/attack2  → 连击②横斩
##   含 slash3/attack3  → 连击③回旋收尾
##   含 slash / attack  → 连击①挥砍
##   含 jumpstart/jumpup→ 起跳
##   含 jumpair/air/fall→ 滞空（循环）
##   含 blockhold       → 举剑待机（循环）
##   含 blockimpact     → 挡下的顿挫
##   含 block / guard   → 举剑进入格挡
## 【判断顺序很重要】BlockHold / BlockImpact 里也都含 "block"，
##   必须**先判 hold / impact 再判裸 block**；顺序反了的话两段新动画都会被
##   识别成"格挡起手"，表现为"举剑动作播一下就卡住、顿挫也不播"。
##   （敌人脚本的 AttackWindup / Attack 是同一个坑，改动画名时两边都要留意）
##   同理 "Execute" 要放在最前面判：它不含任何其它关键词，放前面只是为了
##   以后加"处决收招(ExecuteRecover)"之类的新段时，不会先被别的规则截胡。
## 没识别到的动作，脚本会用"整体姿态"兜底（见 _animate_model / _animate_robot）。
func _setup_animations(model: Node3D) -> void:
	_anim_player = _find_animation_player(model)
	if _anim_player == null:
		return
	_skeleton = _find_skeleton(model)      # 蒙皮骨骼（复位姿势时要用）
	for anim_name in _anim_player.get_animation_list():
		var key := String(anim_name).to_lower().replace("_", "")
		if key.contains("exec"):
			_execute_anim = String(anim_name)
		elif key.contains("idle"):
			_idle_anim = String(anim_name)
			_set_loop(_idle_anim)
		elif key.contains("hurt") or key.contains("damage"):
			_hurt_anim = String(anim_name)
		elif key.contains("death") or key.contains("die"):
			_death_anim = String(anim_name)
		# ⚠ "DodgeBack" 里含 "back"，但**不会**被下面的 walkback/backward 规则吃掉
		#   （那两条判的是 "walkback" 与 "backward"，dodgeback 两者都不含）。
		#   方向判定靠"前"那一条写在前面即可，两条都不含其它已有关键词，放哪都安全。
		elif key.contains("dodgeforward"):
			_dodge_fwd_anim = String(anim_name)
		elif key.contains("dodgeback"):
			_dodge_back_anim = String(anim_name)
		# ⚠⚠ 顺序敏感：这三条**必须放在裸 "walk" 之前**！
		#   下面那条 `key.contains("walk")` 会匹配到 WalkStrafeLeft/WalkBack，
		#   一旦顺序写反，_walk_anim 会被后出现的 WalkStrafeRight 覆盖掉
		#   （自动测试里钉了一条断言专门守这个）。
		elif key.contains("walkstrafeleft") or key.contains("strafeleft"):
			_strafe_left_anim = String(anim_name)
			_set_loop(_strafe_left_anim)
		elif key.contains("walkstraferight") or key.contains("straferight"):
			_strafe_right_anim = String(anim_name)
			_set_loop(_strafe_right_anim)
		elif key.contains("walkback") or key.contains("backward"):
			_walk_back_anim = String(anim_name)
			_set_loop(_walk_back_anim)
		elif key.contains("walk"):
			_walk_anim = String(anim_name)
			_set_loop(_walk_anim)
		# ⚠⚠ 顺序敏感：Slash2 / Slash3 **必须排在裸 "slash" 之前**！！
		#   下面那条 `key.contains("slash")` 会把 Slash2/Slash3 一起吃掉；一旦顺序写反，
		#   遍历到最后一个（Slash3）时把 _slash_anim 覆盖掉 —— 症状是"三段连击全长一个样"，
		#   而且第 1 段的动画名变成了 Slash3（老断言会跟着一起崩）。
		#   与上面 walkstrafeleft / walkback 必须排在 walk 之前是**同一个坑**。
		elif key.contains("slash2") or key.contains("attack2") or key.contains("combo2"):
			_slash2_anim = String(anim_name)
		elif key.contains("slash3") or key.contains("attack3") or key.contains("combo3"):
			_slash3_anim = String(anim_name)
		elif key.contains("slash") or key.contains("attack"):
			_slash_anim = String(anim_name)
		elif key.contains("jumpstart") or key.contains("jumpup"):
			_jump_start_anim = String(anim_name)
		elif key.contains("jumpair") or key.contains("air") or key.contains("fall"):
			_jump_air_anim = String(anim_name)
			_set_loop(_jump_air_anim)
		elif key.contains("blockhold") or key.contains("blockloop"):
			_block_hold_anim = String(anim_name)
			_set_loop(_block_hold_anim)
		elif key.contains("blockimpact") or key.contains("blockhit"):
			_block_impact_anim = String(anim_name)
		elif key.contains("block") or key.contains("guard"):
			_block_anim = String(anim_name)


## 给"循环类"动画打开循环播放。
## 为什么需要：glTF 本身没有循环标记，导入后的 Animation 默认 LOOP_NONE，
## 不打开的话行走/滞空只会播一次就定住。
func _set_loop(anim_name: String) -> void:
	var a := _anim_player.get_animation(anim_name)
	if a != null and a.loop_mode == Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_LINEAR


## 递归查找模型里的 Skeleton3D（蒙皮网格的骨骼）。
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## 把武器资产挂到角色骨骼的挂点上（BoneAttachment3D 挂在 Skeleton3D 下）。
## 挂点自身带一个固定的对齐变换（WEAPON_ALIGN_MODEL），
## 让"武器资产约定(原点=握把中心、刀身 -Z)"落到"手握持、刀身朝上"的正确姿态；
## 之后挥砍/翻滚等动画驱动手臂 → 武器自动跟随，无需为每把武器重做动画。
func _attach_weapon(model: Node3D) -> void:
	if _skeleton == null or PLAYER_WEAPON == null:
		return
	var bone_idx := _skeleton.find_bone(WEAPON_SOCKET)
	if bone_idx < 0:
		push_warning("模型里没有挂点骨骼 %s，武器未装备" % WEAPON_SOCKET)
		return
	_weapon_socket = BoneAttachment3D.new()
	_weapon_socket.name = "WeaponSocket"
	_skeleton.add_child(_weapon_socket)
	_weapon_socket.bone_name = WEAPON_SOCKET
	# 注意：BoneAttachment3D 自己的 transform 每帧都会被"骨骼姿势"覆盖（引擎行为），
	# 所以对齐偏移不能设在挂点上，而要设在**武器子节点**上（见 equip_weapon）。
	_weapon_align_local = WEAPON_ALIGN_LOCAL
	equip_weapon(PLAYER_WEAPON)


## 换武器：传入武器场景（.glb/.tscn）即可；传 null = 徒手（收刀）。
## 约定：武器资产原点 = 握把中心、刀身沿局部 -Z（与 sword_01 一致），
##       对齐由挂点自带的 WEAPON_ALIGN_MODEL 负责，换武器不需要改角色或动画。
func equip_weapon(weapon_scene: PackedScene) -> void:
	if _weapon_socket == null:
		return
	for child in _weapon_socket.get_children():
		child.queue_free()
	_weapon = null
	if weapon_scene == null:
		return
	_weapon = weapon_scene.instantiate() as Node3D
	_weapon.transform = _weapon_align_local    # 对齐偏移（见 _attach_weapon 的说明）
	_weapon_socket.add_child(_weapon)


## 停掉当前动画，并把所有骨骼复位到"绑定姿势"(rest pose)。
## 【为什么必须做】骨骼动画一旦停播，骨骼会**冻结在停播那一帧的姿势**：
##   - 走到一半停下 → 僵在迈步中途（双腿分开）
##   - 落地时收掉 JumpAir → 僵在蜷腿姿势
##   - 受击/死亡时 → 还保留着上一段动作的姿势
## 【现在还剩哪些地方用它】Idle / Hurt / Death 补齐后，站住、受击、倒地都有专属动画了；
## 复位只剩三处职责：落地收掉 JumpAir、翻滚结束复位根位移、以及**老资产缺动画时兜底**
## （那种情况下才由脚本叠加整体姿态：后仰 / 前栽 / 落地压缩）。
func _anim_to_rest() -> void:
	if _anim_player != null and _anim_player.is_playing():
		_anim_player.stop()
		_anim_player.speed_scale = 1.0
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		var rest: Transform3D = _skeleton.get_bone_rest(i)
		_skeleton.set_bone_pose_position(i, rest.origin)
		_skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		_skeleton.set_bone_pose_scale(i, rest.basis.get_scale())


## ⚠ 这里**曾经**有 _setup_roll_root_motion()：RollLeap 动画自带 1m 根位移，
##   需要把它找出来、在翻滚结束时过继给角色本体（否则模型永久领先碰撞体 1 米）。
##   2026-09-20 翻滚被闪避取代，而两段闪避动画**不含净位移**（出片脚本里 root.location.x/y 恒 0），
##   于是这套机制再无触发场景 —— 直接删掉，而不是留一段"永远不会跑"的代码。
##   将来若某段新动画又带了根位移，再按老做法补回来即可（思路见 git 历史）。


## 递归查找第一个 AnimationPlayer。
## 模型层级可能有空节点（如 EMT-KnightRoot → EMT-VisualPivot），所以要递归。
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## 返回 AABB 的 8 个角点（显式类型，供循环直接推断）。
func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	var out: Array[Vector3] = [
		p, p + Vector3(s.x, 0, 0), p + Vector3(0, s.y, 0), p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, s.y, s.z),
		p + s
	]
	return out


# ------------------------------------------------------------------
# 原语小蓝人外观（兜底方案）
# ------------------------------------------------------------------

## 拼接身体：腰以下部件都挂在 VisualPivot 下；
## 手臂/腿是"关节节点"，网格作为其子节点偏移，这样旋转关节=摆肢体。
func _build_robot_visuals() -> void:
	# ---- 腿（两根胶囊，挂在髋部高度）----
	var leg_mat := _make_mat(Color(0.16, 0.36, 0.68), 0.35, 0.55)  # 深蓝
	_leg_r = _limb(Vector3(0.17, 0.62, 0.0))    # 右腿关节
	_leg_l = _limb(Vector3(-0.17, 0.62, 0.0))   # 左腿关节
	_pivot.add_child(_leg_r)
	_pivot.add_child(_leg_l)
	_add_capsule_mesh(_leg_r, Vector3(0.0, -0.31, 0.0), 0.11, 0.62, leg_mat)

	# ---- 躯干（主色胶囊）----
	var torso_mat := _make_mat(Color(0.24, 0.53, 0.92), 0.5, 0.45)  # 亮蓝
	_add_capsule_mesh(_pivot, Vector3(0.0, 0.98, 0.0), 0.34, 0.85, torso_mat)

	# ---- 头 + 深色面罩 ----
	var head_mat := _make_mat(Color(0.86, 0.89, 0.93), 0.15, 0.5)   # 浅灰(像头盔)
	var head := _add_sphere_mesh(_pivot, Vector3(0.0, 1.56, 0.0), 0.24, head_mat)
	var visor_mat := _make_mat(Color(0.05, 0.1, 0.16), 0.0, 0.2)    # 近黑
	_add_box_mesh(head, Vector3(0.0, 0.02, -0.12), Vector3(0.3, 0.09, 0.08), visor_mat)  # 面罩在脸前

	# ---- 手臂（肩关节节点，动画靠转它们）----
	var arm_mat := _make_mat(Color(0.30, 0.58, 0.95), 0.45, 0.5)    # 中蓝
	_shoulder_r = _limb(Vector3(0.42, 1.34, 0.0))
	_shoulder_l = _limb(Vector3(-0.42, 1.34, 0.0))
	_pivot.add_child(_shoulder_r)
	_pivot.add_child(_shoulder_l)
	_add_capsule_mesh(_shoulder_r, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)
	_add_capsule_mesh(_shoulder_l, Vector3(0.0, -0.34, 0.0), 0.09, 0.68, arm_mat)

	# ---- 武器：剑（挂在右肩下，挥剑=甩动右肩）----
	var sword_mat := _make_mat(Color(0.85, 0.87, 0.92), 0.9, 0.22)  # 银白金属
	var grip_mat := _make_mat(Color(0.45, 0.3, 0.18), 0.1, 0.7)     # 棕色握柄
	_add_box_mesh(_shoulder_r, Vector3(0.03, -0.66, 0.02), Vector3(0.07, 0.5, 0.04), sword_mat)
	_add_box_mesh(_shoulder_r, Vector3(0.03, -0.28, 0.02), Vector3(0.09, 0.16, 0.07), grip_mat)


## 攻击命中盒：面前的长方体感应区(平时关闭，判定帧才开)。两种外观共用。
func _create_attack_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.monitoring = false   # 默认不检测
	_hitbox.monitorable = false  # 也不让别人检测到自己
	_pivot.add_child(_hitbox)
	var shape := CollisionShape3D.new()
	shape.name = "HitboxShape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.8)            # 宽1.2 高1.0 纵深1.8米
	shape.shape = box
	shape.position = Vector3(0.0, 1.05, -1.25)   # 放在胸口高度、面前1.25米
	_hitbox.add_child(shape)


## 造一个"关节节点"：只是带位置的 Node3D。
func _limb(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	return n


## 建材质并登记到 _mats（闪白时统一处理）。metallic=金属感 0~1，roughness=粗糙度 0~1。
func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	_mats.append(mat)
	return mat


## 在 parent 下造一根胶囊网格（radius=半径，height=总高）。
func _add_capsule_mesh(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16   # 圆周分段数（越大越圆，越小越省）
	mesh.rings = 6              # 纵向分段数
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造一个球网格。
func _add_sphere_mesh(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下造一个长方体网格。
func _add_box_mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------
# 受击闪白（自发光代替换色，简单有效）
# ------------------------------------------------------------------

## 把所有部件材质打开自发光并设强度 → 角色瞬间发白（受击反馈）。
## 对外部模型同样生效（GLB 材质也登记进了 _mats）。
func _flash(intensity: float) -> void:
	for mat in _mats:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 1.0)
		mat.emission_energy_multiplier = intensity


## 每帧衰减自发光强度，归零后关掉（实现"闪一下"的效果）。
func _decay_flash(delta: float) -> void:
	var alive := false
	for mat in _mats:
		if mat.emission_energy_multiplier > 0.02:
			mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, 0.0, 1.0 - exp(-14.0 * delta))
			alive = true
	if not alive:
		for mat in _mats:
			mat.emission_enabled = false


# ------------------------------------------------------------------
# 姿态动画（_process 每帧按状态摆姿势）
# 原理：旋转各"关节节点"或用正弦波做循环动作；所有 lerp 都带
# 1-exp(-k*dt) 平滑，切换自然不跳变。
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_decay_flash(delta)
	if _pivot == null:
		return
	if _use_model:
		_animate_model(delta)      # 骑士模型：整体姿态
	else:
		_animate_robot(delta)      # 原语小蓝人：肢体级动画
	_apply_land_squash()           # 落地压缩统一在这里生效(避免各状态残留缩放)


## 落地压缩（纯视觉）：落地后 0.18s 内把模型压扁一点（x/z 略宽、y 略矮），
## 让"落地"这一下有重量感。每帧统一设置 scale，所以不会有残留。
## 注：命中盒是 VisualPivot 的子节点，缩放会带来 ±10% 的判定盒变化(0.18s 内，可忽略)。
func _apply_land_squash() -> void:
	if _squash > 0.0:
		var k := _squash / maxf(0.01, land_squash_time)      # 1 → 0
		_pivot.scale = Vector3(1.0 + 0.10 * k, 1.0 - 0.16 * k, 1.0 + 0.10 * k)
	else:
		_pivot.scale = Vector3.ONE


## 原语小蓝人的肢体动画（甩腿/挥剑/收臂等，见状态枚举）。
func _animate_robot(delta: float) -> void:
	match state:
		State.MOVE:
			# 走路/待机：腿摆动 + 身体起伏 + 手臂闲逛轻摆
			var spd := Vector2(velocity.x, velocity.z).length()  # 水平速度大小
			var moving := spd > 0.5
			var t := clampf(spd / move_speed, 0.0, 1.0)          # 0(站)~1(全速)
			var swing := sin(_bob_phase) * 0.7 * t if moving else 0.0  # 摆腿幅度
			if _leg_r != null:
				_leg_r.rotation.x = swing
				_leg_l.rotation.x = -swing                        # 两腿反相
			var bob := sin(_bob_phase * 2.0) * 0.03 * t if moving else 0.0  # 跑步起伏
			_pivot.position.y = bob
			var sway := sin(Time.get_ticks_msec() * 0.003) * 0.08  # 手臂缓慢摇摆
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.15 + sway, 1.0 - exp(-12.0 * delta))
				_shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, -0.08, 1.0 - exp(-12.0 * delta))
			if _shoulder_l != null:
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.15 - sway, 1.0 - exp(-12.0 * delta))
				_shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, 0.08, 1.0 - exp(-12.0 * delta))
		State.DODGE:
			# 闪避(兜底，无动画)：用整体前倾/后仰 + 收臂表达方向 ——
			#   前冲 = 压低前倾扑出去；后撤 = 挺身后仰往后弹。
			# 【为什么不做整身翻滚】翻滚是"绕局部 X 转一圈"的兜底老做法，但闪避是**方向性**动作：
			#   转一圈既看不出"前"也看不出"后"，反而把方向信息抹掉了。
			var lean_tgt := -0.30 if _dodge_is_forward else 0.22
			# 用一条"先冲到目标、后半程回落"的曲线代替匀速：起手最猛、收招回正
			var dp := clampf(_state_time / _dodge_time, 0.0, 1.0)
			var shape := sin(dp * PI)                     # 0 → 1 → 0，两端都回到中立
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, lean_tgt * shape,
				1.0 - exp(-14.0 * delta))
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -0.55, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.55, 1.0 - exp(-14.0 * delta))
		State.BLOCK:
			# 格挡(兜底)：双臂抬到胸前交叉护住、身体微蹲
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-14.0 * delta))
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, -1.35, 1.0 - exp(-16.0 * delta))
				_shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, -0.35, 1.0 - exp(-16.0 * delta))
			if _shoulder_l != null:
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -1.25, 1.0 - exp(-16.0 * delta))
				_shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, 0.40, 1.0 - exp(-16.0 * delta))
		State.EXECUTE:
			# 处决(兜底，无动画)：镜像 Execute 动画的三拍 —— 举剑 → 前刺 → 上撩 → 收招。
			# 兜底只有一根右肩骨可用，所以用 shoulder.x 表达"抬起/前送"、
			# shoulder.z 表达"向上撩开"，够读出三段节奏即可（真正的姿态见 Execute 动画）。
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
			var ex_hit := execute_hit_time
			var ex_end := execute_time
			if _shoulder_r != null:
				if _state_time < ex_hit:
					# ① 举剑：右肩抬到最高、略向后（蓄力）
					var k := _state_time / maxf(0.01, ex_hit)
					_shoulder_r.rotation.x = lerpf(-0.15, 2.2, k * k)
					_shoulder_r.rotation.z = lerpf(-0.35, -0.1, k)
				elif _state_time < ex_hit + 0.22:
					# ② 前刺：手臂从头顶向前送出（判定时刻就在这一段开头）
					var k := clampf((_state_time - ex_hit) / 0.22, 0.0, 1.0)
					_shoulder_r.rotation.x = lerpf(2.2, 1.05, sqrt(k))
					_shoulder_r.rotation.z = lerpf(-0.1, 0.5, sqrt(k))
				else:
					# ③ 上撩(先抬) + 收招(回位)
					var k := clampf((_state_time - ex_hit - 0.22) / maxf(0.01, ex_end - ex_hit - 0.22), 0.0, 1.0)
					if k < 0.35:
						var k2 := k / 0.35
						_shoulder_r.rotation.x = lerpf(1.05, 1.75, sqrt(k2))
						_shoulder_r.rotation.z = lerpf(0.5, 0.95, sqrt(k2))
					else:
						var k2 := (k - 0.35) / 0.65
						_shoulder_r.rotation.x = lerpf(1.75, -0.15, k2 * k2)
						_shoulder_r.rotation.z = lerpf(0.95, -0.35, k2 * k2)
			if _shoulder_l != null:
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.5, 1.0 - exp(-12.0 * delta))
		State.ATTACK:
			# 挥剑三段式(与判定窗对应)：举剑(0~0.13s)→劈下(0.13~0.3s，开判定)→收招(0.3~0.5s)
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			var windup := attack_active_start   # =0.13 举剑结束时刻
			var slash := attack_active_end      # =0.3  判定结束时刻
			if _state_time < windup:
				# ① 举剑过顶(右肩向后上方转) —— 起手让玩家看清
				var k := _state_time / windup
				_shoulder_r.rotation.x = lerpf(-0.15, 1.9, k * k)   # 缓入(k²)
			elif _state_time < slash:
				# ② 向前下方劈砍 —— 判定帧开启，命中盒工作
				var k := (_state_time - windup) / (slash - windup)
				_set_hitbox_active(true)
				_shoulder_r.rotation.x = lerpf(1.9, 0.85, sqrt(k))  # 快劈(sqrt 先快后慢)
			else:
				# ③ 收招回位
				_set_hitbox_active(false)
				var k := (_state_time - slash) / maxf(0.01, attack_total - slash)
				_shoulder_r.rotation.x = lerpf(0.85, -0.15, k * k)
			_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, -0.5, 1.0 - exp(-12.0 * delta))  # 左手护身
		State.HURT:
			# 受击：身体站直复位、双手向后张开(挨打姿势)
			_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
			_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, 0.9, 1.0 - exp(-10.0 * delta))
		State.JUMP_PREP:
			# 原语小蓝人：蓄力段下蹲(整体压低 + 屈腿)
			# ⚠️ 默认进不来（jump_prep_time = 0）；把该参数调回 >0 才会用上这段兜底姿态。
			_pivot.position.y = lerpf(_pivot.position.y, -0.16, 1.0 - exp(-14.0 * delta))
			if _leg_r != null:
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.7, 1.0 - exp(-14.0 * delta))
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.7, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, 0.5, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, 0.5, 1.0 - exp(-14.0 * delta))
		State.JUMP:
			# 原语小蓝人：起跳屈腿收臂，下落时伸腿准备着地
			var rising := velocity.y > 0.0
			var leg_tuck := 0.9 if rising else 0.25
			if _leg_r != null:
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, leg_tuck, 1.0 - exp(-14.0 * delta))
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, leg_tuck, 1.0 - exp(-14.0 * delta))
			if _shoulder_r != null:
				var arm := -0.6 if rising else -0.2
				_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, arm, 1.0 - exp(-14.0 * delta))
				_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, arm, 1.0 - exp(-14.0 * delta))
			_pivot.position.y = 0.0
		State.DEAD:
			# 死亡(原语兜底)：death_time 秒内向前栽倒(-90°)，略微抬离地面避免插进地板
			_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / death_time, 0.0, 1.0)
			_pivot.position.y = lerpf(_pivot.position.y, 0.08, 1.0 - exp(-6.0 * delta))


## 格挡动画的两段调度：进入动作(Block) 播完 → 切到循环(BlockHold)。
## 【为什么要分两段而不是只播一段】
##   只播 BlockHold：一按下就直接是"举着剑"的架势，缺了举剑的过程，很突。
##   只播 Block：0.25s 放完就停在最后一帧，一直按着右键会像卡住。
##   所以按 _state_time 决定：还在 Block 的长度内 = 播起手；之后 = 循环举剑待机。
## 【为什么用 current_animation 判断而不是每帧 play】每帧 play 会把动画重置到第 0 帧，
##   循环动画会永远停在第一帧（原地抽搐）。同名就不重启，只改 speed_scale。
func _block_play() -> void:
	if _anim_player == null:
		return
	if _block_hold_anim != "":
		# 起手动作的"游戏内时长" = 动画长度 ÷ 播放倍速（倍速改了这里也要跟着算）
		var enter_len := 0.0
		if _block_anim != "":
			var a := _anim_player.get_animation(_block_anim)
			if a != null:
				enter_len = a.length / maxf(0.05, block_anim_speed)
		if _state_time < enter_len:
			if _anim_player.current_animation != _block_anim:
				_anim_player.stop()
				_anim_player.play(_block_anim, -1.0, block_anim_speed)
			else:
				_anim_player.speed_scale = block_anim_speed
		else:
			if _anim_player.current_animation != _block_hold_anim:
				_anim_player.play(_block_hold_anim, 0.1, block_anim_speed)
			else:
				_anim_player.speed_scale = block_anim_speed
	elif _block_anim != "":
		# 只有起手动作、没有循环动作：播完就停在最后一帧（举着剑），也不再重启
		if _anim_player.current_animation != _block_anim:
			_anim_player.play(_block_anim, -1.0, block_anim_speed)


## 骑士模型的姿态动画。
## 优先用模型自带的骨骼动画（Walk/闪避两段/Slash/JumpStart/JumpAir + Block 三段）；
## 没有对应动画的动作，才退回"整体姿态"（起伏/前倾/后仰/倒地）。
func _animate_model(delta: float) -> void:
	match state:
		State.MOVE:
			if _anim_player != null and _walk_anim != "":
				# 有行走动画（原地循环）：按"当前速度 ÷ 自然步速"调播放倍速；
				# 站住就切 Idle 呼吸循环（没有 Idle 的老资产才复位成绑定姿势）。
				# ★ 播哪一段由 _locomotion_clip() 决定：自由模式=Walk，锁定模式=侧移/后撤三段。
				#   换段时的处理与原来完全一致（换段才重 play，同段只调 speed_scale），
				#   这样切段不会打断循环、也不会让脚步错位。
				var spd := Vector2(velocity.x, velocity.z).length()
				if spd > 0.5:
					var clip := _locomotion_clip()
					var natural := _natural_speed_for(clip)
					var want := clampf(spd / maxf(0.2, natural), 0.5, walk_max_speed_scale)
					# ⚠⚠ 这里有个**既有的量纲坑**（实测确认，暂不改以免动到已调好的观感）：
					#   Godot 里 speed_scale(属性) 与 play(custom_speed) 是**相乘**的两层
					#   （探针：属性 3.0 × play 2.0 → get_playing_speed() = 6.0）。
					#   本分支第一帧 play(..., want) 设了自定义速度，之后每帧又赋 speed_scale = want，
					#   所以**实际倍速 = want²**（want 上限 2.0 → 实际 4.0 倍）。
					#   【为什么不顺手改成单层】Walk 的自然步速只有 1.0 m/s、move_speed 是 6.2，
					#   真按 2.0 封顶的话跑起来脚会明显跟不上；现在等于"偷偷放到 4 倍"，观感反而更对。
					#   想回归文档语义（实际倍速 == want）就删掉下面那行 speed_scale 赋值。
					#   ★ 侧移三段沿用同一套换算，"实际倍速 = want²"对它们同样成立。
					if _anim_player.current_animation != clip:
						_anim_player.stop()
						_anim_player.play(clip, -1.0, want)
					else:
						_anim_player.speed_scale = want
				elif _idle_anim != "":
					# 站住 → Idle。用 0.15s 混入而不是 stop() 硬切，走↔站之间不会"啪"地跳一下
					if _anim_player.current_animation != _idle_anim:
						_anim_player.play(_idle_anim, 0.15, 1.0)
					else:
						_anim_player.speed_scale = 1.0
				elif _anim_player.is_playing():
					_anim_to_rest()      # 老资产没有 Idle：只能收掉行走动画并复位骨骼
				# 骨骼动画已经在动，整体节点不要再叠加起伏/前倾（会与动画打架）
				_pivot.position.y = lerpf(_pivot.position.y, 0.0, 1.0 - exp(-10.0 * delta))
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
			else:
				var spd_f := Vector2(velocity.x, velocity.z).length()
				var t := clampf(spd_f / move_speed, 0.0, 1.0)
				# 跑步起伏
				_pivot.position.y = sin(_bob_phase * 2.0) * 0.04 * t
				# 跑步前倾(rotation.x 转负 = 顶部朝前压)；静止回正
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.12 * t, 1.0 - exp(-8.0 * delta))
		State.DODGE:
			# 模型自带闪避动画时：整段姿态完全交给动画（前冲/后撤的压低、蹬地、收腿都在骨骼里），
			# 整体节点只把兜底用的旋转缓慢归零，避免和动画叠加成"双重前倾"。
			if _dodge_anim != "":
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-20.0 * delta))
				_pivot.position.y = 0.0
			else:
				# 兜底(静态模型)：整体前倾扑出 / 后仰弹开（方向性动作，见 _animate_robot 的说明）
				var dp := clampf(_state_time / _dodge_time, 0.0, 1.0)
				var lean := (-0.30 if _dodge_is_forward else 0.22) * sin(dp * PI)
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, lean, 1.0 - exp(-14.0 * delta))
				_pivot.position.y = 0.0
		State.BLOCK:
			# 格挡：姿态交给骨骼动画（Block 起手 → BlockHold 循环 → BlockImpact 顿挫），
			# 整体节点不叠加任何姿态（会与动画打架），只把兜底旋转缓慢归零。
			if _anim_player != null:
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
			else:
				# 兜底(静态模型)：整身前倾一点点当作"举剑压低重心"
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.12, 1.0 - exp(-14.0 * delta))
			_pivot.position.y = 0.0
			if _block_impact_time <= 0.0:
				_block_play()          # 顿挫动画播放期间不抢控制权，等它演完再接着调度
		State.EXECUTE:
			# 处决：姿态交给专属的 Execute 动画（举剑→前刺→上划→收招），
			# 整体节点只做两件事：
			#   ① 把兜底旋转归零，别和动画打架（压身/打开都由动画自己表达）；
			#   ② 万一模型里既没有 Execute 也没有 Slash（静态模型），
			#      才用整体姿态兜底走一遍"举剑后仰 → 前刺压上 → 上撩打开"。
			_pivot.position.y = 0.0
			if _anim_player != null and (_execute_anim != "" or _slash_anim != ""):
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			else:
				var lean := 0.22                          # ① 举剑后仰
				if _state_time >= execute_hit_time * 0.55:
					lean = -0.50                          # ② 前刺：压上去
				if _state_time >= execute_hit_time + 0.22:
					lean = 0.18                           # ③ 上撩：胸腔打开
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, lean, 1.0 - exp(-14.0 * delta))
		State.ATTACK:
			# 命中盒时间窗与"有没有动画"无关，每帧都要更新。
			# ★ 窗与段长都读**当前段**：三段各有自己的起手长度，用第 1 段的窗去套第 2/3 段
			#   会让第 3 段的判定在剑还没扫到时就关掉（combo3 的窗是 0.16~0.42，比 0.17~0.28 宽）。
			var step_total := _combo_total(_combo_step)
			var windup := _combo_active_start(_combo_step)
			var slash_end := _combo_active_end(_combo_step)
			_set_hitbox_active(_state_time >= windup and _state_time < slash_end)
			if _anim_player != null and _combo_anim(_combo_step) != "":
				# 有挥砍动画：姿态交给动画，只把兜底用的整体前倾归零
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			else:
				# 兜底：整体突刺表达挥砍（起手后仰 → 判定帧前倾刺出 → 收招回正）
				if _state_time < windup:
					var k := _state_time / maxf(0.01, windup)
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.18, k * k)
				elif _state_time < slash_end:
					var k := (_state_time - windup) / maxf(0.01, slash_end - windup)
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.5, sqrt(k))
				else:
					var k := (_state_time - slash_end) / maxf(0.01, step_total - slash_end)
					_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, k * k)
			_pivot.position.y = 0.0
		State.JUMP_PREP:
			# 蓄力段：姿态完全交给 JumpStart 动画（蹲身→蹬地），整体节点不要再叠加姿态
			# ⚠️ 默认进不来（起跳动画已取消、jump_prep_time = 0）；调回 0.18 即恢复。
			_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			_pivot.position.y = 0.0
		State.JUMP:
			if _anim_player != null and _jump_air_anim != "":
				# 离地即播滞空循环（起跳动画已取消，这里不会再回头播 JumpStart）
				if _anim_player.current_animation != _jump_air_anim:
					_anim_player.speed_scale = 1.0
					_anim_player.play(_jump_air_anim, -1.0, 1.0)
				# 有跳跃动画时不再叠加整体前倾/后仰
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
				_pivot.position.y = 0.0
			else:
				# 兜底(无跳跃动画)：上升身体前收、下落微后仰准备着地
				var lean := -0.20 if velocity.y > 0.0 else 0.12
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, lean, 1.0 - exp(-9.0 * delta))
				_pivot.position.y = 0.0
		State.HURT:
			# 有 Hurt 动画：姿态**全交给动画**（进状态时就播好了，见 _enter_hurt），
			#   整体节点只把兜底旋转归零 —— 再叠加整体后仰就成了"后仰两次"。
			_pivot.position.y = 0.0
			if _anim_player != null and _hurt_anim != "":
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
			else:
				# 兜底(老资产没有 Hurt)：先收掉其它动画并复位骨骼，再叠加整体后仰
				if _anim_player != null and _anim_player.is_playing():
					_anim_to_rest()
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.35, 1.0 - exp(-10.0 * delta))
		State.DEAD:
			# 有 Death 动画：整套倒地由动画演（进 DEAD 时播好，单次播完冻在末帧），
			#   整体节点归零即可（再转一次 = 尸体翻两圈）。
			if _anim_player != null and _death_anim != "":
				_pivot.rotation.x = lerp_angle(_pivot.rotation.x, 0.0, 1.0 - exp(-20.0 * delta))
				_pivot.position.y = 0.0
			else:
				# 兜底(老资产没有 Death)：先复位骨骼，再整体前栽
				if _anim_player != null and _anim_player.is_playing():
					_anim_to_rest()
				_pivot.rotation.x = -PI / 2.0 * clampf(_state_time / death_time, 0.0, 1.0)
				_pivot.position.y = lerpf(_pivot.position.y, 0.08, 1.0 - exp(-6.0 * delta))
