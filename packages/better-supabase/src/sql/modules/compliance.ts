import type { ComplianceEvents } from "../../blocks/compliance/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type {
  BlockSqlDeprecation,
  BlockSqlDefinition,
  BlockSqlUpgrade,
} from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { entityType } from "../resolved-names.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { tableMoves } from "../table-renames.ts";
import { acknowledgementTables } from "./acknowledgements.ts";
import { complianceFunctions } from "./compliance-functions.ts";
import {
  POLICY_ROLE,
  policyFunctions,
  widenPolicyAssignments,
} from "./compliance-policies.ts";
import {
  CONTROL_RESERVED,
  evidenceAttachments,
  FRAMEWORK_KINDS,
} from "./compliance-shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import { subjectTypeRenames } from "./subject-type-renames.ts";

const EVENTS: BlockSqlEvents<ComplianceEvents> = {
  "control.created": {
    subject: "controls",
    payload: ["organizationId", "controlId", "frameworkId", "code"],
  },
  "control.updated": {
    subject: "controls",
    payload: ["organizationId", "controlId", "frameworkId", "code"],
  },
  "control.evidence_added": {
    subject: "controls",
    payload: ["organizationId", "controlId", "evidenceId", "evidenceTaskId"],
  },
  "evidence_task.missed": {
    subject: "evidence-tasks",
    payload: [
      "organizationId",
      "evidenceTaskId",
      "controlId",
      "assigneeId",
      "dueOn",
    ],
  },
  "compliance_policy.published": {
    subject: "policies",
    payload: ["organizationId", "policyId", "versionId", "number"],
  },
};

