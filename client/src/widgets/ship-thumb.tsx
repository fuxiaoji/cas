import { shipPortrait, shipPortraitById, shipPortraitByName } from '../shipPortraits';

export type ShipLike = { id?: string; classId?: string; name?: string; kind?: string };

/** Resolve a portrait by stable identity, then CAS class, then Chinese name. */
export function portraitFor(ship: ShipLike) {
  if (ship.id) {
    const art = shipPortraitById(ship.id);
    if (art) return art;
  }
  if (ship.classId) {
    const art = shipPortrait(ship.classId);
    if (art) return art;
  }
  if (ship.name) return shipPortraitByName(ship.name);
  return undefined;
}

export function ShipThumb({ ship, size = 'md', className = '' }: {
  ship: ShipLike; size?: 'sm' | 'md' | 'lg'; className?: string;
}) {
  const art = portraitFor(ship);
  const classes = `ship-thumb ship-thumb--${size}${className ? ' ' + className : ''}`;
  if (art) return <img className={classes} src={art.src} alt="" loading="lazy" draggable={false} />;
  return <span className={classes + ' ship-thumb--fallback'} aria-hidden="true">{ship.kind ?? '舰'}</span>;
}
