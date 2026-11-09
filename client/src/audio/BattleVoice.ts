import { useEffect, useState } from 'react';
import type { LogEvent, Observation, Side } from '../engine';

const LOCAL_RADIO = __CAS_LOCAL_RADIO__;
const VOICE_COOLDOWN = 12_000;
const CASUALTY_COOLDOWN = 60_000;
const CASUALTY_GAP = 2;
const MAX_QUEUE = 3;
const MAX_LIVE_DELTA = 8;
const MAX_EVENT_AGE = 4;

type Ships = Pick<Observation, 'ships'>['ships'];
type Contacts = Pick<Observation, 'contacts'>['contacts'];

interface VoiceFrame {
  session: number | string;
  observation?: Pick<Observation, 'side' | 'tick' | 'events' | 'ships' | 'contacts'>;
  live: boolean;
  replaying: boolean;
  paused: boolean;
}

type Settings = { enabled: boolean; volume: number; pack: string };
type Clip = { cue: string; id: string; side: Side; pack: string; variant?: string };
type Frame = { scope: string; tick: number; seen: Set<string> };
export type Direction = 'front' | 'port' | 'starboard' | 'astern';
// One archive sighting line per hull family. CA/CB share the cruiser line and
// BC shares the capital-ship line because the archive has no separate clips.
const CONTACT_VARIANTS: Record<string, string> = {
  dd: 'dd', cl: 'cl', ca: 'cl', cb: 'cl', bb: 'bb', bc: 'bb', cv: 'cv',
};
const clampVolume = (volume: number) => Number.isFinite(volume) ? Math.min(1, Math.max(0, volume)) : .9;
const eventId = (event: LogEvent) => event.id == null ? `${event.tick}:${event.kind}:${event.text}` : String(event.id);

// Several archive cues have numbered takes. Pick at random, but never repeat
// the immediately previous take for the same cue.
export function chooseClip<T>(items: readonly T[], previous: T | undefined, random: () => number = Math.random): T | undefined {
  if (!items.length) return undefined;
  if (items.length === 1) return items[0];
  const pool = previous === undefined ? items : items.filter((item) => item !== previous);
  const choices = pool.length ? pool : items;
  return choices[Math.min(choices.length - 1, Math.floor(random() * choices.length))];
}

// Visible-score hint only. Positive means we have sunk more than we lost.
export function casualtyVariant(kills: number, losses: number): 'winning' | 'losing' | undefined {
  const gap = kills - losses;
  return Math.abs(gap) < CASUALTY_GAP ? undefined : gap > 0 ? 'winning' : 'losing';
}

// Derive a warning direction only from this seat's own ships and the event
// coordinate the kernel already exposed to this seat. No hidden truth is read.
export function directionFor(event: LogEvent, ships: Ships): Direction | undefined {
  if (event.x == null || event.y == null || !ships.length) return undefined;
  let nearest: (typeof ships)[number] | undefined;
  let best = Infinity;
  for (const ship of ships) {
    const dx = event.x - ship.x;
    const dy = event.y - ship.y;
    const distance = dx * dx + dy * dy;
    if (distance < best) { best = distance; nearest = ship; }
  }
  if (!nearest) return undefined;
  const bearing = (Math.atan2(event.x - nearest.x, event.y - nearest.y) * 180 / Math.PI + 360) % 360;
  const relative = (bearing - nearest.heading + 360) % 360;
  if (relative < 45 || relative >= 315) return 'front';
  if (relative < 135) return 'starboard';
  if (relative < 225) return 'astern';
  return 'port';
}

// The kernel puts system criticals into kind="critical" and usually leaves
// voiceCue empty (only a fire critical carries cue "fire"). Derive the damage
// dispatch for the mechanisms the archive can actually voice, without touching
// the kernel event or inventing a line for anything else.
export function derivedCue(event: LogEvent): string | undefined {
  if (event.voiceCue) return event.voiceCue;
  if (event.kind !== 'critical') return undefined;
  if (/损管|灭火|消防/.test(event.text)) return 'damage';
  if (/主炮座|主炮塔|主炮弹药库|进水|水线|堵漏/.test(event.text)) return 'damage';
  if (/起火|火灾/.test(event.text)) return 'fire';
  return undefined;
}

