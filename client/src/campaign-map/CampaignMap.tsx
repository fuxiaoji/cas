import { useRef } from 'react';
import type { Side } from '../engine';
import { ChartFace, chartPoint } from './ChartFace';
import { campaignMapStageIds, campaignPlace, charts, places, theaters } from './geography';
import type { CampaignMapEntry, CampaignMapPlaceId, CampaignMapSelection, ChartRegion } from './geography';
import './campaign-map.css';

export type CampaignMapProps = {
  entries: readonly CampaignMapEntry[];
  side: Side;
  selection: CampaignMapSelection;
  onSelectionChange: (selection: CampaignMapSelection) => void;
  activeScenarioId?: string;
};

const regions = Object.keys(charts) as ChartRegion[];
const placeIds = Object.keys(places) as CampaignMapPlaceId[];

type MapPinProps = {
  region: ChartRegion; label: string; lng: number; lat: number; count: number;
  highlighted: boolean; selected?: boolean; fiction?: boolean; below?: boolean;
  onClick: () => void;
};

function MapPin({ region, label, lng, lat, count, highlighted, selected, onClick, below, fiction }: MapPinProps) {
  const [x, y] = chartPoint(region, lng, lat);
  const direction = below ? 'pin-below' : x > .55 ? 'pin-left' : 'pin-right';
  return <button type="button" className={`war-pin ${direction}${fiction ? ' fiction' : ''}`} aria-pressed={selected}
    aria-label={`${label}，${count} 个关卡${fiction ? '，架空推演' : ''}`} data-highlighted={highlighted}
    onClick={onClick} style={{ left: `${x * 100}%`, top: `${y * 100}%` }}>
    <span className="war-pin-rose" aria-hidden="true"><b>{count}</b></span>
    <span className="war-pin-name" aria-hidden="true">{label}</span>
  </button>;
}

export function CampaignMap({ entries, side, selection, onSelectionChange, activeScenarioId }: CampaignMapProps) {
  const tabs = useRef<Partial<Record<ChartRegion, HTMLButtonElement | null>>>({});
  const { region, place } = selection;
  const activePlace = activeScenarioId ? campaignPlace(activeScenarioId) : undefined;
  const activeRegion = activePlace && places[activePlace].region;
  const selectedCount = campaignMapStageIds(entries, side, selection).length;

  function openRegion(next: ChartRegion) {
    onSelectionChange({ region: next });
    tabs.current[next]?.focus({ preventScroll: true });
  }

  return <section className="cas-campaign-map" aria-label="海战地理航图" data-faction={side} data-region={region}>
    <nav className="war-region-tabs" aria-label="战区">
      {regions.map(value => <button type="button" key={value} ref={button => { tabs.current[value] = button; }}
        aria-pressed={value === region && !place} onClick={() => onSelectionChange({ region: value })}>{charts[value].label}</button>)}
    </nav>
    <ChartFace region={region}>
      {region === 'overview' ? theaters.map(theater => {
        const count = theater.regions.reduce((sum, detail) =>
          sum + campaignMapStageIds(entries, side, { region: detail }).length, 0);
        if (!count) return null;
        const highlighted = !!activeRegion && theater.regions.includes(activeRegion);
        return <MapPin key={theater.id} region={region} label={theater.label} lng={theater.lng} lat={theater.lat}
          count={count} highlighted={highlighted} onClick={() => openRegion(highlighted ? activeRegion : theater.regions[0])} />;
      }) : placeIds.filter(id => places[id].region === region).map(id => {
        const location: (typeof places)[CampaignMapPlaceId] = places[id];
        const related = entries.filter(entry => campaignPlace(entry.ibs_id) === id &&
          campaignMapStageIds([entry], side, { region, place: id }).length > 0);
        if (!related.length) return null;
        const count = campaignMapStageIds(related, side, { region, place: id }).length;
        const selected = place === id;
        return <MapPin key={id} region={region} label={location.label} lng={location.lng} lat={location.lat} count={count}
          selected={selected} highlighted={selected || (!place && activePlace === id)}
          below={'labelBelow' in location && location.labelBelow} fiction={related.every(entry => entry.ibs_kind === 'fiction')}
          onClick={() => onSelectionChange(selected ? { region } : { region, place: id })} />;
      })}
      <p className="war-chart-note">交战海域示意 · 海岸线 Natural Earth</p>
    </ChartFace>
    <div className="war-map-summary" role="status">
      <span>{place ? places[place].label : charts[region].label}<b>{selectedCount} 个关卡</b></span>
      {place && <button type="button" onClick={() => openRegion(region)}>显示全战区</button>}
    </div>
  </section>;
}
