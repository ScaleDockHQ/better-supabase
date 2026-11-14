import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { BulkOptions, BulkReport } from "../../core/bulk.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { IdempotencyClaims } from "../../core/idempotent-write.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { CustomFields } from "../custom-fields/custom-fields.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { bulkOfSet } from "../../core/bulk.ts";
import { dbError } from "../../core/errors.ts";
import { idempotentCall } from "../../core/idempotent-write.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { strictChanges } from "../strict-changes.ts";

/** The state a stage's category sets; `completed` and `canceled` are closed. */
export type TaskState =
  | "triage"
  | "backlog"
  | "unstarted"
  | "started"
  | "completed"
  | "canceled";

const STATES: readonly TaskState[] = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
];

export type CloseReason = "completed" | "not_planned" | "duplicate";

/** A work item. `F` types the extra columns the `fields` schema describes. */
export interface Task<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly number: bigint;
  /** `TASK-12`, or the numbering format. */
  readonly identifier: string;
  readonly title: string;
  readonly body?: string;
  readonly parentId?: string;
  readonly teamId?: string;
  readonly projectId?: string;
  readonly iterationId?: string;
  /** 0 none, 1 urgent, 2 high, 3 medium, 4 low. */
  readonly priority: number;
  readonly estimate?: number;
  /** Its own progress; `tree` rolls children up when it has none. */
  readonly progress?: number;
  readonly startAt?: Temporal.Instant;
  readonly endAt?: Temporal.Instant;
  readonly dueAt?: Temporal.Instant;
  readonly pipelineId?: string;
  readonly stageId?: string;
  readonly stageEnteredAt?: Temporal.Instant;
  readonly state: TaskState;
  readonly closeReason?: CloseReason;
  readonly closedAt?: Temporal.Instant;
  /** A locked item keeps its dates, as a locked Gantt bar. */
  readonly locked: boolean;
  readonly rank: string;
  readonly assigneeIds: readonly string[];
  /** How many checklist items it has, and how many are done. */
  readonly checklist: { readonly total: number; readonly done: number };
  /** Its repeat rule, with the reminders block. */
  readonly recurrence?: TaskRecurrence;
  /** The item this one repeats. */
  readonly recursFromId?: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
  readonly archived: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The actions `tasks.bulk` takes. */
export type TaskBulkAction = "archive" | "restore" | "remove";

/** What the set forms of `archive` and `remove` did. */
export interface TaskSetResult {
  /** The items that were changed. */
  readonly ids: readonly string[];
  /** The ids that don't exist or that the caller can't change. */
  readonly skipped: readonly string[];
}

