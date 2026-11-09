# P1 战役大厅与关卡前编成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「选关 → 简报 → 编成 → 出航」做成新战役大厅与独立编成屏幕，覆盖 6 个可出航关卡（圣乔治角、埃斯佩兰斯角等），并保留原 `CampaignArchive` 作为「史料馆」。

**Architecture:** 新增 `CampaignLobby`（三栏：关卡列表 / 战区海图 / 关卡详情）与 `DeploymentScreen`（故事难度历史舰位换舰 + 点价预算 + 校验 + 草稿）。两者共用 `ShipThumb`、`BudgetMeter`、`RuleCheck` 领域组件；数据继续走现有 `campaign` / `campaign_detail` / `campaign_fleet` 三个内核 op。旧 `CampaignArchive` 不删，作为史料馆全屏视图，旧浏览器验收仍可回退。

**Tech Stack:** React 19 + TypeScript + Vite；现有 `ask()` Worker 内核；localStorage 草稿/预设；Playwright 浏览器验收（不可用时用 Edge CDP 凭证替代）。

**Spec:** `docs/design/ux-redesign-v1.md`

## Global Constraints

- 不改 `src/` 内核、CAS 舰卡、点表、历史阵位/航向/航速。
- 故事难度保持「历史舰位数不可增减、逐位换同阵营已登记舰卡、总点价不超过历史兵力预算」。
- 标准/挑战难度不进入编成屏，直接按历史编制出击。
- 所有新样式限定在 `.campaign-lobby` / `.deployment-screen` 下，不覆盖旧 `.campaign-archive`。
- 桌面 1360×768 与 1024×600 不横向滚动；740×360 可滚动但不遮挡主按钮。
- 资料核验状态不出现在主路径；未开放档案只在「史料馆」与列表的折叠区出现。

---

### Task 1: 共享层

**Files:**
- Create: `client/src/ui/tokens.css`
- Modify: `client/src/shipPortraits.ts`
- Modify: `client/src/CampaignArchive.tsx`（导出 `goalText`、`matchNames`）
- Modify: `client/src/campaign-progress.ts`（`CampaignLaunch` 增加 `profile?`）
- Modify: `client/src/main.tsx`（引入 tokens）

**Interfaces:**
- Produces: `shipPortraitByName(name: string)`, `goalText(goal)`, `matchNames`, `CampaignLaunch.profile?: Profile`
- Consumes: `ledger.assets[].character_name`、`CampaignArchive` 的 `Goal` 类型

- [ ] 新建 tokens：`--cas-abyss/deep/panel/line/ink/muted/brass/mint/alert`、字号/间距/圆角。
- [ ] `shipPortraitByName` 按 `character_name` 找立绘，找不到返回 `undefined`。
- [ ] `goalText` 与 `matchNames` 加 `export`。
- [ ] `CampaignLaunch` 增加 `profile?: Profile`，`import type { Profile } from './engine'`。
- [ ] `main.tsx` 顶部 `import './ui/tokens.css'`。
- [ ] 验证：`npm run build` 通过（此时还没用新组件，只验证导出不破坏编译）。

### Task 2: 编成草稿与预设

**Files:**
- Create: `client/src/screens/formation/draft.ts`
- Test: 通过 `node --experimental-strip-types` 不现实；用 `tsc` + 浏览器 CDP 验证。

**Interfaces:**
- Produces:
  - `readDraft(profileId, stageId, difficulty): Draft | undefined`
  - `writeDraft(profileId, stageId, difficulty, draft): void`
  - `readPresets(profileId): FleetPreset[]`
  - `writePresets(profileId, presets): void`
  - `draftKey(stageId, difficulty)`
- Types:
```ts
type Draft = { picks: string[]; profile: Profile; updatedAt: number };
type FleetPreset = Draft & { id: string; name: string; stageId: string; difficulty: CampaignDifficulty };
```

- [ ] `localStorage` key：`cas.deployment.v1:<profileId>`、`cas.fleetPresets.v1:<profileId>`。
- [ ] 读取时校验 `picks` 为字符串数组、`profile` 属于三种、`stageId` 合法；坏数据返回空。
- [ ] 写入失败（配额/隐私模式）静默返回，不抛异常。
- [ ] 验证：浏览器控制台手动写坏数据后重开，页面不崩。

### Task 3: 领域组件

**Files:**
- Create: `client/src/widgets/ship-thumb.tsx`
- Create: `client/src/widgets/formation.tsx`
- Create: `client/src/widgets/widgets.css`

**Interfaces:**
- Produces:
  - `ShipThumb({ ship, size }: { ship: ShipLike; size?: 'sm'|'md'|'lg' })`
  - `portraitFor(ship: ShipLike)`
  - `BudgetMeter({ total, budget, segments })`
  - `RuleCheck({ items }: { items: { ok: boolean; label: string; detail?: string }[] })`
- `ShipLike = { id?: string; classId?: string; name?: string; kind?: string }`

- [ ] `ShipThumb` 优先 `shipPortraitById(id)` → `shipPortrait(classId)` → `shipPortraitByName(name)`；无图时渲染舰种剪影 + `aria-label`。
- [ ] `BudgetMeter` 分段按舰种着色（DD 薄荷 / CA 黄铜 / CL 蓝 / BB 红），超预算变红并显示差额。
- [ ] `RuleCheck` 每条 `ok/!ok` 有图标与文字，失败项带 `detail`。
- [ ] 样式只依赖 `--cas-*` tokens；不引入新依赖。
- [ ] 验证：`tsc --noEmit`。

### Task 4: DeploymentScreen

