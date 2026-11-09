export type QuartermasterCounter = 'ships' | 'supply' | 'ai' | 'exchange';

export const quartermasterCounters: { id: QuartermasterCounter; label: string; note: string }[] = [
  { id: 'ships', label: '舰船', note: '征募入口 · 图鉴摘要' },
  { id: 'supply', label: '补给配给', note: '周券 · 实战补给' },
  { id: 'ai', label: 'AI 战术', note: 'doctrine 风格' },
  { id: 'exchange', label: '礼包与兑换', note: '勋章 · 既有兑换' },
];
