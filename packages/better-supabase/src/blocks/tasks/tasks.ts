import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
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

/** The state a stage's category sets; `completed` and `canceled` are closed. */
export type WorkItemState =
  | "triage"
  | "backlog"
  | "unstarted"
  | "started"
  | "completed"
  | "canceled";

const STATES: readonly WorkItemState[] = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
];

export type CloseReason = "completed" | "not_planned" | "duplicate";

/** A work item. `F` types the extra columns the `fields` schema describes. */
export interface WorkItem<F extends object = Record<never, never>> {
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
  readonly state: WorkItemState;
  readonly closeReason?: CloseReason;
  readonly closedAt?: Temporal.Instant;
  /** A locked item keeps its dates, as a locked Gantt bar. */
  readonly locked: boolean;
  readonly rank: string;
  readonly assigneeIds: readonly string[];
  /** How many checklist items it has, and how many are done. */
  readonly checklist: { readonly total: number; readonly done: number };
  /** Its repeat rule, with the reminders block. */
  readonly recurrence?: WorkItemRecurrence;
  /** The item this one repeats. */
  readonly recursFromId?: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
  readonly archived: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface WorkItemInput<F extends object = Record<never, never>> {
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

export type WorkItemField =
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
export interface WorkItemWindow {
  readonly startAt?: Temporal.Instant | null;
  readonly endAt?: Temporal.Instant | null;
}

export interface WorkItemUpdateOptions {
  /**
   * Keep every change or none: the first change that fails rolls the batch back
   * and comes back as the error, instead of a `rejected` entry.
   */
  readonly atomic?: boolean;
}

/** A work item's repeat rule: an RFC 5545 RRULE from `dtstart` in `tzid`. */
export interface WorkItemRecurrence {
  readonly rrule: string;
  readonly tzid: string;
  readonly dtstart: Temporal.Instant;
}

export interface ChecklistItem {
  readonly id: string;
  readonly workItemId: string;
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
export type WorkItemWatchLevel = "all" | "participating" | "ignore";

export interface WorkItemWatcher {
  readonly userId: string;
  readonly level: Exclude<WorkItemWatchLevel, "ignore">;
}

/**
 * One cell edit or drag: a built-in field or an extra column. `null` clears the
 * field.
 */
export interface WorkItemChange<F extends object = Record<never, never>> {
  readonly workItemId: string;
  readonly field: WorkItemField | (keyof F & string);
  readonly value: unknown;
}

export interface WorkItemChangeResult {
  readonly accepted: readonly {
    readonly workItemId: string;
    readonly field: string;
  }[];
  readonly rejected: readonly {
    readonly workItemId: string;
    readonly field: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

/** A node of `tree`, for a Gantt chart or a nested list. */
export interface WorkItemNode {
  readonly id: string;
  readonly parentId?: string;
  readonly identifier: string;
  readonly title: string;
  readonly state: WorkItemState;
  readonly startAt?: Temporal.Instant;
  readonly endAt?: Temporal.Instant;
  readonly dueAt?: Temporal.Instant;
  readonly locked: boolean;
  readonly depth: number;
  readonly progress: number;
}

export interface WorkItemListOptions {
  readonly teamId?: string;
  readonly projectId?: string;
  readonly iterationId?: string;
  readonly parentId?: string;
  readonly assigneeId?: string;
  readonly states?: readonly WorkItemState[];
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
}

export interface Iteration {
  readonly id: string;
  readonly teamId?: string;
  readonly name: string;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn: Temporal.PlainDate;
}

export interface Tasks<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: WorkItemInput<F>,
    assigneeIds?: readonly string[],
  ): AsyncResult<WorkItem<F>>;
  /** Extra column changes are validated with the `fields` schema first. */
  update(
    changes: readonly WorkItemChange<F>[],
    options?: WorkItemUpdateOptions,
  ): AsyncResult<WorkItemChangeResult>;
  /** Replaces the assignees; new ones are notified and every one watches. */
  assign(workItemId: string, userIds: readonly string[]): AsyncResult<number>;
  archive(workItemId: string, archived?: boolean): AsyncResult<boolean>;
  remove(workItemId: string): AsyncResult<boolean>;
  tree(rootId: string): AsyncResult<WorkItemNode[]>;
  /** One item you can read, or `undefined`. */
  get(workItemId: string): AsyncResult<WorkItem<F> | undefined>;
  checklist(workItemId: string): AsyncResult<ChecklistItem[]>;
  /** Adds a checklist item, or changes the one `checklistItemId` names. */
  saveChecklistItem(
    workItemId: string,
    input: ChecklistItemInput,
    checklistItemId?: string,
  ): AsyncResult<ChecklistItem>;
  removeChecklistItem(checklistItemId: string): AsyncResult<boolean>;
  /**
   * Makes the item repeat (`null` stops it). Needs the reminders block;
   * `workItemRecurrenceSink` creates the next item when one is completed.
   */
  setRecurrence(
    workItemId: string,
    rule: { readonly rrule: string; readonly tzid?: string } | null,
  ): AsyncResult<WorkItemRecurrence | undefined>;
  /** Creates the next item of a repeating one. Service only, idempotent. */
  repeat(workItemId: string, dueAt: Temporal.Instant): AsyncResult<WorkItem<F>>;
  /** Watches, follows or mutes an item (`null` clears). Needs notifications. */
  watch(
    workItemId: string,
    level: WorkItemWatchLevel | null,
  ): AsyncResult<boolean>;
  watchers(workItemId: string): AsyncResult<WorkItemWatcher[]>;
  list(
    organizationId: string,
    options?: WorkItemListOptions,
  ): AsyncResult<WorkItem<F>[]>;
  saveProject(
    organizationId: string,
    project: Partial<
      Omit<Project, "id" | "progress" | "startOn" | "targetOn">
    > & {
      readonly id?: string;
      readonly startOn?: Temporal.PlainDate | null;
      readonly targetOn?: Temporal.PlainDate | null;
      readonly archived?: boolean;
    },
  ): AsyncResult<Project>;
  saveIteration(
    organizationId: string,
    iteration: Partial<Omit<Iteration, "id">> & { readonly id?: string },
  ): AsyncResult<Iteration>;
}

export interface TasksOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the item's extra columns
   * (`blocks.tasks.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Tasks<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** The fields `update` writes without the `fields` schema. */
const BUILT_IN: ReadonlySet<string> = new Set<WorkItemField>([
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

function itemOf(value: unknown): WorkItem {
  const row = recordOf(value, "work item");
  const reason = optionalText(row["close_reason"]);

  return compact<WorkItem>({
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

function checklistSummaryOf(value: unknown): WorkItem["checklist"] {
  const row = isRecord(value) ? value : {};

  return { total: num(row["total"]) ?? 0, done: num(row["done"]) ?? 0 };
}

function recurrenceOf(value: unknown): WorkItemRecurrence | undefined {
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
    workItemId: textOf(row["workItemId"]),
    title: textOf(row["title"]),
    done: row["done"] === true,
    doneAt: optionalInstant(row["doneAt"]),
    doneBy: optionalText(row["doneBy"]),
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  });
}

function watcherOf(value: unknown): WorkItemWatcher {
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

function nodeOf(value: unknown): WorkItemNode {
  const row = recordOf(value, "work item node");

  return compact<WorkItemNode>({
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
    ownerId: optionalText(row["owner_user_id"]),
    status: enumOrThrow(
      row["status"],
      ["planned", "active", "paused", "completed", "canceled"] as const,
      "project status",
    ),
    startOn: date(row["start_on"]),
    targetOn: date(row["target_on"]),
    progress: num(row["progress"]),
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

  const client: Tasks<F> = {
    create: (organizationId, input, assigneeIds) => {
      const { fields: extra, attachmentIds, ...attrs } = input;

      return fields
        .args(extra)
        .andThen((checked) =>
          call(
            "create_work_item",
            {
              tenant: organizationId,
              attrs: {
                ...args(attrs),
                ...(attachmentIds === undefined
                  ? {}
                  : { attachments: [...attachmentIds] }),
                ...(checked === undefined ? {} : { fields: checked }),
              },
              assignees: assigneeIds === undefined ? null : [...assigneeIds],
            },
            itemOf,
          ).andThen(fields.row),
        );
    },
    update: (changes, updateOptions = {}) =>
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
          "update_work_items",
          {
            changes: checked.map((change) => ({
              workItemId: change.workItemId,
              field: change.field,
              value:
                change.field === "window" && isRecord(change.value)
                  ? args(change.value)
                  : valueArg(change.value),
            })),
            ...(updateOptions.atomic === true ? { atomic: true } : {}),
          },
          (value) => {
            const row = recordOf(value, "update_work_items");

            return {
              accepted: recordsOf(row["accepted"], "accepted").map((item) => ({
                workItemId: textOf(item["workItemId"]),
                field: textOf(item["field"]),
              })),
              rejected: recordsOf(row["rejected"], "rejected").map((item) =>
                compact<WorkItemChangeResult["rejected"][number]>({
                  workItemId: textOf(item["workItemId"]),
                  field: textOf(item["field"]),
                  hint: optionalText(item["hint"]),
                  reason: textOf(item["reason"]),
                }),
              ),
            };
          },
        ),
      ),
    assign: (workItemId, userIds) =>
      call(
        "set_work_item_assignees",
        { work_item: workItemId, users: [...userIds] },
        (value) => num(value) ?? 0,
      ),
    archive: (workItemId, archived = true) =>
      call(
        "archive_work_item",
        { work_item: workItemId, archived },
        (value) => value === true,
      ),
    remove: (workItemId) =>
      call(
        "delete_work_item",
        { work_item: workItemId },
        (value) => value === true,
      ),
    tree: (rootId) =>
      call("work_item_tree", { root: rootId }, (value) =>
        recordsOf(value, "work_item_tree").map(nodeOf),
      ),
    get: (workItemId) =>
      call("get_work_item", { work_item: workItemId }, (value) =>
        value === null || value === undefined ? undefined : itemOf(value),
      ).andThen((item) =>
        item === undefined ? AsyncResult.ok(undefined) : fields.row(item),
      ),
    checklist: (workItemId) =>
      call("list_work_item_checklist", { work_item: workItemId }, (value) =>
        recordsOf(value, "list_work_item_checklist").map(checklistItemOf),
      ),
    saveChecklistItem: (workItemId, input, checklistItemId) =>
      call(
        "save_work_item_checklist_item",
        {
          work_item: workItemId,
          checklist_item: checklistItemId ?? null,
          attrs: input,
        },
        checklistItemOf,
      ),
    removeChecklistItem: (checklistItemId) =>
      call(
        "delete_work_item_checklist_item",
        { checklist_item: checklistItemId },
        (value) => value === true,
      ),
    setRecurrence: (workItemId, rule) =>
      call(
        "set_work_item_recurrence",
        {
          work_item: workItemId,
          rrule: rule?.rrule ?? null,
          tzid: rule?.tzid ?? "UTC",
        },
        recurrenceOf,
      ),
    repeat: (workItemId, dueAt) =>
      call(
        "repeat_work_item",
        { work_item: workItemId, due_at: dueAt.toString() },
        itemOf,
      ).andThen(fields.row),
    watch: (workItemId, level) =>
      call(
        "watch_work_item",
        { work_item: workItemId, level },
        (value) => value === true,
      ),
    watchers: (workItemId) =>
      call("list_work_item_watchers", { work_item: workItemId }, (value) =>
        recordsOf(value, "list_work_item_watchers").map(watcherOf),
      ),
    list: (organizationId, list = {}) => {
      const { search, after, limit, ...filter } = list;

      return call(
        "list_work_items",
        {
          tenant: organizationId,
          filter,
          search: search ?? null,
          after: after ?? null,
          page_size: limit ?? null,
        },
        (value) => recordsOf(value, "list_work_items").map(itemOf),
      ).andThen(fields.rows);
    },
    saveProject: (organizationId, project) => {
      const { id, ...attrs } = project;

      return call(
        "save_project",
        { tenant: organizationId, project: id ?? null, attrs: args(attrs) },
        projectOf,
      );
    },
    saveIteration: (organizationId, iteration) => {
      const { id, ...attrs } = iteration;

      return call(
        "save_iteration",
        { tenant: organizationId, iteration: id ?? null, attrs: args(attrs) },
        iterationOf,
      );
    },
  };

  return withBlockHooks(client, options.hooks, {
    block: "tasks",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
