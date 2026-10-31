import type { InspectionsEvents } from "../../blocks/inspections/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { inspectionFindingFunctions } from "./inspections-findings.ts";
import { inspectionFunctions } from "./inspections-functions.ts";
import { inspectionIntegrations } from "./inspections-integrations.ts";
import { inspectionReads } from "./inspections-read.ts";
import { inspectionsSql, typeOf } from "./inspections-sql.ts";
import {
  INSPECTION_MEMBER_ROLES,
  INSPECTION_PROGRAM_STATUSES,
  INSPECTION_STATUSES,
} from "./inspections-values.ts";

const INSPECTION = [
  "organizationId",
  "id",
  "number",
  "kind",
  "title",
  "status",
] as const;

const inspection = { subject: "inspections", payload: INSPECTION } as const;

const program = {
  subject: "inspection-programs",
  payload: ["organizationId", "id", "name", "status"],
} as const;

const FINDING = [
  "organizationId",
  "id",
  "inspectionId",
  "number",
  "type",
  "title",
] as const;

const finding = { subject: "inspection-findings", payload: FINDING } as const;

const EVENTS: BlockSqlEvents<InspectionsEvents> = {
  "inspection_program.created": program,
  "inspection_program.updated": program,
  "inspection_program.approved": program,
  "inspection_program.closed": program,
  "inspection.scheduled": inspection,
  "inspection.updated": inspection,
  "inspection.started": inspection,
  "inspection.completed": inspection,
  "inspection.closed": inspection,
  "inspection.cancelled": {
    subject: "inspections",
    payload: [...INSPECTION, "reason"],
  },
  "inspection_finding.created": finding,
  "inspection_finding.updated": finding,
  "inspection_finding.deleted": finding,
  "inspection_finding.case_raised": {
    subject: "inspection-findings",
    payload: [...FINDING, "caseId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    inspection: {
      table: "inspections",
      singular: "inspection",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["number", "scope", "summary"] },
      },
    },
    inspection_program: {
      table: "programs",
      singular: "inspection_program",
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "manage" },
      },
    },
    inspection_finding: {
      table: "findings",
      singular: "inspection_finding",
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    inspection_member: { table: "members", singular: "inspection_member" },
  },
  events: EVENTS,
  hooks: [
    "before_inspection_schedule",
    "after_inspection_schedule",
    "before_inspection_close",
    "after_inspection_close",
    "before_inspection_finding_create",
    "after_inspection_finding_create",
  ],
  options: [
    "kinds",
    "findingTypes",
    "caseFindingTypes",
    "calendar",
    "extraColumns",
  ],
  tables: {
    programs: {
      name: "inspection_programs",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        periodStart: "period_start",
        periodEnd: "period_end",
        owner: "owner_id",
        status: "status",
        notes: "notes",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["notes"],
    },
    inspections: {
      name: "inspections",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        program: "program_id",
        number: "number",
        sequence: "sequence",
        kind: "kind",
        title: "title",
        scope: "scope",
        criteria: "criteria",
        auditeeType: "auditee_type",
        auditeeId: "auditee_id",
        lead: "lead_id",
        plannedStart: "planned_start",
        plannedEnd: "planned_end",
        startedAt: "started_at",
        completedAt: "completed_at",
        closedAt: "closed_at",
        overdueNotifiedFor: "overdue_notified_for",
        status: "status",
        checklistForm: "checklist_form_id",
        checklistSubmission: "checklist_submission_id",
        summary: "summary",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "scope",
        "criteria",
        "summary",
        "createdBy",
        "overdueNotifiedFor",
      ],
    },
    members: {
      name: "inspection_members",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        inspection: "inspection_id",
        tenant: "tenant_id",
        user: "user_id",
        role: "role",
        createdAt: "created_at",
      },
    },
    findings: {
      name: "inspection_findings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        inspection: "inspection_id",
        number: "number",
        type: "type",
        title: "title",
        description: "description",
        clause: "clause",
        control: "control_id",
        evidence: "evidence",
        case: "case_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "clause", "evidence", "createdBy"],
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = inspectionsSql(ctx);
  const { p, i, m, f, fn, programs, inspections, members, findings } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const text = (column: string, max: number): string =>
    `${column} text check (${column} is null or length(${column}) <= ${String(max)})`;

  const forms = q.forms;

  const formRef = forms.owns("forms")
    ? ` references ${forms.table("forms")} (${forms.col("forms", "id")}) on delete restrict`
    : "";

  const submissionRef = forms.owns("submissions")
    ? ` references ${forms.table("submissions")} (${forms.col("submissions", "id")}) on delete set null`
    : "";

  const controlRef = q.compliance?.owns("controls")
    ? ` references ${q.compliance.table("controls")} (${q.compliance.col("controls", "id")}) on delete set null`
    : "";

  const caseRef = q.cases?.owns("cases")
    ? ` references ${q.cases.table("cases")} (${q.cases.col("cases", "id")}) on delete set null`
    : "";

  const reads = (tenant: string, inspection: string): string =>
    `(${ctx.scope.check(tenant, q.read)}) or ${fn("inspection_role")}(${inspection}) is not null`;

  return `
create table if not exists ${programs} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("periodStart")} date not null,
  ${p("periodEnd")} date not null,
  ${p("owner")} uuid,
  ${p("status")} text not null default 'draft' check (${p("status")} in (${list(INSPECTION_PROGRAM_STATUSES)})),${opt("programs", "notes", () => text(p("notes"), 10_000))}
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("id")}),
  check (${p("periodEnd")} >= ${p("periodStart")})
);${appKey("programs", "tenant_id", `${p("tenant")}, ${p("id")}`)}
create index if not exists ${name("programs", "tenant_idx")} on ${programs} (${p("tenant")}, ${p("periodStart")} desc);
${lockTable(programs, { read: true })}
${readPolicy("programs", ctx.scope.check(p("tenant"), q.read))}

create table if not exists ${inspections} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("program")} uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  ${i("number")} text not null check (length(${i("number")}) between 1 and 100),
  ${i("sequence")} bigint not null,
  -- One of options.kinds; the functions check it.
  ${i("kind")} text not null check (length(${i("kind")}) between 1 and 63),
  ${i("title")} text not null check (length(${i("title")}) between 1 and 300),${opt("inspections", "scope", () => text(i("scope"), 10_000))}${opt("inspections", "criteria", () => text(i("criteria"), 10_000))}
  -- The subject audited, such as a supplier or a site.
  ${i("auditeeType")} text,
  ${i("auditeeId")} text,
  ${i("lead")} uuid,
  ${i("plannedStart")} date,
  ${i("plannedEnd")} date,
  ${i("startedAt")} timestamptz,
  ${i("completedAt")} timestamptz,
  ${i("closedAt")} timestamptz,${opt("inspections", "overdueNotifiedFor", () => `${i("overdueNotifiedFor")} date`)}
  ${i("status")} text not null default 'planned' check (${i("status")} in (${list(INSPECTION_STATUSES)})),
  ${i("checklistForm")} uuid${formRef},
  ${i("checklistSubmission")} uuid${submissionRef},${opt("inspections", "summary", () => text(i("summary"), 20_000))}${opt("inspections", "createdBy", () => `${i("createdBy")} uuid`)}
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  unique (${i("tenant")}, ${i("number")}),
  unique (${i("tenant")}, ${i("id")}),
  check ((${i("auditeeType")} is null) = (${i("auditeeId")} is null)),
  check (${i("plannedEnd")} is null or ${i("plannedStart")} is null or ${i("plannedEnd")} >= ${i("plannedStart")}),
  foreign key (${i("tenant")}, ${i("program")}) references ${programs} (${p("tenant")}, ${p("id")}) on delete restrict
);${addExtraColumns(inspections, q.extras)}${appKey("inspections", "tenant_number", `${i("tenant")}, ${i("number")}`)}${appKey("inspections", "tenant_id", `${i("tenant")}, ${i("id")}`)}
create index if not exists ${name("inspections", "tenant_idx")} on ${inspections} (${i("tenant")}, ${i("status")}, ${i("plannedStart")} desc);
create index if not exists ${name("inspections", "program_idx")} on ${inspections} (${i("tenant")}, ${i("program")}) where ${i("program")} is not null;
create index if not exists ${name("inspections", "lead_idx")} on ${inspections} (${i("tenant")}, ${i("lead")}) where ${i("lead")} is not null;
create index if not exists ${name("inspections", "auditee_idx")} on ${inspections} (${i("tenant")}, ${i("auditeeType")}, ${i("auditeeId")}) where ${i("auditeeType")} is not null;
create index if not exists ${name("inspections", "checklist_form_idx")} on ${inspections} (${i("checklistForm")}) where ${i("checklistForm")} is not null;
create index if not exists ${name("inspections", "checklist_submission_idx")} on ${inspections} (${i("checklistSubmission")}) where ${i("checklistSubmission")} is not null;
${lockTable(inspections, { read: true })}

create table if not exists ${members} (
  ${m("inspection")} uuid not null,
  ${m("tenant")} ${ctx.idType} not null,
  ${m("user")} uuid not null,
  ${m("role")} text not null check (${m("role")} in (${list(INSPECTION_MEMBER_ROLES)})),
  ${m("createdAt")} timestamptz not null default now(),
  primary key (${m("inspection")}, ${m("user")}),
  foreign key (${m("tenant")}, ${m("inspection")}) references ${inspections} (${i("tenant")}, ${i("id")}) on delete cascade
);${appKey("members", "inspection_user", `${m("inspection")}, ${m("user")}`)}
create index if not exists ${name("members", "parent_idx")} on ${members} (${m("tenant")}, ${m("inspection")});
create index if not exists ${name("members", "user_idx")} on ${members} (${m("user")}, ${m("inspection")});
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists ${name("members", "lead_key")} on ${members} (${m("inspection")}) where ${m("role")} = 'lead';
${lockTable(members, { read: true })}

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function ${fn("inspection_role")}(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x.${m("role")} from ${members} x
  where x.${m("inspection")} = inspection_role.inspection_id and x.${m("user")} = auth.uid();
$$;
${userGrant(`${fn("inspection_role")}(uuid)`)}
${readPolicy("inspections", reads(i("tenant"), i("id")))}
${readPolicy("members", reads(m("tenant"), m("inspection")))}

create table if not exists ${findings} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("inspection")} uuid not null,
  -- 1, 2, 3 within the inspection.
  ${f("number")} integer not null check (${f("number")} > 0),
  -- One of options.findingTypes; the functions check it.
  ${f("type")} text not null check (length(${f("type")}) between 1 and 63),
  ${f("title")} text not null check (length(${f("title")}) between 1 and 300),${opt("findings", "description", () => text(f("description"), 10_000))}${opt("findings", "clause", () => text(f("clause"), 200))}
  ${f("control")} uuid${controlRef},${opt("findings", "evidence", () => text(f("evidence"), 10_000))}
  ${f("case")} uuid${caseRef},${opt("findings", "createdBy", () => `${f("createdBy")} uuid`)}
  ${f("createdAt")} timestamptz not null default now(),
  ${f("updatedAt")} timestamptz not null default now(),
  unique (${f("inspection")}, ${f("number")}),
  foreign key (${f("tenant")}, ${f("inspection")}) references ${inspections} (${i("tenant")}, ${i("id")}) on delete cascade
);${appKey("findings", "inspection_number", `${f("inspection")}, ${f("number")}`)}
create index if not exists ${name("findings", "parent_idx")} on ${findings} (${f("tenant")}, ${f("inspection")}, ${f("number")});
create index if not exists ${name("findings", "control_idx")} on ${findings} (${f("control")}) where ${f("control")} is not null;
create index if not exists ${name("findings", "case_idx")} on ${findings} (${f("case")}) where ${f("case")} is not null;
${lockTable(findings, { read: true })}
${readPolicy("findings", reads(f("tenant"), f("inspection")))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("forms").mode === "custom") {
    throw new TypeError(
      "blocks.inspections needs the forms tables for its checklists; forms can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.
${tables(ctx)}
${inspectionFunctions(ctx)}
${inspectionFindingFunctions(ctx)}
${inspectionReads(ctx)}
${inspectionIntegrations(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_inspection_program",
      args: ["{id}", "text", "date", "date", "uuid", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "approve_inspection_program", args: ["uuid"], returns: "jsonb" },
    { name: "close_inspection_program", args: ["uuid"], returns: "jsonb" },
    { name: "list_inspection_programs", args: ["{id}"], returns: "jsonb" },
    { name: "schedule_inspection", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_inspection", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "set_inspection_members",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "start_inspection", args: ["uuid"], returns: "jsonb" },
    {
      name: "save_inspection_checklist",
      args: ["uuid", "jsonb", "boolean"],
      returns: "jsonb",
    },
    { name: "complete_inspection", args: ["uuid", "text"], returns: "jsonb" },
    { name: "close_inspection", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_inspection", args: ["uuid", "text"], returns: "jsonb" },
    { name: "notify_overdue_inspections", args: [], returns: "integer" },
    { name: "get_inspection", args: ["uuid"], returns: "jsonb" },
    { name: "list_inspections", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "add_inspection_finding",
      args: ["uuid", "text", "text", "text", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "update_inspection_finding",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_inspection_finding", args: ["uuid"], returns: "jsonb" },
    {
      name: "raise_inspection_finding_case",
      args: ["uuid", "text", "uuid"],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  numbering: (own) => [
    {
      entity: own.resolved.entityNaming.rename("inspection"),
      entry: { period: "year", format: "AUD-{yyyy}-{n:3}" },
    },
  ],
  relations: (own) => [
    {
      kind: "assesses",
      inverse: "assessed_by",
      types: {
        source: [own.naming.rename("inspection")],
        target: [typeOf(own, "compliance", "control")],
      },
    },
  ],
};

export const INSPECTIONS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "inspections",
  scopes: ["tenant"],
  title: "Audits and inspections",
  description:
    "Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.",
  requires: ["memberships", "permissions", "subjects", "forms"],
  integrates: [
    "cases",
    "compliance",
    "relations",
    "numbering",
    "calendar",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