export interface TaskInput<F extends object = Record<never, never>> {
  readonly title: string;
  readonly body?: string;
  readonly parentId?: string;
  readonly teamId?: string;
  readonly projectId?: string;
  readonly iterationId?: string;
  readonly priority?: number;
  readonly estimate?: number;
  readonly progress?: number;
  readonly startAt?: Temporal.Instant;
  readonly endAt?: Temporal.Instant;
  readonly dueAt?: Temporal.Instant;
  readonly pipelineId?: string;
  readonly stageId?: string;
  /**
   * Files to attach: ids of your own attachments in the organization that have
   * no subject yet, such as uploads made before the item existed.
   */
  readonly attachmentIds?: readonly string[];
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export type TaskField =
  | "title"
  | "body"
  | "parentId"
  | "teamId"
  | "projectId"
  | "iterationId"
  | "priority"
  | "estimate"
  | "progress"
  | "startAt"
  | "endAt"
  | "dueAt"
  | "stageId"
  | "closeReason"
  | "attachments"
  | "window";

/**
 * The value of a `window` change: both ends written in one update, so moving
 * the window never fails the end-after-start check halfway. A key left out
 * keeps its value, and `null` clears it.
 */
export interface TaskWindow {
  readonly startAt?: Temporal.Instant | null;
  readonly endAt?: Temporal.Instant | null;
}

export interface TaskUpdateOptions {
  /**
   * Keep every change or none: the first change that fails rolls the batch back
   * and comes back as the error, instead of a `rejected` entry.
   */
  readonly atomic?: boolean;
  /**
   * Turns the first refused change into the error, with its hint as the code,
   * instead of a `rejected` entry. Accepted changes stay applied unless
   * `atomic` is set too.
   */
  readonly strict?: boolean;
}

/** A work item's repeat rule: an RFC 5545 RRULE from `dtstart` in `tzid`. */
export interface TaskRecurrence {
  readonly rrule: string;
  readonly tzid: string;
  readonly dtstart: Temporal.Instant;
}

export interface ChecklistItem {
  readonly id: string;
  readonly taskId: string;
  readonly title: string;
  readonly done: boolean;
  readonly doneAt?: Temporal.Instant;
  readonly doneBy?: string;
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
}

export interface ChecklistItemInput {
  readonly title?: string;
  readonly done?: boolean;
  /** A rank key; a new item without one goes last. */
  readonly rank?: string;
}

/** `all` watches, `participating` follows, `ignore` mutes. */
export type TaskWatchLevel = "all" | "participating" | "ignore";

export interface TaskWatcher {
  readonly userId: string;
  readonly level: Exclude<TaskWatchLevel, "ignore">;
}

/**
 * One cell edit or drag: a built-in field or an extra column. `null` clears the
 * field.
 */
export interface TaskChange<F extends object = Record<never, never>> {
  readonly taskId: string;
  /**
   * The item's `updatedAt` as you read it. The change is refused with a
   * `STALE_WRITE` conflict when the item changed since.
   */
  readonly expectedVersion?: Temporal.Instant | undefined;
  readonly field: TaskField | (keyof F & string);
  readonly value: unknown;
}

export interface TaskChangeResult {
  readonly accepted: readonly {
    readonly taskId: string;
    readonly field: string;
  }[];
  readonly rejected: readonly {
    readonly taskId: string;
    readonly field: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

/** A node of `tree`, for a Gantt chart or a nested list. */
export interface TaskNode {
  readonly id: string;
  readonly parentId?: string;
  readonly identifier: string;
  readonly title: string;
  readonly state: TaskState;
  readonly startAt?: Temporal.Instant;
  readonly endAt?: Temporal.Instant;
  readonly dueAt?: Temporal.Instant;
  readonly locked: boolean;
  readonly depth: number;
  readonly progress: number;
}

export interface TaskListOptions {
  readonly teamId?: string;
  readonly projectId?: string;
  readonly iterationId?: string;
  readonly parentId?: string;
  readonly assigneeId?: string;
  readonly states?: readonly TaskState[];
  /** Only items that aren't completed or canceled. */
  readonly open?: boolean;
  /** Matches the title, or the start of the identifier. */
  readonly search?: string;
  /** Continues after this item. */
  readonly after?: string;
  readonly limit?: number;
}

export interface Project {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly ownerId?: string;
  readonly status: "planned" | "active" | "paused" | "completed" | "canceled";
  readonly startOn?: Temporal.PlainDate;
  readonly targetOn?: Temporal.PlainDate;
  /** The share of its items that are completed, canceled ones left out. */
  readonly progress?: number;
  /** What the project may cost; `billableTime.projectCosts` compares it. */
  readonly budget?: Money;
  readonly budgetHours?: number;
}

export interface Iteration {
  readonly id: string;
  readonly teamId?: string;
  readonly name: string;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn: Temporal.PlainDate;
}

export interface Tasks<F extends object = Record<never, never>> {
  /**
   * `custom` sets custom field values on the new item, by definition id, after
   * it is created (the `customFields` port; hint `TASKS_CUSTOM_FIELDS_MISSING`
   * without it). When a value is refused the item is removed again and the
   * error returned.
   */
  create(input: {
    organizationId: string;
    input: TaskInput<F>;
    assigneeIds?: readonly string[] | undefined;
    custom?: Readonly<Record<string, string>> | undefined;
    /** Makes a retry return the first result (`idempotency` option). */
    idempotencyKey?: string | undefined;
  }): AsyncResult<Task<F>>;
  /**
   * Copies a task and its assignees, checklist and child tasks. `overrides`
   * replace the fields the caller edited. A template becomes a live task unless
   * `overrides.templateId` is set.
   */
  clone(input: {
    sourceId: string;
    overrides?: Readonly<Record<string, unknown>> | undefined;
  }): AsyncResult<Task<F>>;
  /** Extra column changes are validated with the `fields` schema first. */
  update(
    input: { changes: readonly TaskChange<F>[] } & TaskUpdateOptions,
  ): AsyncResult<TaskChangeResult>;
  /**
   * Moves the item to `stageId` and returns the refusal as the error. It is
   * `update` with one `stageId` change and `strict`, so the `update` hooks see
   * the move.
   */
  move(input: { taskId: string; stageId: string }): AsyncResult<true>;
  /** Replaces the assignees; new ones are notified and every one watches. */
  assign(input: {
    taskId: string;
    userIds: readonly string[];
  }): AsyncResult<number>;
  archive(input: {
    taskId: string;
    archived?: boolean | undefined;
  }): AsyncResult<boolean>;
  /**
   * Archives many items in one statement. Access is checked once, and the ids
   * that don't exist or that you can't edit come back in `skipped`.
   */
  archive(input: {
    taskIds: readonly string[];
    archived?: boolean | undefined;
  }): AsyncResult<TaskSetResult>;
  /** Brings an archived item back and records `task.restored`. */
  restore(taskId: string): AsyncResult<boolean>;
  /** Restores many items in one statement; `skipped` lists the refused ids. */
  restore(taskIds: readonly string[]): AsyncResult<TaskSetResult>;
  remove(taskId: string): AsyncResult<boolean>;
  /** Removes many items in one statement; `skipped` lists the refused ids. */
  remove(taskIds: readonly string[]): AsyncResult<TaskSetResult>;
  /**
   * `archive`, `restore` or `remove` for many tasks in one statement, as the
   * common `bulk(ids, action)` (ADR 0854): `{ succeeded, failed }`, where the
   * ids the set call skipped are `failed` with `not_found`. More ids than the
   * limit (500) fail with `BULK_TOO_MANY`.
   */
  bulk(
    ids: readonly string[],
    action: TaskBulkAction,
    options?: BulkOptions,
  ): AsyncResult<BulkReport>;
  tree(rootId: string): AsyncResult<TaskNode[]>;
  /** One item you can read, or `undefined`. */
  get(taskId: string): AsyncResult<Task<F> | undefined>;
  checklist(taskId: string): AsyncResult<ChecklistItem[]>;
  /** Adds a checklist item, or changes the one `checklistItemId` names. */
  saveChecklistItem(input: {
    taskId: string;
    input: ChecklistItemInput;
    checklistItemId?: string | undefined;
  }): AsyncResult<ChecklistItem>;
  removeChecklistItem(checklistItemId: string): AsyncResult<boolean>;
  /**
   * Makes the item repeat (`null` stops it). Needs the reminders block;
   * `taskRecurrenceSink` creates the next item when one is completed.
   */
  setRecurrence(input: {
    taskId: string;
    rule: { readonly rrule: string; readonly tzid?: string } | null;
  }): AsyncResult<TaskRecurrence | undefined>;
  /** Creates the next item of a repeating one. Service only, idempotent. */
  repeat(input: {
    taskId: string;
    dueAt: Temporal.Instant;
  }): AsyncResult<Task<F>>;
  /** Watches, follows or mutes an item (`null` clears). Needs notifications. */
  watch(input: {
    taskId: string;
    level: TaskWatchLevel | null;
  }): AsyncResult<boolean>;
  watchers(taskId: string): AsyncResult<TaskWatcher[]>;
  list(
    input: { organizationId: string } & TaskListOptions,
  ): AsyncResult<Task<F>[]>;
  saveProject(input: {
    organizationId: string;
    project: Partial<
      Omit<
        Project,
        "id" | "progress" | "startOn" | "targetOn" | "budget" | "budgetHours"
      >
    > & {
      readonly id?: string;
      readonly startOn?: Temporal.PlainDate | null;
      readonly targetOn?: Temporal.PlainDate | null;
      readonly budget?: Money | null;
      readonly budgetHours?: number | null;
      readonly archived?: boolean;
    };
  }): AsyncResult<Project>;
  saveIteration(input: {
    organizationId: string;
    iteration: Partial<Omit<Iteration, "id">> & { readonly id?: string };
  }): AsyncResult<Iteration>;
  /**
   * Moves the item to `stageId`, a stage of the `completed` category, and
   * checks that the item is completed afterwards. A stage of another category
   * comes back as an `invalid_input` error (the item has moved by then).
   */
  complete(input: { taskId: string; stageId: string }): AsyncResult<true>;
  /** `complete` for a stage of the `canceled` category. */
  cancel(input: { taskId: string; stageId: string }): AsyncResult<true>;
  /**
   * Adds `userId` to the item's assignees and keeps the others; `assign`
   * replaces them. The client has no signed-in user, so the caller passes its
   * id (`ctx.user.id` in an action). Returns the assignee count, and does
   * nothing when the user is already assigned.
   */
  assignToMe(input: { taskId: string; userId: string }): AsyncResult<number>;
  /**
   * Moves a closed item back to `stageId`, a stage of an open category, and
   * checks that it is open afterwards.
   */
  reopen(input: { taskId: string; stageId: string }): AsyncResult<true>;
}

export interface TasksOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the item's extra columns (columns the app's schema
   * files add to the table), keyed by database name. It types and parses them
   * on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Tasks<FieldsOf<S>>>>;
  readonly logger?: Logger;
  /** Claims `create({ idempotencyKey })`: `createIdempotency(...)`. */
  readonly idempotency?: IdempotencyClaims | undefined;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * The `custom-fields` port, which `create({ custom })` sets values through.
   * `createBlocks` passes it.
   */
  readonly customFields?: Pick<CustomFields, "setValue">;
}

/** The fields `update` writes without the `fields` schema. */
const BUILT_IN: ReadonlySet<string> = new Set<TaskField>([
  "title",
  "body",
  "parentId",
  "teamId",
  "projectId",
  "iterationId",
  "priority",
  "estimate",
  "progress",
  "startAt",
  "endAt",
  "dueAt",
  "stageId",
  "closeReason",
  "window",
]);

/** The states of an item that is not closed. */
const OPEN_STATES: readonly TaskState[] = [
  "triage",
  "backlog",
  "unstarted",
  "started",
];

const KNOWN = new Set([
  "id",
  "tenant_id",
  "number",
  "identifier",
  "title",
  "body",
  "parent_id",
  "team_id",
  "project_id",
  "iteration_id",
  "priority",
  "estimate",
  "progress",
  "start_at",
  "end_at",
  "due_at",
  "pipeline_id",
  "stage_id",
  "stage_entered_at",
  "state",
  "close_reason",
  "closed_at",
  "locked",
  "rank",
  "archived_at",
  "recurs_from",
  "checklist",
  "recurrence",
  "created_by",
  "created_at",
  "updated_at",
  "assignees",
]);

type Loose<T> = { [K in keyof T]: T[K] | undefined };

function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

const idsOf = (value: unknown): string[] =>
  Array.isArray(value) ? value.map((each) => textOf(each)) : [];

const setResultOf = (value: unknown): TaskSetResult => {
  const row = isRecord(value) ? value : {};

  return { ids: idsOf(row["ids"]), skipped: idsOf(row["skipped"]) };
};

const num = (value: unknown): number | undefined => {
  if (typeof value === "number") {
    return value;
  }

  if (typeof value === "string" && value !== "") {
    return Number(value);
  }

  return undefined;
};

const date = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

function itemOf(value: unknown): Task {
  const row = recordOf(value, "work item");
  const reason = optionalText(row["close_reason"]);

  return compact<Task>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    number: BigInt(textOf(row["number"])),
    identifier: textOf(row["identifier"]),
    title: textOf(row["title"]),
    body: optionalText(row["body"]),
    parentId: optionalText(row["parent_id"]),
    teamId: optionalText(row["team_id"]),
    projectId: optionalText(row["project_id"]),
    iterationId: optionalText(row["iteration_id"]),
    priority: num(row["priority"]) ?? 0,
    estimate: num(row["estimate"]),
    progress: num(row["progress"]),
    startAt: optionalInstant(row["start_at"]),
    endAt: optionalInstant(row["end_at"]),
    dueAt: optionalInstant(row["due_at"]),
    pipelineId: optionalText(row["pipeline_id"]),
    stageId: optionalText(row["stage_id"]),
    stageEnteredAt: optionalInstant(row["stage_entered_at"]),
    state: enumOrThrow(row["state"], STATES, "work item state"),
    closeReason:
      reason === undefined
        ? undefined
        : enumOrThrow(
            reason,
            ["completed", "not_planned", "duplicate"] as const,
            "close reason",
          ),
    closedAt: optionalInstant(row["closed_at"]),
    locked: row["locked"] === true,
    rank: textOf(row["rank"]),
    assigneeIds: Array.isArray(row["assignees"])
      ? row["assignees"].map(String)
      : [],
    checklist: checklistSummaryOf(row["checklist"]),
    recurrence: recurrenceOf(row["recurrence"]),
    recursFromId: optionalText(row["recurs_from"]),
    fields: Object.fromEntries(
      Object.entries(row).filter(([key]) => !KNOWN.has(key)),
    ),
    archived: row["archived_at"] !== null && row["archived_at"] !== undefined,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  });
}

