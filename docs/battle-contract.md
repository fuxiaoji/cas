# 战斗接口（本地 v1／v2）

Windows、Android 和测试驱动共享 Rust JSON 接口。Worker 接收 `{id, request}`，回复 `{id, response}`；内核返回 `{ok:true,data}` 或 `{ok:false,error}`。海图以米计，x 向东、y 向北，0° 为北，航向顺时针，速度以节计。

- `info` 返回内容协议版本和步长；`new` 接收阵营、种子、敌方风格、己方领舰位置和 `variant`（空字符串为白昼、`challenge` 为 3 对 5、`night` 为虚构夜航）；`observe` 只返回玩家视角。`campaign` 无需先开局，返回固定版本的历史档案；`playable: false` 不能当作可启动的 `variant`。
- `preview_route/route` 接收编队、机动方式、航速和多个点；`preview_reform/reform` 预览或执行重整。接纳前不能改变路线。路线响应中的实际航迹可能包括预转向直驶段。
- `aim` 接收舰、可见接触、武器及可选射向，返回合法性、炮位或发射扇区。送入 `fire` 的方向在世界坐标下锁定，窗口到期重新核验；接受命令并不等于已经开火。取消的界面手势不调用 `fire`。
- `ai` 保存风格与三个委托类别；`suggest` 可查建议。玩家接管一个类别，其他类别不变；AI 使用相同的预览和合法性门。
- `step` 推进整数模拟秒。存档以规则版本、种子、部署、时钟和接受命令重建战局。`replay` 是只读重演；`load` 替换当前本地战局；`report` 输出己方可知事件和结局。
- v2 观测增加本舰 `classId`、`gunRange/torpedoRange`（米）、`systems` 和实际炮座射向，敌方接触无舰况。`shells` 投影授权本席可见的齐射进度和发射时固定的航迹；`torpedoes` 中敌方仅有已发现尾迹的位置及方向，无发射点和准确剩余数量。`settling` 表示演习停止接令、等最后八秒弹着。原 `cas-stage0-v1` 存档按旧瞬时炮击规则重建。
- 战情使用本席连续 `id`，音频适配可消费可选 `voiceCue`。v8 的本方武器实际发射和照明可附 `own_ship`，供引导检查本人操作。隐藏事件不会给对方制造编号空洞。部分事件有本席已知的海图坐标，发射迹象可以无坐标。
- `new` 的 `prologue` 和 `night-radar-training` 使用固定部署。序章仅允许操作第五驱逐小队，固定序幕和实时接管可由同一版本及种子重建。

这批是本地接口，不能直接公开到互联网。线上需要服务端持有权威状态、绑定身份与席位并单独处理重连、比赛版本和持久化。离线存档不是云钱包结算凭证。

## 战役接线补充

`new_campaign` 接收 `id`（通道行动 `CAMP-ALLIES-01`／`CAMP-AXIS-01`，圣乔治角 `CAMP-ALLIES-03`／`CAMP-AXIS-03`）、`difficulty`（`story`／`standard`／`challenge`）与可选本机 `seed`、`profile`。新战役冻结规则版本 `cas-campaign-v8` 和内容版本（`cas-channel-runtime-v1` 或 `cas-cape-runtime-v1`）。v5 至 v7 战役按原时序读档，规则、阵营、想定或内容不匹配时拒绝读档。观察的 `campaign` 只含本席任务、标签、难度和可选公开撤离线。终局的 `result.grade` 和 `result.primary` 是本席胜利等级与说明，演习结果的 `primary` 为布尔值。

部署原生服务时，[服务器接口](../server/README.md)包装同一内核；线上战役内测目前开放圣乔治角双线，不向浏览器返回种子、重演存档或未公开命令。开发浏览器默认回环 8021；正式编译时可以用 `VITE_CAS_ACCOUNT_URL` 指定测试服务。默认内测包不配置线上服务，照常支持离线。
