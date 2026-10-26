export {
  type Application,
  type ApplicationDetail,
  type ApplicationState,
  type Candidate,
  createHiring,
  type Hiring,
  type HiringOptions,
  type Interview,
  type Job,
  type JobInput,
  type JobStatus,
  type Recommendation,
  type Scorecard,
  type ScorecardScore,
} from "./hiring.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { hiringBlock } from "./manifest.ts";

export { hiringEvents } from "./events.ts";

export type { HiringEvents } from "./events.ts";

export { APPLICATION_TO_EMPLOYEE, HIRING_AUTOMATIONS } from "./automations.ts";