function nearestContact(event: LogEvent, contacts: Contacts): Contacts[number] | undefined {
  if (event.x == null || event.y == null || !contacts.length) return undefined;
  let nearest: Contacts[number] | undefined;
  let best = Infinity;
  for (const contact of contacts) {
    const dx = event.x - contact.x;
    const dy = event.y - contact.y;
    const distance = dx * dx + dy * dy;
    if (distance < best) { best = distance; nearest = contact; }
  }
  return nearest;
}

export function variantFor(event: LogEvent, ships: Ships, contacts: Contacts): string | undefined {
  const cue = derivedCue(event);
  if (cue === 'torpedo_warning') return directionFor(event, ships);
  if (cue === 'contact') {
    const kind = nearestContact(event, contacts)?.kind?.toLowerCase();
    return kind ? CONTACT_VARIANTS[kind] : undefined;
  }
  if (cue === 'damage') {
    // Damage control is checked first: a "火灾/进水损管" message is a control
    // report, not a fresh fire/flood report. Negative severity means the
    // casualty was reduced; positive means it worsened.
    if (/损管|灭火|消防/.test(event.text)) {
      const reduced = /严重度\s*-\s*\d/.test(event.text);
      if (reduced && /火灾|起火|火势/.test(event.text)) return 'control-fire';
      if (reduced && /进水|水线|堵漏/.test(event.text)) return 'control-flood';
      return 'control';
    }
    if (/主炮座|主炮塔|主炮弹药库/.test(event.text)) return 'turret';
    if (/进水|水线|堵漏/.test(event.text)) return 'flood';
    if (/中雷|鱼雷/.test(event.text)) return 'torpedo';
    return 'gun';
  }
  if (cue === 'fire') {
    // The same kernel cue means "we opened fire" (gun/torpedo launch) and
    // "the ship is on fire" (damage critical). Never play the fire alarm for
    // an offensive launch.
    if (/损管|灭火|消防/.test(event.text)) return undefined;
    if (/起火|火灾/.test(event.text)) return 'damage';
    if (event.kind === 'gun' || event.kind === 'torpedo' || /发射/.test(event.text)) return 'open';
    return undefined;
  }
  return undefined;
}

class FleetRadio {
  private audio = document.createElement('audio');
  private frame?: Frame;
  private lastScope?: string;
  private queue: Clip[] = [];
  private current?: Clip;
  private lastCue = new Map<string, number>();
  private lastArchive = new Map<string, string>();
  private clipFor?: (side: Side, cue: string) => string | undefined;
  private archiveClipsFor?: (side: Side, cue: string, variant?: string) => readonly string[];
  private syntheticClipFor?: (side: Side, cue: string, variant?: string) => string | undefined;
  private commanderClipFor?: (pack: string, cue: string) => string | undefined;
  private ships: Ships = [];
  private contacts: Contacts = [];
  private side: Side = 'allies';
  private losses = 0;
  private kills = 0;
  private casualtyAt = 0;
  private announceSeq = 0;
  private disposed = false;
  private enabled = false;
  private paused = true;
  private pack = 'auto';
  private unlocked = navigator.userActivation?.hasBeenActive ?? false;
  private background = false;

  constructor() {
    this.audio.preload = 'none';
    this.audio.hidden = true;
    this.audio.dataset.channel = 'fleet-radio';
    this.audio.addEventListener('ended', this.complete);
    this.audio.addEventListener('error', this.complete);
    document.body.append(this.audio);
    document.addEventListener('visibilitychange', this.suspendOrResume);
    window.addEventListener('app-background', this.toBackground);
    window.addEventListener('app-foreground', this.toForeground);
    window.addEventListener('pointerup', this.unlock, true);
    window.addEventListener('keydown', this.unlock, true);
    if (LOCAL_RADIO) void import('virtual:cas-fleet-radio-clips').then(({ localClip, archiveClips, syntheticClip }) => {
      if (this.disposed) return;
      this.clipFor = localClip;
      this.archiveClipsFor = archiveClips;
      this.syntheticClipFor = syntheticClip;
      this.pump();
    }).catch(() => { this.queue = []; });
    if (LOCAL_RADIO) void import('virtual:cas-commander-clips').then(({ commanderClip }) => {
      if (this.disposed) return;
      this.commanderClipFor = commanderClip;
      this.pump();
    }).catch(() => { this.queue = []; });
  }

  private isSuspended() { return this.paused || this.background || document.hidden; }

