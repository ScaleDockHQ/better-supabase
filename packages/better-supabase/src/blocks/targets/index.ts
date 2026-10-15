export {
  createTargets,
  type Target,
  type TargetInput,
  type TargetMetric,
  type TargetProgress,
  type Targets,
  type TargetsOptions,
} from "./targets.ts";
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
export { targetsBlock } from "./manifest.ts";
