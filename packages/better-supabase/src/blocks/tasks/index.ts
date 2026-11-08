export {
  type ChecklistItem,
  type ChecklistItemInput,
  type CloseReason,
  createTasks,
  type Iteration,
  type Project,
  type Task,
  type TaskChange,
  type TaskChangeResult,
  type TaskField,
  type TaskInput,
  type TaskListOptions,
  type TaskNode,
  type TaskRecurrence,
  type TaskSetResult,
  type Tasks,
  type TasksOptions,
  type TaskState,
  type TaskUpdateOptions,
  type TaskWindow,
  type TaskWatcher,
  type TaskWatchLevel,
} from "./tasks.ts";

export {
  nextTaskOccurrence,
  taskRecurrenceSink,
  type TaskRecurrenceSinkOptions,
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

export { tasksBlock } from "./manifest.ts";

export {
  taskChecklistBinding,
  taskChecklistOptimistic,
} from "./record-binding.ts";

export type { TaskChecklistOptimisticAction } from "./record-binding.ts";

export {
  taskChangeSchema,
  taskInputSchema,
  taskListFilterSchema,
} from "./schemas.ts";

export { tasksEvents } from "./events.ts";

export type { TasksEvents } from "./events.ts";

export {
  taskFromConversationAction,
  type TaskFromConversationClients,
  type TaskFromConversationOptions,
} from "./actions.ts";