  private unlock = (event: Event) => {
    if (!event.isTrusted) return;
    this.unlocked = true;
    this.pump();
  };

  private toBackground = () => { this.background = true; this.suspendOrResume(); };
  private toForeground = () => { this.background = false; this.suspendOrResume(); };
  private suspendOrResume = () => {
    if (this.isSuspended()) this.audio.pause();
    else this.pump();
  };

  private complete = () => {
    this.current = undefined;
    this.pump();
  };

  private stop() {
    this.queue = [];
    this.current = undefined;
    this.audio.pause();
    this.audio.removeAttribute('src');
    this.audio.load();
    delete this.audio.dataset.eventId;
    delete this.audio.dataset.voiceCue;
    delete this.audio.dataset.voiceVariant;
  }

  private variant(event: LogEvent) {
    return variantFor(event, this.ships, this.contacts);
  }

  private enqueueCue(cue: string, id: string, side: Side, variant: string | undefined, cooldown = true) {
    if (!this.enabled || this.queue.length >= MAX_QUEUE) return;
    const now = performance.now();
    if (cooldown) {
      const before = this.lastCue.get(cue);
      if (before !== undefined && now - before < VOICE_COOLDOWN) return;
      this.lastCue.set(cue, now);
    }
    this.queue.push({ cue, id, side, pack: this.pack, variant });
  }

  private enqueue(event: LogEvent, side: Side) {
    const cue = derivedCue(event);
    if (!cue) return;
    this.enqueueCue(cue, eventId(event), side, this.variant(event));
  }

  // Imperative cues for player-only UI actions (searchlight/illumination,
  // autopilot handover, manual gun order). They never come from AI actions.
  announce(cue: string, variant?: string) {
    this.enqueueCue(cue, `announce:${++this.announceSeq}`, this.side, variant, cue !== 'autopilot');
    this.pump();
  }

  private pickArchive(candidate: Clip) {
    const urls = this.archiveClipsFor?.(candidate.side, candidate.cue, candidate.variant) ?? [];
    const key = `${candidate.side}:${candidate.cue}:${candidate.variant ?? ''}`;
    const chosen = chooseClip(urls, this.lastArchive.get(key));
    if (chosen) this.lastArchive.set(key, chosen);
    return chosen;
  }

  private trackCasualty(event: LogEvent, allowCue: boolean) {
    if (event.voiceCue === 'own_sunk') this.losses++;
    else if (event.voiceCue === 'enemy_sunk') this.kills++;
    else return;
    const variant = casualtyVariant(this.kills, this.losses);
    if (!variant || !allowCue || !this.enabled || this.isSuspended()) return;
    const now = performance.now();
    if (now - this.casualtyAt < CASUALTY_COOLDOWN) return;
    this.casualtyAt = now;
    this.enqueueCue('casualty', `casualty:${this.kills}:${this.losses}`, this.side, variant);
  }

  private pump() {
    if (!this.enabled || !this.unlocked || this.isSuspended() || !this.clipFor) return;
    while (!this.current && this.queue.length) {
      const candidate = this.queue.shift()!;
      // The synthetic damage-control line is an independent UI status layer.
      // It takes precedence for this one cue, never for archive recordings.
      const synthetic = this.syntheticClipFor?.(candidate.side, candidate.cue, candidate.variant);
      const archive = synthetic ? undefined : this.pickArchive(candidate);
      const commander = candidate.pack !== 'auto'
        ? this.commanderClipFor?.(candidate.pack, candidate.cue)
        : undefined;
      // Auto pack: the new Chinese crew archive leads, the original faction
      // sample is only a fallback. A chosen commander stays primary and falls
      // back to the archive, never to the opposite-faction sample.
      const url = synthetic ?? (candidate.pack !== 'auto'
        ? commander ?? archive
        : archive ?? this.clipFor(candidate.side, candidate.cue));
      if (!url) continue;
      this.current = candidate;
      this.audio.src = url;
      this.audio.dataset.eventId = candidate.id;
      this.audio.dataset.voiceCue = candidate.cue;
      if (candidate.variant) this.audio.dataset.voiceVariant = candidate.variant;
      else delete this.audio.dataset.voiceVariant;
    }
    if (this.current && this.audio.paused) void this.audio.play().catch(() => {
      // WebViews may require a fresh gesture. Do not replay or substitute a cue.
    });
  }

