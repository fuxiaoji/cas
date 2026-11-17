# v3 群岛、废墟与公开海怪表现

本轮环境仅接 `salvage.generatorVersion=archipelago-3`。v1、v2 与历史海图沿原分支绘制，历史岸线、舰长线、坐标、碰撞、探测与射击数据未由环境层修改。

## 画面与数据边界

- 环礁、破碎群岛、峡湾、沉城的岸线全部来自原核 `islands`。环礁中间与开口是原核实际水域，沉城水道是实体地基之间的实际间隙。
- 四种地形的高度、林地密度与材质由程序生成。沉城使用破裂混凝土、藻痕、废土色和钢混岸壁；没有固定整图照片。
- 只实例化公开、`charted=true`、`collision=island` 的 `salvage.landmarks`。每个地标保留原 `footprint / island_index / height_m / flood / seed`；程序细节使用独立的局部种子，不占用原核随机源。
- 码头、天线塔、教团柱由程序楼体、破口、楼板、管线和潮线组成。废楼与工业设施各有一张透明局部物件插画，按原地基安放；它们不是岛屿或地图贴图，不产生碰撞。两个新物件已登记在 `godot/assets/environment/salvage-v3-asset-ledger.json`，包含提示词、来源、用途和 SHA-256。
- 海怪只读取已可见 `contact.entityKind / visualType / boss / health_fraction / phase`。完整透明物件按可见航向旋转，普通怪与 Boss 尺寸区分；缺素材时使用程序轮廓。不会根据接触编号查询隐藏舰队。
- Boss 危险区使用公开的中心、半径、开始 tick 与生效 tick。外圈是实际危险边界，进度仅跟随模拟时钟；中心的轻微动画不推进裁决。云、环境及建筑始终在战术实体与预警标记后方。
- 第一章的返航信标仅来自 `chapter.objective.beacon`；档案箱仅按公开 `archiveRuinId` 区分。Boss 生命只显示公开百分比，不推测隐藏 HP。
- 自有舰投影通过统一的 `character_art.gd` 解析准确身份或唯一登记舰名，禁用舰级代表替换；已登记小人优先，原立绘微缩作为末级兜底。原舰长线和切回原剪影的选项保留。

## 验收脚本

- `godot/tests/salvage_environment_v3_review.gd`：真实 v3 多种子、多主题；同种子海岸/地标相同、相同视觉时钟 GPU 像素相同、建筑基座始终位于对应权威岛内、未公开地标不绘制、观察只读、v1/v2 不出现新设施。`--fixture` 为明确标识的独立绘图样本，不代替原核证明。
- `godot/tests/chapter_environment_review.gd`：三场实际 `new_chapter`；最终怪物素材、返航信标、档案标记、Boss 当前公开生命与阶段、攻击预警可见来源。
- `godot/tests/deployment_integration_test.gd`：旧历史编成、复杂岸线与真实航行回归。

最终实际数值与截图以 `artifacts/godot/salvage-v3-environment/receipt.json`、`artifacts/godot/chapter-environment/receipt.json` 及对应日志为准。独立样本位于带 `-fixture` 的目录，不能冒充真实对局。

2026-11-12 最终局部目视收尾：透明高楼按实际轮廓铺到合法浅基底（seed43 主楼294×94米，仍在304×162米登记地基内）；移除每个物件重复的矩形地板框；低矮湿混凝土用不连续裂纹、盐渍、锈蚀和少量裸露钢筋读出废土感，沉城岸浪改为短段，避免整块方形白框强化棋盘观感。岛轮廓、landmark footprint、模拟与旧版本均未改。实际窗口复验 **235/235**，四主题seed40/41/42/43、同源同视觉时钟GPU像素一致；三章公开接触/预警表现 **46/46**。最终seed43近景为 `artifacts/godot/salvage-v3-environment/drowned_city-landmark.png`，不是fixture。当前原核SHA-256登记于两份回执。

## 限制

这是 2D / 2.5D 表现层。建筑插画与怪物投影没有新增实体体积、遮挡规则或漂浮物物理；水面、云、天气与程序岛的原有动态保留。生成地形的可航性与怪物伤害/召唤/阶段规则由原核线独立验收，本文件不替代原生/WASM 与游戏闭环回执。
