export {
  createLeadScoring,
  leadRuleFields,
  type LeadScoring,
  type LeadScoringOptions,
} from "./lead-scoring.ts";

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

export { leadScoringBlock } from "./manifest.ts";

export {
  leadScoringSqlOptions,
  type LeadScoringSqlOptions,
} from "./options.ts";
