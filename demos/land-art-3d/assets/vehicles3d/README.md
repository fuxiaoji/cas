# 海岸样区 · 三维载具

2026-11-16 的独立美术样车，不对应历史 CAS 型号，不修改正式原核、舰表、碰撞、数值或存档。仅步兵使用已认可的二维帧；艇、装甲车辆是可编辑 GLB 网格。

## 八件样车

| 运行资产 | 来源 | 实际三角 | 网格/表面 | 共享材质 | 实际宽×高×长（米，包含天线） |
| --- | --- | ---: | --- | --- | --- |
| cas_landing_craft.glb | Blender 原创 | 5448 | 2/2 | 1 顶点色 | 5.008×5.600×13.430 |
| cas_amphibious_apc.glb | Blender 原创 | 3796 | 2/2 | 1 顶点色 | 3.910×3.960×7.890 |
| cas_tank_cc0.glb | Quaternius CC0 改造 | 6064 | 2/2 | 1 顶点色 | 3.936×3.115×8.952 |
| cas_heavy_landing_craft.glb | Blender 原创重型登陆艇 | 6636 | 2/2 | 1 顶点色 | 7.142×7.390×23.400 |
| cas_fast_assault_boat.glb | Blender 原创刚性充气突击艇 | 4244 | 1/1 | 1 顶点色 | 3.060×1.940×7.493 |
| cas_self_propelled_artillery.glb | Blender 原创履带自行火炮 | 6004 | 2/2 | 1 顶点色 | 4.220×4.165×10.420 |
| cas_transport_helicopter.glb | 3DAssets.dev CC0 军用化改装 | 3736 | 3/3 | 1 顶点色 | 11.005×4.591×13.128 |
| cas_attack_helicopter.glb | Blender 原创武装突击直升机 | 4352 | 4/4 | 1 顶点色 | 11.670×3.530×11.965 |

直升机宽度含旋翼直径；全高含天线、旋翼。船的全高还包括水线以下部分，不能把这列当甲板或舱体高度。八件本体合计 **40,280 三角、18 网格/表面**，额外三艇尾迹各16个三角。每个刚性总成已经合批，不把旋翼、炮塔、跳板焊成一件。原三件运行 GLB 未重导，SHA 逐项登记在 manifest 的 `original_three_preserved_sha256` 中。

以上是 Godot 4.7.2 实际导入 GLB 后的 MeshInstance3D 全局 AABB，去除实体展示旋转、炮塔重置为 rest 零旋转、排除所有空锚点，记录于 `vehicle-manifest.json`。炮塔扫描时伸出的炮管改变外接长宽，早先 9.019m 是扫描中的外接长度；源模型 rest 长为 8.952m。原 Blender 尚未刷新的 mesh bounds 曾把坦克高度多算约一米，已弃用。APC 炮塔顶部约 2.915m，接近 4m 的总高度包括天线；坦克车体约 1.36m、炮塔上层约 2.30m，总高也包含天线。样图用的平面现设 Y=0，不能以旧样图 Y=-0.84 的统一底板判断陆车悬空。

## 尺度、朝向与动画接口

