import chartData from './chart-data.json';
import type { Side } from '../engine';

export const charts = chartData.charts;
export type ChartRegion = keyof typeof charts;
type DetailRegion = Exclude<ChartRegion, 'overview'>;
type Location = { label: string; lng: number; lat: number };
type MapPlace = Location & { region: DetailRegion; labelBelow?: boolean };

// The original chart grouped the campaign by approximate engagement locations.
// Keep the coordinates as read from campaign-briefings.json at the pinned release.
export const places = {
  plymouth: { region: 'channel', label: '普利茅斯外海', lng: -4.25, lat: 50.04 },
  'iron-bottom': { region: 'iron', label: '铁底湾', lng: 159.83, lat: -9.23 },
  kula: { region: 'central', label: '库拉湾口', lng: 157.1, lat: -7.79 },
  vella: { region: 'central', label: '韦拉拉韦拉', lng: 156.58, lat: -7.58, labelBelow: true },
  'central-fiction': { region: 'central', label: '所罗门推演', lng: 157.96, lat: -8.63 },
  george: { region: 'north', label: '圣乔治角外海', lng: 152.72, lat: -4.88 },
  empress: { region: 'north', label: '奥古斯塔皇后湾', lng: 154.73, lat: -6.26 },
  'bougainville-fiction': { region: 'north', label: '布干维尔推演', lng: 155.18, lat: -6.91, labelBelow: true },
  'philippine-sea': { region: 'marianas', label: '菲律宾海推演', lng: 140.1, lat: 14.8 },
} as const satisfies Record<string, MapPlace>;
export type CampaignMapPlaceId = keyof typeof places;

const placeByScenario: Readonly<Record<string, CampaignMapPlaceId>> = {
  'IBS-S-01': 'iron-bottom',
  'IBS-S-02': 'kula',
  'IBS-S-03': 'plymouth',
  'IBS-S-04': 'iron-bottom',
  'IBS-S-05': 'george',
  'IBS-S-06': 'iron-bottom',
  'IBS-S-07': 'central-fiction',
  'IBS-S-08': 'kula',
  'IBS-S-09': 'iron-bottom',
  'IBS-S-10': 'iron-bottom',
  'IBS-S-11': 'empress',
  'IBS-S-12': 'bougainville-fiction',
  'IBS-S-13': 'vella',
  'IBS-S-14': 'vella',
  'IBS-S-EM-01': 'philippine-sea',
  'IBS-S-FM-01': 'iron-bottom',
};

export const theaters: readonly (Location & { id: string; regions: readonly [DetailRegion, ...DetailRegion[]] })[] = [
  { id: 'europe', label: '欧洲战区', regions: ['channel'], lng: -4.25, lat: 50.04 },
  { id: 'south-pacific', label: '所罗门战区', regions: ['iron', 'central', 'north'], lng: 159.83, lat: -9.23 },
  { id: 'west-pacific', label: '西太平洋', regions: ['marianas'], lng: 140.1, lat: 14.8 },
];

export type CampaignMapEntry = {
  ibs_id: string;
  ibs_kind: string;
  stage_ids: readonly string[];
};
export type CampaignMapSelection = { region: ChartRegion; place?: CampaignMapPlaceId };

export function campaignPlace(scenarioId: string) {
  return Object.hasOwn(placeByScenario, scenarioId) ? placeByScenario[scenarioId] : undefined;
}

export function campaignMapStageIds(entries: readonly CampaignMapEntry[], side: Side, selection: CampaignMapSelection): string[] {
  const prefix = side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-';
  return entries.flatMap(entry => {
    const place = campaignPlace(entry.ibs_id);
    const matches = selection.region === 'overview' ||
      (place && places[place].region === selection.region && (!selection.place || place === selection.place));
    return matches ? entry.stage_ids.filter(stageId => stageId.startsWith(prefix)) : [];
  });
}