**Files:**
- Create: `client/src/screens/formation/DeploymentScreen.tsx`
- Create: `client/src/screens/formation/deployment.css`
- Modify: `client/src/engine.ts`（如需导出 `Profile` 已有）

**Interfaces:**
- Props:
```ts
{
  stageId: string; difficulty: 'story'; side: Side; profileId: string;
  profiles: Profile[]; defaultProfile: Profile;
  onBack: () => void;
  onLaunch: (launch: { fleet: string[]; profile: Profile }) => void;
  busy?: boolean;
}
```
- Consumes: `ask<FleetPick>({ op:'campaign_fleet', id: stageId, difficulty })`；`FleetPick` 形状 `{ budget, historical:{class,name,kind,points,slot}[], options:{id,class,name,kind,points}[] }`。

- [ ] 加载 `campaign_fleet`；失败显示错误 + 重试。
- [ ] `picks` 初始：草稿优先，否则 `historical.map(s => s.class)`。
- [ ] 槽位行：序号、立绘、舰名、舰级/舰种、点价、标签（历史舰/已登记）、更换、阵位锁。
- [ ] 候选面板：选中槽位后打开；过滤（全部/DD/CL/CA/BB）、搜索、排序（点价/舰种/舰名）；候选池 = `historical` 去重 + `options`；超预算/无效给出禁用原因；显示 `delta`。
- [ ] 右栏：预算、校验（舰位数/同阵营/点价/舰卡有效/阵位保持）、战术风格、按历史编制、保存预设/载入预设、出航。
- [ ] 草稿每次改动立即写；`onLaunch({ fleet: picks, profile })`。
- [ ] 740×360：隐藏左栏，右栏变底部预算/出航条，候选面板全屏 sheet。
- [ ] 验证：`tsc --noEmit`；1360/1024/740 截图。

### Task 5: CampaignLobby

**Files:**
- Create: `client/src/screens/campaign/CampaignLobby.tsx`
- Create: `client/src/screens/campaign/campaign-lobby.css`

**Interfaces:**
- Props:
```ts
{
  busy: boolean; progress?: CampaignProgress; online: boolean;
  profileId: string; profiles: Profile[]; defaultProfile: Profile;
  onCampaign?: (launch: CampaignLaunch) => void;
  onClaim: (stageId: string) => void;
  onReturn?: () => void; onStory?: () => void; onReview?: () => void; onNight: () => void;
}
```
- Consumes: `ask<Archive>({op:'campaign'})`, `ask<RecordDetail>({op:'campaign_detail', id})`, `CampaignMap`, `campaignBest`, `campaignRewards`, `CampaignRewardActions`, `CampaignStarRating`, `goalText`, `matchNames`, `campaignText`.

- [ ] 顶部：返回、标题、战线切换、总星数、史料馆、剧情模式。
- [ ] 左栏：按年份分组的关卡列表；显示星数、状态（可出击/已完成/奖励待领/仅离线/档案整理中）；未开放关卡折叠区。
- [ ] 中栏：复用 `CampaignMap`；选择战区/地点过滤关卡；当前关卡高亮。
- [ ] 右栏：关卡详情（标题/日期/环境/命令/决定/战术/三星条件/奖励/三档难度/CTA）。
- [ ] 故事难度 CTA → 渲染 `DeploymentScreen`；标准/挑战 CTA → 直接 `onCampaign({stageId,difficulty})`。
- [ ] 「史料馆」→ 渲染旧 `CampaignArchive`，`onReturn` 关闭。
- [ ] 未开放关卡：只展示档案缺口，不显示假按钮。
- [ ] 740×360：左栏折叠为顶部横向关卡条，详情为主滚动区。
- [ ] 验证：`tsc --noEmit`；三档截图。

### Task 6: App 接线

**Files:**
- Modify: `client/src/main.tsx`
- Modify: `client/src/campaign-progress.ts`（Task 1 已完成）

**Interfaces:**
- `launchCampaign({stageId,difficulty,fleet,profile})` 使用 `profile ?? port.preset.profile`；线上仍走服务端 `battles`。
- 路由 `section === 'archive'` 渲染 `CampaignLobby`。

- [ ] 替换 `CampaignArchive` 路由为 `CampaignLobby`，传入 `profile.id`、`port.profiles`、`port.preset.profile`。
- [ ] 保留 `CampaignArchive` 的 battle-result 导入（`CampaignMissionBrief` / `CampaignResultSummary` / `CampaignRewardActions`）。
- [ ] `launchCampaign` 透传 `profile`；线上分支不接受 fleet/profile。
- [ ] 验证：从母港点「战役航线」进入新大厅；控制台无错误。

### Task 7: 验收

**Files:**
- Modify: `client/tests/browser-esperance.mjs`（改为新流程）
- Create: `client/tests/browser-deployment.mjs`（编成换舰 + 草稿 + 740×360）
- Evidence: `artifacts/client/campaign-p1/`

- [ ] `npm run build` 通过（tsc + vite）。
- [ ] 启动 dev server，用浏览器逐段：
  1. 母港 → 战役 → 同盟战线 → 埃斯佩兰斯角 → 编成出击；
  2. 换第 3 舰位，确认预算/校验更新；
  3. 出航，确认 `observe().campaign.stageId === 'CAMP-ALLIES-02'` 且舰名符合换舰结果；
  4. 返回母港重进编成，确认草稿保留；
  5. 740×360 截图无横向滚动。
- [ ] 把截图与 JSON 凭证写进 `artifacts/client/campaign-p1/`。
- [ ] `plan.md` 记录本批；`havedone.md` 追加证据、边界与未做项。
