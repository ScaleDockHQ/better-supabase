export {
  type ChecklistItem,
  type ChecklistItemInput,
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
  type WorkItemRecurrence,
  type WorkItems,
  type WorkItemsOptions,
  type WorkItemState,
  type WorkItemWatcher,
  type WorkItemWatchLevel,
} from "./work-items.ts";

export {
  nextWorkItemOccurrence,
  workItemRecurrenceSink,
  type WorkItemRecurrenceSinkOptions,
} from "./recurrence.ts";

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

export {
  workItemChecklistOptimistic,
  workItemChecklistSection,
} from "./section.ts";

export type { WorkItemChecklistOptimisticAction } from "./section.ts";

export {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "./schemas.ts";

export { workItemsEvents } from "./events.ts";

export type { WorkItemsEvents } from "./events.ts";
