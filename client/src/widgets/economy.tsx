// Shared economy widgets for the quartermaster ledger and the night recruit
// screen. Both scenes inherit the --cas-* tokens; the day/night look comes from
// the container overrides, never from a second component.
import { useEffect, useRef } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent, ReactNode } from 'react';
import './economy.css';

export type WalletTone = 'credits' | 'marks' | 'ticket' | 'up';
export type WalletItem = {
  key: string;
  label: string;
  value: number;
  icon?: string;
  tone?: WalletTone;
  hint?: string;
};
export type ShopAction = {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  primary?: boolean;
  title?: string;
};
export type ShopMeta = { label: string; value: ReactNode };

export function WalletBar({ items, className = '', label = '账面资源' }: {
  items: WalletItem[]; className?: string; label?: string;
}) {
  return <div className={'cas-wallet' + (className ? ' ' + className : '')} aria-label={label}>
    {items.map(item => <span key={item.key} className="cas-wallet__item" data-wallet-item={item.key}
      data-tone={item.tone ?? 'ticket'} title={item.hint}>
      {item.icon && <i aria-hidden="true">{item.icon}</i>}
      <small>{item.label}</small>
      <b>{item.value.toLocaleString()}</b>
    </span>)}
  </div>;
}

export function PityMeter({ value, limit, label = '保底计数', caption, compact = false }: {
  value: number; limit: number; label?: string; caption?: string; compact?: boolean;
}) {
  const done = Math.max(0, Math.min(value, limit));
  const percent = limit > 0 ? done / limit * 100 : 0;
  return <div className={'cas-pity' + (compact ? ' cas-pity--compact' : '')}
    role="group" aria-label={`${label} ${done} / ${limit}`}>
    <div className="cas-pity__head"><span>{label}</span><b>{done} / {limit}</b></div>
    <div className="cas-pity__track" role="img" aria-label={`${label}进度 ${done} / ${limit}`}>
      <i style={{ width: percent + '%' }} />
    </div>
    {caption && <small className="cas-pity__caption">{caption}</small>}
  </div>;
}

export function Drawer({ open, name, title, kicker, onClose, children, footer, wide = false }: {
  open: boolean; name?: string; title: string; kicker?: string; onClose: () => void;
  children: ReactNode; footer?: ReactNode; wide?: boolean;
}) {
  useEffect(() => {
    if (!open) return;
    const close = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      onClose();
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [open, onClose]);
  const closeRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (open) closeRef.current?.focus({ preventScroll: true });
  }, [open]);
  if (!open) return null;
  return <div className="cas-drawer-layer" data-drawer={name}
    onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
    <section className={'cas-drawer' + (wide ? ' cas-drawer--wide' : '')}
      role="dialog" aria-modal="true" aria-label={title}>
      <header className="cas-drawer__head">
        <div>{kicker && <small>{kicker}</small>}<h2>{title}</h2></div>
        <button ref={closeRef} type="button" className="cas-drawer__close" onClick={onClose} aria-label="关闭">×</button>
      </header>
      <div className="cas-drawer__body">{children}</div>
      {footer && <footer className="cas-drawer__foot">{footer}</footer>}
    </section>
  </div>;
}

export function ShopCard({
  id, className = '', selected, onSelect, art, artAlt = '', kicker, title, subtitle,
  tags, meta, price, priceNote, status, tone = 'dim', reason, action, children, data,
}: {
  id: string; className?: string; selected?: boolean; onSelect?: () => void;
  art?: string; artAlt?: string; kicker?: string; title: string; subtitle?: string;
  tags?: string[]; meta?: ShopMeta[]; price?: ReactNode; priceNote?: ReactNode;
  status?: string; tone?: 'ok' | 'owned' | 'locked' | 'warn' | 'dim';
  reason?: string; action?: ShopAction; children?: ReactNode;
  data?: Record<string, string | number | boolean | undefined>;
}) {
  const content = <>
    {art && <div className="cas-card__art"><img src={art} alt={artAlt} loading="lazy" /></div>}
    <div className="cas-card__body">
      {kicker && <small className="cas-card__kicker">{kicker}</small>}
      <div className="cas-card__head">
        <h3>{title}</h3>
        {status && <span className={'cas-card__status is-' + tone}>{status}</span>}
      </div>
      {subtitle && <p className="cas-card__sub">{subtitle}</p>}
      {tags && tags.length > 0 && <div className="cas-card__tags">
        {tags.map(tag => <span key={tag}>{tag}</span>)}
      </div>}
      {meta && meta.length > 0 && <dl className="cas-card__meta">
        {meta.map(row => <div key={row.label}><dt>{row.label}</dt><dd>{row.value}</dd></div>)}
      </dl>}
      {children}
    </div>
  </>;
  const choose = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      onSelect?.();
    }
  };
  return <article className={'cas-card' + (selected ? ' is-selected' : '') + (className ? ' ' + className : '')}
    data-item={id} data-status={tone} {...data}>
    {onSelect
      ? <div className="cas-card__choose" role="button" tabIndex={0} aria-pressed={!!selected}
        onClick={onSelect} onKeyDown={choose}>{content}</div>
      : <div className="cas-card__choose cas-card__choose--static">{content}</div>}
    {(price || priceNote || action) && <footer className="cas-card__foot">
      <span className="cas-card__price">{price && <b>{price}</b>}{priceNote && <small>{priceNote}</small>}</span>
      {action && <button type="button" className={'cas-btn' + (action.primary ? ' cas-btn--primary' : '')}
        disabled={action.disabled} title={action.title} onClick={action.onClick}>{action.label}</button>}
    </footer>}
    {reason && <p className="cas-card__reason">{reason}</p>}
  </article>;
}
