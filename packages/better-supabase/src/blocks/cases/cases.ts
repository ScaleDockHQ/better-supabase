import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** A case kind. */
export interface CaseKind {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly prefix: string;
  readonly requiresRootCause: boolean;
  readonly requiresActions: boolean;
  readonly requiresEffectiveness: boolean;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The input of `saveKind`. */
export interface CaseKindInput {
  readonly key: string;
  readonly name: string;
  readonly prefix: string;
  readonly requiresRootCause?: boolean;
  readonly requiresActions?: boolean;
  readonly requiresEffectiveness?: boolean;
}

/** A case action. */
export interface CaseAction {
  readonly id: string;
  readonly organizationId: string;
  readonly caseId: string;
  readonly type: string;
  readonly title: string;
  readonly assigneeId?: string;
  readonly dueAt?: Temporal.Instant;
  readonly required: boolean;
  readonly completedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

/** The input of `createAction`. */
export interface CaseActionInput {
  readonly type: string;
  readonly title: string;
  readonly assigneeId?: string;
  readonly dueAt?: Temporal.Instant;
  readonly required?: boolean;
}

/** A case. */
export interface Case {
  readonly id: string;
  readonly organizationId: string;
  readonly kindId: string;
  readonly number: string;
  readonly title: string;
  readonly description?: string;
  readonly severity?: string;
  readonly source?: string;
  readonly reporterId?: string;
  readonly ownerId?: string;
  readonly occurredAt?: Temporal.Instant;
  readonly detectedAt: Temporal.Instant;
  readonly dueOn?: Temporal.PlainDate;
  readonly status: "open" | "closed" | "cancelled";
  readonly rootCause?: string;
  readonly effective?: boolean;
  readonly effectivenessDueOn?: Temporal.PlainDate;
  readonly closedAt?: Temporal.Instant;
  readonly closedBy?: string;
  readonly closeNote?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly actions?: readonly CaseAction[];
  readonly blockers?: readonly string[];
}

/** The input of `open`. */
export interface CaseInput {
  readonly title: string;
  readonly description?: string;
  readonly severity?: string;
  readonly source?: string;
  readonly occurredAt?: Temporal.Instant;
  readonly ownerId?: string;
  readonly dueOn?: Temporal.PlainDate;
}

/** The changes `update` accepts. */
export interface CaseChange {
  readonly title?: string;
  readonly description?: string;
  readonly severity?: string;
  readonly ownerId?: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly occurredAt?: Temporal.Instant;
}

/** The filters `list` accepts. */
export interface CaseListOptions {
  readonly status?: "open" | "closed" | "cancelled";
  readonly severity?: string;
  readonly ownerId?: string;
  readonly search?: string;
  readonly limit?: number;
}

/** One Pareto row. */
export interface CaseStat {
  readonly key: string;
  readonly count: number;
}

/** The cases client. */
export interface Cases {
  saveKind(organizationId: string, input: CaseKindInput): AsyncResult<CaseKind>;
  archiveKind(kindId: string): AsyncResult<CaseKind>;
  kinds(
    organizationId: string,
    options?: { readonly includeArchived?: boolean },
  ): AsyncResult<readonly CaseKind[]>;
  open(
    organizationId: string,
    kind: string,
    input: CaseInput,
  ): AsyncResult<Case>;
  update(caseId: string, changes: CaseChange): AsyncResult<Case>;
  get(caseId: string): AsyncResult<Case>;
  list(
    organizationId: string,
    options?: CaseListOptions,
  ): AsyncResult<readonly Case[]>;
  recordRootCause(caseId: string, rootCause: string): AsyncResult<Case>;
  createAction(caseId: string, input: CaseActionInput): AsyncResult<CaseAction>;
  completeAction(actionId: string): AsyncResult<CaseAction>;
  removeAction(actionId: string): AsyncResult<CaseAction>;
  recordEffectiveness(
    caseId: string,
    effective: boolean,
    note?: string,
  ): AsyncResult<Case>;
  closeBlockers(caseId: string): AsyncResult<readonly string[]>;
  close(caseId: string, note?: string): AsyncResult<Case>;
  reopen(caseId: string, reason: string): AsyncResult<Case>;
  cancel(caseId: string, reason: string): AsyncResult<Case>;
  stats(
    organizationId: string,
    options?: { readonly since?: Temporal.PlainDate; readonly until?: Temporal.PlainDate },
  ): AsyncResult<readonly CaseStat[]>;
  notifyDueEffectiveness(): AsyncResult<number>;
}

/** `createCases` options. */
export interface CasesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Cases>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const kindOf = (value: unknown, fn: string): CaseKind => {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    prefix: textOf(row["prefix"]),
    requiresRootCause: row["requiresRootCause"] === true,
    requiresActions: row["requiresActions"] === true,
    requiresEffectiveness: row["requiresEffectiveness"] === true,
    ...(row["archivedAt"] === null || row["archivedAt"] === undefined
      ? {}
      : { archivedAt: requiredInstant(row["archivedAt"], fn) }),
    createdAt: requiredInstant(row["createdAt"], fn),
    updatedAt: requiredInstant(row["updatedAt"], fn),
  };
};

const actionOf = (value: unknown, fn: string): CaseAction => {
  const row = recordOf(value, fn);
  const dueAt = optionalInstant(row["dueAt"]);
  const completedAt = optionalInstant(row["completedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    caseId: textOf(row["caseId"]),
    type: textOf(row["type"]),
    title: textOf(row["title"]),
    ...(row["assigneeId"] === null || row["assigneeId"] === undefined
      ? {}
      : { assigneeId: textOf(row["assigneeId"]) }),
    ...(dueAt === undefined ? {} : { dueAt }),
    required: row["required"] === true,
    ...(completedAt === undefined ? {} : { completedAt }),
    createdAt: requiredInstant(row["createdAt"], fn),
  };
};

const caseOf = (value: unknown, fn: string): Case => {
  const row = recordOf(value, fn);
  const occurredAt = optionalInstant(row["occurredAt"]);
  const closedAt = optionalInstant(row["closedAt"]);
  const archivedAt = optionalInstant(row["archivedAt"]);
  const description = optionalText(row["description"]);
  const severity = optionalText(row["severity"]);
  const source = optionalText(row["source"]);
  const reporterId = optionalText(row["reporterId"]);
  const ownerId = optionalText(row["ownerId"]);
  const rootCause = optionalText(row["rootCause"]);
  const closedBy = optionalText(row["closedBy"]);
  const closeNote = optionalText(row["closeNote"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kindId: textOf(row["kindId"]),
    number: textOf(row["number"]),
    title: textOf(row["title"]),
    ...(description === undefined ? {} : { description }),
    ...(severity === undefined ? {} : { severity }),
    ...(source === undefined ? {} : { source }),
    ...(reporterId === undefined ? {} : { reporterId }),
    ...(ownerId === undefined ? {} : { ownerId }),
    ...(occurredAt === undefined ? {} : { occurredAt }),
    detectedAt: requiredInstant(row["detectedAt"], fn),
    ...(row["dueOn"] === null || row["dueOn"] === undefined
      ? {}
      : { dueOn: temporal().PlainDate.from(textOf(row["dueOn"])) }),
    status: enumOrThrow(row["status"], ["open", "closed", "cancelled"], fn),
    ...(rootCause === undefined ? {} : { rootCause }),
    ...(row["effective"] === null || row["effective"] === undefined
      ? {}
      : { effective: row["effective"] === true }),
    ...(row["effectivenessDueOn"] === null || row["effectivenessDueOn"] === undefined
      ? {}
      : {
          effectivenessDueOn: temporal().PlainDate.from(
            textOf(row["effectivenessDueOn"]),
          ),
        }),
    ...(closedAt === undefined ? {} : { closedAt }),
    ...(closedBy === undefined ? {} : { closedBy }),
    ...(closeNote === undefined ? {} : { closeNote }),
    ...(archivedAt === undefined ? {} : { archivedAt }),
    createdAt: requiredInstant(row["createdAt"], fn),
    updatedAt: requiredInstant(row["updatedAt"], fn),
    ...(row["actions"] === undefined
      ? {}
      : {
          actions: recordsOf(row["actions"], `${fn}.actions`).map((item) =>
            actionOf(item, `${fn}.actions`),
          ),
        }),
    ...(row["blockers"] === undefined
      ? {}
      : { blockers: stringsOf(row["blockers"]) }),
  };
};

/** The `cases` SQL module as typed calls. */
export function createCases<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CasesOptions<S>): Cases {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  blockFields(options.fields, "case fields");

  const client: Cases = {
    saveKind: (organizationId, input) =>
      call(
        "save_case_kind",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          prefix: input.prefix,
          requires_root_cause: input.requiresRootCause ?? true,
          requires_actions: input.requiresActions ?? true,
          requires_effectiveness: input.requiresEffectiveness ?? false,
          kind_id: null,
        },
        (value) => kindOf(value, "save_case_kind"),
      ),
    archiveKind: (kindId) =>
      call("archive_case_kind", { kind_id: kindId }, (value) =>
        kindOf(value, "archive_case_kind"),
      ),
    kinds: (organizationId, input) =>
      call(
        "list_case_kinds",
        {
          tenant: organizationId,
          include_archived: input?.includeArchived ?? false,
        },
        (value) =>
          recordsOf(value, "list_case_kinds").map((row) =>
            kindOf(row, "list_case_kinds"),
          ),
      ),
    open: (organizationId, kind, input) =>
      call(
        "open_case",
        {
          tenant: organizationId,
          kind,
          title: input.title,
          description: input.description ?? null,
          severity: input.severity ?? null,
          source: input.source ?? "internal",
          occurred_at: input.occurredAt?.toString() ?? null,
          owner_id: input.ownerId ?? null,
          due_on: input.dueOn?.toString() ?? null,
        },
        (value) => caseOf(value, "open_case"),
      ),
    update: (caseId, changes) =>
      call(
        "update_case",
        { case_id: caseId, changes },
        (value) => caseOf(value, "update_case"),
      ),
    get: (caseId) =>
      call("get_case", { case_id: caseId }, (value) =>
        caseOf(value, "get_case"),
      ),
    list: (organizationId, input) =>
      call(
        "list_cases",
        {
          tenant: organizationId,
          filters: {
            ...(input?.status === undefined ? {} : { status: input.status }),
            ...(input?.severity === undefined ? {} : { severity: input.severity }),
            ...(input?.ownerId === undefined ? {} : { owner: input.ownerId }),
            ...(input?.search === undefined ? {} : { search: input.search }),
            ...(input?.limit === undefined ? {} : { limit: input.limit }),
          },
        },
        (value) =>
          recordsOf(value, "list_cases").map((row) => caseOf(row, "list_cases")),
      ),
    recordRootCause: (caseId, rootCause) =>
      call(
        "record_case_root_cause",
        { case_id: caseId, root_cause: rootCause },
        (value) => caseOf(value, "record_case_root_cause"),
      ),
    createAction: (caseId, input) =>
      call(
        "create_case_action",
        {
          case_id: caseId,
          type: input.type,
          title: input.title,
          assignee_id: input.assigneeId ?? null,
          due_at: input.dueAt?.toString() ?? null,
          required: input.required ?? true,
        },
        (value) => actionOf(value, "create_case_action"),
      ),
    completeAction: (actionId) =>
      call("complete_case_action", { action_id: actionId }, (value) =>
        actionOf(value, "complete_case_action"),
      ),
    removeAction: (actionId) =>
      call("remove_case_action", { action_id: actionId }, (value) =>
        actionOf(value, "remove_case_action"),
      ),
    recordEffectiveness: (caseId, effective, note) =>
      call(
        "record_case_effectiveness",
        { case_id: caseId, effective, note: note ?? null },
        (value) => caseOf(value, "record_case_effectiveness"),
      ),
    closeBlockers: (caseId) =>
      call("case_close_blockers", { case_id: caseId }, stringsOf),
    close: (caseId, note) =>
      call("close_case", { case_id: caseId, note: note ?? null }, (value) =>
        caseOf(value, "close_case"),
      ),
    reopen: (caseId, reason) =>
      call("reopen_case", { case_id: caseId, reason }, (value) =>
        caseOf(value, "reopen_case"),
      ),
    cancel: (caseId, reason) =>
      call("cancel_case", { case_id: caseId, reason }, (value) =>
        caseOf(value, "cancel_case"),
      ),
    stats: (organizationId, input) =>
      call(
        "case_stats",
        {
          tenant: organizationId,
          since: input?.since?.toString() ?? null,
          until: input?.until?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "case_stats").map((row) => ({
            key: textOf(row["key"]),
            count: Number(row["count"]),
          })),
      ),
    notifyDueEffectiveness: () =>
      call("notify_due_case_effectiveness", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "cases",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
