# CAS 动漫云海 UI 重构

用户批准：2026-11-11。小人制作保持暂停。

## 体验原则

母港看角色，编队做选择，战场看海域与威胁，剧情看人物与故事。每个画面有一个主视觉和一个主要行动。文字服务选择，数字在需要决策时出现。通过场景、角色裁切、物件和图标传达内容，不靠重复边框和说明撑满画面。

## 视觉准则

采用用户提供的三张参考中的青蓝水色、日光岩岸、软白云与云影。根据后续字体与设计反馈，主界面调整为冷白 #F5F8FA、海军墨蓝 #182F46、海水青 #23869A、暖金 #F2CF84、警示珊瑚 #D96C60。统一内置 Noto Sans SC：正文 400、操作 500、章节 600、仅母港主操作 700 字重；禁用宋体与系统字体混搭。常用操作 20–22、正文 20–24、章节 28–32 基准像素，通过字重和间距区分层级，不继续放大标题。辅助战术信息不低于 18；长舰名省略并保留完整提示。

母港以连续场景构图承载角色，导航位于边缘；移除覆盖海面的整块白色介绍卡。一般控件使用小圆角、低填色与一致焦点，图标成套，不混用胶囊与大圆角卡片。剧情控件在画面边缘轻量显示，角色对白不套应用工具栏。

海域必须实际运动：有方向的碎浪、岸浪周期、航迹与云影，不用静态海图加闪点代替动态水面。新搜打撤航次的天气由原核版本化过程驱动，按模拟时钟逐步变化，暂停不推进天气；水纹等环境动画可继续。历史战役保留原定环境；风的表现不能冒充未实现的风对弹道/航行修正。

## 页面职责

- 母港：大角色与港口场景、一个出航入口、少量常用导航。
- 准备：阵容、装备、任务与预算的明确取舍；其余详情展开。
- 战斗：常驻必要信息、情境命令、可固定详细指挥抽屉。
- 剧情：独立全屏演出，无钱包或全局底栏。
- 征募：独立主视觉，面部/立绘镜头、可跳过演出、清楚费用与规则。
- 经济：物件图、相关货币、明确提升效果，战报和交易详情按需查看。

## 参考

- https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md
- https://github.com/saschb2b/skills/blob/main/skills/productivity/game-design/SKILL.md
- https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/disciplines/game-ui-ux/SKILL.md
- https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/disciplines/create-game-assets/SKILL.md
- https://www.badnorth.com/
- https://developer.apple.com/videos/play/meet-with-apple/247/

借鉴参考的视觉与交互方法，不把其他游戏截图作为发行素材。CAS 裁决、真实坐标和可见性来源不变。
