export {
  createRisks,
  type Risk,
  type RiskAssessment,
  type RiskAssessmentInput,
  type RiskChange,
  type RiskDetail,
  type RiskHeatmap,
  type RiskHeatmapCell,
  type RiskInput,
  type RiskLink,
  type RiskListOptions,
  type RiskMatrix,
  type RiskMatrixBand,
  type RiskMatrixInput,
  type RiskMatrixLevel,
  type RiskRating,
  type Risks,
  type RiskScoring,
  type RisksOptions,
  type RiskStatus,
  type RiskTreatment,
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

export { risksSqlOptions, type RisksSqlOptions } from "./options.ts";

export {
  riskAssessmentInputSchema,
  riskInputSchema,
  riskMatrixInputSchema,
} from "./schemas.ts";

export { risksEvents } from "./events.ts";

export type {
  RiskAssessedEventData,
  RiskClosedEventData,
  RiskEventData,
  RiskMatrixEventData,
  RiskReviewDateReachedEventData,
  RiskReviewedEventData,
  RiskTreatmentChangedEventData,
  RisksEvents,
} from "./events.ts";