- 1 单位=1米，Godot +Y 向上，前向 -Z；Blender +Y 向前经 glTF 转换。所有显示与运动在同一 Node3D 锚点，运动方向按真实位移求朝向。
- APC 最低 Y≈0.00000002；坦克最低 Y≈-0.00000030，浮点误差内接地。船根节点为水线，最低 Y=-0.80，天线顶 Y=4.80；船漂浮时根节点置海面 Y=0.12。
- `Hull` 是固定几何，`Ramp` / `Turret` 是独立活动父节点，下面只有一件刚性合并网格。跳板可绕 X 轴开启至约 -1.4 弧度。炮塔可独立绕 Y 旋转，船轻微俯仰/横摇。
- `Waterline`、`GroundContact`、`UnloadPoint`、`DeckPassengerAnchor`、`Muzzle` 是接口空锚点，测量不包含它们。当前仅展示巡航和炮塔扫描，不冒充真实部署、伤害、登陆裁决。
- `scripts/coastal_vehicles.gd` 挂独立 Node3D，调用 `build(height_at: Callable)`。普通艇在 (-24,-86)、两栖车在 (-14,-23)、坦克在 (5,-9) 周边低速演示；实际地面高度读取样区的同一高度函数。`set_demo_time(seconds)` 可复现检查帧。
- 新增重艇在 (-56,-112)、快艇 (10,-72)、自行炮 (28,-18)、运直 (-44,-35) 离地11m、武直 (40,-37) 离地14m。普通艇/重艇/快艇的路线椭圆半径分别为 (9,5)/(13,8)/(12,7)。`SHOWCASE` 公开米制路线、速度相位和艺术舱位。船后独立 `ArtWake` 是轻量透明网格，排除模型 AABB；舰艇根节点仍是水线，朝向与尾迹共用同一锚点。
- 两种直升机均保留 `MainRotor` 绕 Y 旋转和 `TailRotor` 绕 X 旋转，武直有独立 `ChinGun`、双联火箭巢、串列座舱。运输机是滑橇+大舱体，武直是轮式起落架+短翼/小突击舱；没有把同一模型换名冒充两种。
- 重艇水线以下最低 Y=-1.22，快艇最低 Y=-0.50；自行炮与武直最低 Y=0，运直为0.000114（浮点级误差）。所有地面/航空模型足底验收误差<0.001m。跳板 `set_ramp_open(id,0..1)`；`get_vehicle_anchor(id,socket_name)` 返回船舱/乘员/卸载/炮口空锚点。舱位仅为艺术接口，不替代正式载舰资格、乘员守恒或游戏数值。
- 静态同材质零件和同一活动总成已经合批，用共享顶点色保留钢材、橡胶、舷窗与甲板颜色，没有多张纹理。未做 LOD、实际履带变形、车轮独立滚动或手机实机性能验收；后续接正式事件再完善。
- Blender 导出先清除旧颜色层，保证唯一正确 `COLOR_0`；Godot 展示模块对共享的局部材质启用 `vertex_color_use_as_albedo`。`godot-vehicle-palette.png` 是实际海岸场景 GPU 截图，已目检军绿车身、黑色橡胶、蓝色舷窗与米色甲板；不能仅凭 Blender 预览宣称运行颜色正确。
- 新八件总览为 `godot-vehicle-catalog.png`，航空近景为 `godot-rotorcraft-close.png`，均由真实 Godot GPU 渲染，已检查绿漆、橡胶、甲板、蓝色座舱与独立部件。新 loft 网格显式校正外法线，避免座舱上表面被背面剔除；武直座舱也已抬到机体外可见的位置。

## 免费来源优先与许可

先检索 Kenney Watercraft Kit、Quaternius 与 CC0 登陆载具候选。Kenney 水上包主要为民船、帆船，未拿它们冒充军用登陆艇；登陆艇和两栖车因此在 Blender 中独立建模。未使用 Tripo，也未花费积分。

坦克作者 Quaternius，原包 **Animated Tanks Pack，CC0-1.0**。官方页面：https://quaternius.com/packs/animatedtanks.html 。原页 `vendor/animatedtanks.html` 保存了明确 CC0 链接；镜像许可表 `source/QUATERNIUS-LICENSES.md` 的 tank_pack 条目对应原页。下载路径：

https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/main/public/glb/tank_pack/Tank.glb

原文件 SHA256 `1e46eaeef496c569f7b8e85aae8c49e113568d12c0f303e641b7a3d2e0b4b700`；保存在 `vendor/Tank.glb`。另下载 `Tank2.glb` 仅做候选，未接运行。

