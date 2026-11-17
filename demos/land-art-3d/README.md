# 浅湾：陆地三维美术 Demo

这是一份可运行的美术样区，用于确认海岸、港镇、自然地貌、配色和本人SD的组合效果。2026-11-16第二轮增加废土工业与沉没遗迹、围墙工事、八类真3D载具、动态碎浪及沼泽/河谷/山脊/海崖。当前提供看景与交互，没有接入战斗、家园经济或正式账号。

## 打开

双击工程根目录的 `CAS-Land-Art-Demo.cmd`。

本轮实际截图与可播放海浪在 `CAS-Coast-Review.cmd`，或打开 `output/coast-v2-20261116/index.html`。

在Godot编辑器中导入本目录的 `project.godot`，运行 `coast_demo.tscn` 即可。`scenes/editable_coast.scn` 是已生成的静态三维场景，可以直接查看、选中和调整地形、建筑、树石、相机、灯光。动态源代码在 `scripts/` 和 `shaders/`，编辑后重新运行。

## 操作

- 鼠标左键拖动看景，滚轮缩放；触摸支持单指拖动、双指缩放，触摸真机待测。
- 点击“海湾 / 港镇 / 山林 / 家园样板”切换镜头，也可以按1、2、3、4。
- “更多景观”提供沼泽河谷、海崖、废土工业、海图预览、围墙防线；对应数字5–9。
- 近景20m、远景100m标尺按相机实际投影计算。海图预览隐藏小型模型而保持原地理，返回近景恢复。
- 点击“晴日 / 薄暮 / 阵雨”比较光照、云和降雨。
- Tab隐藏/恢复界面；F11切换全屏；Esc退出。
- 初次打开会显示海岸/港镇资源准备提示。

## 内容

程序生成连续高程、沙滩、岸壁、浅海和坡地；水波、浅水光纹、岸沫、云、草和雨持续变化。模型散件可替换组合，没有使用整张固定地图照片。

五栋港镇建筑和码头由共享材质的真实三维几何组成，包含瓦片、屋檐、窗框、百叶、阳台、门阶、庭院、木箱和码头桩栏杆。新增12类家园建筑样板：灯塔指挥所、回收场、菜畦育苗、工坊、仓库、能源储能、营舍、整备医疗、研究所、反甲炮、防空、掩体战壕。实际保存为`scenes/facilities/`独立可编辑场景。展示区排列便于比样，正式家园不要求照抄此布局。

植被使用免费许可模型，修正瘦长怪树和伞状松的默认选择，分块实例化并避让建筑、道路、陡坡；实际采用清单和来源在`assets/vendor/nature-refine/`。地表草仍随风变化。只有本人角色/步兵用2D动作，树石、建筑、登陆艇和战斗载具均为真3D。

目前有普通登陆艇、重型登陆艇、快速突击艇、8轮两栖车、坦克、自行火炮、运输直升机和武装直升机。八件GLB共40,280三角、18表面，约2.71MB，保留Blender源、独立炮塔/跳板/旋翼、地面/水线及舱位接口。旋翼和艇尾迹实际运动；沿展示路线行驶，真实登卸载/战斗AI仍待接。三条水艇航线对默认种子逐相位检查完整艇体与龙骨净空。元数据、许可、尺寸和核验在`assets/vehicles3d/`。

另增9类废土建筑与火力点，以及围墙、主门和侧通道，合计33处新增设施/墙段；连同既有港镇和家园样板，全场51处设施实例。破楼板、外露钢筋、锈管、船壳工棚、补丁棚布、油罐/吊机与沙袋炮位均为真实几何。位置和足迹可编辑，不意味着正式塔防裁决已经接好。

`scripts/coastal_geography.gd`统一这份720×720m样区的米制高度、岸型、河流与沼泽，装饰随机与地理随机分开。海浪具有实际顶点起伏、传播的碎浪与泡沫，湿地使用独立低洼水面和芦苇。宽滩/窄湾/海崖可分辨；`landing_at`只是局部地面演示，尚不含正式吃水、连续滩宽、接近水路、后方通路和拥堵校验。该样区不是满级家园岛，也不是正式随机地图生成器。

