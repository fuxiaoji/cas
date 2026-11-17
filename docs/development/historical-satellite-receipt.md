# 历史战役卫星底图恢复记录

2026-11-12。按用户“战役模式的地图改成原来的卫星地图版本”恢复 Godot 战斗海图的旧版表现。战役大厅原本使用的世界矢量图保持原样；剧情、搜打撤、潮汐活动继续使用程序动漫海域。

## 旧版来源与覆盖范围

- 图像：`client/public/maps/ironbottom.jpg`，3072 × 2304；由 `scripts/build-map-mosaics.py` 拼接既有 `artifacts/basemap` 中的 ArcGIS World_Imagery z10 缓存。本次没有下载新底图或生成替代照片。
- Godot 副本：`godot/assets/maps/ironbottom.jpg`，与旧图逐字节相同；SHA-256：`f3ce52c262e36f65bf635af83d07b671204d4b031c2dfadbf74b7db846c78fe2`。本次恢复不增补来源授权，沿用旧项目已有本地资产的来源记录。
- 旧配准：`client/src/basemaps.ts`、`client/public/maps/manifest.json`、`client/src/BattleMap.tsx`；Godot 登记在 `godot/data/historical-basemaps.json`。
- 缓存图边界：西经度 158.203125、东经度 161.015625、北纬度 -8.059229627200187、南纬度 -10.141931686131025。

| 历史海域 variant | 旧世界坐标原点，经度 / 纬度 | 恢复行为 |
| --- | --- | --- |
| `savo` | 159.5834 / -9.417 | 旧卫星底图 |
| `esperance` | 159.5894 / -9.3419 | 旧卫星底图 |
| `tassafaronga` | 159.6902 / -9.3545 | 旧卫星底图 |
| `kula-gulf-rts`、`empress`、`channel-action-rts`、`cape-st-george-rts` | 旧版未登记卫星配准 | 保留旧平面战术海图 |

未登记旧配准的历史海域不借用铁底湾照片、不猜经纬原点。后续若扩充这些海域的卫星覆盖，需先取得对应图像及可靠配准，再追加登记。

## 表现边界

`historical_map.gd` 复用旧版地理到米制世界坐标的转换：

```
x = (lon - lon_w) × 111320 × cos(lat_origin)
y = (lat - lat_origin) × 110574
```

底图只经现有 `SeaMap.project` 投影，并裁切到原核战场边界和可见窗口；与舰船、射程圈、弹道共享平移、缩放和战斗震动。旧图的 1.3 倍亮度及深蓝覆盖层保留。卫星模式不叠加程序岛屿、云层或重画岸线；切回战术海图时仍使用原核原有岛岸。

历史判定采用原历史 variant 白名单，并排除 `chapter` / `salvage` / `tide`，不依赖兼用于其他玩法的 `campaign_mode`。同海域的历史演练沿用卫星图；普通演练不会误用。视图面板提供“卫星底图 / 战术海图”切换；没有旧配准的海域明确保留战术海图。

本次未更改 Rust、原始 PDF、参考项目、规则表、舰队序列、阵位、航向距离、岸线、探测、环境、胜负、养成隔离或存档格式，也不以图像像素重新摆放舰船。旧地图已有地理近似不在本次表现恢复中重新拟合。

## 实测

Godot 4.7.2，真实 NVIDIA GeForce RTX 5070 / OpenGL 窗口，`godot/tests/historical_satellite_review.gd`：**74 / 74 通过**，回执 `artifacts/godot/historical-satellite/receipt.json`。

- 三个实际历史战役开局：`CAMP-ALLIES-02` 埃斯佩兰斯、`CAMP-ALLIES-10` 萨沃、`CAMP-ALLIES-05` 塔萨法隆加；保留原核夜间、降雨、海况与可见度。
- 独立旧常量核对原点及萨沃岛地标经纬转换；原图副本 SHA 一致。
- 真实鼠标点选舰船、滚轮锚点缩放、右键拖拽、战斗震动与逆投影；所有图层共用同一坐标变换。
- 960 × 540、1280 × 720、1600 × 900、1600 × 720 实际窗口；13 张 GPU 截图。
- 开关底图、缩放、拖动和渲染前后，原核序列化存档及公开观察内容完全相等。
- 埃斯佩兰斯真实 AI 指挥后在 185 秒发生一门三管主炮的公开齐射，共渲染 3 发；沿用此前炮弹表现路径，不制造射击事件。
- 库拉湾和奥古斯塔皇后湾使用原战术海图；实际搜打撤航次、剧情、潮汐活动、普通演练不套用照片。
- 既有 `campaign_caption_review.gd`：**6 / 6 通过**。

主截图：`artifacts/godot/historical-satellite/esperance-overview-1280x720.png`；另有三个海域的多尺寸与真实射击截图。Godot 内保留原生脚本、JSON 配准和可导入贴图，可直接编辑。
