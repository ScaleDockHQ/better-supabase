import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.cases.options";

const DEFAULT_SEVERITIES: readonly string[] = [
  "low",
  "medium",
  "high",
  "critical",
];

const DEFAULT_SOURCES: readonly string[] = [
  "internal",
  "customer",
  "supplier",
  "inspection",
  "regulator",
  "employee",
  "anonymous",
];

/** A kind each organization starts with (`options.kinds`). */
export interface CaseKindDefinition {
  /** Lowercase letters, digits and underscores, such as `near_miss`. */
  readonly key: string;
  readonly name: string;
  /** 1 to 6 capital letters that start the case numbers, such as `NC`. */
  readonly prefix: string;
  /** Days after the required actions are done that effectiveness is due. */
  readonly effectivenessAfterDays?: number;
  /** Default true. */
  readonly requiresRootCause?: boolean;
  /** Default true. */
  readonly requiresActions?: boolean;
  /** Default false. */
  readonly requiresEffectiveness?: boolean;
  /** The documents the case affects need a new effective version. Default false. */
  readonly requiresRevisions?: boolean;
}

/** One or more case kinds. */
export type CaseKindList = readonly [
  CaseKindDefinition,
  ...CaseKindDefinition[],
];

/** The kinds `options.kinds` falls back to. */
export const DEFAULT_CASE_KINDS: CaseKindList = [
  { key: "nonconformity", name: "Nonconformity", prefix: "NC" },
  { key: "complaint", name: "Complaint", prefix: "CMP" },
  { key: "incident", name: "Incident", prefix: "INC" },
  { key: "near_miss", name: "Near miss", prefix: "NM", requiresActions: false },
  {
    key: "observation",
    name: "Observation",
    prefix: "OBS",
    requiresRootCause: false,
    requiresActions: false,
  },
  {
    key: "improvement",
    name: "Improvement",
    prefix: "IMP",
    requiresRootCause: false,
  },
  {
    key: "change",
    name: "Change request",
    prefix: "CHG",
    requiresRootCause: false,
    requiresRevisions: true,
  },
  { key: "finding", name: "Audit finding", prefix: "FND" },
];

/** The stages every kind's pipeline starts with. */
export const CASE_STAGES = [
  { key: "reported", name: "Reported", category: "open" },
  { key: "investigating", name: "Investigating", category: "open" },
  { key: "acting", name: "Acting", category: "open" },
  { key: "verifying", name: "Verifying", category: "open" },
  { key: "closed", name: "Closed", category: "closed" },
  { key: "canceled", name: "Canceled", category: "canceled" },
] as const;

const VALUE = /^[a-z][a-z0-9_]{0,40}$/;
const PREFIX = /^[A-Z]{1,6}$/;

/** The keys the case reads return next to the extra columns. */
const CASE_RESERVED = [
  "fields",
  "kind",
  "actions",
  "blockers",
  "relations",
] as const;

function valuesOf(
  ctx: BlockSqlContext,
  name: string,
  fallback: readonly string[],
): readonly string[] {
  const values = ctx.list(name, fallback);

  if (values.length === 0) {
    throw new TypeError(`${WHERE}.${name} must name at least one value`);
  }

  for (const value of values) {
    if (!VALUE.test(value)) {
      throw new TypeError(
        `${WHERE}.${name}: "${value}" must be lowercase letters, digits and underscores`,
      );
    }
  }

  if (new Set(values).size !== values.length) {
    throw new TypeError(`${WHERE}.${name} lists a value twice`);
  }

  return values;
}

const flagProblem = (kind: Record<string, unknown>): string | undefined =>
  [
    "requiresRootCause",
    "requiresActions",
    "requiresEffectiveness",
    "requiresRevisions",
  ].find((key) => kind[key] !== undefined && typeof kind[key] !== "boolean");