const NAMES: BlockSqlNames = {
  migrations: tableMoves("compliance", 2),
  entities: {
    control: {
      table: "controls",
      singular: "control",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
    control_framework: { table: "frameworks", singular: "control_framework" },
    evidence_task: { table: "tasks", singular: "evidence_task" },
    compliance_policy: {
      table: "policies",
      singular: "compliance_policy",
      formerly: "policy",
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    frameworks: {
      name: "control_frameworks",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        kind: "kind",
        version: "version",
        description: "description",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["kind", "version", "description", "createdAt", "updatedAt"],
    },
    controls: {
      name: "controls",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        framework: "framework_id",
        code: "code",
        title: "title",
        description: "description",
        owner: "owner_id",
        applicable: "applicable",
        source: "source",
        jurisdiction: "jurisdiction",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "description",
        "owner",
        "source",
        "jurisdiction",
        "createdAt",
        "updatedAt",
      ],
    },
    evidence: {
      name: "control_evidence",
      app: {},
      lifecycle: { tenant: "tenant", user: "collectedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        control: "control_id",
        task: "task_id",
        attachment: "attachment_id",
        note: "note",
        collectedBy: "collected_by",
        collectedAt: "collected_at",
        validUntil: "valid_until",
      },
      optional: ["note"],
    },
    tasks: {
      name: "evidence_tasks",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        control: "control_id",
        title: "title",
        assignee: "assignee_id",
        intervalDays: "interval_days",
        dueOn: "due_on",
        lastCollectedAt: "last_collected_at",
        notifiedFor: "notified_for",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["assignee", "lastCollectedAt", "createdAt", "updatedAt"],
    },
    policies: {
      name: "compliance_policies",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        title: "title",
        owner: "owner_id",
        requiresAck: "requires_acknowledgement",
        currentVersion: "current_version_id",
        versionNumber: "version_number",
        publishedAt: "published_at",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["owner", "createdAt", "updatedAt"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const frameworks = ctx.table("frameworks");
  const controls = ctx.table("controls");
  const evidence = ctx.table("evidence");
  const tasks = ctx.table("tasks");
  const policies = ctx.table("policies");
  const f = (column: string): string => ctx.col("frameworks", column);
  const k = (column: string): string => ctx.col("controls", column);
  const e = (column: string): string => ctx.col("evidence", column);
  const t = (column: string): string => ctx.col("tasks", column);
  const p = (column: string): string => ctx.col("policies", column);
  const read = ctx.permission("read", moduleOperations("compliance").read);
  const versions = ctx.of("versions");
  const attachments = evidenceAttachments(ctx);
  const extras = ctx.extraColumns("controls", CONTROL_RESERVED);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const added = (
    logical: string,
    column: string,
    line: () => string,
  ): string =>
    ctx.has(logical, column)
      ? `\nalter table ${ctx.table(logical)} add column if not exists ${line()};`
      : "";

  const kind = (): string =>
    `${f("kind")} text not null default 'standard' check (${f("kind")} in (${FRAMEWORK_KINDS.map((item) => `'${item}'`).join(", ")}))`;

  const label = (column: string) => (): string =>
    `${k(column)} text check (${k(column)} is null or length(${k(column)}) between 1 and 200)`;

  const readPolicy = (logical: string, using: string): string => {
    const policy = ctx.owns(logical)
      ? name(logical, "read")
      : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`);

    return renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: policy,
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );
  };

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const versionRef = versions.owns("versions")
    ? ` references ${versions.table("versions")} (${versions.col("versions", "id")}) on delete restrict`
    : "";

  return `
create table if not exists ${frameworks} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("key")} text not null check (${f("key")} ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  ${f("name")} text not null check (length(${f("name")}) between 1 and 200),${opt("frameworks", "kind", kind)}${opt("frameworks", "version", () => `${f("version")} text check (${f("version")} is null or length(${f("version")}) <= 50)`)}${opt("frameworks", "description", () => `${f("description")} text check (${f("description")} is null or length(${f("description")}) <= 4000)`)}${opt("frameworks", "createdAt", () => `${f("createdAt")} timestamptz not null default now()`)}${opt("frameworks", "updatedAt", () => `${f("updatedAt")} timestamptz not null default now()`)}
  unique (${f("tenant")}, ${f("key")}),
  unique (${f("tenant")}, ${f("id")})
);${added("frameworks", "kind", kind)}${appKey("frameworks", "tenant_key", `${f("tenant")}, ${f("key")}`)}${appKey("frameworks", "tenant_id", `${f("tenant")}, ${f("id")}`)}
${lockTable(frameworks, { read: true })}
${readPolicy("frameworks", ctx.scope.check(f("tenant"), read))}

create table if not exists ${controls} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("framework")} uuid not null,
  ${k("code")} text not null check (length(${k("code")}) between 1 and 50),
  ${k("title")} text not null check (length(${k("title")}) between 1 and 200),${opt("controls", "description", () => `${k("description")} text check (${k("description")} is null or length(${k("description")}) <= 10000)`)}${opt("controls", "owner", () => `${k("owner")} uuid`)}
  -- A control out of scope (excluded in the statement of applicability).
  ${k("applicable")} boolean not null default true,${opt("controls", "source", label("source"))}${opt("controls", "jurisdiction", label("jurisdiction"))}${opt("controls", "createdAt", () => `${k("createdAt")} timestamptz not null default now()`)}${opt("controls", "updatedAt", () => `${k("updatedAt")} timestamptz not null default now()`)}
  unique (${k("framework")}, ${k("code")}),
  unique (${k("tenant")}, ${k("id")}),
  foreign key (${k("tenant")}, ${k("framework")}) references ${frameworks} (${f("tenant")}, ${f("id")}) on delete cascade
);${added("controls", "source", label("source"))}${added("controls", "jurisdiction", label("jurisdiction"))}${addExtraColumns(controls, extras)}${appKey("controls", "framework_code", `${k("framework")}, ${k("code")}`)}${appKey("controls", "tenant_id", `${k("tenant")}, ${k("id")}`)}
create index if not exists ${name("controls", "tenant_idx")} on ${controls} (${k("tenant")}, ${k("framework")});${
    ctx.has("controls", "owner")
      ? `
create index if not exists ${name("controls", "owner_idx")} on ${controls} (${k("tenant")}, ${k("owner")}) where ${k("owner")} is not null;`
      : ""
  }
${lockTable(controls, { read: true })}
${readPolicy("controls", ctx.scope.check(k("tenant"), read))}

create table if not exists ${tasks} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("control")} uuid not null,
  ${t("title")} text not null check (length(${t("title")}) between 1 and 200),${opt("tasks", "assignee", () => `${t("assignee")} uuid`)}
  -- Collecting evidence moves due_on this many days past the collection.
  ${t("intervalDays")} integer not null check (${t("intervalDays")} between 1 and 3650),
  ${t("dueOn")} date not null,${opt("tasks", "lastCollectedAt", () => `${t("lastCollectedAt")} timestamptz`)}
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  ${t("notifiedFor")} date,
  ${t("active")} boolean not null default true,${opt("tasks", "createdAt", () => `${t("createdAt")} timestamptz not null default now()`)}${opt("tasks", "updatedAt", () => `${t("updatedAt")} timestamptz not null default now()`)}
  foreign key (${t("tenant")}, ${t("control")}) references ${controls} (${k("tenant")}, ${k("id")}) on delete cascade
);
create index if not exists ${name("tasks", "parent_idx")} on ${tasks} (${t("tenant")}, ${t("control")});
${ctx.has("tasks", "assignee") ? `create index if not exists ${name("tasks", "assignee_idx")} on ${tasks} (${t("tenant")}, ${t("assignee")}, ${t("dueOn")}) where ${t("assignee")} is not null;\n` : ""}create index if not exists ${name("tasks", "due_idx")} on ${tasks} (${t("dueOn")}) where ${t("active")};
${lockTable(tasks, { read: true })}
${readPolicy("tasks", ctx.has("tasks", "assignee") ? `${t("assignee")} = (select auth.uid()) or ${ctx.scope.check(t("tenant"), read)}` : ctx.scope.check(t("tenant"), read))}

create table if not exists ${evidence} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("control")} uuid not null,
  ${e("task")} uuid references ${tasks} (${t("id")}) on delete set null,
  -- The file behind the evidence, an attachment on the control.
  ${e("attachment")} uuid${attachments === undefined ? "" : ` references ${attachments.table("attachments")} (${attachments.col("attachments", "id")}) on delete cascade`},${opt("evidence", "note", () => `${e("note")} text check (${e("note")} is null or length(${e("note")}) <= 4000)`)}
  ${e("collectedBy")} uuid,
  ${e("collectedAt")} timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  ${e("validUntil")} date,
  check (${e("attachment")} is not null${ctx.has("evidence", "note") ? ` or ${e("note")} is not null` : ""}),
  foreign key (${e("tenant")}, ${e("control")}) references ${controls} (${k("tenant")}, ${k("id")}) on delete cascade
);
create index if not exists ${name("evidence", "parent_idx")} on ${evidence} (${e("tenant")}, ${e("control")}, ${e("collectedAt")} desc);
create index if not exists ${name("evidence", "request_idx")} on ${evidence} (${e("task")}) where ${e("task")} is not null;
create index if not exists ${name("evidence", "attachment_idx")} on ${evidence} (${e("attachment")}) where ${e("attachment")} is not null;
${lockTable(evidence, { read: true })}
${readPolicy("evidence", ctx.scope.check(e("tenant"), read))}

