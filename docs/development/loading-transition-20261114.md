# 按真实页面准备程度保持的转场屏障

`page_transition.gd` 保留原 `capture_previous`、`play` 和 `preview_at`。新异步页面使用独立的遮盖、准备、揭幕协议，不能用固定延时冒充加载完成，也不因减少动态设置而跳过准备。

```gdscript
transition.capture_previous(app, next)
var generation: int = transition.begin_cover(app, previous, next)
# 等待时同时检查自己的请求仍然有效，取消不会发送旧 finished。
while transition.is_current_generation(generation):
    if transition.is_loading_covered(generation):
        break
    await get_tree().process_frame
# 根据实际阶段/ResourceLoader 状态报告进度；未知时不显示百分比。
transition.update_loading(real_progress, "正在准备页面", true, generation)
# 页面已经构建并至少完成一帧实际绘制后：
transition.finish_loading(page, generation)
```

`begin_cover(app, previous, next) -> int` 返回代次；它消费此前捕获的像素，不自行查询世界或账户。`covered()` 保留原信号，新增 `loading_covered(generation)` 方便单个请求核验。新协议等待满遮幕实际 `frame_post_draw` 后才公布 covered，避免同步页面构建抢在 GPU 绘制之前；无头验证改等一帧。状态保持全屏、不揭幕，直至本代 `finish_loading`。该方法可以提前调用：只记录就绪，仍完成遮盖后马上揭幕，没有最低加载停留时间。揭幕结束才发原 `finished()`。

`update_loading(progress, label, determinate=true, generation=-1)` 的已知进度严格取调用方的 0–1 数值；未知工作只显示三点活动指示，不按时间增长假百分比。`finish_loading(page, generation=-1) -> bool` 对失效代次返回 false。建议异步调用方始终传入代次。`cancel()` 递增代次、关闭遮幕、恢复页面透明度和输入，不为已取消请求发完成信号。

中段沿用三名已登记本人 SD 和动漫云浪全屏画面，短距离水平三步跳之后反向继续，落地停顿、错相和影子保持；不横穿屏幕或在周期边界瞬移。减少动态/关闭动画使用静态浅色遮幕和真实状态，仍须收到页面就绪才释放。原装饰 `play` 的 1.18 秒设计和 F6 编辑预览保持独立。

验收脚本：`res://tests/loading_transition_review.gd`。使用真实生产 overlay 和独立表现 host，不打开账户、不向原核发命令；分别检验慢准备、快准备、已知/未知进度、减少动态、关闭动画、取消、重复请求、输入屏障与旧预览/播放兼容。无头 35 项、实际 GPU 37 项通过。首轮单一时刻采样碰巧取到循环相同落点，改为持有期间逐帧记录，没有降低运动断言或修改生产动画：1.25 秒采样 198 帧，三人横移范围 149–224 逻辑像素，跳高约 58 像素，接地连续帧水平锁定。两张实际时序图已目检；真实 25% 进度、未知三点与静态低动效状态清楚可读，快就绪总约 1.17 秒，无额外停留。GPU 回执与截图位于 `artifacts/loading-transition/`，完整日志在 `artifacts/loading-transition-gpu.log`；正常主备账户/核清单 SHA 均未变，两个既有用户进程未关闭。真实首屏冷启动与主路由资源准备由 Main/Boot 集成测试另验。
