# 返航灯岛：移动端直接操作（2026-11-13）

## 操作与边界

岛屿是主视图，主屏底栏只保留建造、招募、部队、驻舰、出航五项。点设施本人轮廓打开旁边的操作卡；未选中时不显示建设控制台。详情只显示当前维修、升级或收取动作与相关成本。资源不足时成本标记和按钮状态同时说明原因。

建造入口打开可横向浏览的物件卡片。选择后进入岛上预览，鼠标/触摸拖动或点空地选择位置；合法位置有勾，海面/占用位置有叉和短原因。只有“确认建造”调用原 `HomeService.place` 事务，取消、拖动、缩放、返回母港均不调用建设或扣款。成功后选中新设施。全局返回/Esc先调用 `consume_back()` 收起当前层，直接母港仍能直接离开。

普通鼠标拖动和单指拖动平移，滚轮/双指缩放；复位恢复完整岛屿。拖动阈值区分点击，物件的透明图像命中优先于邻近占地中心。镜头参数有界，不改变12×9权威建设格或可建陆地判断。

设施有真实待收产出才出现气泡。气泡和顶栏均调用原服务的“全部收取”，不会假装只收当前设施。无产出时收取禁用。行动未结束时显示继续当前行动，不能重新建设或开启第二航次；未获岛时引导真实登陆剧情，不用翻页直接发岛权。

出航保留真实拥有舰娘选择、五支已实装人格、装弹/运输预设和三座具名本地人机岛，统一为一个“出发”按钮；远征遗迹来源继续预选遗迹模式。正常新档和历史模式不变。部队详情中的1000–6000协议编制上限只是设定容量，不是本局出动人数或免费兵力。

## 原生编辑与素材接口

- `godot/scenes/ui/home_island.tscn`：原生Control/Container，顶栏、底栏、建造托盘、锚定卡、预览确认层独立可编辑。保留 `Layout/Bottom` 与 `_units/_garrison/_sortie` 接口。
- `home_island.gd`：保留 `bind(owner)`、`refresh()`，新增 `consume_back()->bool`。没有修改家园经济或原核协议。
- `home_island_canvas.gd`：保留 `rect()/land()/point()/observe()`，暴露镜头范围、设施比例/锚点、海陆颜色、种子和贴图目录。
- `home_building_art.gd`：同一设施物件在岛上、卡片和详情复用。优先读取 `res://assets/home/buildings/{hq,recycler,forge,solar,medical,turret,aa,depot,dock}.png`。仅缺文件的编辑器预览使用程序备用图，不覆盖已生成图片。
- 环境目录 `res://assets/home/environment/`：`tree_cluster/rock_cluster/grass_patch/coastal_cliff/ruin_cluster/ground_patch/beach_patch.png`。程序种子岸线、草色纹理和建设网格保持独立，透明散件只补绘细节，不带固定整岛地图或改碰撞。草土低对比叠合、岸内沙边、岸岩/内陆废墟分组；设施占位处省略冲突散件。
- 高精家园素材单独使用线性MIP过滤和实际导入的MIP层；角色SD及其他场景过滤设置未更改。建筑比例、脚点仍可在Inspector调整。

## 实际验收

专用 `godot/tests/home_mobile_review.gd` 用Godot `Input.parse_input_event` 路由实际鼠标、屏幕触摸、滚轮、双指与Esc，不直接发送按钮pressed信号冒充输入。正常43舰获岛档克隆与普通新档均位于 `C:/Users/fwj/AppData/Local/Temp/CAS-home-mobile-review/`；用户主档和备份只取哈希，不回滚或覆盖。生产验证仅在隔离副本设置两小时的时钟夹具，调用真实产率与收取事务，没有直接填写物资。

覆盖960×540、1280×720、1920×1080的触达/不裁切、相机复位、点物件、预览非法位/鼠标与触摸拖动、取消/返回零扣费、确认精确扣费与磁盘重载、气泡真实到账/不重复、活动航次阻断/恢复、普通新档引导。最终屏幕中的家园主要动作及本页弹窗操作目标至少44px，多数为48px以上。全局母港导航由Root单独验证。

旧 `home_ui_review.gd` 改用普通新档，通过真实补弹把装载计划与旧100%请求的教学夹具一致；不改真实终局、重演或去重断言。默认核仍为7134b025…，没有 `CAS_SIM_PATH` 覆盖。最终回执和选取PNG保留在 `artifacts/mobile-home-20261113/`，大克隆档留在C盘隔离目录。

最终：真实GPU145/145、无头128/128、旧UI兼容43/43；专用验证每轮133条实际Input事件，17张原生GPU截图。16张采用贴图实际读取均有10级MIP，海岛画布采用 `LINEAR_WITH_MIPMAPS`，导入后画面已与原锯齿图对照目检。主档及备份本轮均保持SHA256 `041d04a5a8840c0712f7c38a9b79cb9ad51eb8b20670cd2a0b786fda05508b8e`，不把之前轮次的旧哈希当成当前用户存档。回执详见该目录 `final-index.json`、`gpu-receipt.json`、`headless-receipt.json`、`legacy-ui-receipt.json`。

复跑：项目Godot可执行文件加 `--headless --path D:/desktop/cas/godot --script res://tests/home_mobile_review.gd`；实际GPU图去掉 `--headless`。旧兼容改用 `res://tests/home_ui_review.gd`。无头通过不代表画面已验收，最终PNG另做目检；本轮没有改历史物理、战斗控制器或账户服务。
