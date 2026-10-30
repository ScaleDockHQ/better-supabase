import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { CASE_STATS_GROUPS } from "../../sql/modules/cases-values.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  CASE_ACTION_TYPES,
  CASE_BLOCKERS,
  CASE_STATUSES,
} from "../../sql/modules/cases-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a case stands; its stage's outcome sets it. */
export type CaseStatus = (typeof CASE_STATUSES)[number];

/** What a case action does. */
export type CaseActionType = (typeof CASE_ACTION_TYPES)[number];

/** A hint code `blockers` returns: what still stops a case from closing. */
export type CaseBlocker = (typeof CASE_BLOCKERS)[number];

/** What `stats` groups by. */
export type CaseStatsGroup = (typeof CASE_STATS_GROUPS)[number];

/** A kind of case, such as a complaint, with what closing it requires. */
export interface CaseKind {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  /** The capital letters its case numbers start with, such as `CMP`. */
  readonly prefix: string;
  readonly pipelineId?: string;
  readonly investigationFormId?: string;
  readonly effectivenessFormId?: string;
  /** Days after the required actions are done that effectiveness is due. */
  readonly effectivenessAfterDays?: number;
  readonly requiresRootCause: boolean;
  readonly requiresActions: boolean;
  readonly requiresEffectiveness: boolean;
  /** The documents the case `affects` need a new effective version. */
  readonly requiresRevisions: boolean;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CaseKindInput {
  /** Lowercase letters, digits and underscores, unique per organization. */
  readonly key: string;
  readonly name: string;
  /** 1 to 6 capital letters. */
  readonly prefix: string;
  readonly investigationFormId?: string | null;
  readonly effectivenessFormId?: string | null;
  /** 1 to 365. */
  readonly effectivenessAfterDays?: number | null;
  /** Default true. */
  readonly requiresRootCause?: boolean;
  /** Default true. */
  readonly requiresActions?: boolean;
  /** Default false. */
  readonly requiresEffectiveness?: boolean;
  /** Default false. */
  readonly requiresRevisions?: boolean;
  /** Changes this kind instead of creating one. */
  readonly kindId?: string;
}

/** A case. `F` types the extra columns the `fields` schema describes. */
export interface Case<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly kindId: string;
  /** The kind's prefix and its number, such as `NC-2026-0001`. */
  readonly number: string;
  readonly title: string;
  readonly description?: string;
  readonly severity?: string;
  readonly source: string;
  readonly reporterId?: string;
  /** How to reach whoever reported it through a public form. */
  readonly reporterContact?: Readonly<Record<string, unknown>>;
  readonly ownerId?: string;
  readonly occurredAt?: Temporal.Instant;
  readonly detectedAt?: Temporal.Instant;
  readonly dueOn?: Temporal.PlainDate;
  readonly pipelineId?: string;
  readonly stageId?: string;
  readonly stageEnteredAt?: Temporal.Instant;
  readonly status: CaseStatus;
  readonly rootCause?: string;
  readonly rootCauseSubmissionId?: string;
  /** Whether the actions worked; absent until recorded. */
  readonly effective?: boolean;
  readonly effectivenessDueOn?: Temporal.PlainDate;
  readonly effectivenessNote?: string;
  readonly effectivenessSubmissionId?: string;
  readonly closedAt?: Temporal.Instant;
  readonly closedBy?: string;
  readonly closeNote?: string;
  /** Its place in its stage's column. */
  readonly rank?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

/** An action of a case: a work item of the tasks block. */
export interface CaseAction {
  readonly id: string;
  readonly taskId: string;
  readonly type: CaseActionType;
  readonly required: boolean;
  readonly title?: string;
  readonly state?: string;
  readonly dueAt?: Temporal.Instant;
  /** The work item is completed or canceled. */
  readonly done: boolean;
  readonly assignees: readonly string[];
  readonly createdAt: Temporal.Instant;
}

/** A case with its kind, stage, actions, blockers and relation counts. */
export interface CaseDetail<
  F extends object = Record<never, never>,
> extends Case<F> {
  readonly kind: CaseKind;
  readonly stage?: {
    readonly id: string;
    readonly key: string;
    readonly name: string;
    readonly outcome: string;
  };
  readonly actions: readonly CaseAction[];
  readonly blockers: readonly CaseBlocker[];
  /** How many links of each relation kind the case has, such as `affects`. */
  readonly relations: Readonly<Record<string, number>>;
}

export interface CaseInput<F extends object = Record<never, never>> {
  /** The key of a kind, such as `complaint`. */
  readonly kind: string;
  readonly title: string;
  readonly description?: string | null;
  /** One of `options.severities`. */
  readonly severity?: string | null;
  /** One of `options.sources`. Default `internal`. */
  readonly source?: string;
  readonly occurredAt?: Temporal.Instant | null;
  readonly ownerId?: string | null;
  readonly dueOn?: Temporal.PlainDate | null;
  /** The extra columns, keyed by database name. */
  readonly fields?: Partial<F>;
}

/** What `update` changes; keys left out keep their value. */
export interface CaseChange<F extends object = Record<never, never>> {
  readonly title?: string;
  readonly description?: string | null;
  readonly severity?: string | null;
  readonly source?: string;
  readonly ownerId?: string | null;
  readonly occurredAt?: Temporal.Instant | null;
  readonly dueOn?: Temporal.PlainDate | null;
  readonly reporterContact?: Readonly<Record<string, unknown>> | null;
  readonly fields?: Partial<F>;
}

/**
 * Where `move` puts a case: a stage of its pipeline and its place there. A
 * closing stage runs the close guard.
 */
export interface CaseMove {
  readonly stageId: string;
  readonly rank?: string;
}

export interface CaseActionInput {
  readonly type: CaseActionType;
  readonly title: string;
  readonly assigneeId?: string | null;
  readonly dueAt?: Temporal.Instant | null;
  /** Closing waits for required actions. Default true. */
  readonly required?: boolean;
}

/** The action `createAction` or `linkAction` added. */
export interface CaseActionAdded {
  readonly actionId: string;
  readonly taskId: string;
}

export interface CaseListOptions {
  /** A kind's key. */
  readonly kind?: string;
  readonly status?: CaseStatus;
  readonly severity?: string;
  readonly source?: string;
  readonly owner?: string;
  readonly stage?: string;
  /** Only open cases past their due date. */
  readonly overdue?: boolean;
  /** Matches the title, number, description or root cause. */
  readonly search?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  /** The `nextCursor` of the previous page. */
  readonly cursor?: string;
}

export interface CasePage<F extends object = Record<never, never>> {
  /** Newest first. */
  readonly items: readonly Case<F>[];
  /** Undefined on the last page. */
  readonly nextCursor?: string;
}

export interface CaseStatsOptions {
  /** Default `severity`. */
  readonly groupBy?: CaseStatsGroup;
  /** A kind's key. */
  readonly kind?: string;
  readonly since?: Temporal.PlainDate;
  /** Inclusive. */
  readonly until?: Temporal.PlainDate;
}

/** One group of `stats`; `key` is null for cases without a value. */
export interface CaseStat {
  readonly key: string | null;
  readonly count: number;
}

export interface Cases<F extends object = Record<never, never>> {
  /** Creates or changes a kind; needs `cases.manage`. */
  saveKind(input: CaseKindInput): AsyncResult<CaseKind>;
  /** Archives a kind; its cases stay. Needs `cases.manage`. */
  archiveKind(kindId: string): AsyncResult<CaseKind>;
  /** The organization's kinds by name. */
  kinds(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly CaseKind[]>;
  /** Opens a case on its kind's first stage; needs `cases.create`. */
  open(input: CaseInput<F>): AsyncResult<Case<F>>;
  /** Changes a case; needs `cases.write` or being its owner. */
  update(caseId: string, change: CaseChange<F>): AsyncResult<Case<F>>;
  /** Moves a case on its board; a closing stage needs `cases.close`. */
  move(caseId: string, to: CaseMove): AsyncResult<Case<F>>;
  recordRootCause(
    caseId: string,
    rootCause: string,
    options?: { readonly submissionId?: string },
  ): AsyncResult<Case<F>>;
  /** Adds a new work item as an action; needs the tasks block. */
  createAction(
    caseId: string,
    input: CaseActionInput,
  ): AsyncResult<CaseActionAdded>;
  /** Makes an existing work item an action. */
  linkAction(
    caseId: string,
    taskId: string,
    type: CaseActionType,
    options?: { readonly required?: boolean },
  ): AsyncResult<CaseActionAdded>;
  /** Removes an action; the work item stays. */
  removeAction(actionId: string): AsyncResult<Case<F>>;
  recordEffectiveness(
    caseId: string,
    effective: boolean,
    options?: { readonly submissionId?: string; readonly note?: string },
  ): AsyncResult<Case<F>>;
  /** What still stops the case from closing; empty when it may close. */
  blockers(caseId: string): AsyncResult<readonly CaseBlocker[]>;
  /**
   * Closes a case; fails with the first blocker's code while one remains. Needs
   * `cases.close` or being its owner.
   */
  close(caseId: string, note?: string): AsyncResult<Case<F>>;
  /** Reopens a closed or canceled case; needs `cases.close`. */
  reopen(caseId: string, reason?: string): AsyncResult<Case<F>>;
  /** Cancels an open case; needs `cases.close`. */
  cancel(caseId: string, reason?: string): AsyncResult<Case<F>>;
  get(caseId: string): AsyncResult<CaseDetail<F>>;
  list(options?: CaseListOptions): AsyncResult<CasePage<F>>;
  /** Counts per group, most first. */
  stats(options?: CaseStatsOptions): AsyncResult<readonly CaseStat[]>;
  /** Reports the cases whose effectiveness check is due; service role only. */
  notifyDueEffectiveness(): AsyncResult<number>;
}

export interface CasesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the case's extra columns
   * (`blocks.cases.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Cases<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const optionalBoolean = (value: unknown): boolean | undefined =>
  typeof value === "boolean" ? value : undefined;

const dateArg = (
  value: Temporal.PlainDate | null | undefined,
): string | null | undefined =>
  value === undefined ? undefined : value === null ? null : value.toString();

function kindOf(value: unknown, fn: string): CaseKind {
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
    requiresRevisions: row["requiresRevisions"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("pipelineId", optionalText(row["pipelineId"])),
    ...optional(
      "investigationFormId",
      optionalText(row["investigationFormId"]),
    ),
    ...optional(
      "effectivenessFormId",
      optionalText(row["effectivenessFormId"]),
    ),
    ...optional(
      "effectivenessAfterDays",
      optionalNumber(row["effectivenessAfterDays"]),
    ),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function caseOf(value: unknown, fn: string): Case {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kindId: textOf(row["kindId"]),
    number: textOf(row["number"]),
    title: textOf(row["title"]),
    source: textOf(row["source"]),
    status: enumOrThrow(row["status"], CASE_STATUSES, "case status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("description", optionalText(row["description"])),
    ...optional("severity", optionalText(row["severity"])),
    ...optional("reporterId", optionalText(row["reporterId"])),
    ...optional(
      "reporterContact",
      isRecord(row["reporterContact"]) ? row["reporterContact"] : undefined,
    ),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("occurredAt", optionalInstant(row["occurredAt"])),
    ...optional("detectedAt", optionalInstant(row["detectedAt"])),
    ...optional("dueOn", optionalDate(row["dueOn"])),
    ...optional("pipelineId", optionalText(row["pipelineId"])),
    ...optional("stageId", optionalText(row["stageId"])),
    ...optional("stageEnteredAt", optionalInstant(row["stageEnteredAt"])),
    ...optional("rootCause", optionalText(row["rootCause"])),
    ...optional(
      "rootCauseSubmissionId",
      optionalText(row["rootCauseSubmissionId"]),
    ),
    ...optional("effective", optionalBoolean(row["effective"])),
    ...optional("effectivenessDueOn", optionalDate(row["effectivenessDueOn"])),
    ...optional("effectivenessNote", optionalText(row["effectivenessNote"])),
    ...optional(
      "effectivenessSubmissionId",
      optionalText(row["effectivenessSubmissionId"]),
    ),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("closedBy", optionalText(row["closedBy"])),
    ...optional("closeNote", optionalText(row["closeNote"])),
    ...optional("rank", optionalText(row["rank"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

const blockersOf = (value: unknown): readonly CaseBlocker[] =>
  Array.isArray(value)
    ? value.map((code) => enumOrThrow(code, CASE_BLOCKERS, "case blocker"))
    : [];

function actionOf(row: Readonly<Record<string, unknown>>): CaseAction {
  return {
    id: textOf(row["id"]),
    taskId: textOf(row["taskId"]),
    type: enumOrThrow(row["type"], CASE_ACTION_TYPES, "case action type"),
    required: row["required"] === true,
    done: row["done"] === true,
    assignees: Array.isArray(row["assignees"])
      ? row["assignees"].map((id) => textOf(id))
      : [],
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("title", optionalText(row["title"])),
    ...optional("state", optionalText(row["state"])),
    ...optional("dueAt", optionalInstant(row["dueAt"])),
  };
}

function detailOf(value: unknown, fn: string): CaseDetail {
  const row = recordOf(value, fn);
  const stage = isRecord(row["stage"]) ? row["stage"] : undefined;
  const relations = isRecord(row["relations"]) ? row["relations"] : {};

  return {
    ...caseOf(row, fn),
    kind: kindOf(row["kind"], fn),
    actions: Array.isArray(row["actions"])
      ? row["actions"].filter(isRecord).map(actionOf)
      : [],
    blockers: blockersOf(row["blockers"]),
    relations: Object.fromEntries(
      Object.entries(relations).map(([kind, count]) => [kind, numberOf(count)]),
    ),
    ...optional(
      "stage",
      stage === undefined
        ? undefined
        : {
            id: textOf(stage["id"]),
            key: textOf(stage["key"]),
            name: textOf(stage["name"]),
            outcome: textOf(stage["outcome"]),
          },
    ),
  };
}

function addedOf(value: unknown, fn: string): CaseActionAdded {
  const row = recordOf(value, fn);

  return { actionId: textOf(row["actionId"]), taskId: textOf(row["taskId"]) };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

/**
 * Cases: nonconformities, complaints, incidents, near misses and other kinds,
 * each on its kind's pipeline, investigated to a root cause, worked through
 * actions, checked for effectiveness and closed once nothing blocks them.
 */
export function createCases<S extends StandardSchemaV1 | undefined = undefined>(
  options: CasesOptions<S>,
): Cases<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const fields: BlockFields<F> = blockFields(options.fields, "case fields");
  const one = (fn: string) => (value: unknown) => caseOf(value, fn);

  const client: Cases<F> = {
    saveKind: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_case_kind",
          {
            tenant: organizationId,
            key: input.key,
            name: input.name,
            prefix: input.prefix,
            investigation_form_id: input.investigationFormId ?? null,
            effectiveness_form_id: input.effectivenessFormId ?? null,
            effectiveness_after_days: input.effectivenessAfterDays ?? null,
            requires_root_cause: input.requiresRootCause ?? true,
            requires_actions: input.requiresActions ?? true,
            requires_effectiveness: input.requiresEffectiveness ?? false,
            requires_revisions: input.requiresRevisions ?? false,
            kind_id: input.kindId ?? null,
          },
          (value) => kindOf(value, "save_case_kind"),
        ),
      ),
    archiveKind: (kindId) =>
      call("archive_case_kind", { kind_id: kindId }, (value) =>
        kindOf(value, "archive_case_kind"),
      ),
    kinds: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_case_kinds",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_case_kinds").map((row) =>
              kindOf(row, "list_case_kinds"),
            ),
        ),
      ),
    open: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "open_case",
              {
                tenant: organizationId,
                kind: input.kind,
                title: input.title,
                description: input.description ?? null,
                severity: input.severity ?? null,
                source: input.source ?? "internal",
                occurred_at: instantArg(input.occurredAt) ?? null,
                owner_id: input.ownerId ?? null,
                due_on: dateArg(input.dueOn) ?? null,
                fields: checked ?? null,
              },
              one("open_case"),
            ).andThen(fields.row),
          ),
      ),
    update: (caseId, change) =>
      fields
        .args(change.fields)
        .andThen((checked) =>
          call(
            "update_case",
            {
              case_id: caseId,
              changes: definedOf({
                ...change,
                occurredAt: instantArg(change.occurredAt),
                dueOn: dateArg(change.dueOn),
                fields: checked,
              }),
            },
            one("update_case"),
          ).andThen(fields.row),
        ),
    move: (caseId, to) =>
      call(
        "update_case",
        { case_id: caseId, changes: definedOf(to) },
        one("update_case"),
      ).andThen(fields.row),
    recordRootCause: (caseId, rootCause, record = {}) =>
      call(
        "record_case_root_cause",
        {
          case_id: caseId,
          root_cause: rootCause,
          submission_id: record.submissionId ?? null,
        },
        one("record_case_root_cause"),
      ).andThen(fields.row),
    createAction: (caseId, input) =>
      call(
        "create_case_action",
        {
          case_id: caseId,
          type: input.type,
          title: input.title,
          assignee_id: input.assigneeId ?? null,
          due_at: instantArg(input.dueAt) ?? null,
          required: input.required ?? true,
        },
        (value) => addedOf(value, "create_case_action"),
      ),
    linkAction: (caseId, taskId, type, link = {}) =>
      call(
        "link_case_action",
        {
          case_id: caseId,
          task_id: taskId,
          type,
          required: link.required ?? true,
        },
        (value) => addedOf(value, "link_case_action"),
      ),
    removeAction: (actionId) =>
      call(
        "remove_case_action",
        { action_id: actionId },
        one("remove_case_action"),
      ).andThen(fields.row),
    recordEffectiveness: (caseId, effective, record = {}) =>
      call(
        "record_case_effectiveness",
        {
          case_id: caseId,
          effective,
          submission_id: record.submissionId ?? null,
          note: record.note ?? null,
        },
        one("record_case_effectiveness"),
      ).andThen(fields.row),
    blockers: (caseId) =>
      call("case_close_blockers", { case_id: caseId }, blockersOf),
    close: (caseId, note) =>
      call(
        "close_case",
        { case_id: caseId, note: note ?? null },
        one("close_case"),
      ).andThen(fields.row),
    reopen: (caseId, reason) =>
      call(
        "reopen_case",
        { case_id: caseId, reason: reason ?? null },
        one("reopen_case"),
      ).andThen(fields.row),
    cancel: (caseId, reason) =>
      call(
        "cancel_case",
        { case_id: caseId, reason: reason ?? null },
        one("cancel_case"),
      ).andThen(fields.row),
    get: (caseId) =>
      call("get_case", { case_id: caseId }, (value) =>
        detailOf(value, "get_case"),
      ).andThen(fields.row),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_cases",
          { tenant: organizationId, filters: definedOf(list) },
          (value) => {
            const page = recordOf(value, "list_cases");

            return {
              items: recordsOf(page["items"], "list_cases").map((row) =>
                caseOf(row, "list_cases"),
              ),
              ...optional("nextCursor", optionalText(page["nextCursor"])),
            };
          },
        ).andThen((page) =>
          fields
            .rows(page.items)
            .map((items) => ({ ...page, items }) satisfies CasePage<F>),
        ),
      ),
    stats: (stats = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "case_stats",
          {
            tenant: organizationId,
            kind: stats.kind ?? null,
            since: dateArg(stats.since) ?? null,
            until: dateArg(stats.until) ?? null,
            group_by: stats.groupBy ?? "severity",
          },
          (value) =>
            recordsOf(value, "case_stats").map((row) => ({
              key: optionalText(row["key"]) ?? null,
              count: numberOf(row["count"]),
            })),
        ),
      ),
    notifyDueEffectiveness: () =>
      call("notify_due_case_effectiveness", {}, (value) => numberOf(value)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "cases",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