/** Why `value` is not a valid kind, or undefined when it is. */
export function caseKindProblem(value: unknown): string | undefined {
  if (!isRecord(value)) {
    return "a kind must be an object";
  }

  if (typeof value["key"] !== "string" || !VALUE.test(value["key"])) {
    return "key must be lowercase letters, digits and underscores, up to 41";
  }

  if (
    typeof value["name"] !== "string" ||
    value["name"].trim().length === 0 ||
    value["name"].length > 200
  ) {
    return "name must be 1 to 200 characters";
  }

  if (typeof value["prefix"] !== "string" || !PREFIX.test(value["prefix"])) {
    return "prefix must be 1 to 6 capital letters";
  }

  const days = value["effectivenessAfterDays"];

  if (
    days !== undefined &&
    (!Number.isInteger(days) || Number(days) < 1 || Number(days) > 365)
  ) {
    return "effectivenessAfterDays is a whole number from 1 to 365";
  }

  const flag = flagProblem(value);

  return flag === undefined ? undefined : `${flag} must be true or false`;
}

/** `options.kinds`, checked; the eight default kinds when left out. */
export function caseKindsOf(ctx: BlockSqlContext): CaseKindList {
  const raw = ctx.option("kinds");

  if (raw === undefined) {
    return DEFAULT_CASE_KINDS;
  }

  const [first, ...rest] = (Array.isArray(raw) ? raw : []).map(
    (kind, index) => {
      const problem = caseKindProblem(kind);

      if (problem !== undefined) {
        throw new TypeError(`${WHERE}.kinds[${String(index)}]: ${problem}`);
      }

      // SAFETY: caseKindProblem checked every key CaseKindDefinition has.
      return kind as CaseKindDefinition;
    },
  );

  if (first === undefined) {
    throw new TypeError(`${WHERE}.kinds must list at least one kind`);
  }

  const kinds: CaseKindList = [first, ...rest];

  if (new Set(kinds.map((kind) => kind.key)).size !== kinds.length) {
    throw new TypeError(`${WHERE}.kinds lists a key twice`);
  }

  return kinds;
}

/**
 * `options.intakeKind`: the kind `case_from_submission` opens when the answers
 * name none. One of the seeded kinds; `complaint` by default.
 */
function intakeKindOf(ctx: BlockSqlContext, kinds: CaseKindList): string {
  const fallback = kinds.some((kind) => kind.key === "complaint")
    ? "complaint"
    : kinds[0].key;

  const key = ctx.text("intakeKind", fallback);

  if (!kinds.some((kind) => kind.key === key)) {
    throw new TypeError(
      `${WHERE}.intakeKind: "${key}" is not one of options.kinds`,
    );
  }

  return key;
}

