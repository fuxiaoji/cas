import { useEffect, useState } from 'react';
import type { LogEvent, Observation, Side } from '../engine';

const LOCAL_RADIO = __CAS_LOCAL_RADIO__;
const VOICE_COOLDOWN = 12_000;
const MAX_QUEUE = 3;
const MAX_LIVE_DELTA = 8;
const MAX_EVENT_AGE = 4;

interface VoiceFrame {
  session: number | string;
  observation?: Pick<Observation, 'side' | 'tick' | 'events'>;
  live: boolean;
  replaying: boolean;
  paused: boolean;
}

type Settings = { enabled: boolean; volume: number; pack: string };
type Clip = { cue: string; id: string; side: Side; pack: string };
type Frame = { scope: string; tick: number; seen: Set<string> };
const clampVolume = (volume: number) => Number.isFinite(volume) ? Math.min(1, Math.max(0, volume)) : .9;
const eventId = (event: LogEvent) => event.id == null ? `${event.tick}:${event.kind}:${event.text}` : String(event.id);

class FleetRadio {
  private audio = document.createElement('audio');
  private frame?: Frame;
  private lastScope?: string;
  private queue: Clip[] = [];
  private current?: Clip;
  private lastCue = new Map<string, number>();
  private clipFor?: (side: Side, cue: string) => string | undefined;
  private commanderClipFor?: (pack: string, cue: string) => string | undefined;
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
    if (LOCAL_RADIO) void import('virtual:cas-fleet-radio-clips').then(({ localClip }) => {
      if (this.disposed) return;
      this.clipFor = localClip;
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
  }

  private enqueue(event: LogEvent, side: Side) {
    if (!event.voiceCue || this.queue.length >= MAX_QUEUE) return;
    const now = performance.now();
    const before = this.lastCue.get(event.voiceCue);
    if (before !== undefined && now - before < VOICE_COOLDOWN) return;
    this.lastCue.set(event.voiceCue, now);
    this.queue.push({ cue: event.voiceCue, id: eventId(event), side, pack: this.pack });
  }

  private pump() {
    if (!this.enabled || !this.unlocked || this.isSuspended() || !this.clipFor) return;
    while (!this.current && this.queue.length) {
      const candidate = this.queue.shift()!;
      // A chosen commander pack must never silently fall back to the faction
      // radio: without the private files the seat stays silent instead.
      const url = candidate.pack !== 'auto'
        ? this.commanderClipFor?.(candidate.pack, candidate.cue)
        : this.clipFor(candidate.side, candidate.cue);
      if (!url) continue;
      this.current = candidate;
      this.audio.src = url;
      this.audio.dataset.eventId = candidate.id;
      this.audio.dataset.voiceCue = candidate.cue;
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
    const scope = `${session}:${side}`;
    if (!this.frame || scope !== this.frame.scope || tick < this.frame.tick) {
      const freshBattle = this.lastScope !== scope && tick === 0;
      this.lastScope = scope;
      this.frame = { scope, tick, seen: new Set(events.map(eventId)) };
      this.stop();
      this.lastCue.clear();
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
        if (this.enabled && !this.isSuspended() && advancingNormally && tick - event.tick <= MAX_EVENT_AGE) this.enqueue(event, side);
      }
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
    setEnabled: (enabled: boolean) => setSettings((previous) => ({ ...previous, enabled })),
    setVolume: (volume: number) => setSettings((previous) => ({ ...previous, volume: clampVolume(volume) })),
    setPack: (pack: string) => setSettings((previous) => ({ ...previous, pack: pack || 'auto' })) };
}
