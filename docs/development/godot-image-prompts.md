# Godot 本轮图片提示词与来源

使用内置 imagegen，未使用CLI/API回退。所有采用图片已复制到项目；源图片、角色identity、SHA-256和逐张提示词保存在各图旁JSON与 `tools/first-wave-generated-art.json`、`tools/initial-fleet-generated-art.json`。

## 弗莱彻第二版

目标 `godot/assets/characters/chibis-generated/ibs-u-usn-fletcher.png`。参考一为CAS现有弗莱彻立绘，参考二为用户站Spine静态小人，只提供比例和笔触，不转移红发/眼镜等外观。生成要求：单个透明角色，两头身，头部连帽约占总高55%–60%，小肩短躯干短四肢，保留金发短发/青色眼睛与围巾/白帽金舵轮/深蓝金边外套及灰色小舰装，清楚深色线稿、少量平涂明暗，80px可辨，右向三分之四站姿，去掉书本减细节，不要厚涂、长腿、底座、文字或第二个人物。第一版厚涂长身稿已标记拒稿，不用于投影。

## 征募云海背景

目标 `godot/assets/backgrounds/recruit-sky.png`。完整提示词：

> Original wide 16:9 background art for a premium anime naval character recruitment menu. NO characters, NO text, NO logos, NO buttons or UI. A luminous sea of layered soft ivory and powder-blue clouds above a serene faraway ocean horizon, pale lilac shadows, subtle warm sunlight from upper right, delicate faint maritime chart arcs and distant navigation stars worked into the atmospheric painting, refined Japanese animation background painting, elegant and spacious. Left quarter should be pale clean sky for dark navy typography; center and right open for three overlaid tall shipgirl illustrations. Bottom 15 percent a softly shadowed slate blue cloud bank to support pale ivory action buttons. It should feel like a hopeful voyage and summoning a distant signal, luxurious illustrated game banner rather than a photorealistic sky. Avoid rainbow neon, mechanical UI panels, ships or buildings, gacha brand motifs, copied game logos, ornate borders. Beautiful painterly cloud structure with crisp light, restrained saturation.

## 参考截图

- [明日方舟编队](https://www.biubiu001.com/mrfz/42489.html)：角色与职业/等级的集中识别、右侧强行动、已编入状态。
- [碧蓝航线编队](https://game.xiaomi.com/viewpoint/1127866428_1604657313151_16)：舰位与角色、旗舰与舰队区分。
- [原神祈愿截图](https://ol.3dmgame.com/gl/190989.html)：插画主视觉、底部抽取、细节/历史分层。仅学习结构，不采用页面中的角色/概率等事实作为CAS规则。

研究截图只保存在 `artifacts/design-references/`，不加入游戏资源。