function checklistSummaryOf(value: unknown): Task["checklist"] {
  const row = isRecord(value) ? value : {};

  return { total: num(row["total"]) ?? 0, done: num(row["done"]) ?? 0 };
}

function recurrenceOf(value: unknown): TaskRecurrence | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    rrule: textOf(value["rrule"]),
    tzid: textOf(value["tzid"]),
    dtstart: requiredInstant(value["dtstart"], "dtstart"),
  };
}

function checklistItemOf(value: unknown): ChecklistItem {
  const row = recordOf(value, "checklist item");

  return compact<ChecklistItem>({
    id: textOf(row["id"]),
    taskId: textOf(row["taskId"]),
    title: textOf(row["title"]),
    done: row["done"] === true,
    doneAt: optionalInstant(row["doneAt"]),
    doneBy: optionalText(row["doneBy"]),
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  });
}

function watcherOf(value: unknown): TaskWatcher {
  const row = recordOf(value, "watcher");

  return {
    userId: textOf(row["userId"]),
    level: enumOrThrow(
      row["level"],
      ["all", "participating"] as const,
      "watch level",
    ),
  };
}

function nodeOf(value: unknown): TaskNode {
  const row = recordOf(value, "work item node");

  return compact<TaskNode>({
    id: textOf(row["id"]),
    parentId: optionalText(row["parentId"]),
    identifier: textOf(row["identifier"]),
    title: textOf(row["title"]),
    state: enumOrThrow(row["state"], STATES, "work item state"),
    startAt: optionalInstant(row["startAt"]),
    endAt: optionalInstant(row["endAt"]),
    dueAt: optionalInstant(row["dueAt"]),
    locked: row["locked"] === true,
    depth: num(row["depth"]) ?? 0,
    progress: num(row["progress"]) ?? 0,
  });
}