榛穗、雪栀、栗遥使用项目已批准的本人SD，每人6帧：待机、眨眼和4步态，在港镇和家园各展示一组。Sprite3D按原脚底锚点显示，已修正三维Y轴偏移并核左右镜像。SD采用可读性展示尺度，与真实人的物理身高不同；本样区尚无物理战斗实体。

## 素材来源

- 自然素材以本轮`assets/vendor/nature-refine/selected.json`和该目录来源记录为准。上一版保留的Quaternius [Ultimate Nature Pack](https://quaternius.com/packs/ultimatenature.html)树石为CC0，所取GLB来自保留原包来源映射的[公开格式转换镜像](https://github.com/trebeljahr/quaternius-showcase)，旧来源与SHA在`artifacts/land-art-demo-20261115/sources/quaternius-mirror-downloads.json`；旧文件不覆盖。
- Kenney Nature Kit保留为未使用备选。第一版Stylized Nature官方网盘曾额度满；本轮免费候选和最终取用记录分开，不把下载失败文件当作可用模型。
- 字体复用项目Noto Sans SC，许可在 `assets/fonts/OFL.txt`。界面使用实际wght轴500，避免变量字体默认Thin。
- 建筑、地形和水云着色器由本项目制作；角色来源/逐帧SHA/原裁区/脚底信息见 `assets/cast/cast-manifest.json`。

本轮未调用Tripo、未生成付费模型。参考截图用于研究，没有成为发行贴图。

## 已验证与边界

Godot4.7.2 Compatibility在Windows/RTX5070上实际运行并截图，场景无脚本/着色器错误；真实鼠标检查港镇镜头、滚轮缩放与地图拖动。晴日/薄暮/阵雨通过实际渲染截图比较。可编辑SCN成功保存并另行加载验证。

桌面性能只属于这份美术样区，数值见 `artifacts/land-art-demo-20261115/desktop-sample-metrics.json`；其中Godot静态分配值不是完整进程RSS，绘制/图元统计含相关渲染通道。本轮没有Android实机或完整战斗性能结论，也没有替换正常游戏入口、原核和账号。

画面仍供风格评审：树木采用免费包轮廓，地表和道路微细节、聚落密度可以在确定方向后继续调整；当前没有完整新地形规则、经济/工事平衡或随机全岛系统。

第二轮记录在 `docs/development/coastal-wasteland-demo-20261116.md` 与 `artifacts/coast-v2-20261116/`。Windows桌面实际截图、独立地理/设施/模型检查、近远镜头统计不替代中端手机实机验收。旧轮次回执是当时快照，不用于证明新版已验收。正式接入次序见 `docs/design/coastal-wasteland-followup-20261116.md`。

## 复现截图

使用已安装Godot在本工程后加用户参数 `-- --capture`，会实际渲染晴日海湾、港镇、山林、薄暮、阵雨与两张无界面近景，写入项目 `artifacts/land-art-demo-20261115/screenshots/`。截图同时更新可编辑SCN；这不是图片生成的效果图。

本轮更新使用`-- --capture-home`，截图写到`artifacts/home-design-20261116/screenshots/`，保留第一轮已认可截图。`home_gallery.tscn`运行时逐一渲染12建筑并保存可编辑设施场景。设计图册在工程根目录`CAS-Home-Design.cmd`，完整大纲在`docs/design/home-building-economy-defense-outline-20261116.md`。本轮检查与边界在`artifacts/home-design-20261116/delivery-validation.json`，不将桌面模型与美术通过冒称新家园经济或Android通过。

第二轮使用`-- --capture-terrain`，保存11个实际镜头、16帧四秒海浪采样、近远景统计与新的可编辑静态SCN；输出到`artifacts/coast-v2-20261116/`。重打包图册执行`python scripts/package-coast-v2-review.py`，路径/原图SHA复核加`--check`。地理/设施/GLB/静态快照复核：Godot加`--headless --script res://tools/check_coast_v2.gd`。
