import type { RecordBinding } from "../record-bindings.ts";
import type { ChecklistItem, Tasks } from "./tasks.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A pending write to a work item's checklist, for `useOptimistic`. */
export type WorkItemChecklistOptimisticAction =
  | { readonly type: "save"; readonly item: ChecklistItem }
  | { readonly type: "remove"; readonly id: string };

const byRank = (left: ChecklistItem, right: ChecklistItem): number =>
  left.rank < right.rank ? -1 : left.rank > right.rank ? 1 : 0;

/**
 * The checklist with a pending write applied: `save` adds the item or replaces
 * the one with the same id, kept in rank order; `remove` takes it out.
 */
export function workItemChecklistOptimistic(
  state: readonly ChecklistItem[],
  action: WorkItemChecklistOptimisticAction,
): readonly ChecklistItem[] {
  switch (action.type) {
    case "save": {
      return [
        ...state.filter((item) => item.id !== action.item.id),
        action.item,
      ].toSorted(byRank);
    }

    case "remove": {
      return state.filter((item) => item.id !== action.id);
    }

    default: {
      const never: never = action;

      return never;
    }
  }
}

/**
 * A task's checklist, on the task's own page: the subject is the task (`{ type:
 * "task", id }`, or its renamed type). A checklist change emits `task.updated`,
 * which makes the binding stale.
 */
export const taskChecklistBinding: RecordBinding<
  Tasks,
  readonly ChecklistItem[],
  never,
  WorkItemChecklistOptimisticAction
> = defineRecordBinding({
  permissions: { read: "read", write: "write" },
  load: (client: Tasks, subject) => client.checklist(subject.id),
  events: ["task.updated"],
  optimistic: workItemChecklistOptimistic,
});

/** @deprecated Use `taskChecklistBinding`. */
export const workItemChecklistBinding: typeof taskChecklistBinding =
  taskChecklistBinding;
