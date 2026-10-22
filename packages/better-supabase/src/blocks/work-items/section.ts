import type { Section } from "../sections.ts";
import type { ChecklistItem, WorkItems } from "./work-items.ts";

import { defineSection } from "../sections.ts";

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
 * A work item's checklist, on the work item's own page: the subject is the work
 * item (`{ type: "work_item", id }`, or its renamed type). A checklist change
 * emits `work_item.updated`, which makes the section stale.
 */
export const workItemChecklistSection: Section<
  WorkItems,
  readonly ChecklistItem[],
  never,
  WorkItemChecklistOptimisticAction
> = defineSection({
  permissions: { read: "read", write: "write" },
  load: (client: WorkItems, subject) => client.checklist(subject.id),
  events: ["work_item.updated"],
  optimistic: workItemChecklistOptimistic,
});
