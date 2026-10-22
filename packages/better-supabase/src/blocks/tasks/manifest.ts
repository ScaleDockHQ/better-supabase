import type { BlockOf } from "../define-block.ts";
import type { TasksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { tasksEvents } from "./events.ts";
import { tasksSqlOptions } from "./options.ts";
import { workItemRecurrenceSink } from "./recurrence.ts";
import {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "./schemas.ts";
import { workItemChecklistSection } from "./section.ts";
import { createTasks } from "./tasks.ts";

/** The `tasks` block's manifest (ADR 0029). */
export const tasksBlock: BlockOf<
  "tasks",
  typeof createTasks,
  TasksEvents,
  Record<never, never>,
  "sink",
  { readonly checklist: typeof workItemChecklistSection }
> = defineBlock({
  name: "tasks",
  sql: ["tasks"],
  options: { tasks: tasksSqlOptions },
  events: tasksEvents,
  provides: { sink: (client) => workItemRecurrenceSink(client) },
  create: createTasks,
  sections: { checklist: workItemChecklistSection },
  category: "work",
  recipes: ["work-item-board", "work-item-grid", "entity-form", "my-work"],
  schemas: {
    work_item: {
      input: workItemInputSchema,
      change: workItemChangeSchema,
      listFilter: workItemListFilterSchema,
    },
  },
});
