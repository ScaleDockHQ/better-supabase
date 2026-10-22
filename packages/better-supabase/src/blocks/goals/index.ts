export {
  createGoals,
  type Target,
  type TargetInput,
  type TargetMetric,
  type TargetProgress,
  type Goals,
  type GoalsOptions,
} from "./goals.ts";

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

export { goalsBlock } from "./manifest.ts";
