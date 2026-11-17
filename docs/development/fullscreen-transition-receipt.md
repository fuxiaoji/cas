# 全屏动漫转场与 Godot 编辑回执

日期：2026-11-12。范围仅为页面呈现和导航验收等待，不改历史舰表、战斗模型、双盲、时间推进、经济或随机地图数据。

## 设计结果

旧效果为小面积小人跳动加页面淡入；本次改为完整覆盖画面、展开新页的短转场。三种效果为云浪擦除、圆形揭幕、斜向帆片，配原创程序化云朵、两层海浪和金色边缘。小人从已有己方 SD 投影中选取，仅作点缀。默认总时长 0.56 秒，没有进度条、假加载或等待用户确认。

关闭页面动效、启用减少动态、headless、初次启动无旧页、同页刷新均立即切换。活动的遮罩短暂接收点按，结束隐藏后恢复穿透。全屏 CanvasLayer 不依赖页面布局，四种分辨率均验收。

## 实际查阅的开源案例

通过 GitHub 连接器检索仓库、读取原始源码和许可证，并用网页搜索补充发现。没有安装运行第三方插件，没有复制第三方美术；本项目控制器、云浪构图和三个遮罩为独立实现。

| 案例 | 核实内容与借鉴 | 许可证与查阅快照 |
| --- | --- | --- |
| [Saltmire Transitions](https://github.com/saltmire/saltmire-transitions) | 查阅 `transition.gd`、`circle.gdshader`、`wipe.gdshader`；借鉴 ColorRect + ShaderMaterial、cover/reveal 分段及圆形适配宽高比的组织方式。 | [原始 LICENSE.txt](https://raw.githubusercontent.com/saltmire/saltmire-transitions/master/LICENSE.txt)：MIT，Copyright (c) 2026 Saltmire。Git tree 快照 `7c6f5cc07ec3f80110387f1d0e21dd82065cf827`。 |
| [IUX Games EasyTransition](https://github.com/IUXGames/EasyTransition) | 查阅 `addons/easytransition/easytransition.gd` 和 `transition.gdshader`；参考全屏幕进出动画、圆形/方向性遮罩的常见表现。 | [原始 LICENSE](https://raw.githubusercontent.com/IUXGames/EasyTransition/main/LICENSE)：MIT，Copyright (c) 2026 IUX Games。Git tree 快照 `653fb68324b4150580de84055dfd229bd6d4e6ca`。 |

以上 Git tree 标识记录查阅时的源码树，不代表加入项目的依赖版本。项目未引入上述代码副本或依赖。

## 编辑入口

- `godot/scenes/ui/page_transition.tscn`：游戏实际实例化的 CanvasLayer。根节点 Inspector 可直接调整样式、总时长、云/海/金色、小人开关、旧帧移除时点。`Editor Preview` 滑块直接预览 0–1 的帧；编辑颜色和样式实时刷新编辑器画面。
- `godot/scenes/ui/page_transition_overlay.tscn`：实际运行的命名节点 `OldFrame`、`Mask`、`Actor`、`Timeline`。选中 Timeline，在 Animation 面板选择 `cover_reveal` 可编辑遮罩进出曲线。动画长度可调整，控制器按资源长度换算总时长。
- `godot/shaders/cartoon_transition.gdshader`：原创遮罩、云形和海浪构图；Mask 的 ShaderMaterial 为每个场景实例独立资源。
- `godot/scenes/demos/transition_gallery.tscn`：独立 F6 演示，三个按钮和减少动态选项均为可直接选中的真实 Control 节点。演示不加载战斗核心或玩家账号、不写存档。并非替代运行场景的孤立美术稿；其转场实例和游戏为同一 PackedScene。

改动 Timeline 时，保持完全覆盖的停留段包住 `Swap Fraction` 指定时点，避免从旧截图切到新页的瞬间露边。默认覆盖停留为 0.235–0.295 秒，移除旧帧约为 0.255 秒。

## 同步页面 API 的整合

保留 `show_page()` 原有同步建页语义，防止 `enter_battle()` 返回后立即更新海图或创建窗口时拿到旧对象。旧页销毁和窗口模式改变之前调用 `capture_previous(app,next)`，现有新页创建后的 `play(app,page,previous,next)` 不变。

旧画面只保留一张已向该玩家渲染的像素图，在遮罩完全覆盖时隐藏并释放，转场结束再次清理。没有读取敌舰/地图模型、重新模拟或消耗权威随机数。装饰选择使用自己的 RandomNumberGenerator；没有修改全局 RNG。GPU 截图不可用时直接切换。

## 验收证据

- Godot 4.7.2 headless 编辑器导入、F6 演示启动：无脚本解析错误。
- `godot/tests/fullscreen_transition_review.gd`：Windows + NVIDIA OpenGL Compatibility，**50/50**；960×540、1280×720、1600×900、1440×720 各测三种遮罩的九点全覆盖和揭幕端点，另测旧帧中点释放、动效结束恢复输入、关闭/减少动态直切、同页刷新。独立纯展示 fixture，不读取或写入玩家账号。
- 上述脚本 headless 分支 **2/2**：命名节点/动画资源存在，路线立即切换。
- 实际 `fleet_navigation_review.gd`：**56/56**，87 个内部指针输入事件，验证母港导航、编队、仓库、秘书舰与实际转场。使用独立测试账号。
- 图片和 GPU 回执：`artifacts/godot/fullscreen-transition/`；实际导航回执：`artifacts/godot/fleet-navigation/receipt.json`；日志：`artifacts/transition-gpu.log`、`artifacts/transition-fleet-integration.log`。

旧导航验收曾假定页面两帧内即可点按；新增 `godot/tests/transition_settle.gd` 按实际 `is_busy()` 等待，1.2 秒超时保护，没有通过取消遮罩绕过输入行为。相关旧 click 和截图 helper 已采用此等待。

## 编辑性边界

本次转场的实际运行场景、子节点、遮罩材质、动画和 F6 演示均可编辑。其余复杂战斗 HUD 仍有脚本创建的区域，不能因为项目可打开就宣称全部完成可视化场景转换；需逐个把稳定界面迁入 PackedScene，保留数据/命令绑定和 Remote 检查。母港、活动、充值页面的运行场景化由主代理同时整合，本文不替它们签收。
