import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import {
  DEFAULT_INSPECTION_CASE_FINDING_TYPES,
  DEFAULT_INSPECTION_FINDING_TYPES,
  DEFAULT_INSPECTION_KINDS,
} from "./inspections-values.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.inspections.options";

const KEY = /^[a-z][a-z0-9_]{0,62}$/;

/** The keys the inspection reads return next to the extra columns. */
const INSPECTION_RESERVED = [
  "fields",
  "members",
  "findings",
  "checklist",
  "assessedControls",
  "auditee",
] as const;

/** `options.<name>`, checked as a list of unique keys. */
function keysOf(
  ctx: BlockSqlContext,
  name: string,
  fallback: readonly string[],
): readonly string[] {
  const values = ctx.list(name, fallback);

  if (values.length === 0) {
    throw new TypeError(`${WHERE}.${name} must name at least one value`);
  }

  for (const value of values) {
    if (!KEY.test(value)) {
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

/** `options.kinds`, `findingTypes` and `caseFindingTypes`, checked. */
export function inspectionOptions(ctx: BlockSqlContext): {
  readonly kinds: readonly string[];
  readonly findingTypes: readonly string[];
  readonly caseFindingTypes: readonly string[];
} {
  const kinds = keysOf(ctx, "kinds", DEFAULT_INSPECTION_KINDS);

  const findingTypes = keysOf(
    ctx,
    "findingTypes",
    DEFAULT_INSPECTION_FINDING_TYPES,
  );

  const caseFindingTypes = ctx.list(
    "caseFindingTypes",
    DEFAULT_INSPECTION_CASE_FINDING_TYPES,
  );

  for (const type of caseFindingTypes) {
    if (!findingTypes.includes(type)) {
      throw new TypeError(
        `${WHERE}.caseFindingTypes: "${type}" is not one of options.findingTypes`,
      );
    }
  }

  return { kinds, findingTypes, caseFindingTypes };
}

const textArray = (values: readonly string[]): string =>
  `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

/** A subject type of another block, after its renames when it's installed. */
export const typeOf = (
  own: BlockSqlContext,
  module: string,
  entity: string,
): string =>
  own.installed(module) ? entityType(own.of(module).resolved, entity) : entity;

/** The block contexts the inspections functions read, when they're there. */
function linked(ctx: BlockSqlContext, module: string) {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the inspections files share. */
export interface InspectionsSql {
  readonly fn: (name: string) => string;
  /** A column of the programs table. */
  readonly p: (column: string) => string;
  /** A column of the inspections table. */
  readonly i: (column: string) => string;
  /** A column of the members table. */
  readonly m: (column: string) => string;
  /** A column of the findings table. */
  readonly f: (column: string) => string;
  /** `row.column`, or `null` when the table lacks the column. */
  readonly of: (table: string, row: string, column: string) => string;
  readonly has: (table: string, column: string) => boolean;
  readonly programs: string;
  readonly inspections: string;
  readonly members: string;
  readonly findings: string;
  readonly extras: readonly ExtraColumn[];
  /** The subject types, after renames, as SQL literals. */
  readonly subject: string;
  readonly findingSubject: string;
  readonly programSubject: string;
  /** The compliance control's subject type, as a SQL literal. */
  readonly controlSubject: string;
  readonly kinds: string;
  readonly findingTypes: string;
  readonly caseFindingTypes: string;
  readonly forms: BlockSqlContext;
  readonly cases: BlockSqlContext | undefined;
  readonly relations: BlockSqlContext | undefined;
  readonly compliance: BlockSqlContext | undefined;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  /**
   * The caller manages inspections, or writes them and is one of `roles` on
   * inspection `inspection`.
   */
  readonly acts: (
    tenant: string,
    inspection: string,
    roles: readonly string[],
  ) => string;
  /** The caller reads inspections, or is a member of `inspection`. */
  readonly sees: (tenant: string, inspection: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  /** Refuses moving `row` from its status to `to`. */
  readonly statusInvalid: (row: string, to: string) => string;
  readonly missing: string;
  readonly programMissing: string;
  readonly findingMissing: string;
  readonly programJson: (row: string) => string;
  readonly inspectionJson: (row: string) => string;
  readonly findingJson: (row: string) => string;
  /** Records an `inspection.*` event of an inspections row. */
  readonly record: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
  readonly recordProgram: (
    type: string,
    row: string,
    summary: string,
  ) => string;
  readonly recordFinding: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function inspectionsSql(ctx: BlockSqlContext): InspectionsSql {
  const p = (column: string): string => ctx.col("programs", column);
  const i = (column: string): string => ctx.col("inspections", column);
  const m = (column: string): string => ctx.col("members", column);
  const f = (column: string): string => ctx.col("findings", column);
  const fn = (name: string): string => ctx.fn(name);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const of = (table: string, row: string, column: string): string =>
    has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

  const options = inspectionOptions(ctx);
  const extras = ctx.extraColumns("inspections", INSPECTION_RESERVED);
  const read = ctx.permission("read", OPERATIONS["inspections.read"]);
  const write = ctx.permission("write", OPERATIONS["inspections.write"]);
  const manage = ctx.permission("manage", OPERATIONS["inspections.manage"]);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const role = (inspection: string): string =>
    `${fn("inspection_role")}(${inspection})`;

  return {
    fn,
    p,
    i,
    m,
    f,
    of,
    has,
    programs: ctx.table("programs"),
    inspections: ctx.table("inspections"),
    members: ctx.table("members"),
    findings: ctx.table("findings"),
    extras,
    subject: sqlString(ctx.naming.rename("inspection")),
    findingSubject: sqlString(ctx.naming.rename("inspection_finding")),
    programSubject: sqlString(ctx.naming.rename("inspection_program")),
    controlSubject: sqlString(typeOf(ctx, "compliance", "control")),
    kinds: textArray(options.kinds),
    findingTypes: textArray(options.findingTypes),
    caseFindingTypes: textArray(options.caseFindingTypes),
    forms: ctx.of("forms"),
    cases: linked(ctx, "cases"),
    relations: linked(ctx, "relations"),
    compliance: linked(ctx, "compliance"),
    read,
    write,
    manage,
    allowed,
    acts: (tenant, inspection, roles) =>
      `(${allowed(tenant, manage)} or (auth.uid() is not null and ${ctx.can("tenant", tenant, write)} and ${role(inspection)} in (${roles.map((r) => sqlString(r)).join(", ")})))`,
    sees: (tenant, inspection) =>
      `(${allowed(tenant, read)} or ${role(inspection)} is not null)`,
    invalid: (message) => fail("INSPECTION_INVALID", message, "22023"),
    forbidden: (message) => fail("INSPECTION_FORBIDDEN", message),
    statusInvalid: (row, to) =>
      `raise exception 'the inspection can''t move from % to %', ${row}.${i("status")}, ${sqlString(to)} using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', ${row}.${i("status")}, 'to', ${sqlString(to)})::text;`,
    missing: fail("INSPECTION_NOT_FOUND", "no such inspection", "P0002"),
    programMissing: fail(
      "INSPECTION_PROGRAM_NOT_FOUND",
      "no such audit programme in this organization",
      "P0002",
    ),
    findingMissing: fail(
      "INSPECTION_FINDING_NOT_FOUND",
      "no such finding",
      "P0002",
    ),
    programJson: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'name', ${row}.${p("name")}, 'periodStart', ${row}.${p("periodStart")}, 'periodEnd', ${row}.${p("periodEnd")}, 'ownerId', ${row}.${p("owner")}, 'status', ${row}.${p("status")}, 'notes', ${of("programs", row, "notes")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    inspectionJson: (row) =>
      `jsonb_build_object('id', ${row}.${i("id")}, 'organizationId', ${row}.${i("tenant")}, 'programId', ${row}.${i("program")}, 'number', ${row}.${i("number")}, 'kind', ${row}.${i("kind")}, 'title', ${row}.${i("title")}, 'scope', ${of("inspections", row, "scope")}, 'criteria', ${of("inspections", row, "criteria")}, 'auditee', case when ${row}.${i("auditeeType")} is null then null else jsonb_build_object('type', ${row}.${i("auditeeType")}, 'id', ${row}.${i("auditeeId")}) end, 'leadId', ${row}.${i("lead")}, 'plannedStart', ${row}.${i("plannedStart")}, 'plannedEnd', ${row}.${i("plannedEnd")}, 'startedAt', ${row}.${i("startedAt")}, 'completedAt', ${row}.${i("completedAt")}, 'closedAt', ${row}.${i("closedAt")}, 'status', ${row}.${i("status")}, 'checklistFormId', ${row}.${i("checklistForm")}, 'checklistSubmissionId', ${row}.${i("checklistSubmission")}, 'summary', ${of("inspections", row, "summary")}, 'createdBy', ${of("inspections", row, "createdBy")}, 'createdAt', ${row}.${i("createdAt")}, 'updatedAt', ${row}.${i("updatedAt")}${extraFieldsJson(row, extras)})`,
    findingJson: (row) =>
      `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'inspectionId', ${row}.${f("inspection")}, 'number', ${row}.${f("number")}, 'type', ${row}.${f("type")}, 'title', ${row}.${f("title")}, 'description', ${of("findings", row, "description")}, 'clause', ${of("findings", row, "clause")}, 'controlId', ${row}.${f("control")}, 'evidence', ${of("findings", row, "evidence")}, 'caseId', ${row}.${f("case")}, 'needsCase', ${row}.${f("type")} = any (${textArray(options.caseFindingTypes)}), 'createdBy', ${of("findings", row, "createdBy")}, 'createdAt', ${row}.${f("createdAt")}, 'updatedAt', ${row}.${f("updatedAt")})`,
    record: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${i("tenant")}, 'id', ${row}.${i("id")}, 'number', ${row}.${i("number")}, 'kind', ${row}.${i("kind")}, 'title', ${row}.${i("title")}, 'status', ${row}.${i("status")}${extra})`,
        subject: `'inspections/' || ${row}.${i("id")}::text`,
        tenant: `${row}.${i("tenant")}`,
        audit: {
          category: "data",
          targetType: "inspection",
          recordId: `${row}.${i("id")}::text`,
          targetLabel: `${row}.${i("title")}`,
          summary: sqlString(summary),
        },
      }),
    recordProgram: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'name', ${row}.${p("name")}, 'status', ${row}.${p("status")})`,
        subject: `'inspection-programs/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "inspection_program",
          recordId: `${row}.${p("id")}::text`,
          targetLabel: `${row}.${p("name")}`,
          summary: sqlString(summary),
        },
      }),
    recordFinding: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${f("tenant")}, 'id', ${row}.${f("id")}, 'inspectionId', ${row}.${f("inspection")}, 'number', ${row}.${f("number")}, 'type', ${row}.${f("type")}, 'title', ${row}.${f("title")}${extra})`,
        subject: `'inspection-findings/' || ${row}.${f("id")}::text`,
        tenant: `${row}.${f("tenant")}`,
        audit: {
          category: "data",
          targetType: "inspection_finding",
          recordId: `${row}.${f("id")}::text`,
          targetLabel: `${row}.${f("title")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
