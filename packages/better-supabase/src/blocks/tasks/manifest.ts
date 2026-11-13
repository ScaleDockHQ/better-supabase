import type { BlockOf } from "../define-block.ts";
import type { TasksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { taskFromConversationFactory } from "./actions.ts";
import { tasksEvents } from "./events.ts";
import { tasksSqlOptions } from "./options.ts";
import { taskChecklistBinding } from "./record-binding.ts";
import { taskRecurrenceSink } from "./recurrence.ts";
import {
  taskChangeSchema,
  taskInputSchema,
  taskListFilterSchema,
} from "./schemas.ts";
import { createTasks } from "./tasks.ts";

/** The `tasks` block's manifest (ADR 0029). */
export const tasksBlock: BlockOf<
  "tasks",
  typeof createTasks,
  TasksEvents,
  { readonly customFields: "optional" },
  "sink",
  typeof taskChecklistBinding
> = defineBlock({
  name: "tasks",
  sql: ["tasks"],
  options: { tasks: tasksSqlOptions },
  consumes: { customFields: "optional" },
  events: tasksEvents,
  provides: { sink: (client) => taskRecurrenceSink(client) },
  create: createTasks,
  record: taskChecklistBinding,
  category: "work",
  entities: {
    task: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    project: { mutability: "editable", emits: { update: false } },
    iteration: { mutability: "editable", emits: { update: false } },
    checklist_item: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  description:
    "Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.",
  recipes: ["work-item-board", "work-item-grid", "entity-form", "my-work"],
  actions: [
    {
      kind: "tasks.from_conversation",
      title: "Create a task from the conversation",
    },
  ],
  handlers: { "tasks.from_conversation": taskFromConversationFactory },
  schemas: {
    task: {
      input: taskInputSchema,
      change: taskChangeSchema,
      listFilter: taskListFilterSchema,
    },
  },
});
