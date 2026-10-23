export {
  type ComputedScore,
  createScores,
  type Score,
  type ScoreBand,
  type ScoreBreakdown,
  type ScoreMetric,
  type ScoreModel,
  type ScoreModelDetail,
  type ScoreModelInput,
  type ScoreModelVersion,
  type ScoreRule,
  type Scores,
  type ScoresOptions,
} from "./scores.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { scoresBlock } from "./manifest.ts";

export { scoresBinding } from "./record-binding.ts";

export { scoresEvents } from "./events.ts";

export type {
  ScoreChangedEventData,
  ScoreModelEventData,
  ScoresEvents,
} from "./events.ts";

export type { ScoresSqlOptions } from "./options.ts";
