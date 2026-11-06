import type {ReactNode} from 'react';
import {charts, type ChartRegion} from './geography';

export function chartPoint(region: ChartRegion, lng: number, lat: number) {
  const [west, east, south, north] = charts[region].bounds;
  return [(lng - west) / (east - west), (north - lat) / (north - south)] as const;
}

export function ChartFace({region, children}: {region: ChartRegion; children?: ReactNode}) {
  const chart = charts[region];
  const coordinate = (value: number, positive: string, negative: string) =>
    `${Math.abs(value).toFixed(0)}°${value < 0 ? negative : positive}`;
  return <div className="war-chart-face">
    <svg viewBox="0 0 960 540" preserveAspectRatio="none" className="war-geography" aria-hidden="true">
      {Array.from({length: 11}, (_, i) => {
        const x = i * 96;
        return <path className="war-grid-line" key={`longitude-${i}`} d={`M${x} 0V540`}/>;
      })}
      {Array.from({length: 7}, (_, i) => {
        const y = i * 90;
        return <path className="war-grid-line" key={`latitude-${i}`} d={`M0 ${y}H960`}/>;
      })}
      <path className="war-land" d={chart.coast} fillRule="evenodd" vectorEffect="non-scaling-stroke"/>
    </svg>
    {chart.labels.map(([label, lng, lat]) => {
      const [x, y] = chartPoint(region, Number(lng), Number(lat));
      return <span key={label} className="war-chart-label" aria-hidden="true"
        style={{left: `${x * 100}%`, top: `${y * 100}%`}}>{label}</span>;
    })}
    <div className="war-chart-coordinates" aria-hidden="true">
      {coordinate(chart.bounds[0], 'E', 'W')} – {coordinate(chart.bounds[1], 'E', 'W')}
    </div>
    <svg className="war-compass" viewBox="0 0 48 58" aria-hidden="true">
      <text x="24" y="11" textAnchor="middle">N</text>
      <circle cx="24" cy="35" r="14"/>
      <path d="M24 16 29 36 24 33 19 36Z" className="war-compass-needle"/>
      <path d="M24 35V54M6 35H42"/>
    </svg>
    {children}
  </div>;
}
