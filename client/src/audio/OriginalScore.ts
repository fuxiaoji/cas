import { useEffect, useRef, useState } from 'react';
import prologue from './score/prologue.ogg';
import maneuver from './score/maneuver.ogg';
import engagement from './score/engagement.ogg';
import victory from './score/victory.ogg';
import defeat from './score/defeat.ogg';

// Third-party World of Warships OST cuts. Provenance, hashes and segment
// windows are in ./score/ledger.json. Private CAS playtest use only; public
// release requires clearance for the source tracks.
const cues = {
  prologue: { source: prologue, loop: true, gain: 0.77, title: 'Duty Calls' },
  maneuver: { source: maneuver, loop: true, gain: 0.63, title: 'World of Warships OST 7' },
  engagement: { source: engagement, loop: true, gain: 0.92, title: 'World of Warships OST 23' },
  victory: { source: victory, loop: false, gain: 0.8, title: 'World of Warships OST 11' },
  defeat: { source: defeat, loop: false, gain: 0.76, title: 'World of Warships OST 12' },
} as const;

type Cue = keyof typeof cues;
export type ScoreScene = 'off' | Cue;
type Settings = { enabled: boolean; volume: number };
type ScoreFrame = { scene: ScoreScene; paused?: boolean; settingsKey?: string };

const INITIAL: Settings = { enabled: true, volume: 0.54 };
const DUCK = 0.29;
const SWITCH_MS = 230;
const RETURN_MS = 560;
const clamp = (value: number) => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : INITIAL.volume;

function loadSettings(key: string): Settings {
  try {
    const saved = JSON.parse(localStorage.getItem(key) ?? '{}');
    return { enabled: saved.enabled !== false, volume: clamp(saved.volume) };
  } catch { return INITIAL; }
}

class OriginalScore {
  private readonly audio = document.createElement('audio');
  private scene: ScoreScene = 'off';
  private current?: Cue;
  private settings = INITIAL;
  private paused = false;
  private background = false;
  private animation?: number;
  private attempt?: Promise<void>;
  private disposed = false;

  constructor() {
    this.audio.hidden = true;
    this.audio.preload = 'none';
    this.audio.dataset.channel = 'cas-original-score';
    document.body.append(this.audio);
    document.addEventListener('visibilitychange', this.sync);
    document.addEventListener('play', this.radioChanged, true);
    document.addEventListener('pause', this.radioChanged, true);
    document.addEventListener('ended', this.radioChanged, true);
    window.addEventListener('app-background', this.toBackground);
    window.addEventListener('app-foreground', this.toForeground);
    window.addEventListener('pointerup', this.onGesture, true);
    window.addEventListener('keydown', this.onGesture, true);
  }

  update(scene: ScoreScene, paused: boolean, settings: Settings) {
    this.scene = scene;
    this.paused = paused;
    this.settings = settings;
    this.sync();
  }

  private toBackground = () => { this.background = true; this.sync(); };
  private toForeground = () => { this.background = false; this.sync(); };
  private onGesture = (event: Event) => { if (event.isTrusted && this.audio.paused) this.sync(); };
  private radioChanged = (event: Event) => {
    if (event.target instanceof HTMLAudioElement && event.target.dataset.channel === 'fleet-radio') this.sync();
  };

  private fade(volume: number, duration: number, done?: () => void) {
    if (this.animation !== undefined) cancelAnimationFrame(this.animation);
    this.animation = undefined;
    const start = this.audio.volume;
    if (duration <= 0 || Math.abs(start - volume) < 0.001) {
      this.audio.volume = volume;
      done?.();
      return;
    }
    const began = performance.now();
    const frame = (time: number) => {
      const progress = Math.max(0, Math.min(1, (time - began) / duration));
      this.audio.volume = start + (volume - start) * progress;
      if (progress < 1) this.animation = requestAnimationFrame(frame);
      else { this.animation = undefined; done?.(); }
    };
    this.animation = requestAnimationFrame(frame);
  }

  private switchTo(scene: ScoreScene) {
    this.audio.pause();
    this.attempt = undefined;
    if (scene === 'off') {
      this.current = undefined;
      delete this.audio.dataset.track;
      this.audio.removeAttribute('src');
      this.audio.load();
      return;
    }
    this.current = scene;
    this.audio.src = cues[scene].source;
    this.audio.loop = cues[scene].loop;
    this.audio.dataset.track = scene;
    this.sync();
  }

  private sync = () => {
    if (this.disposed) return;
    const { scene, settings, audio } = this;
    if (this.paused || this.background || document.hidden || !settings.enabled || settings.volume === 0) {
      this.fade(0, 0);
      audio.pause();
      if (scene !== this.current && scene === 'off') this.switchTo('off');
      return;
    }
    if (scene !== this.current) {
      if (scene === 'off' && !this.current) return;
      this.fade(0, audio.paused ? 0 : SWITCH_MS, () => this.switchTo(scene));
      return;
    }
    if (audio.ended) return;
    if (audio.paused && !this.attempt) {
      const attempt = audio.play();
      this.attempt = attempt;
      void attempt.catch(() => {
        // Some shells require a gesture. The next trusted interaction retries.
      }).finally(() => {
        if (this.attempt === attempt) this.attempt = undefined;
      });
    }
    const radio = document.querySelector<HTMLAudioElement>('audio[data-channel="fleet-radio"]');
    const radioSpeaking = radio && !radio.paused && !radio.ended;
    this.fade(settings.volume * cues[scene].gain * (radioSpeaking ? DUCK : 1), radioSpeaking ? 110 : RETURN_MS);
  };

  dispose() {
    this.disposed = true;
    this.fade(0, 0);
    this.switchTo('off');
    this.audio.remove();
    document.removeEventListener('visibilitychange', this.sync);
    document.removeEventListener('play', this.radioChanged, true);
    document.removeEventListener('pause', this.radioChanged, true);
    document.removeEventListener('ended', this.radioChanged, true);
    window.removeEventListener('app-background', this.toBackground);
    window.removeEventListener('app-foreground', this.toForeground);
    window.removeEventListener('pointerup', this.onGesture, true);
    window.removeEventListener('keydown', this.onGesture, true);
  }
}

export function useOriginalScore({ scene, paused = false, settingsKey = 'cas.original-score.v1' }: ScoreFrame) {
  const score = useRef<OriginalScore | undefined>(undefined);
  const [settings, setSettings] = useState(() => loadSettings(settingsKey));
  useEffect(() => {
    const music = new OriginalScore();
    score.current = music;
    return () => { music.dispose(); score.current = undefined; };
  }, []);
  useEffect(() => {
    score.current?.update(scene, paused, settings);
    try { localStorage.setItem(settingsKey, JSON.stringify(settings)); }
    catch { /* A preference write cannot interrupt the score. */ }
  }, [scene, paused, settings, settingsKey]);
  return {
    ...settings,
    setEnabled: (enabled: boolean) => setSettings(current => ({ ...current, enabled })),
    setVolume: (volume: number) => setSettings(current => ({ ...current, volume: clamp(volume) })),
  };
}
