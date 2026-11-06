// Ending and exact cast selection adapted from 铁底湾 0.6.11 campaign/ending.ts.
import { campaignShipName } from '../campaign-labels';
import type { Observation } from '../engine';
import { shipPortrait } from '../shipPortraits';
import ledger from './ledger.json';

const files = import.meta.glob<string>('./assets/*.webp', { eager: true, import: 'default', query: '?url' });
const artUrl = (path: string) => files['./assets/' + path];

export type Ending = 'victory' | 'defeat';
type Participant = { name: string; classId: string; characterId: string | null };
export type EndingActor = { id: string; name: string; portrait?: string };
export type EndingFrame = {
  stageId: string;
  side: Observation['side'];
  outcome: Ending;
  stageTitle: string;
  resultText?: string;
  actors: EndingActor[];
  plate: string;
  illustration?: string;
};

export function campaignEndingFor(observation: Observation): EndingFrame | undefined {
  const { campaign, result, side } = observation;
  if (!campaign || !result || (result.winner !== 'allies' && result.winner !== 'axis')) return;
  if (!campaign.stageId.startsWith(side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-')) return;
  const roster = (campaign as typeof campaign & { roster?: Participant[] }).roster;
  if (!roster?.length) return;
  const outcome: Ending = result.winner === side ? 'victory' : 'defeat';
  const board = ledger.assets.find(asset => asset.stage_id === campaign.stageId && asset.outcome === outcome);
  if (!board) return;
  const plate = ledger.assets.find(asset => asset.scenario_id === board.scenario_id && asset.outcome === outcome && !asset.stage_id);
  if (!plate) return;

  const actors = roster.map((ship, index) => {
    const portrait = ship.characterId ? shipPortrait(ship.classId, ship.characterId) : undefined;
    return { id: ship.characterId ?? 'participant-' + index, name: portrait?.name ?? campaignShipName(ship.name, side), portrait: portrait?.src };
  });
  const ids = new Set(actors.map(actor => actor.id));
  const alias = ledger.cast_alias;
  const sameCast = board.source_cast?.length === actors.length && ids.size === actors.length && board.source_cast.every(sourceId =>
    ids.has(campaign.stageId === alias.stage_id && sourceId === alias.source_id ? alias.cas_id : sourceId));
  return {
    stageId: campaign.stageId, stageTitle: campaign.missionLabel, side, outcome, actors, plate: artUrl(plate.path),
    illustration: sameCast ? artUrl(board.path) : undefined,
    resultText: typeof result.primary === 'string' ? result.primary : undefined,
  };
}

// The original plates are empty scenery. This layout is only used when the
// original ensemble CG cannot be shown with the actual roster.
export function endingLayout({ actors, outcome }: EndingFrame) {
  const count = actors.length;
  const defeats: Record<number, [number, number][]> = {
    3: [[24, 51], [71, 48], [50, 80]],
    4: [[21, 49], [63, 44], [35, 77], [77, 79]],
    5: [[15, 53], [42, 42], [76, 46], [32, 80], [69, 79]],
  };
  const positions = outcome === 'defeat' ? defeats[count] : undefined;
  return actors.map((actor, index) => {
    if (positions) {
      const [x, y] = positions[index];
      return { actor, x, y, width: 22, height: 35, angle: [-58, 78, 147, -126, 54][index] };
    }
    const columns = Math.min(count, 5), rows = Math.ceil(count / columns);
    const row = Math.floor(index / columns);
    const x = 50 + ((index % columns) - (columns - 1) / 2) * (86 / Math.max(columns, 3));
    const y = rows === 1 ? outcome === 'defeat' ? 63 : 94 : 56 + row * (38 / (rows - 1));
    return { actor, x, y, width: Math.min(30, 92 / columns), height: Math.min(64, 78 / rows), angle: 0 };
  });
}
