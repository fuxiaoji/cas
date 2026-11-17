# 新经济、舰娘详情与自有舰战役演练验收

日期：2026-11-11。范围为 Godot 客户端实际页面与原核接线；本文不表示支付、PvP 或其他未开放服务已完成。所有验收使用隔离的临时账号，未改用户存档、原始 PDF 或参考项目。

## 页面与源文件

| 页面/产物 | 源文件 | 已交付行为 |
| --- | --- | --- |
| 军需 | [supply_presentation.gd](../../godot/scripts/supply_presentation.gd) | 舰娘、补给、礼包、兑换、舰队战术五分类；物件/角色图、价格与可购状态；连接真实购买事务；仓库入口 |
| 舰娘详情 | [ship_detail_presentation.gd](../../godot/scripts/ship_detail_presentation.gd) | 独立 `render(app, ship)`；原始舰表、等级/熟练度、综合舰装、舵手/火炮/损管/指挥四组水手；装卸与成长刷新 |
| 资源与天梯 | [mission_presentation.gd](../../godot/scripts/mission_presentation.gd) | 读取实际任务、体力、预算、奖励与周剩余次数；出击交给主客户端，不在表现层发奖励 |
| 出航、活动与邮件 | [modes_presentation.gd](../../godot/scripts/modes_presentation.gd) | 打捞、剧情、战役、资源、天梯、学堂图像入口；活动与邮件独立；邮件附件、签到和周补给沿现有服务提交 |
| 征募接线 | [recruit_presentation.gd](../../godot/scripts/recruit_presentation.gd) | 常驻/UP征募、已提交结果的演出和回看、元词兑换入口；演出跳过与重播不重复扣券 |
| 战役部署 | [campaign_deployment.gd](../../godot/scripts/campaign_deployment.gd) | 新增故事难度“自有舰战役演练”开关；仅自有候选、禁止重复身份、未拥有舰位明确提示；保留历史借用和标准/挑战入口 |
| 经济与推进服务 | [economy.gd](../../godot/scripts/economy.gd)、[meta_economy.gd](../../godot/scripts/meta_economy.gd)、[progression.gd](../../godot/scripts/progression.gd) | 所有钱包、实例所属、奖励和存档变更的实际服务层；UI不另存一套结果 |
| 主路由 | [main.gd](../../godot/scripts/main.gd) | `shop`、`ship_detail`、`mail`、`resources`、`ladder` 及真实任务出航接线 |

## 11 类 API 接线与边界

| 类别 | 实际调用 | 边界 |
| --- | --- | --- |
| 1. 账户展示 | `wallet()`、`roster()` | 银币对应 `credits`，元词对应 `origins`；显示真实拥有状态和体力，不由 UI 补足资产 |
| 2. 军需目录 | `supply_catalog()` | 使用目录价格、货币、`owned` 与 `limit_remaining`，已拥有/限购/不足状态阻止购买 |
| 3. 商品事务 | `purchase(id, count, request_id)` | 直接购舰、补给、礼包、兑换均由服务提交；不使用假到账动画代替事务 |
| 4. 旧战术商品 | `progression.ai_options()`、`buy_profile()` | 保留原战术解锁；不能把未购策略显示为可用 |
| 5. 成长与整备 | `growth_profile()`、`train()`、`repair()`、`rearm()`、`mastery_rewards()`、`claim_mastery_reward()` | 训练读取实际银币/材料价格；训练获得经验，熟练度通过实际参战获得；熟练奖励按每舰每档一次提交；舰表原值不被成长覆盖 |
| 6. 实例目录 | `gear_inventory(ship_id, slot)` | 读取唯一物件、品质、主副词条和所属；禁止把其他舰娘占用物件当成仓库库存 |
| 7. 装卸事务 | `assign_item(ship_id, slot, instance_id)` | `equipment/helmsman/gunnery/damage_control/command` 五槽；空实例 ID 卸下，物件返回仓库 |
| 8. 任务与原核出航 | `mission_catalog(kind)`、`app.launch_mission(kind,id)` → `preview_sortie/begin_sortie/native_start` | 体力及编队由实际航次校验/冻结；资源副本与天梯真实出航。周元词次数耗尽后仍可打，奖励展示读取剩余次数 |
| 9. 活动与邮件 | `claim_mail()`、`claim_attendance()`、`weekly_status()`、`buy_weekly_ticket()`、`claim_weekly_supply()` | 独立页面，共用已有领取记录；已领附件不能重复领；当前为本地既有活动/欢迎邮件，不是线上邮件后台 |
| 10. 征募演出 | `recruit()`、`recruit_animation()` | 抽取先提交再演出；跳过到总览，回看不重新抽取；概率/保底继续由经济层处理 |
| 11. 自有舰战役 | `campaign_growth(request)` → `new_campaign.ownedGrowth` | 必须 `story` + 显式 `fleet/groups` + 全部不重复的已拥有身份；`context.deployment=owned_practice`。UI不能把未拥有历史借舰带入成长演练 |

## 202 艘舰表来源

[ship-reference.json](../../godot/data/ship-reference.json) 由 [build-godot-ship-reference.py](../../scripts/build-godot-ship-reference.py) 按 `ranked_fleets::data` 的取卡顺序生成：已核时期卡 → 已核合并卡 → 原核已有的序章/演习舰级参考。覆盖集合与 Godot 可玩身份的 202 条完全一致；只规范化身份和显示舰名，其他舰表字段逐项断言与源记录相同。

