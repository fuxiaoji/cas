import labels from '../../data/campaign/locale/zh-labels.json';
import type { Observation, Side } from './engine';

const scenarioTitles: Record<string, string> = labels.scenario_titles;
const shipNames: Record<Side, Record<string, string>> = labels.ships;
const groupNames: Record<string, string> = labels.force_groups;
const legacyFormations: Record<string, string> = labels.legacy_formation_fallbacks;

const formationTypes: Record<string, string> = {
  Desron: '驱逐舰中队', Desdiv: '驱逐舰分队', Crudiv: '巡洋舰分队', Batdiv: '战列舰分队',
  'Task Group': '特混编队', TG: '特混编队', TF: '特遣舰队',
};

const proseNames: Record<string, string> = {
  ...labels.ships.allies, ...labels.ships.axis, ...labels.formations, ...labels.terms,
};
const escapePattern = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const prosePattern = new RegExp(
  '(?<![A-Za-z0-9])(?:' + Object.keys(proseNames)
    .sort((a, b) => b.length - a.length).map(escapePattern).join('|') + ')(?![A-Za-z0-9])',
  'g',
);
const formationPattern = /\b(Desron|Desdiv|Crudiv|Batdiv|Task Group|TG|TF)\s*(\d+(?:\.\d+)*(?:–\d+)?)\b/g;

export function campaignScenarioTitle(casId: string, oldTitle: string) {
  return scenarioTitles[casId] ?? oldTitle;
}

export function campaignShipName(name: string, side: Side) {
  return shipNames[side][name] ?? name;
}

export function campaignText(text: string) {
  return text.replace(prosePattern, match => proseNames[match]).replace(
    formationPattern, (_, kind: string, number: string) => `第 ${number} ${formationTypes[kind]}`,
  );
}

export function campaignForceGroup(key: string) {
  return groupNames[key];
}

export function campaignLegacyFormation(id: string, note?: string | null) {
  if (note) return campaignText(note.split('（', 1)[0].trim());
  return legacyFormations[id] ?? '原编队';
}

// Keep the worker/server observation and the stored replay untouched.
export function campaignObservationLabels(observation: Observation): Observation {
  if (!observation.campaign) return observation;
  const side = observation.side;
  const opposite = side === 'allies' ? 'axis' : 'allies';
  return {
    ...observation,
    ships: observation.ships.map(ship => ({ ...ship, name: campaignShipName(ship.name, side) })),
    fleets: observation.fleets.map(fleet => ({
      ...fleet, name: campaignText(fleet.name), notice: fleet.notice && campaignText(fleet.notice),
    })),
    contacts: observation.contacts.map(contact => contact.name
      ? { ...contact, name: campaignShipName(contact.name, opposite) }
      : contact),
    events: observation.events.map(event => ({ ...event, text: campaignText(event.text) })),
  };
}
