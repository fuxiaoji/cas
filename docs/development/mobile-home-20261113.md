# 家园交互、精细海岛与战术SD（2026-11-13）

状态：已完成并通过本轮整合验收。正常启动入口为项目根目录CAS-Godot.cmd；总回执见artifacts/mobile-home-20261113/integration-receipt.json。

## 操作与导航

竞技从母港顶栏移到出航正下方。新入口保留实际人机排位/3v3路由，返回到发起页面。家园为海岛主画面：建设/招募/部队/驻舰/出航五入口；点设施才显示升级/维修/生产。建设采用图像托盘→岛上预览→显式确认，取消不扣材料；返回优先关本地层，母港直接回港。岛可平移缩放与复位。资源详情不铺回主屏。

参考研究的实际图片、来源与取舍见docs/design/mobile-home-reference-20261113.md。原作参考图仅在artifacts研究目录，不作为发行素材。

## 转场

完整动漫云浪/圆形/纸帆遮幕保留；三名随机本人SD在1.18秒内向右推进14%屏宽，三次蓄力、腾空、落地，脚触地时水平停住，三人错相。减少动态/关闭动效即时切页，取消和快切释放输入屏障。真实60fps Main录屏与770项检查见docs/design/three-short-hop-transition.md、artifacts/hop-transition/receipt.json。

## 海岛资产与拼装

九种设施与七类环境散件按统一日漫军港材质制作：米白墙体、青绿金属、铜色管线、暖窗与海洋风化。真正透明独立物件，不是固定整岛背景。程序地形仍按种子生成岸线、草土、沙滩、可建格，素材在岸内/有效范围拼装；建筑占格、产量、费用、医疗、运输与NPC规则未改。源、提示词和PNG检查见docs/art/home-detailed-20261113/。

## 战术人格

五支可实战人格各有本人对应十二姿态SD，另有原创敌方安保机器人和四种载具。小人进入实际陆战，位置、射击、受击、搜索、战败消费真实公开观察；登船消失不判死。倒地为失衡→多种方向躺倒，白眼/吐舌或少量卡通白泡沫，停留4秒再淡出。暂停与恢复不虚构旧伤亡。

二十人格编制上限1000–6000写入catalog/personnel_cap，详情可查；它是核心全编制上限，不发放虚构库存或免费增援。本版真实先遣行动仍2–4身体加装备，最多32己方、64敌人；逐身体储备生产与千人同屏尚未实现。详见docs/art/tactical-sprites-20261113/README.md。

## 验收与边界

正式默认7134核、无环境覆盖，以下均通过：

| 验证 | 最终结果 | 证据 |
|---|---:|---|
| 家园真实GPU/鼠标/触摸事件/生产与扣费 | 145/145，133个真实Input事件 | artifacts/mobile-home-20261113/gpu-receipt.json |
| 家园无头状态/保存、旧UI教学兼容 | 128/128、43/43 | 同目录headless-receipt.json、legacy-ui-receipt.json |
| 母港竞技、出航、返回本地层与直接母港 | 58/58，51个真实鼠标事件，三尺寸 | navigation/receipt.json |
| 战术SD真实Main战斗、组件及可编辑预览 | 54/54、96/96 | artifacts/tactical-sprite/final-index.json |
| 三段横跳、既有音画与切页兼容 | 770项 | artifacts/hop-transition及docs/design/three-short-hop-transition.md |
| 正常核绑定、普通新档Main启动与恢复 | 14/14、26/26 | artifacts/mobile-home-runtime.log、mobile-home-main.log |
| 正常启动器 | --check成功；核仍7134b0254ce4ef91 | artifacts/godot-launch-build.log、godot-launch-import.log |

Root目检最终Home初始/落位/最小窗出航及五本人60姿态/倒地预览。16件Home与7张战术图均真实MIP导入，缩小后平滑；001最后行跨格残片已由内置图片编辑修正并重跑150项。17张Home截图保留在artifacts/mobile-home-20261113，建设与返回不扣费、确认真实扣费、重载保持；当前用户主/备档本轮只读SHA同为041d04a5a8840c0712f7c38a9b79cb9ad51eb8b20670cd2a0b786fda05508b8e。

可编辑入口：godot/scenes/ui/home_island.tscn、tactical_sprite_preview.tscn（F6滑块选12姿态）、tactical_sprite.tscn，以及godot/scenes/demos/transition_gallery.tscn。详细家园输入/测试说明见docs/development/home-mobile-20261113.md；动画事件和聚焦说明见docs/design/tactical-sprite-animation.md。

后续美术迭代仍可改善沙边弧线和同类遗迹重复感。满五组同时上同一滩头仍可能拥挤，提供聚焦/全图与缩放；视觉有界散开不改变真实脚点或射程。仅五支开放编制具有战斗SD，十五支图鉴预告未虚报完成。原核与WASM的既有逐字节证明沿用上一轮冻结回执；本轮没有引擎或历史数据改动，不冒称重跑全部历史核页认证。

全部只修改Godot呈现、输入、原创素材和编制设定；Rust、历史想定、旧快照和原始PDF/参考项目不改。测试使用PID隔离档或此前真正完成教学的QA档，当前用户主/备档只读，不将测试结果写回或回滚其新进展。Windows真实GPU与触摸事件注入不等于实体手机验收或Godot安卓包交付。

可再生Rust增量缓存因D盘空间不足完整移到C:/Users/fwj/.codex/cache/cas-mobile-home-20261113/incremental保留；未删除原始资料或宣传成片/可编辑源。临时录制写C盘，仓库只留最终轻量证据。
