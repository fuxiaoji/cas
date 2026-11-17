# 陆地重构：免费素材候选与最小工具链

核查日期：2026-11-15。状态：**来源页已核实，候选尚未下载/入库/实机测试**。配套[总计划](land-scene-3d-reconstruction-plan-20261115.md)与[资产队列](land-3d-asset-queue-20261115.csv)。

## 1. 采用顺序

先查项目已有资产，再筛选许可明确的免费模型与材质；可以整理的就用Blender统一尺寸、材质与LOD。普通硬表面模块适合程序化制作。只有确实缺少合适素材、又需要世界观特色的模型才进入Tripo队列。

“免费下载”“CC0”“开源代码”分别记录。模型采用资产自己的许可，工具采用代码许可；GitHub仓库的开源许可不自动覆盖网页截图、第三方模型或生成服务。首轮优先CC0；需要署名的素材另记作者、原链接和分发要求；不把非商用/仅编辑用途的免费资源混入可发行包。

## 2. 可开始筛选的免费目录

| ID | 官方来源与已核事实 | 在CAS中优先筛什么 | 改造/筛除理由 |
| --- | --- | --- | --- |
| F01 | [Quaternius Ultimate Stylized Nature](https://quaternius.com/packs/ultimatestylizednature.html)：CC0，63模型，页面列glTF/FBX/OBJ/Blend | 树、灌木、岩石、少量地表植物，作为首轮自然模块来源 | 同一库优先保证整体协调；仍要实测叶片透明、材质数和实际三角形，不假定自带手机LOD |
| F02 | [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html)：CC0；官方区分免费Standard、额外内容和含引擎工程的Source | F01缺少的树形、岩石或地面植物 | 116是完整目录量，页面说明免费部分约60–70%，不把全部116或Godot着色器工程视为免费可得；逐件核所下载版本 |
| F03 | [Kenney Nature Kit](https://kenney.nl/assets/nature-kit)：CC0，330项 | 岩石/树基础轮廓、规模试验、缺项底模 | 形状较简洁，先作灰盒/底模候选；用户要的精细度不能靠原样堆叠满足 |
| F04 | [Kenney City Kit Suburban](https://kenney.nl/assets/city-kit-suburban)：CC0，40项 | 住宅体块、屋顶/门窗、城郊组团底模 | 校正层高、檐口、浅墙/瓦顶材质，剔除不合年代/轮廓的物件；不直接决定整岛建筑风格 |
| F05 | [Kenney City Kit Industrial](https://kenney.nl/assets/city-kit-industrial)：CC0，页面列40项 | 仓库、厂房、生产设施轮廓与工业组团 | 工业用途、装卸口、庭院和实际产线须另接原核，模型存在不等于经济功能完成 |
| F06 | [Kenney City Kit Roads](https://kenney.nl/assets/city-kit-roads)：CC0，官方页列90项 | 路缘、路口、围栏和道路组织参考/底模 | 弯道、桥头与坡路按实际地形由Blender/程序补模块；不能把平面道路贴到断崖假装连接 |
| F07 | [Quaternius Ultimate Modular Ruins](https://quaternius.com/packs/ultimatemodularruins.html)：CC0，90模型 | 残墙、断柱、瓦砾组合，搜集废墟结构候选 | 题材偏古典/地牢，不能整包当现代水世界城市；拆合适零件并重做现代立面/锈蚀材料 |
| F08 | [Poly Haven模型目录](https://polyhaven.com/models)、[许可](https://polyhaven.com/license) | 已免费释放的自然岩石、工业散件、地表材料；少量样本作高模烘焙来源 | CC0；[Vault](https://polyhaven.com/vaults)有早期访问内容，非全目录即时免费。扫描高模先减面/烘焙，不整包原分辨率导入手机 |
| F09 | [ambientCG材质](https://ambientcg.com/)、[官方许可](https://docs.ambientcg.com/license/) | 沙、土、草、岩、混凝土、砖、金属的共享材质起点 | CC0；是材质资源，不声称替代完整三维地形生成器。选择512/1K档并统一动漫色调、粗糙度和纹理密度 |
| F10 | [Quaternius Buildings](https://quaternius.com/packs/buildings.html)：CC0，9建筑 | F04不足时比较普通建筑体块 | 仅备用，先评风格再下载；不为使用更多库牺牲一致性 |

以上数量用于说明官方包范围，不作为我们必须引入的数量。F05已核官方搜索页面，下载前保存实际包版本与许可文件；各网站页面可能更新，正式入库以实际取得的压缩包/文件为准。只取样区需要的少量资产，避免一次下载大型库后不加筛选。

### 首轮免费选样

从F01/F02选择两类乔木、一类灌木、三类岩石；从F04选择一栋住宅；从F05选择一栋仓库；F06仅取少量道路/路缘结构；F09选四种基础地表材质。先用这些与自制码头/坡路完成可运行样区，再决定是否扩大库。

每个候选要回答：正常操作距离是否足够精细，和本人SD是否协调，能否改成统一材质，是否需要过量透明/材质批次，是否具有正确入口和完整轮廓。若不合格，记录“改造耗时高于自制”“年代/风格不合”“拓扑/透明过重”等具体原因；不能只写“免费素材不好看”就启动整库付费生成。

## 3. 地形插件与代码候选

| 来源 | 核查结论 | 决定 |
| --- | --- | --- |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D)、[平台说明](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/platforms.md)、[1.0.2发布](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable) | 官方列Mobile与Compatibility支持，Android有特定设备/纹理注意事项；发行说明不能替代本工程Godot4.7.2实测 | 作为固定版本对照候选；先验区域读写、存读、射线、Windows/arm64。工具许可与所用贴图分别登记 |
| [Godot程序几何](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/index.html) | 可用ArrayMesh/SurfaceTool建立数据驱动的网格 | 自有分块高度场是可控备选；岸线/崖面/道路共同读原核，不以固定模型替代地图生成 |

不先同时引入多个地形、散布、道路大型插件。优先复用现有种子/地理接口，减少不同系统各自产生碰撞与可走区。

## 4. Blender AI与技术美术技能核查

两条聊天给出的工具候选已经分清宿主与桥。核查的是当前README/官方文档，**没有安装或连接成功的结论**。

| 候选 | 实际关系 | 本项目取舍 |
| --- | --- | --- |
| [arjun988/blender-skills](https://github.com/arjun988/blender-skills) | 面向社区BlenderMCP的技能库，覆盖环境、材质、优化/导出等工作流；安装名称可能仍用旧桥名 | 后续按需摘选环境、优化、导出少数工作流，不为“技能多”整包安装 |
| [SamuelAsherRivello/ai-skills-blender](https://github.com/SamuelAsherRivello/ai-skills-blender) | 面向官方Blender Lab MCP，维护Codex包 | 只有选择官方桥后才选配；不能直接当社区桥适配包 |
| [官方Blender Lab MCP](https://projects.blender.org/lab/blender_mcp)、[工具清单](https://projects.blender.org/lab/blender_mcp/raw/branch/main/readme_tools.rst) | 官方Lab项目与可执行/检查工具确实存在 | 实施时检查本机Blender版本与固定版本；不是现在已连接的工具 |
| [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender) | 第三方社区项目，旧名blender-mcp，与官方Lab不是同一桥 | 如确需交互，可选它作为唯一社区桥候选；先只读查询与预览验证，不同时叠桥 |
| [Tripo3D-Plugin-dsh](https://github.com/Tripo-Developer/Tripo3D-Plugin-dsh) | DeepSeek Harness专用skills-only插件，依赖该宿主的注册方式 | 不作为Codex原生插件直接安装 |
| [Tripo官方MCP alpha](https://github.com/Tripo-Developer/tripo-mcp) | 依赖Tripo专用Blender Addon/通信，README仍标alpha | 不把它当通用Blender桥；首轮不选作必需依赖 |

推荐最小组合：**现有Godot＋Blender后台执行＋免费模型/材质**。不需要等MCP装好才开始整理资产。用户已确认电脑安装Blender，本轮只读检索未定位其确切路径/版本；实施时查实际安装位置，不重装覆盖用户环境。

后台执行使用独立Blender进程，输出`.blend`、GLB和预览，避免操作用户当前打开的文件。参数依据[Blender官方启动参数实现](https://github.com/blender/blender/blob/main/source/creator/creator_args.cc)核对。需要界面观察才启用单一桥，不把安装工具本身当成交付。

## 5. Tripo仅补缺项

用户确认同时有Studio会员和API额度；本轮未登录核余额，也不需要再次问是否购买。网页与API仍是分别管理的额度，自动任务用API实际余额与当日计费核算。官方[说明](https://www.tripo3d.ai/help/api-plugins/tripo-studiotripo-api)与[CLI页面](https://studio.tripo3d.ai/cli)说明二者区别及当期活动；活动不作为本项目预算来源。

自动化优先核[官方CLI](https://developers.tripo3d.ai/en/docs/cli)或当前API，不经第三方免费代理转发用户凭据。先锁定CLI/模型/API版本；[旧模型下线公告](https://developers.tripo3d.ai/en/blog/legacy-model-deprecation)说明旧默认值存在时效性，执行时重新核可用模型，不照抄alpha示例。

[Studio导出](https://www.tripo3d.ai/product-doc/export-and-integration/export-dcc)支持GLB等格式。重拓扑后的UV/纹理处理依所用路径区分：[Studio Retopo](https://www.tripo3d.ai/product-doc/module-post-processing/retopo)与[API mesh/decimate](https://developers.tripo3d.ai/en/docs/mesh-decimate)并非完全相同。生成物仍要逐件测量实际面数、材质、UV、形状与碰撞，不能写“目标低模”就算手机资产合格。

### 有缺项时的任务模板

- 身份：原创前文明信标/水世界遗迹等，附项目原创简图或已确认可用于生成的参考。
- 形体：只做一个可复用散件，给米制尺寸范围、可见轮廓、完整背面；不带整座岛/摄影机/文字/商标/自带地面。
- 风格：明快动漫战术海岛、可信材质层次、统一色板，避免照片扫描与过度卡通互混。
- 接口：门洞、停靠点、可走面由约束图标明，最终仍在Blender测量/修复。
- 输出：候选原模；清单给运行LOD0目标、材质/纹理上限与可动部件，不假定生成器严格兑现。
- 预算：任务数量、估计积分与停止条件先登记；失败一次分析形体/输入问题，不无限重试。

Tripo顺序G01–G08见总计划第七节与资产队列。若已有免费资产能满足，同项付费调用数量为零。

## 6. 入库记录与发行

每个最终文件保存：资产ID、原作者、原页、包版本、许可文件及SHA、下载日期、原文件SHA、修改说明、导出器版本、实际三角/材质/贴图、米制尺寸、LOD/碰撞/功能锚点和截图。免费原包与项目改造分别保管；只发布用到的运行资产与必要许可，不把研究截图、整个原包或重复高分辨率纹理打进APK。

本轮仅核网页/仓库来源和计划，未下载模型包、未安装桥或技能、未生成模型。所有候选仍需入库时逐项复核与同场目检。
