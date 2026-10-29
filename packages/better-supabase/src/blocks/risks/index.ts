export {
  createRisks,
  type Risk,
  type RiskAssessment,
  type RiskAssessmentInput,
  type RiskBand,
  type RiskChange,
  type RiskHeatmap,
  type RiskHeatmapCell,
  type RiskInput,
  type RiskLevel,
  type RiskListOptions,
  type RiskMatrix,
  type Risks,
  type RisksOptions,
} from "./risks.ts";

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

export { risksBlock } from "./manifest.ts";

export { riskInputSchema } from "./schemas.ts";

export type { RiskInput as RiskInputSchema } from "./schemas.ts";

export { risksEvents } from "./events.ts";

export type {
  RiskAssessedEventData,
  RiskCreatedEventData,
  RiskLifecycleEventData,
  RiskMatrixSavedEventData,
  RisksEvents,
  RiskTreatmentChangedEventData,
  RiskUpdatedEventData,
} from "./events.ts";
