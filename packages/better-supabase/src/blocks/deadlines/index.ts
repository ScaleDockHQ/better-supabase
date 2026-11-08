export {
  createDeadlines,
  evaluateVersion,
  validateRuleVersion,
  type Deadline,
  type DeadlineListOptions,
  type Deadlines,
  type DeadlinesOptions,
  type DeadlineSubject,
  type RuleVersion,
} from "./deadlines.ts";

export type {
  Applies,
  Condition,
  ConditionValue,
  DateRegime,
  DeadlineBasis,
  DeadlineCitation,
  DeadlineCount,
  DeadlineCounting,
  DeadlineException,
  DeadlineExceptionResult,
  DeadlineFacts,
  DeadlineGroup,
  DeadlineGroupResult,
  DeadlineHoliday,
  DeadlineResult,
  DeadlineReview,
  DeadlineRule,
  DeadlineSpec,
  RuleVersionContent,
} from "../../sql/modules/deadlines-values.ts";

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

export { deadlinesBlock } from "./manifest.ts";

export { deadlinesEvents } from "./events.ts";

export type { DeadlineEventData, DeadlinesEvents } from "./events.ts";
