export {
  type CloseReason,
  createWorkItems,
  type Iteration,
  type Project,
  type WorkItem,
  type WorkItemChange,
  type WorkItemChangeResult,
  type WorkItemField,
  type WorkItemInput,
  type WorkItemListOptions,
  type WorkItemNode,
  type WorkItems,
  workItemsSubjects,
  type WorkItemsOptions,
  type WorkItemState,
} from "./work-items.ts";

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

export { workItemsBlock } from "./manifest.ts";

export { workItemsEvents } from "./events.ts";

export type { WorkItemsEvents } from "./events.ts";
