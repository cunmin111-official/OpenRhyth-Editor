# Tasks

- [x] Task 1: 判定引擎核心 — 实现判定队列、输入状态跟踪、Tap/Drag/Hold 判定逻辑
  - [x] 添加判定相关变量（combo, max_combo, perfect1_cnt, perfect_cnt, good_cnt, miss_cnt, total_notes_real, is_input_active, hold_tracking 等）
  - [x] 重构 `_input` 为判定引擎提供输入状态（is_input_active 跟踪，ESC 除外）
  - [x] 实现 `judge_note(note_data, input_time)` 核心函数，返回 grade
  - [x] 实现 Tap 判定：遍历未判定的 Tap 音符，优先判定时间最早的音符
  - [x] 实现 Drag 判定：在当前时间 ≥ note_time 时，检查 is_input_active，有则 perfect1，否则在 +50ms 时 miss
  - [x] 实现 Hold 判定：开始时刻检查输入定级，跟踪 hold_active，监测中间松手（is_input_active=false 时改判 miss），结束时刻（E）才结算
  - [x] 实现在 `_process` 中每帧调用判定轮询（处理 Drag 超时 miss 和 Hold 结束结算）
  - [x] 处理多音符竞争：同一输入只判定最早音符

- [x] Task 2: 准度/分数/连击显示替换
  - [x] 用真实公式替换 `_process` 中的 placeholder passed_count 逻辑
  - [x] 实现准度计算：$Acc = \frac{(perfect1+perfect)+0.6\times good}{total\_notes}$，向下取整2位小数
  - [x] 实现分数计算：$Score = 900{,}000\times Acc + 100{,}000\times \frac{MaxCombo}{NotesCNT} + Perfect1Count$
  - [x] 实现连击显示（combo_label）和最大连击追踪
  - [x] 更新 accuracy_label 显示真实准度

- [x] Task 3: 判定特效与音符生命周期管理
  - [x] 在 judgment 发生时，在音符落点的 3D 位置创建 Sprite3D，设置 `billboard = BILLBOARD_FIXED_Y`（始终面向屏幕），直接添加到 `world_3d`（不挂接到判定线）
  - [x] 加载对应纹理：perfect1→perfect1.png，perfect→perfect.png，good→good.png
  - [x] 特效 Sprite3D 渐隐 ~0.5 秒后 `queue_free` 移除
  - [x] Miss 时不渲染特效
  - [x] 判定后隐藏音符渲染节点（Tap/Drag 直接隐藏，Hold 分阶段隐藏 head 和 body）

- [x] Task 4: 修改 `update_notes` 跳过已判定音符
  - [x] 在 `update_single_note` 和 `update_hold_note` 中，如果音符已被判定（judged=true），跳过渲染

# Task Dependencies

- [Task 1] 无依赖（基础判定引擎）
- [Task 2] 依赖 [Task 1]（需要判定结果来计算）
- [Task 3] 依赖 [Task 1]（需要判定结果来触发特效）
- [Task 4] 依赖 [Task 1]（需要 judged 标记来跳过渲染）