function projectOf(value: unknown): Project {
  const row = recordOf(value, "project");

  return compact<Project>({
    id: textOf(row["id"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    ownerId: optionalText(row["owner_id"]),
    status: enumOrThrow(
      row["status"],
      ["planned", "active", "paused", "completed", "canceled"] as const,
      "project status",
    ),
    startOn: date(row["start_on"]),
    targetOn: date(row["target_on"]),
    progress: num(row["progress"]),
    budget:
      row["budget_currency"] === null || row["budget_currency"] === undefined
        ? undefined
        : optionalMoneyOf(row["budget_amount"], row["budget_currency"]),
    budgetHours: num(row["budget_hours"]),
  });
}

function iterationOf(value: unknown): Iteration {
  const row = recordOf(value, "iteration");

  return compact<Iteration>({
    id: textOf(row["id"]),
    teamId: optionalText(row["team_id"]),
    name: textOf(row["name"]),
    startsOn: date(row["starts_on"]) ?? temporal().PlainDate.from("1970-01-01"),
    endsOn: date(row["ends_on"]) ?? temporal().PlainDate.from("1970-01-01"),
  });
}

/** A value as the database reads it: instants and dates as ISO text. */
function valueArg(value: unknown): unknown {
  if (
    value instanceof temporal().Instant ||
    value instanceof temporal().PlainDate
  ) {
    return value.toString();
  }

  return value;
}

const args = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).map(([key, value]) => [key, valueArg(value)]),
  );

