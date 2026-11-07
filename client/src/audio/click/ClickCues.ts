import { useEffect, useState } from 'react';

// Port of the 0.6.11 operation click cues. The original ships no audio files
// for these four prompts: SoundDirector.uiCue in the reference worktree
// (mobile/src/sound.ts) synthesizes each kind from short sine tones on a
// shared AudioContext. The tones, spacing and envelope below are the original
// values, so CAS reproduces the prompts without carrying any recording.
type Kind = 'tap' | 'confirm' | 'select' | 'error';
const TONES: Record<Kind, number[]> = { confirm: [720, 1080], error: [220, 170], select: [900], tap: [1250] };
const TONE_GAP = .065;
const TONE_GLIDE = .04;
const TONE_ATTACK = .004;
const TONE_DECAY = .055;
const TONE_STOP = .06;
const GAIN_SCALE = .11;
const LOG_LIMIT = 60;

type Settings = { enabled: boolean; volume: number };
const clampVolume = (volume: number) => Number.isFinite(volume) ? Math.min(1, Math.max(0, volume)) : .35;

export const clickCues: { settings: Settings; enabled: boolean } = {
  settings: { enabled: true, volume: .35 },
  enabled: navigator.userActivation?.hasBeenActive ?? false,
};

let context: AudioContext | undefined;
let suspended = document.hidden;
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => { suspended = document.hidden; }, false);
  window.addEventListener('app-background', () => { suspended = true; }, false);
  window.addEventListener('app-foreground', () => { suspended = false; }, false);
  const unlock = (event: Event) => { if (event.isTrusted) clickCues.enabled = true; };
  window.addEventListener('pointerup', unlock, true);
  window.addEventListener('keydown', unlock, true);
}

/** Short synthesized prompt; mirrors the original uiCue gate for tone and volume. */
export function playClickCue(kind: Kind) {
  if (!clickCues.enabled || suspended || document.hidden || !clickCues.settings.enabled) return;
  const level = clickCues.settings.volume * GAIN_SCALE;
  if (level <= 0) return;
  try {
    context ??= new AudioContext();
    if (context.state === 'suspended') context.resume().catch(() => { /* The next gesture retries. */ });
    const now = context.currentTime;
    for (const [index, frequency] of TONES[kind].entries()) {
      const at = now + index * TONE_GAP;
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.setValueAtTime(frequency, at);
      oscillator.frequency.exponentialRampToValueAtTime(frequency * .7, at + TONE_GLIDE);
      gain.gain.setValueAtTime(.0001, at);
      gain.gain.exponentialRampToValueAtTime(Math.max(.0001, level), at + TONE_ATTACK);
      gain.gain.exponentialRampToValueAtTime(.0001, at + TONE_DECAY);
      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(at);
      oscillator.stop(at + TONE_STOP);
      oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
    }
    // QA trace: the synthesized prompt leaves no media element to observe.
    document.dispatchEvent(new CustomEvent('cas-ui-cue', { detail: { kind, level, at: Math.round(now * 1000) } }));
  } catch { /* Devices without WebAudio keep all controls functional. */ }
}

function readSettings(key: string): Settings {
  try {
    const saved = JSON.parse(localStorage.getItem(key) ?? '{}');
    return { enabled: saved.enabled !== false, volume: clampVolume(saved.volume) };
  } catch { return { enabled: true, volume: .35 }; }
}

export function useClickCues(settingsKey: string) {
  const [settings, setSettings] = useState(() => readSettings(settingsKey));
  useEffect(() => {
    clickCues.settings = settings;
    try { localStorage.setItem(settingsKey, JSON.stringify(settings)); }
    catch { /* An unavailable local setting must not interrupt controls. */ }
  }, [settings, settingsKey]);
  return { enabled: settings.enabled, volume: settings.volume,
    setEnabled: (enabled: boolean) => setSettings((previous) => ({ ...previous, enabled })),
    setVolume: (volume: number) => setSettings((previous) => ({ ...previous, volume: clampVolume(volume) })) };
}