来源为 `src/ranked_fleets.rs`、`src/ranked_profiles_merged.inc`、`data/stage0.json`、`data/campaign/period/prologue-runtime.json`、`data/ships/period-cards.json`、`data/ships/merged-cards.json`。产物保留每舰 `source_kind/source_class/source_file/source_pages` 和上述六文件 SHA-256。使用同舰级参考的身份保留 `same_class` 标记，并不冒称每个身份都有独立时期舰卡。

舰表展示耐久、航速、装甲、转向、主副炮、鱼雷及受损航速等原值；账户加成只列在成长页。装备“综合强化”作用于耐久/航速/炮击；四组水手按实际主副词条展示。同步机动成功率用于打捞，战役沿用原控制，详情页已明确提示。

## 实际验收与截图

| 检查 | 结果 | 记录与测试 |
| --- | --- | --- |
| 新经济/详情 UI | **59/59**，16 张图 | [meta-ui/receipt.json](../../artifacts/godot/meta-ui/receipt.json)；[meta_ui_test.gd](../../godot/tests/meta_ui_test.gd) |
| 历史部署回归 | **72/72**，4 张图 | [deployment/receipt.json](../../artifacts/godot/deployment/receipt.json)；[deployment_integration_test.gd](../../godot/tests/deployment_integration_test.gd) |
| 自有舰演练 | **42/42**，6 张图 | [owned-campaign/receipt.json](../../artifacts/godot/owned-campaign/receipt.json)；[owned_campaign_ui_test.gd](../../godot/tests/owned_campaign_ui_test.gd) |
| 完整菜单定向回归 | **26/26**，本次为 headless | [full-modes/ui-receipt.json](../../artifacts/godot/full-modes/ui-receipt.json)；[full_modes_ui_test.gd](../../godot/tests/full_modes_ui_test.gd) |

窗口检查计数包含截图保存检查。经济 UI 的装备/水手使用临时账号中明确创建的测试物件；购买、兑换、邮件、训练、装卸回调均真实执行。资源任务完整出航由主客户端集成验收覆盖，不把目录页面渲染当成副本通关证据。征募定向检查用隔离账号的保证 UP 测试配置检查演出，未修改正式卡池。

16 张经济截图位于 `artifacts/godot/meta-ui/`：`shop-{supply,ships,bundles,exchange,tactics}.png`、`mail.png`、`activity.png`、`resources.png`、`ladder.png`、`ship-{reference,growth,equipment,crews,trained,equipped,crews-equipped}.png`。已目视物件图、四组水手图、礼包三角色、训练价格、详情与入口排版。

自有演练通过真实原核出航与真实终局验证：Lv.30 耐久约 +5%；原舰位位置、航向、航速、编队号保持；去除唯一新增成长字段后保存的初始生成参数相同；成长快照可重载；结算零历史星且不修改历史推进；实际参战积累熟练度；演练前个人 17 耐久/9 弹药保持不被扣取。默认历史部署与预设导入、九舰替换、单舰特混的既有 72 项回归同时通过。

熟练度小额奖励追加验收：成长页在熟练度条下提供一行四档按钮，250/500/750/1000 各可领取 5 元词及 50 银币，未达成与已领取均禁用；具体档位与奖励直接读取 `mastery_rewards()`，回调提交 `claim_mastery_reward()`，不扣除或增长熟练度。[mastery_reward_ui_test.gd](../../godot/tests/mastery_reward_ui_test.gd) 的 **21/21** 定向检查通过，记录见 [mastery-receipt.json](../../artifacts/godot/meta-ui/mastery-receipt.json)。它使用临时账号的明确熟练度边界测试值，验证 249 禁领、250 达标真实到账、重复幂等、重新载入保留领取标记、四档累计仅 20 元词/200 银币；没有伪造战斗结果。这是后续 headless 定向验收，未重新声称跑过全部 59 项或增加窗口截图。

## 明确未开放与模式边界

后续默认搜打撤更新为 v3 后，完整 [client_integration_test.gd](../../godot/tests/client_integration_test.gd) 窗口回归 **135/135** 通过，记录见 [free-fleets-integration/receipt.json](../../artifacts/godot/free-fleets-integration/receipt.json)：99 次 Godot 内部指针事件走过十连征募、两编队真实出航、搜索中途存档并重启、实际撤离、卖货、军需购买、单舰训练与弹药计划、再次交战失败、历史借用战役真实终局。对新原核只扩展真实伤害事件识别为 `damage` 或 `creature_hit`，并新增真实 HP 下降与 `salvage-v3` / `archipelago-3` 版本断言；没有伪造战果或放宽到账与幂等检查。单舰弹药计划的原有“不提前扣装载量”语义继续通过；新批量整备另由根代理验收。

- `payment_status().enabled=false`；充值和多人奖励按钮禁用。没有实装支付到账、线上 PvP 账户服务或 PvP 奖励。
- 历史借用、标准和挑战不应用账户成长；历史原始舰表、阵位与敌军不因养成改变。自有演练是显式选择的独立模式，独立奖励由实际结算服务处理，不计历史星数。
- UI 不产生战斗胜利、掉落或奖励；剧情、战役、资源副本、天梯的资源以原核结果及经济服务返回为准。
- 小人生成继续暂停。本次美术复用既有角色图，采用实际新增弹药箱及四类水手组物件插画；不涉及战场环境生成规则。
