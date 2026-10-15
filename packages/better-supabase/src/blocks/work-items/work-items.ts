import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
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

export interface WorkItem {
  readonly id: string;
  readonly organizationId: string;
  readonly number: bigint;
  /** `TASK-12`, or the number-sequences format. */
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
  readonly fields: Readonly<Record<string, unknown>>;
  readonly archived: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface WorkItemInput {
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
  | "closeReason";

/** One cell edit or drag. `null` clears the field. */
export interface WorkItemChange {
  readonly workItemId: string;
  readonly field: WorkItemField;
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

export interface WorkItems {
  create(
    organizationId: string,
    input: WorkItemInput,
    assigneeIds?: readonly string[],
  ): AsyncResult<WorkItem>;
  update(changes: readonly WorkItemChange[]): AsyncResult<WorkItemChangeResult>;
  /** Replaces the assignees; new ones are notified and every one watches. */
  assign(workItemId: string, userIds: readonly string[]): AsyncResult<number>;
  archive(workItemId: string, archived?: boolean): AsyncResult<boolean>;
  remove(workItemId: string): AsyncResult<boolean>;
  tree(rootId: string): AsyncResult<WorkItemNode[]>;
  list(
    organizationId: string,
    options?: WorkItemListOptions,
  ): AsyncResult<WorkItem[]>;
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

export interface WorkItemsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<WorkItems>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

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
  if (typeof value === "number") return value;
  if (typeof value === "string" && value !== "") return Number(value);
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
    fields: Object.fromEntries(
      Object.entries(row).filter(([key]) => !KNOWN.has(key)),
    ),
    archived: row["archived_at"] !== null && row["archived_at"] !== undefined,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  });
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
 * The work-items block: issues and tasks on pipelines, with batched edits
 * for a grid or a Gantt chart, assignees, a progress tree, projects and
 * iterations.
 */
export function createWorkItems(options: WorkItemsOptions): WorkItems {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: WorkItems = {
    create: (organizationId, input, assigneeIds) =>
      call(
        "create_work_item",
        {
          tenant: organizationId,
          attrs: args(input),
          assignees: assigneeIds === undefined ? null : [...assigneeIds],
        },
        itemOf,
      ),
    update: (changes) =>
      call(
        "update_work_items",
        {
          changes: changes.map((change) => ({
            workItemId: change.workItemId,
            field: change.field,
            value: valueArg(change.value),
          })),
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
    list: (organizationId, list = {}) => {
      const { search, after, limit, ...filter } = list;
      return call(
        "list_work_items",
        {
          tenant: organizationId,
          filter: filter,
          search: search ?? null,
          after: after ?? null,
          page_size: limit ?? null,
        },
        (value) => recordsOf(value, "list_work_items").map(itemOf),
      );
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
    block: "work-items",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/**
 * The `config.subjects` entry for work items, so comments, tags, files,
 * relations (`blocks` for Gantt dependencies), rank and search attach.
 * The board moves an item by its stage id.
 */
export function workItemsSubjects(
  options: { readonly schema?: string; readonly url?: string } = {},
): { readonly work_item: SubjectConfig } {
  return {
    work_item: {
      table: `${options.schema ?? "better_supabase"}.work_items`,
      idType: "uuid",
      tenant: "tenant_id",
      title: "title",
      deletedAt: "archived_at",
      permissions: { read: "work_items.read", write: "work_items.write" },
      rank: { column: "rank", group: "stage_id" },
      search: { title: "title", body: ["identifier", "body"] },
      ...(options.url === undefined ? {} : { url: options.url }),
    },
  };
}
