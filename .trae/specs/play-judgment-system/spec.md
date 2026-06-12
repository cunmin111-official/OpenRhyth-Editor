# Play Page Judgment System Spec

## Why

当前游玩页面（play_page.gd）缺少真正的判定系统——连击数和分数只是简单的"已过音符计数"，没有基于输入时机的判定、没有准度计算、也没有判定特效。需要实现完整的 Tap/Hold/Drag 判定逻辑、准度/分数计算公式和判定特效渲染，使游玩模块具备可玩的节奏游戏核心体验。

## What Changes

- **判定引擎**：新增基于输入时机的实时判定模块，覆盖 Tap/Hold/Drag 三种音符类型，按"时间早的优先"规则处理多音符竞争
- **Hold 中间松手检测**：Hold 音符开始后若键盘/触摸全部释放则立刻改判为 Miss
- **准度/分数/连击替换**：用真实公式替换当前 placeholder
- **判定特效**：在 3D 世界空间使用 billboard Sprite3D 渲染 perfect1/perfect/good 图片特效，渐隐后移除，Miss 时不渲染
- **音符生命周期管理**：判定后及时隐藏渲染节点，Hold 分阶段隐藏

## Impact

- Affected specs: play_page.gd (~860 lines → ~1000+ lines)
- Affected code:
  - `scene/play/play_page.gd` — 核心修改文件
  - `res/judgeEffects/` — 使用已有图片资源 perfect1.png / perfect.png / good.png
  - 移除"『洛神』"autoplay 相关引用（该功能只属于 preview_page）

## ADDED Requirements

### Requirement: Judgment Engine

The system SHALL provide real-time judgment for Tap, Hold, and Drag notes based on input timing.

#### Scenario: Tap Judgment
- **GIVEN** a Tap note with a target time T
- **WHEN** an input event (key press or touch) occurs at time T - 200ms ≤ input_time ≤ T + 200ms
- **THEN** the system SHALL assign a grade based on the time difference:
  - |diff| ≤ 50ms → "perfect1"
  - |diff| ≤ 100ms → "perfect"
  - |diff| ≤ 200ms → "good"
  - input_time < T - 200ms → ignored (no bad judgment)
  - input_time > T + 200ms → "miss"

#### Scenario: Hold Judgment
- **GIVEN** a Hold note with start time S and end time E
- **WHEN** an input event occurs at S - 200ms ≤ input_time ≤ S + 200ms
- **THEN** the grade is determined by first-input timing per Tap rules
- **AND** the initial tap starts the hold tracking
- **AND** scoring/combo is **deferred until E**
- **WHEN** all held keys/touches are released before E (is_input_active becomes false while hold is active)
- **THEN** immediately rejudge as "miss"
- **AND** if any input remains until E, the initial grade stands and scoring/combo is applied at E

#### Scenario: Drag Judgment
- **GIVEN** a Drag note with target time T
- **WHEN** an input event occurs at T ≤ input_time ≤ T + 50ms
- **THEN** judge as "perfect1"
- **WHEN** no input occurs within [T, T + 50ms]
- **THEN** at T + 50ms (in _process), auto-judge as "miss"

#### Scenario: Multiple Notes in Same Window
- **GIVEN** multiple notes with overlapping judgment windows
- **WHEN** an input event triggers judgment
- **THEN** the note with the earliest target time is judged first
- **AND** the input is consumed (cannot judge multiple notes from one input)

#### Scenario: Input Sources
- **GIVEN** the play page is active
- **WHEN** a keyboard key (excluding ESC) is pressed or released
- **OR** a screen touch occurs
- **THEN** the input state (`is_input_active`) SHALL be true when any key is held or any touch is active
- **AND** false only when no keys are held AND no touches are active

### Requirement: Score & Accuracy

The system SHALL calculate and display accuracy, score, and combo in real time.

#### Scenario: Accuracy Calculation
- **GIVEN** judgment results for all notes
- **WHEN** accuracy is calculated
- **THEN** use formula: $Acc = \frac{(perfect1\_count + perfect\_count) + 0.6 \times good\_count}{total\_notes} \times 100\%$
- **AND** round down to 2 decimal places
- **AND** display replacing the current "准度100.00%" placeholder

#### Scenario: Score Calculation
- **GIVEN** accuracy and combo results
- **WHEN** score is calculated
- **THEN** use formula: $Score = 900{,}000 \times Acc + 100{,}000 \times \frac{MaxCombo}{NotesCNT} + Perfect1Count$
- **AND** display as 7-digit integer replacing the current placeholder

#### Scenario: Combo
- **GIVEN** a judgment result
- **WHEN** grade is perfect1, perfect, or good
- **THEN** combo counter increments by 1
- **WHEN** grade is miss
- **THEN** combo resets to 0

### Requirement: Judge Effect Display

The system SHALL display visual effects at judgment time using Sprite3D.

#### Scenario: Show Judge Effect
- **GIVEN** a judgment occurs with grade perfect1, perfect, or good
- **WHEN** the judgment is made
- **THEN** a **Sprite3D** with `billboard = BaseMaterial3D.BILLBOARD_FIXED_Y` (始终面向屏幕) is created at the note's 3D world position
- **AND** the sprite is **NOT** parented to the judge line (added directly to `world_3d`), so it is unaffected by judge line transforms
- **AND** the corresponding texture is loaded from `res/judgeEffects/` (perfect1.png / perfect.png / good.png)
- **AND** the sprite fades out over ~0.5 seconds and is then removed (queue_free)
- **WHEN** grade is miss
- **THEN** no effect is rendered

### Requirement: Note Cleanup After Judgment

The system SHALL clean up rendered notes after they are judged.

#### Scenario: Tap Note Cleanup
- **GIVEN** a Tap note that has been judged (any grade)
- **WHEN** after judgment
- **THEN** the note's sprite is hidden (visible = false)

#### Scenario: Hold Note Partial Cleanup
- **GIVEN** a Hold note being tracked
- **WHEN** head passes the judgment line (time > start time)
- **THEN** the head sprite is hidden (body continues to display remaining portion)
- **WHEN** end time passes (time > end time), regardless of judgment
- **THEN** the body and head sprites are hidden

#### Scenario: Drag Note Cleanup
- **GIVEN** a Drag note that has been judged
- **WHEN** after judgment
- **THEN** the note's sprite is hidden

## MODIFIED Requirements

### Requirement: Process Loop (modified)

将 `_process` 中的简单 pass_count 逻辑替换为：
1. 每帧调用判定引擎轮询 Drag 的 miss 超时 和 Hold 结束结算
2. 更新准度/分数/连击显示
3. 更新判定特效（渐隐动画）
4. 保持现有的 shader_effects 和 judge_lines 更新

### Requirement: Build 3D Scene (modified)

为每个非假音符（isFake=0）附加一个 `judged` 标记（初始 false），用于跟踪判定状态。

## REMOVED Requirements

### Requirement: Placeholder Score/Combo

**Reason**: 被真实判定系统替代
**Migration**: 删除 `_process` 中的 passed_count 循环和占位 score/combo 逻辑，替换为真实计算公式

### Requirement: "『洛神』" Autoplay Text

**Reason**: autoplay 提示属于预览页面（preview_page），与游玩页面（play_page）无关。判定效果直接使用 judgeEffects 中的图片资源作为 UI。
