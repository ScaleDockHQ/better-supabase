import type { EntitySchema } from "../entity-schema.ts";
import type { TaskChange, TaskInput, TaskListOptions } from "./tasks.ts";

import { entitySchema } from "../entity-schema.ts";

const STATES = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
] as const;

/** What `create` takes, with the bounds the SQL checks. */
export const taskInputSchema: EntitySchema<TaskInput> = entitySchema<TaskInput>(
  {
    title: "TaskInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 500 },
      body: { kind: "string", optional: true },
      parentId: { kind: "uuid", optional: true },
      teamId: { kind: "uuid", optional: true },
      projectId: { kind: "uuid", optional: true },
      iterationId: { kind: "uuid", optional: true },
      priority: { kind: "integer", optional: true, minimum: 0, maximum: 4 },
      estimate: { kind: "number", optional: true, minimum: 0 },
      progress: { kind: "integer", optional: true, minimum: 0, maximum: 100 },
      startAt: { kind: "instant", optional: true },
      endAt: { kind: "instant", optional: true },
      dueAt: { kind: "instant", optional: true },
      pipelineId: { kind: "uuid", optional: true },
      stageId: { kind: "uuid", optional: true },
      attachmentIds: { kind: "uuid", optional: true, array: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  },
);

/**
 * One edit `update` takes. `field` is a built-in field or an extra column, so
 * any name passes; the SQL rejects an unknown one.
 */
export const taskChangeSchema: EntitySchema<TaskChange> =
  entitySchema<TaskChange>({
    title: "TaskChange",
    fields: {
      taskId: { kind: "uuid" },
      expectedVersion: {
        kind: "instant",
        optional: true,
        description:
          "The item's `updatedAt` as you read it; a newer item is a `STALE_WRITE` conflict.",
      },
      field: { kind: "string", minLength: 1 },
      value: { kind: "unknown", description: "`null` clears the field." },
    },
  });

/** The options `list` takes. */
export const taskListFilterSchema: EntitySchema<TaskListOptions> =
  entitySchema<TaskListOptions>({
    title: "TaskListOptions",
    fields: {
      teamId: { kind: "uuid", optional: true },
      projectId: { kind: "uuid", optional: true },
      iterationId: { kind: "uuid", optional: true },
      parentId: { kind: "uuid", optional: true },
      assigneeId: { kind: "uuid", optional: true },
      states: { kind: "enum", values: STATES, optional: true, array: true },
      open: { kind: "boolean", optional: true },
      search: { kind: "string", optional: true },
      after: { kind: "uuid", optional: true },
      limit: { kind: "integer", optional: true, minimum: 1 },
    },
  });
