# 原创音乐与横向小人转场

设计从“母港休息、剧情留白、战斗推进、家园期待”四种体验展开。音乐不承担攻略信息；危险仍由真实预警、音效、人物语音表达。共11首不同主题，曲名、调性、速度、时长、音符和声部来源见 `music/original-v1`。当前音色为原创合成编制，后续可在同一MIDI上换真人演奏或更精细的原创音源。

`CasAudioDirector.set_scene` 支持 title / harbor / story / story_tension / battle / landing / home / tide / victory / defeat。harbor及编队/仓库/军需/征募菜单在现实本地06:00–17:59选白日，其余夜港；30秒检查跨界，可注入时钟测试。salvage兼容映射为story探索曲，原战场仍battle。Root负责页面与世界事件接线。

两个音乐播放器保留连续交叠，约0.85秒等功率淡化；旧解码器在完成淡化后停止。电台duck独立于切曲，避免一条音量Tween取消另一条；`set_dialogue_active` 为剧情演出提供同样空间。用户音量、总开关、广播开关沿用原JSON结构，测试可以注入隔离settings_path。保留语音本席可见事件、去重和未知方向不猜测规则。

转场当前已按后续“不要一下子划走”的反馈改为1.18秒、屏内前进14%宽度的三段短跳；每跳落地停住，腾空才前进。三种全屏动漫遮盖/揭幕、约三名随机已登记本人SD、减少动态和输入释放保持。原0.62秒屏外横穿设计及下列历史验收属于上一轮，最新参数、真实60fps短片和770项回归见[三段短跳说明](three-short-hop-transition.md)。音乐部分保持原样。

范围：表现与音频，不改变模拟时钟、世界坐标、裁决、经济或历史战役。循环/响度等自动检查不等同于完整主观音乐审美评价；A/B试听合集中各曲顺序和截点明确记录，便于继续美术/音乐评审。

验收：11首约704.82秒/8.90MB，解码音频99/99；WASAPI真实A/B短段播放与尾端跨8小节循环/单次结束、双播放器/duck/昼夜/保留音量，以及4窗口横移转场共147/147；音量设置实际UI7/7；既有全屏转场50/50、真实切页与屏障9/9，共312项通过。混音-22.47～-21.79LUFS，真峰-11.46～-9.25dBTP，无削波，实际循环接缝最大样本差0.00511。胜负结束后的总线静音为预期。默认0.62秒、关闭/减少动效均核验。详情及试听见 `artifacts/original-music/receipt.json`，没有写正常账号或原音量设置。

既有 `economy_audio_test` 的旧经济结算夹具在到达音频前已被新版合法性检查拒绝（line55–58）；日志保留，不计为通过，也未为过测修改经济逻辑。其旧MP4期望已随授权替换原创音乐；音频与实际设置的完整独立测试如上。
# 最终主路径集成复核

2026-11-13 正式默认核 `7134b0254ce4ef91317181545eac2844813d8b6b54d95f644a5ec65db9a1a79b` 部署后，空 `CAS_SIM_PATH` 再次通过音画147/147，真实音频驱动WASAPI，原音量设置未写入。另有生产 Main 路由59/59：title→title、home/home_recruit→home、home_story前篇→story_tension+duck、原章节对白回顾→story+duck、海陆实战→landing、肉鸽大厅/实战→tide、真实中止结果→defeat；经过实际开始与微步更新后仍保持对应乐曲。独立家园教学120/120包含真实胜利结果→victory、战后故事→story。回执分别为 `artifacts/godot/original-music-transition/receipt.json`、`artifacts/scene-music-routing/receipt.json`、`artifacts/home-story/receipt.json`。不把暂停状态的音乐解码误当播放失败，不把原账号正在进行的guide节点误当对白；初版路由测试误判证据原样保留。

