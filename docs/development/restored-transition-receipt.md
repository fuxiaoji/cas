# 恢复轻量转场与三名放大小人

2026-11-12。用户要求过场改回原来的版本，小人放大、约三个。本轮恢复页面淡入与小人跳动的旧表现，而不是继续默认随机1–20人的全屏云浪遮盖。

## 旧版依据与实际修改

- 既有 [全屏转场回执](fullscreen-transition-receipt.md) 明确记录，之前是“小面积小人跳动加页面淡入”。旧实机图 `artifacts/godot/fleet-navigation/04-jumping-transition.png` 保留了出航页上单个小人跳动的原构图；本轮依照这个模式恢复，不冒称找回了已不存在的旧源码逐字节版本。
- `page_transition.gd` 默认 `full_screen_wipe=false`、总长0.42秒：新页面同步建立并短淡入，没有旧页截图、云浪全屏覆盖或加载停留。短暂透明输入门阻止误点新页面，完成或取消即释放。
- 默认三名，按可用本人SD随机挑选，不重复、不借其他角色；账户不足三名就用实际数量。数量上限硬夹到3，旧场景若序列化20或异常值也不会恢复密集人群。210名素材候选沿用现有身份登记，没有生成新图或变更源像素。
- 小人集中在画面中下方，目标高度约画布26%；1600×900设计画布实际包围高约226–254px，1280×720窗口约180–200px。各自独立相位、速度、起跳延时、跳高和轻摆，画面保持三人而不是随机人数。
- 同页刷新、关闭页面动效、减少动态、headless均直接切换；快速连续导航、取消、页面销毁不遗留半透明页面或输入遮罩。仅UI私有随机源和帧时间，不读战斗真态、不发战斗/经济命令、不改账户进度。
- 三种既有全屏转场仍保留为显式编辑选项和原F6演示，默认游戏不启用；没有为了恢复轻量默认删掉已可编辑的遮罩/Timeline。

## 实际验收

- `godot/tests/chibi_crowd_transition_review.gd` 真实NVIDIA GPU **239/239**：80次全部三人，选到137个不同身份、单次无重复；960×540、1280×720、1600×900、1600×720四窗口大小/边界/独立动作/背景未覆盖。另验旧序列化大值硬上限、实际淡入、取消、快速导航、减少动态、同页、空/少量可用角色，以及场景参数修改保存再加载。
- `godot/tests/restored_transition_route_review.gd` **9/9**：使用隔离新账户，真实母港→出航页，三名本人SD与轻量淡入；真实指针无法误触下方返回按钮，动画自然结束后页面完全可见，连续切页最终落在指定页面，账户货币/进度完全不变。
- 既有 `fullscreen_transition_review.gd` 明确启用可选全屏模式后 **50/50**，三种遮罩四窗口完全覆盖/揭幕和输入释放仍通过。这验证保留选项，不是默认轻量效果的替代证据。
- 专项回执/四窗口图：`artifacts/godot/restored-transition/receipt.json`；真实菜单回执 `actual-route-receipt.json` 和 `actual-modes-three-large-chibis.png`。已实际目检三人大小与真实页面构图。

## 编辑入口

实际运行场景 `godot/scenes/ui/page_transition.tscn`；Inspector直接调整 `Full Screen Wipe`、`Duration`、`Max Transition Characters`、`Character Height Fraction` 和角色开关。`page_transition_overlay.tscn` 保留Actor与Timeline原生节点。可选全屏演示为 `godot/scenes/demos/transition_gallery.tscn`，明确启用其全屏选项，不改变默认游戏。

本轮仅改转场相关源/测试/演示场景与本回执，未修改原始PDF、参考项目、历史战斗参数、账户正式存档或卫星地图代码。