const textArray = (values: readonly string[]): string =>
  `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

/** The SQL pieces the cases files share. */
export interface CasesSql {
  readonly fn: (name: string) => string;
  /** A column of the kinds table. */
  readonly k: (column: string) => string;
  /** A column of the cases table. */
  readonly c: (column: string) => string;
  /** A column of the actions table. */
  readonly a: (column: string) => string;
  /** `row.column` of a cases row, or `null` when the table lacks it. */
  readonly caseOf: (row: string, column: string) => string;
  readonly has: (table: string, column: string) => boolean;
  readonly kinds: string;
  readonly cases: string;
  readonly actions: string;
  readonly extras: readonly ExtraColumn[];
  /** The cases' subject type, after renames. */
  readonly type: string;
  /** `type` as a SQL literal. */
  readonly subject: string;
  readonly seeded: readonly CaseKindDefinition[];
  readonly intakeKind: string;
  /** `options.severities` as a SQL `text[]` literal. */
  readonly severities: string;
  /** `options.sources` as a SQL `text[]` literal. */
  readonly sources: string;
  /** The pipelines context. */
  readonly pipelines: BlockSqlContext;
  /** The tasks context, when its tables are there to run actions on. */
  readonly tasks: BlockSqlContext | undefined;
  /** The task subject type, after the tasks block's renames. */
  readonly taskType: string;
  /** The relations context, when its table is there to read links from. */
  readonly relations: BlockSqlContext | undefined;
  /** The approvals context, when its tables are there to file requests in. */
  readonly approvals: BlockSqlContext | undefined;
  /** The versions context, when its tables are there to snapshot cases in. */
  readonly versions: BlockSqlContext | undefined;
  readonly read: string;
  readonly create: string;
  readonly write: string;
  readonly close: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  /** `allowed`, or the caller owns the case in `row`. */
  readonly ownerOr: (row: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly closed: string;
  readonly kindInvalid: (message: string) => string;
  readonly kindMissing: string;
  readonly kindArchived: string;
  readonly kindJson: (row: string) => string;
  readonly caseJson: (row: string) => string;
  /** The stage's outcome (`open`, `success`, `failure`) of stage id `stage`. */
  readonly outcome: (stage: string) => string;
  /**
   * Records a `case.*` event of a cases row whose kind key is in `kind`, with
   * `extra` keys added to the payload and `summary` in the audit log.
   */
  readonly record: (
    type: string,
    row: string,
    kind: string,
    summary: string,
    extra?: string,
  ) => string;
  /** Records a `case_kind.*` event of a kinds row. */
  readonly recordKind: (type: string, row: string, summary: string) => string;
}

export function casesSql(ctx: BlockSqlContext): CasesSql {
  const k = (column: string): string => ctx.col("kinds", column);
  const c = (column: string): string => ctx.col("cases", column);
  const a = (column: string): string => ctx.col("actions", column);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const caseOf = (row: string, column: string): string =>
    has("cases", column) ? `${row}.${c(column)}` : "null";

  const extras = ctx.extraColumns("cases", CASE_RESERVED);
  const seeded = caseKindsOf(ctx);
  const type = ctx.naming.rename("case");
  const pipelines = ctx.of("pipelines");

  const tasks =
    ctx.installed("tasks") && ctx.of("tasks").mode !== "custom"
      ? ctx.of("tasks")
      : undefined;

  const relations =
    ctx.installed("relations") && ctx.of("relations").mode !== "custom"
      ? ctx.of("relations")
      : undefined;

  const approvals =
    ctx.installed("approvals") && ctx.of("approvals").mode !== "custom"
      ? ctx.of("approvals")
      : undefined;

  const versions =
    ctx.installed("versions") && ctx.of("versions").mode !== "custom"
      ? ctx.of("versions")
      : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const read = ctx.permission("read", OPERATIONS["cases.read"]);

  return {
    fn: (name) => ctx.fn(name),
    k,
    c,
    a,
    caseOf,
    has,
    kinds: ctx.table("kinds"),
    cases: ctx.table("cases"),
    actions: ctx.table("actions"),
    extras,
    type,
    subject: sqlString(type),
    seeded,
    intakeKind: intakeKindOf(ctx, seeded),
    severities: textArray(valuesOf(ctx, "severities", DEFAULT_SEVERITIES)),
    sources: textArray(valuesOf(ctx, "sources", DEFAULT_SOURCES)),
    pipelines,
    tasks,
    taskType: tasks === undefined ? "task" : entityType(tasks.resolved, "task"),
    relations,
    approvals,
    versions,
    read,
    create: ctx.permission("create", OPERATIONS["cases.create"]),
    write: ctx.permission("write", OPERATIONS["cases.write"]),
    close: ctx.permission("close", OPERATIONS["cases.close"]),
    manage: ctx.permission("manage", OPERATIONS["cases.manage"]),
    allowed,
    ownerOr: (row, permission) =>
      `(${allowed(`${row}.${c("tenant")}`, permission)} or (coalesce(${row}.${c("owner")} = (select auth.uid()), false) and ${allowed(`${row}.${c("tenant")}`, read)}))`,
    invalid: (message) => fail("CASE_INVALID", message, "22023"),
    forbidden: (message) => fail("CASE_FORBIDDEN", message),
    missing: fail("CASE_NOT_FOUND", "no such case", "P0002"),
    closed: fail("CASE_CLOSED", "the case is closed or canceled", "55000"),
    kindInvalid: (message) => fail("CASE_KIND_INVALID", message, "22023"),
    kindMissing: fail(
      "CASE_KIND_NOT_FOUND",
      "no such case kind in this organization",
      "P0002",
    ),
    kindArchived: fail(
      "CASE_KIND_ARCHIVED",
      "the case kind is archived",
      "55000",
    ),
    kindJson: (row) =>
      `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}, 'key', ${row}.${k("key")}, 'name', ${row}.${k("name")}, 'prefix', ${row}.${k("prefix")}, 'pipelineId', ${row}.${k("pipeline")}, 'investigationFormId', ${row}.${k("investigationForm")}, 'effectivenessFormId', ${row}.${k("effectivenessForm")}, 'effectivenessAfterDays', ${row}.${k("effectivenessAfterDays")}, 'requiresRootCause', ${row}.${k("requiresRootCause")}, 'requiresActions', ${row}.${k("requiresActions")}, 'requiresEffectiveness', ${row}.${k("requiresEffectiveness")}, 'requiresRevisions', ${row}.${k("requiresRevisions")}, 'archivedAt', ${row}.${k("archivedAt")}, 'createdAt', ${row}.${k("createdAt")}, 'updatedAt', ${row}.${k("updatedAt")})`,
    caseJson: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'kindId', ${row}.${c("kind")}, 'number', ${row}.${c("number")}, 'title', ${row}.${c("title")}, 'description', ${caseOf(row, "description")}, 'severity', ${row}.${c("severity")}, 'source', ${row}.${c("source")}, 'reporterId', ${row}.${c("reporter")}, 'reporterContact', ${caseOf(row, "reporterContact")}, 'ownerId', ${row}.${c("owner")}, 'occurredAt', ${row}.${c("occurredAt")}, 'detectedAt', ${row}.${c("detectedAt")}, 'dueOn', ${row}.${c("dueOn")}, 'pipelineId', ${row}.${c("pipeline")}, 'stageId', ${row}.${c("stage")}, 'stageEnteredAt', ${row}.${c("stageEnteredAt")}, 'status', ${row}.${c("status")}, 'rootCause', ${row}.${c("rootCause")}, 'rootCauseSubmissionId', ${row}.${c("rootCauseSubmission")}, 'effective', ${row}.${c("effective")}, 'effectivenessDueOn', ${row}.${c("effectivenessDueOn")}, 'effectivenessNote', ${row}.${c("effectivenessNote")}, 'effectivenessSubmissionId', ${row}.${c("effectivenessSubmission")}, 'closedAt', ${row}.${c("closedAt")}, 'closedBy', ${row}.${c("closedBy")}, 'closeNote', ${row}.${c("closeNote")}, 'rank', ${row}.${c("rank")}, 'archivedAt', ${row}.${c("archivedAt")}, 'createdBy', ${caseOf(row, "createdBy")}, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${row}.${c("updatedAt")}${extraFieldsJson(row, extras)})`,
    outcome: (stage) =>
      `(select s.${pipelines.col("stages", "outcome")} from ${pipelines.table("stages")} s where s.${pipelines.col("stages", "id")} = ${stage})`,
    record: (eventType, row, kind, summary, extra = "") =>
      ctx.record({
        type: eventType,
        payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'caseId', ${row}.${c("id")}, 'kind', ${kind}, 'number', ${row}.${c("number")}, 'title', ${row}.${c("title")}, 'status', ${row}.${c("status")}${extra})`,
        subject: `'cases/' || ${row}.${c("id")}::text`,
        tenant: `${row}.${c("tenant")}`,
        audit: {
          category: "data",
          targetType: "case",
          recordId: `${row}.${c("id")}::text`,
          targetLabel: `${row}.${c("number")} || ' ' || ${row}.${c("title")}`,
          summary: sqlString(summary),
        },
      }),
    recordKind: (eventType, row, summary) =>
      ctx.record({
        type: eventType,
        payload: `jsonb_build_object('organizationId', ${row}.${k("tenant")}, 'caseKindId', ${row}.${k("id")}, 'key', ${row}.${k("key")}, 'name', ${row}.${k("name")}, 'prefix', ${row}.${k("prefix")})`,
        subject: `'case-kinds/' || ${row}.${k("id")}::text`,
        tenant: `${row}.${k("tenant")}`,
        audit: {
          category: "data",
          targetType: "case_kind",
          recordId: `${row}.${k("id")}::text`,
          targetLabel: `${row}.${k("name")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