create table if not exists ${policies} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("key")} text not null check (${p("key")} ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  ${p("title")} text not null check (length(${p("title")}) between 1 and 200),${opt("policies", "owner", () => `${p("owner")} uuid`)}
  ${p("requiresAck")} boolean not null default true,
  -- The published version (versions block), frozen.
  ${p("currentVersion")} uuid${versionRef},
  ${p("versionNumber")} integer,
  ${p("publishedAt")} timestamptz,
  ${p("archivedAt")} timestamptz,${opt("policies", "createdAt", () => `${p("createdAt")} timestamptz not null default now()`)}${opt("policies", "updatedAt", () => `${p("updatedAt")} timestamptz not null default now()`)}
  unique (${p("tenant")}, ${p("key")}),
  unique (${p("tenant")}, ${p("id")})
);${appKey("policies", "tenant_key", `${p("tenant")}, ${p("key")}`)}${appKey("policies", "tenant_id", `${p("tenant")}, ${p("id")}`)}
create index if not exists ${name("policies", "version_idx")} on ${policies} (${p("currentVersion")}) where ${p("currentVersion")} is not null;
${lockTable(policies, { read: true })}
${readPolicy("policies", ctx.scope.check(p("tenant"), read))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("versions").mode === "custom") {
    throw new TypeError(
      "blocks.compliance needs the versions tables; versions can't be in custom mode",
    );
  }

  if (ctx.of("acknowledgements").mode === "custom") {
    throw new TypeError(
      "blocks.compliance needs the acknowledgements tables; acknowledgements can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge
-- through the acknowledgements block.
${tables(ctx)}${complianceFunctions(ctx)}${policyFunctions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("controls", CONTROL_RESERVED),
  ).contract;

  return [
    {
      name: "save_control_framework",
      args: ["{id}", "text", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "list_control_frameworks", args: ["{id}"], returns: "jsonb" },
    {
      name: "save_control",
      args: [
        "uuid",
        "text",
        "text",
        "text",
        "uuid",
        "boolean",
        "uuid",
        "text",
        "text",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "get_control", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_controls",
      args: ["{id}", "uuid", "text", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "add_control_evidence",
      args: ["uuid", "uuid", "text", "date", "uuid"],
      returns: "jsonb",
    },
    { name: "remove_control_evidence", args: ["uuid"], returns: "jsonb" },
    {
      name: "save_evidence_task",
      args: ["uuid", "text", "integer", "date", "uuid", "boolean", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_evidence_tasks",
      args: ["{id}", "uuid", "uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "control_posture", args: ["{id}", "uuid"], returns: "jsonb" },
    { name: "notify_overdue_evidence_tasks", args: [], returns: "integer" },
    {
      name: "save_compliance_policy",
      args: ["{id}", "text", "text", "uuid", "boolean", "uuid"],
      returns: "jsonb",
    },
    {
      name: "publish_compliance_policy",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "archive_compliance_policy", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_compliance_policies",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  acknowledgements: (own) => {
    const policies = own.tableName("policies");

    return [
      {
        subject: entityType(own.resolved, "compliance_policy"),
        versionColumn: own.colName("policies", "currentVersion"),
        record: {
          table: `${policies.schema}.${policies.name}`,
          idType: "uuid",
          tenant: own.colName("policies", "tenant"),
          permission: own.permissionKey(
            "read",
            moduleOperations("compliance").read,
          ),
        },
      },
    ];
  },
};

const TO_ACKNOWLEDGEMENTS: BlockSqlUpgrade = {
  from: 1,
  description:
    "Policy acknowledgements move onto the acknowledgements block: each policy_acknowledgements row becomes an acknowledgement of the policy's version, every live policy that requires acknowledgement is assigned to every member, and policy_acknowledgements, acknowledge_compliance_policy and compliance_policy_acknowledgements go.",
  sql: (ctx) => {
    const acknowledgements = ctx.of("acknowledgements");

    if (ctx.mode === "custom" || acknowledgements.mode === "custom") {
      return "";
    }

    const acks = acknowledgements.table("acknowledgements");
    const assignments = acknowledgements.table("assignments");

    const a = (column: string): string =>
      acknowledgements.col("acknowledgements", column);

    const g = (column: string): string =>
      acknowledgements.col("assignments", column);

    const p = (column: string): string => ctx.col("policies", column);
    const old = `${ctx.schema}.policy_acknowledgements`;
    const type = sqlString(entityType(ctx.resolved, "compliance_policy"));

    return `-- The acknowledgements tables, so the policy acknowledgements can move before the module files run.
${acknowledgementTables(acknowledgements)}

do $$
begin
  if to_regclass(${sqlString(ctx.table("policies"))}) is null then
    return;
  end if;
  insert into ${assignments} (${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("principalType")}, ${g("principalId")})
  select x.${p("tenant")}, ${type}, x.${p("id")}::text, 'role', ${sqlString(POLICY_ROLE)}
  from ${ctx.table("policies")} x
  where x.${p("requiresAck")} and x.${p("archivedAt")} is null
  on conflict (${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("principalType")}, ${g("principalId")}) do nothing;
end;
$$;

do $$
begin
  if to_regclass(${sqlString(old)}) is null then
    return;
  end if;
  insert into ${acks} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("version")}, ${a("user")}, ${a("acknowledgedAt")})
  select x.tenant_id, ${type}, x.policy_id::text, x.version_id, x.user_id, x.acknowledged_at
  from ${old} x
  on conflict (${a("subjectType")}, ${a("subjectId")}, ${a("version")}, ${a("user")}) do nothing;
  drop table ${old} cascade;
end;
$$;

drop function if exists ${ctx.fn("acknowledge_compliance_policy")}(uuid);
drop function if exists ${ctx.fn("compliance_policy_acknowledgements")}(uuid);
drop function if exists ${ctx.fn("list_compliance_policies")}(${ctx.idType}, boolean, boolean);`;
  },
};

const DEPRECATED: readonly BlockSqlDeprecation[] = [
  {
    kind: "table",
    symbol: "better_supabase.policy_acknowledgements",
    use: "better_supabase.acknowledgements (subject_type compliance_policy)",
    since: "0.47.0",
    removed: "0.47.0",
  },
  {
    kind: "function",
    symbol: "better_supabase.acknowledge_compliance_policy",
    use: "better_supabase.acknowledge('compliance_policy', policy_id)",
    since: "0.47.0",
    removed: "0.47.0",
  },
  {
    kind: "function",
    symbol: "better_supabase.compliance_policy_acknowledgements",
    use: "better_supabase.acknowledgement_status('compliance_policy', policy_id) and acknowledgements_of",
    since: "0.47.0",
    removed: "0.47.0",
  },
];

export const COMPLIANCE: BlockSqlDefinition = {
  name: "compliance",
  scopes: ["tenant"],
  title: "Compliance controls",
  description:
    "Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge through the acknowledgements block.",
  requires: ["memberships", "permissions", "versions", "acknowledgements"],
  integrates: ["attachments", "notifications", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [TO_ACKNOWLEDGEMENTS],
  deprecated: DEPRECATED,
  names: NAMES,
  contract,
  build,
  contributes: CONTRIBUTES,
  data: (ctx, layout) =>
    [subjectTypeRenames(ctx, layout), widenPolicyAssignments(ctx)]
      .filter((part) => part !== "")
      .join("\n\n"),
};
