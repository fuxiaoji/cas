# 三段短跳页面转场

本轮根据“仍像一下子划走”的反馈，替换此前0.62秒横穿1.76屏的行进曲线。只改表现、测试与本文档，原SD图、音乐、账户、模拟时钟及7134默认内核均不修改。

默认总长1.18秒；三名随机、不同身份且连续两次尽量不同的已登记SD仍约占屏高26%。三人中心从约18%/43%/68%到32%/57%/82%，总共只前进14%屏宽。每人三跳，单跳约0.33秒，16%周期为起跳蓄力、64%为腾空、20%为落地回弹。水平位置只在腾空段缓入缓出推进，落地段真正停住；峰高58设计像素，个体幅度约±10%变化。三人起跳错开约0.04秒，再用高度、轻微倾斜和落地压缩区分。小接地影在腾空时收缩变淡，帮助看清离地与落脚；下缘原图步摆保持轻微，不冒称新骨骼动画。

仍保留全屏动漫云浪、圆形和纸帆三类PPT遮盖/揭幕。页面同步构建，动画内没有额外加载停顿；人物结束时淡出。减少动态与关闭动效时即切。快速替换转场前先撤掉旧遮幕再截图，避免把旧三人冻结进新背景。动画结束和取消均释放输入。

Inspector可调整duration/hop_count/travel_distance_fraction/hop_height/show_ground_shadow，保存重载有效，预览时间滑块显示完整步态；原生Actor、ActorShadow、Timeline继续可编辑。F6演示为godot/scenes/demos/transition_gallery.tscn。

## 视觉证据

主短片为artifacts/hop-transition/actual-main-60fps.mp4。Godot内置MovieWriter直接录生产Main的编队、出航、家园三次切页，每次71帧、60fps，即1.183秒；255帧总长4.25秒。没有运动补帧或根据坐标重画。同目录formation-60fps-storyboard.png、modes-60fps-storyboard.png、home-60fps-storyboard.png均从短片抽帧，已逐张目检三次抬升/落地、三人错相、短段前进与完整揭幕。

actual-three-hop-routes.mp4是另一组墙钟截图证据，PNG同步编码降低捕获帧率，不用它评价正常播放帧率。正常观感使用上面的MovieWriter短片。墙钟捕获三次切页也都释放屏障，约1.24–1.47秒。测试临时PNG与AVI在转成最终短片/时序图后因D盘满已清理；JSON观察和可重建测试/制作脚本保留。

## 验收

770项通过、0失败：新hop_transition_review.gd85项；既有全屏50、可选轻转场239、实际切页9、原创音画兼容147、昼夜/全屏实际切页240。包括四窗口三跳高度、地面水平锁定、屏内可见性，真实鼠标屏障、快切、减少动态、Inspector参数重载、正常主档/备份及音量设置保全。时序图和真实短片为独立视觉验收，不以坐标变化单独签收观感。

受影响旧测试只调整对应设计的等待/距离预期：original_music_transition_review.gd转场段、fullscreen_transition_review.gd、anime_transition_clock_review.gd。共享transition_settle.gd等待上界改为max(duration+0.6,1.2)秒，只等待真实屏障完成。显式0.42秒轻模式测试保留。

总回执artifacts/hop-transition/receipt.json、MovieWriter回执movie-receipt.json、各轮artifacts/hop-*.log。正常主账户及备份未变，测试只创建PID隔离新档；未发战斗或经济命令。
