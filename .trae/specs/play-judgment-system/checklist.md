# Checklist

## Task 1: 判定引擎核心
- [x] 判定相关变量已添加（combo, max_combo, perfect1/perfect/good/miss 计数, is_input_active, hold_tracking）
- [x] `_input` 正确跟踪 is_input_active（任意键/触摸按下为 true，全部释放为 false，ESC 除外）
- [x] `judge_note()` 函数根据时间差返回正确 grade（perfect1/perfect/good/miss）
- [x] Tap 判定：±50ms→perfect1，±100ms→perfect，±200ms→good，>200ms→miss，<-200ms→忽略
- [x] Drag 判定：当前时间≥目标时间时有输入→perfect1，否则在+50ms时→miss
- [x] Hold 判定：开始时刻定级，跟踪松手，中间松手→miss，结束（E）才结算计分
- [x] 每帧 `_process` 调用判定轮询
- [x] 多音符竞争：同一输入只判定最早音符

## Task 2: 准度/分数/连击显示
- [x] placeholder passed_count 逻辑已移除
- [x] 准度公式正确实现，显示替换 "准度100.00%"
- [x] 分数公式正确实现，显示替换 placeholder
- [x] 连击正确追踪并显示在 combo_label
- [x] 最大连击正确追踪用于分数计算

## Task 3: 判定特效与音符生命周期
- [x] perfect1/perfect/good 判定时在音符世界坐标创建 Sprite3D，billboard=FIXED_Y，直接添加到 world_3d
- [x] 对应纹理正确加载（perfect1.png / perfect.png / good.png）
- [x] 特效在 ~0.5 秒内渐隐并 `queue_free`
- [x] Miss 时不渲染特效
- [x] 判定后 Tap/Drag 音符渲染节点隐藏
- [x] Hold 分阶段隐藏 head（通过判定线时）和 body（结束时）

## Task 4: update_notes 跳过已判定音符
- [x] update_single_note 检查 judged 标记跳过已判定音符
- [x] update_hold_note 检查 judged 标记跳过已判定音符
