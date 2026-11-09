import './widgets.css';

export type BudgetSegment = { kind: string; points: number };

const kindTone: Record<string, string> = {
  DD: 'mint', CL: 'blue', CA: 'brass', BB: 'alert',
};

export function BudgetMeter({ total, budget, segments }: {
  total: number; budget: number; segments: BudgetSegment[];
}) {
  const over = total > budget;
  const remaining = budget - total;
  return <section className={'budget-meter' + (over ? ' is-over' : '')} aria-label="点价预算">
    <header className="budget-meter__head">
      <span>点价预算</span>
      <b>{total.toLocaleString()} <i>/ {budget.toLocaleString()}</i></b>
    </header>
    <div className="budget-meter__bar" role="img" aria-label={`点价 ${total} 分，预算 ${budget} 分`}>
      {segments.map((segment) => <i key={segment.kind} data-tone={kindTone[segment.kind] ?? 'muted'}
        style={{ width: budget > 0 ? Math.max(0, Math.min(100, segment.points / budget * 100)) + '%' : 0 }} />)}
    </div>
    <footer className="budget-meter__foot">
      {segments.filter((segment) => segment.points > 0).map((segment) =>
        <span key={segment.kind}><s data-tone={kindTone[segment.kind] ?? 'muted'} />{segment.kind} {segment.points.toLocaleString()}</span>)}
      <b>{over ? `超出 ${(-remaining).toLocaleString()} 分` : `预算内 · 余 ${remaining.toLocaleString()} 分`}</b>
    </footer>
  </section>;
}

export type RuleItem = { ok: boolean; label: string; detail?: string };

export function RuleCheck({ items }: { items: RuleItem[] }) {
  return <ul className="rule-check" aria-label="编成校验">
    {items.map((item) => <li key={item.label} data-ok={item.ok}>
      <em aria-hidden="true">{item.ok ? '✓' : '✗'}</em>
      <span>{item.label}</span>
      {item.detail && <small>{item.detail}</small>}
    </li>)}
  </ul>;
}
