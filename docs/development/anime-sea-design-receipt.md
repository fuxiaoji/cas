# 动漫云海表现与验收（2026-11-11）

本批只改变 Godot 视觉投影。源世界中的陆地多边形、舰长线、航向/距离、探测、原核随机数、航行与碰撞均未修改。

## 设计落实

- 以用户第三张俯视海域图组织场景，参考前两张的青蓝浅水、柔和日光和岩岸植被。
- 海面去掉旧重复写实纹理及横条纹；使用低频流动明暗、近岛青绿浅水、轻微焦散与成片的短暂日光反射。
- 原始陆地完整绘制，再把原创岩石/林地材质映射到同一多边形；内部平台与岩壁裁切在原岸线内。纹理没有河流、峡湾或水潭，不制造可航行区域的错误暗示。
- 原创透明云图缓慢漂移，分层柔云影；云只针对本席已知单位柔和淡开。单位和战术标识绘制在云层上方。
- 日/暮/夜色读取原核 `environment.light`；不更改历史环境。视觉不伪装成侦察迷雾。
- 默认隐藏网格与常驻手势说明，仍可切纯战术海图。`cinematic` 模式进一步隐藏舰名、地标文字和小地图，供剧情使用。
- 通过 `draw_primitive` 绘制已三角化的装饰，修复历史凹岸交集产生细条导致的重复三角化错误；完整原陆地始终保留。

## 素材

- `godot/assets/environment/anime-cloud-v2.png`：内置 image_gen 原创透明柔云。
- `godot/assets/environment/anime-island-v2.png`：内置 image_gen 原创俯视岩石林地材质。
- 来源、提示词摘要、尺寸与 SHA256 见同目录 `anime-style-ledger.json`。没有生成或改动小人。

## 验收

- Godot 4.7.2 headless 导入成功。
- `godot/tests/anime_sea_review.gd`：实际 OpenGL 窗口导出 5 张截图；seed 6106 / 8 岛；完整观察值不变，坐标投影往返检查通过。
- 截图：`artifacts/godot/anime-sea/day-overview.png`、`day-fleet.png`、`day-island.png`、`cinematic.png`、`tactical-overview.png`；已目视白云、岛体、浅水和战术标识。
- `godot/tests/deployment_integration_test.gd`：最终 68/68，原生 Rust 实际历史编成/出航，日志 `artifacts/godot/deployment-anime-coast-final.log` 无 ERROR / 三角化错误。
- 夜战已在同批 `artifacts/godot/immersive-battle/06-night-radar.png` 中检查，保持原核夜间条件。

## 范围

这是 2.5D 表现层：岛岸高度由受光平台/岩壁构图呈现，海浪与云为着色和图像层，不是新建完整三维地形/天气模拟。当前一个岩岸林地材质家族；尚未增加多种气候生态素材。浅水渐变只作美术表现，不声明新增水深规则。
