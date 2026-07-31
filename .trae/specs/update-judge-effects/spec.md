# 更新判定特效 Spec

## Why
当前判定特效为单帧贴图（perfect1/perfect/good.png）+ 0.5s 渐隐，表现单一。项目已有 judge0~judge5.png 逐帧素材，需要通过逐帧动画 + 放大淡出 + 分级颜色渲染提升打击反馈质感。

## What Changes
- 新增逐帧判定特效：使用 judge0~judge5.png（6 帧），每帧约 20ms 切换，播放期间叠加放大-淡出效果。
- 分级颜色渲染：perfect1 → #1685A9，perfect → #197855，good → #D12920，miss → 不显示；渲染时保留原图灰度（用原图亮度 × 分级颜色着色）。
- 保留原动画（perfect1/perfect/good.png 单帧渐隐），可在设置中选择保留或移除。
- 新增"判定特效"设置区：选择特效模式（逐帧动画 / 原动画）、调整大小曲线参数，并显示大小曲线预览图。
- play_page.gd 与 preview_page.gd 共用同一套特效渲染逻辑与设置。

## Impact
- 受影响 Spec：无既有 spec。
- 受影响代码：
  - `scene/play/play_page.gd`：`spawn_judge_effect`、`_new_effect_sprite`、`fade_hold_effect`、特效对象池
  - `scene/preview/preview_page.gd`：`spawn_judge_effect`、`fade_hold_effect`、`_trigger_note_effect`
  - `scene/Global.gd`：新增判定特效设置 getter/setter 与默认值
  - `scene/settings/settings_page.gd`：游玩 Tab 新增"判定特效"设置区与曲线预览
  - `res/judgeEffects/judge0~judge5.png`：逐帧动画素材（未导入，运行时由 Godot 自动导入）

## ADDED Requirements

### Requirement: 逐帧判定特效
系统 SHALL 使用 judge0~judge5.png 作为 6 帧动画渲染判定特效。
- 每帧间隔 SHALL 为 20ms（总共约 120ms）。
- 动画播放期间 SHALL 叠加"放大 + 淡出"效果（大小按设置曲线变化，透明度由不透明渐变到 0）。
- 分级颜色渲染：
  - perfect1 → #1685A9
  - perfect → #197855
  - good → #D12920
  - miss → 不显示任何特效
- 渲染时 SHALL 保留原图灰度：取帧图像的亮度（luminance），再乘以分级颜色，得到最终显示颜色。

#### Scenario: Tap 判定为 Perfect1
- **WHEN** 一个 tap 音符被判定为 perfect1
- **THEN** 在判定位置播放 judge0~judge5 逐帧动画，每帧 20ms，颜色为 #1685A9，期间放大并淡出

#### Scenario: 判定为 Miss
- **WHEN** 音符被判定为 miss
- **THEN** 不显示任何判定特效

### Requirement: 原动画模式
系统 SHALL 保留原动画（perfect1/perfect/good.png 单帧渐隐特效），并可在设置中选择"保留"或"移除"。
- 默认 SHALL 使用新逐帧动画。
- 设置中选择"原动画"时 SHALL 继续使用 perfect1/perfect/good.png 单帧 + 渐隐逻辑（含 Hold 特效生命周期）。

#### Scenario: 设置选择原动画
- **WHEN** 用户在设置中把特效模式切换为"原动画"
- **THEN** play/preview 页面使用 perfect1/perfect/good.png 单帧渐隐效果

### Requirement: 判定特效设置项
系统 SHALL 在设置页面（游玩 Tab）新增"判定特效"设置区，包含：
- 特效模式选择：逐帧动画 / 原动画
- 大小调整曲线参数：起始大小、峰值大小、峰值时刻、结束大小
- 大小曲线预览图：随参数变化实时绘制 scale(时间) 曲线

#### Scenario: 切换特效模式
- **WHEN** 用户在设置中切换特效模式
- **THEN** 设置持久化到 settings.json，并在下次进入 play/preview 时生效

#### Scenario: 查看大小曲线
- **WHEN** 用户调整曲线参数
- **THEN** 设置区中实时显示更新后的 scale-时间曲线预览，且预览图中反映参数变化

## MODIFIED Requirements

### Requirement: 特效渲染入口统一
play_page.gd 与 preview_page.gd 的 `spawn_judge_effect` SHALL 根据 `Global` 中的特效模式设置，分别走逐帧动画或原动画分支；两者 SHALL 共享相同的颜色/曲线配置。
Hold 特效的生命周期（持续显示到结束、结束后渐隐）SHALL 在新逐帧动画模式下同样成立。

## REMOVED Requirements
无（原动画保留为可选项）。