/**
 * The tasks block: issues and tasks on pipelines, with batched edits for a grid
 * or a Gantt chart, assignees, a progress tree, projects and iterations.
 */
export function createTasks<S extends StandardSchemaV1 | undefined = undefined>(
  options: TasksOptions<S>,
): Tasks<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "work item fields",
  );

  /**
   * `create_task`, claimed through the `idempotency` option when a key is
   * given.
   */
  const claimed = (
    name: string,
    scope: string,
    key: string | undefined,
    sent: Readonly<Record<string, unknown>>,
  ): AsyncResult<Task> =>
    idempotentCall({
      claims: options.idempotency,
      key,
      scope,
      name,
      args: sent,
      run: () => call(name, sent, (value) => value),
      decode: itemOf,
    });

  /** Moves the item, then checks the state the stage's category gave it. */
  const settle = (
    { taskId, stageId }: { taskId: string; stageId: string },
    expected: readonly TaskState[],
    label: string,
  ): AsyncResult<true> =>
    hooked
      .move({ taskId, stageId })
      .andThen(() => hooked.get(taskId))
      .andThen((item) =>
        Promise.resolve(
          item !== undefined && expected.includes(item.state)
            ? ok(true as const)
            : err(
                dbError(
                  "invalid_input",
                  `Stage ${stageId} does not make work item ${taskId} ${label}`,
                ),
              ),
        ),
      );

  const client: Tasks<F> = {
    create: ({
      organizationId,
      input,
      assigneeIds,
      custom,
      idempotencyKey,
    }) => {
      const { fields: extra, attachmentIds, ...attrs } = input;
      const entries = Object.entries(custom ?? {});

      if (entries.length > 0 && options.customFields === undefined) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            "createTasks needs the customFields port to set custom values",
            { hint: "TASKS_CUSTOM_FIELDS_MISSING" },
          ),
        );
      }

      return fields
        .args(extra)
        .andThen((checked) =>
          claimed("create_task", organizationId, idempotencyKey, {
            tenant: organizationId,
            attrs: {
              ...args(attrs),
              ...(attachmentIds === undefined
                ? {}
                : { attachments: [...attachmentIds] }),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            assignees: assigneeIds === undefined ? null : [...assigneeIds],
          }).andThen(fields.row),
        )
        .andThen(async (created) => {
          for (const [definitionId, value] of entries) {
            // SAFETY: the check above returned when entries exist without the port.
            const set = await options.customFields!.setValue({
              subject: { type: "task", id: created.id },
              definitionId,
              value,
            });

            if (!set.ok) {
              await hooked.remove(created.id);

              return set;
            }
          }

          return ok(created);
        });
    },
    clone: ({ sourceId, overrides }) =>
      call(
        "clone_task",
        { source: sourceId, overrides: overrides ?? null },
        itemOf,
      ).andThen(fields.row),
    update: ({ changes, ...updateOptions }) =>
      AsyncResult.from(async () => {
        for (const change of changes) {
          if (BUILT_IN.has(change.field)) {
            continue;
          }

          const valid = await fields.write({ [change.field]: change.value });

          if (!valid.ok) {
            return valid;
          }
        }

        return ok(changes);
      }).andThen((checked) =>
        call(
          "update_tasks",
          {
            changes: checked.map((change) => ({
              taskId: change.taskId,
              field: change.field,
              ...(change.expectedVersion === undefined
                ? {}
                : { expectedVersion: change.expectedVersion.toString() }),
              value:
                change.field === "window" && isRecord(change.value)
                  ? args(change.value)
                  : valueArg(change.value),
            })),
            ...(updateOptions.atomic === true ? { atomic: true } : {}),
          },
          (value) => {
            const row = recordOf(value, "update_tasks");

            return {
              accepted: recordsOf(row["accepted"], "accepted").map((item) => ({
                taskId: textOf(item["taskId"]),
                field: textOf(item["field"]),
              })),
              rejected: recordsOf(row["rejected"], "rejected").map((item) =>
                compact<TaskChangeResult["rejected"][number]>({
                  taskId: textOf(item["taskId"]),
                  field: textOf(item["field"]),
                  hint: optionalText(item["hint"]),
                  reason: textOf(item["reason"]),
                }),
              ),
            };
          },
        ).andThen((result) => strictChanges(result, updateOptions.strict)),
      ),
    move: ({ taskId, stageId }) =>
      hooked
        .update({
          changes: [{ taskId, field: "stageId", value: stageId }],
          strict: true,
        })
        .map(() => true as const),
    assign: ({ taskId, userIds }) =>
      call(
        "set_task_assignees",
        { task: taskId, users: [...userIds] },
        (value) => num(value) ?? 0,
      ),
    // SAFETY: the implementation handles both overloads of `archive`.
    archive: ((
      input:
        | { taskId: string; archived?: boolean | undefined }
        | { taskIds: readonly string[]; archived?: boolean | undefined },
    ) => {
      const archived = input.archived ?? true;

      return "taskIds" in input
        ? call(
            "archive_tasks",
            { ids: [...input.taskIds], archived },
            setResultOf,
          )
        : call(
            "archive_task",
            { task: input.taskId, archived },
            (value) => value === true,
          );
    }) as Tasks<F>["archive"],
    // SAFETY: the implementation handles both overloads of `restore`.
    restore: ((target: string | readonly string[]) =>
      typeof target === "string"
        ? call(
            "archive_task",
            { task: target, archived: false },
            (value) => value === true,
          )
        : call(
            "archive_tasks",
            { ids: [...target], archived: false },
            setResultOf,
          )) as Tasks<F>["restore"],
    // SAFETY: the implementation handles both overloads of `remove`.
    remove: ((target: string | readonly string[]) =>
      typeof target === "string"
        ? call("delete_task", { task: target }, (value) => value === true)
        : call(
            "delete_tasks",
            { ids: [...target] },
            setResultOf,
          )) as Tasks<F>["remove"],
    bulk: (ids, action, bulkOptions) =>
      bulkOfSet(
        ids,
        (unique) =>
          action === "remove"
            ? call("delete_tasks", { ids: [...unique] }, setResultOf)
            : call(
                "archive_tasks",
                { ids: [...unique], archived: action === "archive" },
                setResultOf,
              ),
        bulkOptions,
      ),
    tree: (rootId) =>
      call("task_tree", { root: rootId }, (value) =>
        recordsOf(value, "task_tree").map(nodeOf),
      ),
    get: (taskId) =>
      call("get_task", { task: taskId }, (value) =>
        value === null || value === undefined ? undefined : itemOf(value),
      ).andThen((item) =>
        item === undefined ? AsyncResult.ok(undefined) : fields.row(item),
      ),
    checklist: (taskId) =>
      call("list_task_checklist", { task: taskId }, (value) =>
        recordsOf(value, "list_task_checklist").map(checklistItemOf),
      ),
    saveChecklistItem: ({ taskId, input, checklistItemId }) =>
      call(
        "save_task_checklist_item",
        { task: taskId, checklist_item: checklistItemId ?? null, attrs: input },
        checklistItemOf,
      ),
    removeChecklistItem: (checklistItemId) =>
      call(
        "delete_task_checklist_item",
        { checklist_item: checklistItemId },
        (value) => value === true,
      ),
    setRecurrence: ({ taskId, rule }) =>
      call(
        "set_task_recurrence",
        { task: taskId, rrule: rule?.rrule ?? null, tzid: rule?.tzid ?? "UTC" },
        recurrenceOf,
      ),
    repeat: ({ taskId, dueAt }) =>
      call(
        "repeat_task",
        { task: taskId, due_at: dueAt.toString() },
        itemOf,
      ).andThen(fields.row),
    watch: ({ taskId, level }) =>
      call("watch_task", { task: taskId, level }, (value) => value === true),
    watchers: (taskId) =>
      call("list_task_watchers", { task: taskId }, (value) =>
        recordsOf(value, "list_task_watchers").map(watcherOf),
      ),
    list: ({ organizationId, ...list }) => {
      const { search, after, limit, ...filter } = list;

      return call(
        "list_tasks",
        {
          tenant: organizationId,
          filter,
          search: search ?? null,
          after: after ?? null,
          page_size: limit ?? null,
        },
        (value) => recordsOf(value, "list_tasks").map(itemOf),
      ).andThen(fields.rows);
    },
    saveProject: ({ organizationId, project }) => {
      const { id, budget, ...attrs } = project;

      const amounts =
        budget === undefined
          ? {}
          : {
              budgetAmount: budget === null ? null : amountText(budget),
              budgetCurrency: budget?.currency ?? null,
            };

      return call(
        "save_project",
        {
          tenant: organizationId,
          project: id ?? null,
          attrs: { ...args(attrs), ...amounts },
        },
        projectOf,
      );
    },
    saveIteration: ({ organizationId, iteration }) => {
      const { id, ...attrs } = iteration;

      return call(
        "save_iteration",
        { tenant: organizationId, iteration: id ?? null, attrs: args(attrs) },
        iterationOf,
      );
    },
    complete: (input) => settle(input, ["completed"], "completed"),
    cancel: (input) => settle(input, ["canceled"], "canceled"),
    reopen: (input) => settle(input, OPEN_STATES, "open"),
    assignToMe: ({ taskId, userId }) =>
      hooked.get(taskId).andThen((item) => {
        if (item === undefined) {
          return Promise.resolve(
            err(dbError("not_found", `Work item ${taskId} not found`)),
          );
        }

        if (item.assigneeIds.includes(userId)) {
          return Promise.resolve(ok(item.assigneeIds.length));
        }

        return hooked.assign({
          taskId,
          userIds: [...item.assigneeIds, userId],
        });
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Tasks<F> = withBlockHooks(client, options.hooks, {
    block: "tasks",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