改造：静态烘焙原休止姿态、移除无关 Icosphere、原 -X 前向转换至 -Z、统一配色与米制、压窄/降低夸张轮廓、足底归零、独立炮塔、刚性总成合批。原素材的带骨骼履带版本仍在 vendor 内；运行样车目前没有冒称其履带动作已接。

`source/` 保存八个 `.blend` 源文件、生成脚本和检查脚本，用 `.gdignore` 隔离自动导入。无需更改用户 Godot 的全局 Blender 路径；运行只依赖八个 GLB。使用本机已有 Blender 5.0 zip 的独立便携解压版，没有改动参考工程或原压缩包。

新增运输直升机使用 [3DAssets.dev Utility helicopter](https://3dassets.dev/assets/air-land-sea-vehicles-utility-helicopter-7dbc148e)，官方页明确 **CC0 1.0 Universal**（可商业、修改、再分发），并标记作者使用AI工具；它是可编辑的真实网格，并非图片。原文件 `vendor/utility-helicopter-cc0.glb` SHA256 为 `5b01f318035776d9cc632d76dc25ac9a0447b94e37180f46850bdb154b8faff5`，原许可页保存为 `vendor/utility-helicopter-license.html`。下载地址：https://cdn.3dassets.dev/assets/20028/v1/model.glb 。改造包括1.55倍米制统一、前向归一、军绿色顶点材质、舱门/外挂油箱/进气口和活动旋翼。其余四种新载具为本项目 Blender 原创；没有付费模型或 Tripo 消耗。

新增5份 `.blend`、`build_expanded_vehicles.py` 与实际GPU图册脚本也在 `source/`。运行只依赖八个 GLB，不需要 Blender 插件。新生成器导入基础部件函数时不会触发原三件重导，生成结束会验证原三 SHA。需要更多部队时优先复用这批功能不同的底盘/艇型，再增加确有玩法用途的型号。

## 重导与复核

基础 `source/build_vehicles.py` 留作原三件源头；扩充已有目录时不运行它。增补采用下述新生成器，再 Godot `--editor --import --quit`，最后执行 `--headless --script res://assets/vehicles3d/source/vehicle_check.gd`。检查从实际运行 GLB 回写尺寸、网格、表面与三角，并核所有载具移动方向和前向点积 >0.99。该测试真实加载网格与活动节点，不检测手机负载。

**本轮增补请只运行 `build_expanded_vehicles.py`**，随后导入、`vehicle_check.gd`、GPU `vehicle_catalog_gpu.gd`。不应为新增型号重新生成原三 GLB。检查已通过八件位移/前向点积>0.999、活动节点、两机主旋翼角度变化、真实顶点色数组、足底、三原件SHA保持；图片另经目检。图册桌面设备是RTX5070，不是安卓结果。单件3.7–6.6k三角、1材质属于初步资源控制；远景LOD、几十件同时入场的实例化/阴影策略和中端手机实机内存/发热仍待下一阶段。

## 新海岸下的艇体航线净空

`source/vehicle_water_routes_check.gd` 读取实际 `coastal_geography.gd`（seed714），对三艇完整360°路线每0.5°检查一次。每相位覆盖完整模型AABB平面的四角及≤1.5m内部网格，并外扩0.15m；地形同时取原高度和真实渲染三角插值的较高值。龙骨高度按升沉最低点、横摇/俯仰幅度极值和0.015m额外余量保守计算，不只检查船根。

共检查133,200个艇体地形点：普通艇最小水深2.605m、龙骨净空1.682m；重艇3.308m/1.907m；快艇3.868m/3.281m。全部超过0.75m净空下限。原普通艇(-28,-64)和原重艇(-62,-80)在新悬崖地理下失败，因此两条路线均已移离岸线；快艇路线保留。完整前后结果、地理SHA和模块SHA在 `vehicle-water-route-verification.json`。这是默认种子艺术样区的有限采样核验，不能冒充随机地图通用寻路、连续碰撞或正式原核通行裁决；地理变化后应重跑。