  update({ session, observation, live, replaying, paused }: VoiceFrame, settings: Settings) {
    this.audio.volume = settings.volume;
    const wasEnabled = this.enabled;
    this.enabled = settings.enabled;
    this.paused = paused;
    this.pack = settings.pack;
    if (!observation || !live || replaying) {
      if (this.frame) this.stop();
      this.frame = undefined;
      return;
    }
    if (!this.enabled && wasEnabled) this.stop();
    const { side, tick, events } = observation;
    this.ships = observation.ships;
    this.contacts = observation.contacts;
    this.side = side;
    const scope = `${session}:${side}`;
    if (!this.frame || scope !== this.frame.scope || tick < this.frame.tick) {
      const freshBattle = this.lastScope !== scope && tick === 0;
      this.lastScope = scope;
      this.frame = { scope, tick, seen: new Set(events.map(eventId)) };
      this.stop();
      this.lastCue.clear();
      this.lastArchive.clear();
      this.losses = events.filter((event) => event.voiceCue === 'own_sunk').length;
      this.kills = events.filter((event) => event.voiceCue === 'enemy_sunk').length;
      this.casualtyAt = 0;
      if (freshBattle && this.enabled) {
        const start = events.find((event) => event.tick === 0 && event.voiceCue === 'battle_start');
        if (start) this.enqueue(start, side);
      }
    } else {
      const advancingNormally = tick - this.frame.tick <= MAX_LIVE_DELTA;
      this.frame.tick = tick;
      for (const event of events) {
        const id = eventId(event);
        if (this.frame.seen.has(id)) continue;
        this.frame.seen.add(id);
        const live = this.enabled && !this.isSuspended() && advancingNormally && tick - event.tick <= MAX_EVENT_AGE;
        if (live) this.enqueue(event, side);
        this.trackCasualty(event, live);
      }
    }
    if (!wasEnabled && this.enabled && this.frame) {
      // Enabling the radio mid-battle must start from the visible sunk events
      // already in the observation, not from zero.
      this.losses = events.filter((event) => event.voiceCue === 'own_sunk').length;
      this.kills = events.filter((event) => event.voiceCue === 'enemy_sunk').length;
    }
    this.suspendOrResume();
  }

  dispose() {
    this.disposed = true;
    document.removeEventListener('visibilitychange', this.suspendOrResume);
    window.removeEventListener('app-background', this.toBackground);
    window.removeEventListener('app-foreground', this.toForeground);
    window.removeEventListener('pointerup', this.unlock, true);
    window.removeEventListener('keydown', this.unlock, true);
    this.audio.removeEventListener('ended', this.complete);
    this.audio.removeEventListener('error', this.complete);
    this.stop();
    this.audio.remove();
  }
}

function readSettings(key: string): Settings {
  try {
    const saved = JSON.parse(localStorage.getItem(key) ?? '{}');
    return { enabled: saved.enabled !== false, volume: clampVolume(saved.volume),
      pack: typeof saved.pack === 'string' && saved.pack ? saved.pack : 'auto' };
  } catch { return { enabled: true, volume: .9, pack: 'auto' }; }
}

export function useBattleVoice({ settingsKey = 'cas.fleet-radio.v1', ...frame }: VoiceFrame & { settingsKey?: string }) {
  const [settings, setSettings] = useState(() => readSettings(settingsKey));
  const [radio, setRadio] = useState<FleetRadio>();
  useEffect(() => {
    if (!LOCAL_RADIO) return;
    const player = new FleetRadio();
    setRadio(player);
    return () => player.dispose();
  }, []);
  useEffect(() => {
    try { localStorage.setItem(settingsKey, JSON.stringify(settings)); }
    catch { /* An unavailable local setting must not interrupt the battle. */ }
    radio?.update(frame, settings);
  }, [radio, settings, settingsKey, frame.session, frame.observation, frame.live, frame.replaying, frame.paused]);
  return { available: LOCAL_RADIO, enabled: settings.enabled, volume: settings.volume, pack: settings.pack,
    announce: (cue: string, variant?: string) => radio?.announce(cue, variant),
    setEnabled: (enabled: boolean) => setSettings((previous) => ({ ...previous, enabled })),
    setVolume: (volume: number) => setSettings((previous) => ({ ...previous, volume: clampVolume(volume) })),
    setPack: (pack: string) => setSettings((previous) => ({ ...previous, pack: pack || 'auto' })) };
}
