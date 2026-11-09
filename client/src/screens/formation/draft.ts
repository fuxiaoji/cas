// Deployment drafts and named presets live in localStorage, keyed by the local
// commander. They are UI conveniences only: the kernel re-validates every
// pick when the sortie starts (src/campaign/fleet.rs).
import type { CampaignDifficulty } from '../../campaign-progress';
import { profileIds } from '../../engine';
import type { Profile } from '../../engine';

export interface DeploymentDraft {
  picks: string[];
  profile: Profile;
  updatedAt: number;
}

export interface FleetPreset extends DeploymentDraft {
  id: string;
  name: string;
  stageId: string;
  difficulty: CampaignDifficulty;
}

const profiles: readonly Profile[] = profileIds;
const difficulties: readonly CampaignDifficulty[] = ['story', 'standard', 'challenge'];
const MAX_PRESETS = 24;

export function draftKey(stageId: string, difficulty: CampaignDifficulty) {
  return stageId + ':' + difficulty;
}

const draftKeyFor = (profileId: string) => 'cas.deployment.v1:' + profileId;
const presetKeyFor = (profileId: string) => 'cas.fleetPresets.v1:' + profileId;

function isProfile(value: unknown): value is Profile {
  return typeof value === 'string' && profiles.includes(value as Profile);
}

function isDifficulty(value: unknown): value is CampaignDifficulty {
  return typeof value === 'string' && difficulties.includes(value as CampaignDifficulty);
}

function isPicks(value: unknown): value is string[] {
  return Array.isArray(value) && value.length > 0 && value.every((pick) => typeof pick === 'string' && pick.length > 0);
}

function readJson(key: string): unknown {
  try {
    return JSON.parse(window.localStorage.getItem(key) ?? 'null');
  } catch {
    return null;
  }
}

function writeJson(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Private mode or a full quota must not stop the sortie screen.
  }
}

export function readDraft(profileId: string, stageId: string, difficulty: CampaignDifficulty): DeploymentDraft | undefined {
  const book = readJson(draftKeyFor(profileId));
  if (!book || typeof book !== 'object' || Array.isArray(book)) return undefined;
  const row = (book as Record<string, unknown>)[draftKey(stageId, difficulty)];
  if (!row || typeof row !== 'object' || Array.isArray(row)) return undefined;
  const value = row as Record<string, unknown>;
  if (!isPicks(value.picks) || !isProfile(value.profile)) return undefined;
  return { picks: value.picks, profile: value.profile, updatedAt: typeof value.updatedAt === 'number' ? value.updatedAt : 0 };
}

export function writeDraft(profileId: string, stageId: string, difficulty: CampaignDifficulty, draft: DeploymentDraft) {
  const book = readJson(draftKeyFor(profileId));
  const next = book && typeof book === 'object' && !Array.isArray(book) ? { ...(book as Record<string, unknown>) } : {};
  next[draftKey(stageId, difficulty)] = draft;
  writeJson(draftKeyFor(profileId), next);
}

export function readPresets(profileId: string): FleetPreset[] {
  const value = readJson(presetKeyFor(profileId));
  if (!Array.isArray(value)) return [];
  return value.flatMap((row) => {
    if (!row || typeof row !== 'object') return [];
    const item = row as Record<string, unknown>;
    if (typeof item.id !== 'string' || typeof item.name !== 'string' || typeof item.stageId !== 'string' ||
        !isDifficulty(item.difficulty) || !isPicks(item.picks) || !isProfile(item.profile)) return [];
    return [{
      id: item.id, name: item.name, stageId: item.stageId, difficulty: item.difficulty,
      picks: item.picks, profile: item.profile,
      updatedAt: typeof item.updatedAt === 'number' ? item.updatedAt : 0,
    }];
  }).slice(0, MAX_PRESETS);
}

export function writePresets(profileId: string, presets: FleetPreset[]) {
  writeJson(presetKeyFor(profileId), presets.slice(0, MAX_PRESETS));
}

export function appendPreset(profileId: string, preset: FleetPreset): FleetPreset[] {
  const next = [preset, ...readPresets(profileId).filter((item) => item.id !== preset.id)].slice(0, MAX_PRESETS);
  writePresets(profileId, next);
  return next;
}

export { isDifficulty, isPicks, isProfile };
