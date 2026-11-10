import type { DeadlinesEvents } from "../../blocks/deadlines/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type {
  BlockSqlDefinition,
  BlockSqlDeprecation,
  BlockSqlLayout,
  BlockSqlUpgrade,
} from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  sha256HexSql,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";
import { inlineSubjectReadable } from "./attachments-app.ts";
import { evaluatorSql } from "./deadlines-evaluator.ts";
import { validatorSql } from "./deadlines-validator.ts";
import {
  DEADLINE_RESULTS,
  DEADLINE_STATES,
  RULE_VERSION_STATUSES,
} from "./deadlines-values.ts";
import { OPERATIONS } from "./permissions-model.ts";

const PAYLOAD = [
  "organizationId",
  "id",
  "subjectType",
  "subjectId",
  "groupKey",
  "ruleKey",
  "period",
  "result",
  "dueOn",
  "provisional",
] as const;

const deadline = { subject: "deadlines", payload: [...PAYLOAD] } as const;

const EVENTS: BlockSqlEvents<DeadlinesEvents> = {
  "deadline.computed": deadline,
  "deadline.satisfied": deadline,
};

const NAMES: BlockSqlNames = {
  entities: {
    deadline: { table: "deadlines", singular: "deadline", primary: true },
  },
  events: EVENTS,
  hooks: [],
  options: [],
  tables: {
    ruleSets: {
      name: "deadline_rule_sets",
      app: {},
      columns: {
        id: "id",
        jurisdiction: "jurisdiction",
        kind: "kind",
        title: "title",
        createdAt: "created_at",
      },
    },
    ruleVersions: {
      name: "deadline_rule_versions",
      app: {},
      columns: {
        id: "id",
        ruleSet: "rule_set_id",
        version: "version",
        status: "status",
        rules: "rules",
        groups: "groups",
        counting: "counting",
        meta: "meta",
        contentHash: "content_hash",
        effectiveFrom: "effective_from",
        approvedBy: "approved_by",
        approvedAt: "approved_at",
        approvalId: "approval_id",
        createdAt: "created_at",
      },
    },
    deadlines: {
      name: "deadlines",
      app: {},
      lifecycle: { tenant: "tenant", user: "satisfiedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        jurisdiction: "jurisdiction",
        kind: "kind",
        groupKey: "group_key",
        ruleKey: "rule_key",
        period: "period",
        ruleVersion: "rule_version_id",
        facts: "facts",
        result: "result",
        dueOn: "due_on",
        provisional: "provisional",
        missing: "missing",
        exception: "exception",
        review: "review",
        basis: "basis",
        deadline: "deadline",
        citation: "citation",
        asOf: "as_of",
        state: "state",
        satisfiedAt: "satisfied_at",
        satisfiedBy: "satisfied_by",
        satisfiedAction: "satisfied_action",
        computedAt: "computed_at",
        createdAt: "created_at",
      },
    },
  },
};

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The SHA-256 of a version's content, shared by approval and the upgrade. */
function contentHashSql(ctx: BlockSqlContext): string {
  return `-- The SHA-256 content hash of a rule set version: its rules, groups,
-- counting block and meta.
create or replace function ${ctx.fn("version_content_hash")}(rules jsonb, groups jsonb, counting jsonb, meta jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select ${sha256HexSql("convert_to(jsonb_build_object('rules', rules, 'groups', groups, 'counting', counting, 'meta', meta)::text, 'UTF8')")}
$$;
${triggerGrant(`${ctx.fn("version_content_hash")}(jsonb, jsonb, jsonb, jsonb)`)}`;
}

/**
 * Converts a rule of the version 1 shape (anchor and offset) to a rule and its
 * group.
 */
function fromV1Sql(ctx: BlockSqlContext): string {
  return `-- A rule of the version 1 shape (anchor, offset, requires) as a rule of
-- its own group: the offset counts from the anchor, or before it when it is
-- negative, and each required fact must be present.
create or replace function ${ctx.fn("deadline_rule_from_v1")}(rule jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
      'key', rule -> 'key',
      'group', rule -> 'key',
      'deadline', jsonb_build_object(
        'n', abs((rule #>> '{offset,amount}')::integer),
        'unit', rule #> '{offset,unit}',
        case when (rule #>> '{offset,amount}')::integer < 0 then 'before' else 'from' end, rule -> 'anchor'),
      'citation', rule -> 'citation')
    || case when rule ? 'title' then jsonb_build_object('title', rule -> 'title') else '{}'::jsonb end
    || case when rule ? 'adjust' then jsonb_build_object('adjust', rule -> 'adjust') else '{}'::jsonb end
    || coalesce((
      select jsonb_build_object('applies', jsonb_object_agg(r.name, 'present'))
      from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'requires') = 'array' then rule -> 'requires' else '[]'::jsonb end) r(name)
      having count(*) > 0
    ), '{}'::jsonb)
$$;
${triggerGrant(`${ctx.fn("deadline_rule_from_v1")}(jsonb)`)}`;
}

const TO_GROUPS: BlockSqlUpgrade = {
  from: 1,
  description:
    "Rule set versions take groups, a counting block and meta, and rules move to the v2 grammar: each version 1 rule (anchor, offset) becomes a rule of its own group, and an approved version keeps its old hash in meta.previous_content_hash. Deadlines gain group_key (backfilled from rule_key), period, provisional, exception, review, basis, deadline and as_of; save_rule_version takes the content, and the per-rule unique constraint gives way to a unique index per group and period.",
  sql: (ctx) => {
    if (ctx.mode === "custom") {
      return "";
    }

    const v = (column: string): string => ctx.col("ruleVersions", column);
    const d = (column: string): string => ctx.col("deadlines", column);
    const versions = ctx.table("ruleVersions");
    const deadlines = ctx.table("deadlines");
    const name = ctx.tableName("deadlines").name;

    return `${contentHashSql(ctx)}

${fromV1Sql(ctx)}

do $$
begin
  if to_regclass(${sqlString(versions)}) is null then
    return;
  end if;
  alter table ${versions} add column if not exists ${v("groups")} jsonb not null default '[]'::jsonb;
  alter table ${versions} add column if not exists ${v("counting")} jsonb;
  alter table ${versions} add column if not exists ${v("meta")} jsonb;
  alter table ${deadlines} add column if not exists ${d("groupKey")} text;
  alter table ${deadlines} add column if not exists ${d("period")} text check (${d("period")} ~ '^[0-9]{4}-[0-9]{2}$');
  alter table ${deadlines} add column if not exists ${d("provisional")} boolean not null default false;
  alter table ${deadlines} add column if not exists ${d("exception")} jsonb;
  alter table ${deadlines} add column if not exists ${d("review")} jsonb not null default '[]'::jsonb;
  alter table ${deadlines} add column if not exists ${d("basis")} jsonb;
  alter table ${deadlines} add column if not exists ${d("deadline")} jsonb;
  alter table ${deadlines} add column if not exists ${d("asOf")} date not null default current_date;
  update ${deadlines} set ${d("groupKey")} = ${d("ruleKey")} where ${d("groupKey")} is null;
  alter table ${deadlines} alter column ${d("groupKey")} set not null;
  alter table ${deadlines} alter column ${d("ruleKey")} drop not null;
  alter table ${deadlines} drop constraint if exists ${sqlIdent(`${name}_result_check`)};
  alter table ${deadlines} add constraint ${sqlIdent(`${name}_result_check`)} check (${d("result")} in (${quoted(DEADLINE_RESULTS)}));
  alter table ${deadlines} drop constraint if exists ${sqlIdent(`${name}_period_due_check`)};
  alter table ${deadlines} add constraint ${sqlIdent(`${name}_period_due_check`)} check (${d("period")} is null or ${d("result")} = 'due');
  alter table ${deadlines} drop constraint if exists ${sqlIdent(`${name}_subject_rule_key`)};

  alter table ${versions} disable trigger bsb_deadlines_version_frozen;
  with converted as (
    select x.${v("id")} as id,
      (select jsonb_agg(${ctx.fn("deadline_rule_from_v1")}(r.value) order by r.ord) from jsonb_array_elements(x.${v("rules")}) with ordinality r(value, ord)) as rules,
      (select jsonb_agg(jsonb_build_object('key', r.value -> 'key', 'citation', r.value -> 'citation') order by r.ord) from jsonb_array_elements(x.${v("rules")}) with ordinality r(value, ord)) as groups,
      case when x.${v("status")} = 'approved'
        then coalesce(x.${v("meta")}, '{}'::jsonb) || jsonb_build_object('previous_content_hash', x.${v("contentHash")})
        else x.${v("meta")} end as meta
    from ${versions} x
    where exists (select 1 from jsonb_array_elements(x.${v("rules")}) r(value) where r.value ? 'anchor')
  )
  update ${versions} x set ${v("rules")} = c.rules, ${v("groups")} = c.groups, ${v("meta")} = c.meta,
    ${v("contentHash")} = case when x.${v("status")} = 'approved'
      then ${ctx.fn("version_content_hash")}(c.rules, c.groups, x.${v("counting")}, c.meta) else x.${v("contentHash")} end
  from converted c where x.${v("id")} = c.id;
  alter table ${versions} enable trigger bsb_deadlines_version_frozen;
end;
$$;

drop function if exists ${ctx.fn("save_rule_version")}(text, text, jsonb, date, text);
drop function if exists ${ctx.fn("validate_deadline_rules")}(jsonb);`;
  },
};

const DEPRECATED: readonly BlockSqlDeprecation[] = [
  {
    kind: "function",
    symbol: "better_supabase.evaluate_deadline_rule",
    use: "better_supabase.evaluate_deadlines(content, facts, as_of, group_key); removed in 0.58",
    since: "0.56.0",
    wrapper: (
      ctx,
    ) => `create or replace function ${ctx.fn("evaluate_deadline_rule")}(rule jsonb, facts jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_rule jsonb := case when rule ? 'anchor' then ${ctx.fn("deadline_rule_from_v1")}(rule) else rule end;
  v_result jsonb;
begin
  v_result := ${ctx.fn("evaluate_deadlines")}(
    jsonb_build_object('rules', jsonb_build_array(v_rule),
      'groups', jsonb_build_array(jsonb_build_object('key', v_rule -> 'group', 'citation', v_rule -> 'citation'))),
    coalesce(facts, '{}'::jsonb), current_date) -> 0;
  if v_result ->> 'result' = 'due' then
    return jsonb_build_object('status', 'due', 'dueOn', v_result -> 'dueOn');
  end if;
  return jsonb_build_object('status', 'unknown', 'missing', v_result -> 'missing');
end;
$$;
comment on function ${ctx.fn("evaluate_deadline_rule")}(jsonb, jsonb) is 'deprecated: use evaluate_deadlines';
${userGrant(`${ctx.fn("evaluate_deadline_rule")}(jsonb, jsonb)`)}`,
  },
  {
    kind: "function",
    symbol: "better_supabase.compute_deadline",
    use: "better_supabase.compute_deadlines(..., group_key); removed in 0.58",
    since: "0.56.0",
    wrapper: (
      ctx,
    ) => `create or replace function ${ctx.fn("compute_deadline")}(tenant ${ctx.idType}, subject_type text, subject_id text, jurisdiction text, kind text, rule_key text, facts jsonb default '{}', as_of date default current_date)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${ctx.fn("compute_deadlines")}(tenant, subject_type, subject_id, jurisdiction, kind, facts, as_of, rule_key) -> 0
$$;
comment on function ${ctx.fn("compute_deadline")}(${ctx.idType}, text, text, text, text, text, jsonb, date) is 'deprecated: use compute_deadlines';
${userGrant(`${ctx.fn("compute_deadline")}(${ctx.idType}, text, text, text, text, text, jsonb, date)`)}`,
  },
];

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const idType = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const s = (column: string): string => ctx.col("ruleSets", column);
  const v = (column: string): string => ctx.col("ruleVersions", column);
  const d = (column: string): string => ctx.col("deadlines", column);
  const sets = ctx.table("ruleSets");
  const versions = ctx.table("ruleVersions");
  const deadlines = ctx.table("deadlines");
  const deadlinesName = ctx.tableName("deadlines").name;
  const read = ctx.permission("read", OPERATIONS["deadlines.read"]);
  const write = ctx.permission("write", OPERATIONS["deadlines.write"]);

  const approvals = ctx.installed("approvals")
    ? ctx.of("approvals")
    : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const subjects = subjectsOption(ctx);

  const visible = (type: string, id: string, tenant: string): string =>
    `(${SERVICE_CALLER} or ${fn("deadline_subject_readable")}(${type}, ${id}, ${tenant}))`;

  const serviceOnly = (what: string): string =>
    `if not ${SERVICE_CALLER} then
    ${fail("DEADLINE_FORBIDDEN", `only the service role may ${what}`)}
  end if;`;

  const missing = fail("DEADLINE_NOT_FOUND", "no such deadline", "P0002");

  const content = (row: string): string =>
    `jsonb_build_object('rules', ${row}.${v("rules")}, 'groups', ${row}.${v("groups")}) || case when ${row}.${v("counting")} is null then '{}'::jsonb else jsonb_build_object('counting', ${row}.${v("counting")}) end || case when ${row}.${v("meta")} is null then '{}'::jsonb else jsonb_build_object('meta', ${row}.${v("meta")}) end`;

  const versionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${v("id")}, 'jurisdiction', (select z.${s("jurisdiction")} from ${sets} z where z.${s("id")} = ${row}.${v("ruleSet")}), 'kind', (select z.${s("kind")} from ${sets} z where z.${s("id")} = ${row}.${v("ruleSet")}), 'version', ${row}.${v("version")}, 'status', ${row}.${v("status")}, 'rules', ${row}.${v("rules")}, 'groups', ${row}.${v("groups")}, 'counting', ${row}.${v("counting")}, 'meta', ${row}.${v("meta")}, 'contentHash', ${row}.${v("contentHash")}, 'effectiveFrom', ${row}.${v("effectiveFrom")}, 'approvedBy', ${row}.${v("approvedBy")}, 'approvedAt', ${row}.${v("approvedAt")}, 'createdAt', ${row}.${v("createdAt")})`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'subjectType', ${row}.${d("subjectType")}, 'subjectId', ${row}.${d("subjectId")}, 'jurisdiction', ${row}.${d("jurisdiction")}, 'kind', ${row}.${d("kind")}, 'groupKey', ${row}.${d("groupKey")}, 'ruleKey', ${row}.${d("ruleKey")}, 'period', ${row}.${d("period")}, 'ruleVersionId', ${row}.${d("ruleVersion")}, 'ruleVersion', (select x.${v("version")} from ${versions} x where x.${v("id")} = ${row}.${d("ruleVersion")}), 'facts', ${row}.${d("facts")}, 'result', ${row}.${d("result")}, 'dueOn', ${row}.${d("dueOn")}, 'provisional', ${row}.${d("provisional")}, 'missing', to_jsonb(${row}.${d("missing")}), 'exception', ${row}.${d("exception")}, 'review', ${row}.${d("review")}, 'basis', ${row}.${d("basis")}, 'deadline', ${row}.${d("deadline")}, 'citation', ${row}.${d("citation")}, 'asOf', ${row}.${d("asOf")}, 'state', ${row}.${d("state")}, 'satisfiedAt', ${row}.${d("satisfiedAt")}, 'satisfiedBy', ${row}.${d("satisfiedBy")}, 'satisfiedAction', ${row}.${d("satisfiedAction")}, 'computedAt', ${row}.${d("computedAt")}, 'createdAt', ${row}.${d("createdAt")})`;

  const payload = (row: string): string =>
    `jsonb_build_object('organizationId', ${row}.${d("tenant")}, 'id', ${row}.${d("id")}, 'subjectType', ${row}.${d("subjectType")}, 'subjectId', ${row}.${d("subjectId")}, 'groupKey', ${row}.${d("groupKey")}, 'ruleKey', ${row}.${d("ruleKey")}, 'period', ${row}.${d("period")}, 'result', ${row}.${d("result")}, 'dueOn', ${row}.${d("dueOn")}, 'provisional', ${row}.${d("provisional")})`;

  const record = (
    type: "deadline.computed" | "deadline.satisfied",
    row: string,
  ): string =>
    ctx.record({
      type,
      payload: payload(row),
      subject: `'deadlines/' || ${row}.${d("id")}::text`,
      tenant: `${row}.${d("tenant")}`,
      audit: {
        category: "data",
        targetType: "deadline",
        recordId: `${row}.${d("id")}::text`,
        targetLabel: `${row}.${d("groupKey")} || coalesce(' ' || ${row}.${d("period")}, '') || ' ' || ${row}.${d("subjectType")} || '/' || ${row}.${d("subjectId")}`,
        summary: sqlString(type.replace("deadline.", "deadline ")),
      },
    });

  const approvalCheck =
    approvals === undefined
      ? ""
      : `if approve_rule_version.approval_id is null then
    ${fail("DEADLINE_APPROVAL_REQUIRED", "a rule set version is approved through an approval request", "55000")}
  end if;
  select r.${approvals.col("requests", "status")} into v_status from ${approvals.table("requests")} r
  where r.${approvals.col("requests", "id")} = approve_rule_version.approval_id
    and r.${approvals.col("requests", "subjectType")} = 'deadline_rule_version'
    and r.${approvals.col("requests", "subjectId")} = approve_rule_version.version_id::text;
  if v_status is distinct from 'approved' then
    ${fail("DEADLINE_APPROVAL_REQUIRED", "the approval request for this version is not approved", "55000")}
  end if;`;

  const policyOf = (table: string, name: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table,
        name: sqlIdent(name),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { target: table },
    );

  // The policy inlines the check over the row's columns (ADR 0644); the
  // function stays for the types a later module's table holds and for the
  // write paths. Without subjects every subject passes.
  const own = (column: string): string => `${deadlines}.${d(column)}`;

  const subjectPolicy = inlineSubjectReadable(
    ctx,
    layout,
    subjects,
    {
      type: own("subjectType"),
      id: own("subjectId"),
      tenant: own("tenant"),
      fallback: `${fn("deadline_subject_readable")}(${own("subjectType")}, ${own("subjectId")}, ${own("tenant")})`,
    },
    { module: "deadlines", guest: false, typeNotNull: true },
  );

  const readPolicy = renderPolicy(
    makePolicy({
      table: deadlines,
      name: sqlIdent(`${deadlinesName}_read`),
      command: "select",
      roles: ["authenticated"],
      using: `${ctx.scope.check(d("tenant"), read)} and ${subjectPolicy}`,
    }),
    { target: deadlines },
  );

  const appKey = ctx.owns("deadlines")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${deadlinesName}_tenant_id_key`)} on ${deadlines} (${d("tenant")}, ${d("id")});`;

  const periodKey = `(${d("tenant")}, ${d("subjectType")}, ${d("subjectId")}, ${d("groupKey")}, (coalesce(${d("period")}, '')))`;

  return `${schemaPreamble(ctx)}
-- Deadlines: rule sets owned by the platform (no tenant), versioned and approved
-- once, and the deadlines computed from a subject's facts. A version is data:
-- ordered groups, ordered rules with conditions, exceptions and a deadline
-- grammar, a counting block with holidays, and opaque meta. Each group yields
-- one deadline per subject (one per month for a periodic rule): due on a
-- date, unknown with the facts it waits for, pending, undated, or refused as
-- not covered, not applicable, not required or barred.
create table if not exists ${sets} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("jurisdiction")} text not null check (${s("jurisdiction")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${s("kind")} text not null check (${s("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${s("title")} text check (${s("title")} is null or length(${s("title")}) <= 200),
  ${s("createdAt")} timestamptz not null default now(),
  constraint ${sqlIdent(`${ctx.tableName("ruleSets").name}_key`)} unique (${s("jurisdiction")}, ${s("kind")})
);
${lockTable(sets, { read: true })}
${policyOf(sets, `${ctx.tableName("ruleSets").name}_read`, "true")}

create table if not exists ${versions} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("ruleSet")} uuid not null references ${sets} (${s("id")}) on delete cascade,
  ${v("version")} integer not null check (${v("version")} >= 1),
  ${v("status")} text not null default 'draft' check (${v("status")} in (${quoted(RULE_VERSION_STATUSES)})),
  ${v("rules")} jsonb not null,
  ${v("groups")} jsonb not null default '[]'::jsonb,
  ${v("counting")} jsonb,
  ${v("meta")} jsonb,
  ${v("contentHash")} text,
  ${v("effectiveFrom")} date,
  ${v("approvedBy")} uuid,
  ${v("approvedAt")} timestamptz,
  ${v("approvalId")} uuid,
  ${v("createdAt")} timestamptz not null default now(),
  unique (${v("ruleSet")}, ${v("version")}),
  check (${v("status")} = 'draft' or (${v("contentHash")} is not null and ${v("effectiveFrom")} is not null and ${v("approvedAt")} is not null))
);
create index if not exists ${sqlIdent(`${ctx.tableName("ruleVersions").name}_effective_idx`)} on ${versions} (${v("ruleSet")}, ${v("effectiveFrom")} desc) where ${v("status")} = 'approved';
${lockTable(versions, { read: true })}
${policyOf(versions, `${ctx.tableName("ruleVersions").name}_read`, `${v("status")} = 'approved'`)}

-- An approved version never changes and is never deleted.
create or replace function ${fn("deadline_version_frozen")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.${v("status")} = 'approved' then
    ${fail("DEADLINE_RULE_VERSION_FROZEN", "an approved rule set version never changes", "23000")}
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("deadline_version_frozen")}()`)}
drop trigger if exists bsb_deadlines_version_frozen on ${versions};
create trigger bsb_deadlines_version_frozen
  before update or delete on ${versions}
  for each row execute function ${fn("deadline_version_frozen")}();

create table if not exists ${deadlines} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${idType} not null,
  ${d("subjectType")} text not null check (${d("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${d("subjectId")} text not null check (length(${d("subjectId")}) between 1 and 200),
  ${d("jurisdiction")} text not null,
  ${d("kind")} text not null,
  ${d("groupKey")} text not null,
  ${d("ruleKey")} text,
  ${d("period")} text check (${d("period")} ~ '^[0-9]{4}-[0-9]{2}$'),
  ${d("ruleVersion")} uuid not null references ${versions} (${v("id")}) on delete restrict,
  ${d("facts")} jsonb not null default '{}'::jsonb,
  ${d("result")} text not null,
  ${d("dueOn")} date,
  ${d("provisional")} boolean not null default false,
  ${d("missing")} text[] not null default '{}',
  ${d("exception")} jsonb,
  ${d("review")} jsonb not null default '[]'::jsonb,
  ${d("basis")} jsonb,
  ${d("deadline")} jsonb,
  ${d("citation")} jsonb not null,
  ${d("asOf")} date not null default current_date,
  ${d("state")} text not null default 'pending' check (${d("state")} in (${quoted(DEADLINE_STATES)})),
  ${d("satisfiedAt")} timestamptz,
  ${d("satisfiedBy")} uuid,
  ${d("satisfiedAction")} text check (${d("satisfiedAction")} is null or length(${d("satisfiedAction")}) <= 200),
  ${d("computedAt")} timestamptz not null default now(),
  ${d("createdAt")} timestamptz not null default now(),
  constraint ${sqlIdent(`${deadlinesName}_result_check`)} check (${d("result")} in (${quoted(DEADLINE_RESULTS)})),
  check ((${d("result")} = 'due') = (${d("dueOn")} is not null)),
  constraint ${sqlIdent(`${deadlinesName}_period_due_check`)} check (${d("period")} is null or ${d("result")} = 'due')
);${appKey}
create unique index if not exists ${sqlIdent(`bsb_${deadlinesName}_subject_group_period_key`)} on ${deadlines} ${periodKey};
create index if not exists ${sqlIdent(`${deadlinesName}_version_idx`)} on ${deadlines} (${d("ruleVersion")});
create index if not exists ${sqlIdent(`${deadlinesName}_due_idx`)} on ${deadlines} (${d("tenant")}, ${d("dueOn")}) where ${d("state")} = 'pending';
${lockTable(deadlines, { read: true })}

-- Whether the caller may read the subject a deadline belongs to: its row is
-- visible to them (the subject table's own policies apply) and they hold its
-- read permission, as blocks.deadlines.on or config.subjects declares it.
-- Without subjects every subject passes; with them an unlisted type fails.
-- plpgsql, so a subject table a later module creates binds late.
create or replace function ${fn("deadline_subject_readable")}(subject_type text, subject_id text, tenant ${idType})
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return ${subjects.length === 0 ? "true" : `coalesce(${subjectReadable(ctx, subjects, { type: "deadline_subject_readable.subject_type", id: "deadline_subject_readable.subject_id", tenant: "deadline_subject_readable.tenant" })}, false)`};
end;
$$;
revoke execute on function ${fn("deadline_subject_readable")}(text, text, ${idType}) from public, anon;
grant execute on function ${fn("deadline_subject_readable")}(text, text, ${idType}) to authenticated, service_role;
${readPolicy}
${evaluatorSql(fn, userGrant, triggerGrant)}
${validatorSql(fn, userGrant, triggerGrant)}
${contentHashSql(ctx)}

${fromV1Sql(ctx)}

-- Saves a rule set version's content ({ rules, groups, counting?, meta? }) as
-- a new draft version, creating the rule set on first use. A draft is replaced
-- by the next save until it is approved. Service role only.
create or replace function ${fn("save_rule_version")}(jurisdiction text, kind text, content jsonb, effective_from date default null, title text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_set ${sets};
  v_row ${versions};
  v_issues text[];
  v_counting jsonb := case when jsonb_typeof(save_rule_version.content -> 'counting') = 'object' then save_rule_version.content -> 'counting' end;
  v_meta jsonb := case when jsonb_typeof(save_rule_version.content -> 'meta') = 'object' then save_rule_version.content -> 'meta' end;
begin
  ${serviceOnly("save rule set versions")}
  if save_rule_version.jurisdiction is null or save_rule_version.jurisdiction !~ '^[a-z][a-z0-9_-]{0,62}$'
    or save_rule_version.kind is null or save_rule_version.kind !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${fail("DEADLINE_RULES_INVALID", "a rule set has a lower case jurisdiction and kind", "22023")}
  end if;
  v_issues := ${fn("validate_deadline_rules")}(save_rule_version.content);
  if cardinality(v_issues) > 0 then
    raise exception 'invalid rules: %', array_to_string(v_issues, '; ') using errcode = '22023', hint = 'DEADLINE_RULES_INVALID', detail = jsonb_build_object('issues', to_jsonb(v_issues))::text;
  end if;
  insert into ${sets} (${s("jurisdiction")}, ${s("kind")}, ${s("title")})
  values (save_rule_version.jurisdiction, save_rule_version.kind, nullif(btrim(save_rule_version.title), ''))
  on conflict on constraint ${sqlIdent(`${ctx.tableName("ruleSets").name}_key`)} do update set ${s("title")} = coalesce(nullif(btrim(save_rule_version.title), ''), ${sets}.${s("title")})
  returning * into v_set;
  select * into v_row from ${versions} x
  where x.${v("ruleSet")} = v_set.${s("id")} and x.${v("status")} = 'draft'
  order by x.${v("version")} desc limit 1 for update;
  if found then
    update ${versions} x set ${v("rules")} = save_rule_version.content -> 'rules', ${v("groups")} = save_rule_version.content -> 'groups',
      ${v("counting")} = v_counting, ${v("meta")} = v_meta, ${v("effectiveFrom")} = save_rule_version.effective_from
    where x.${v("id")} = v_row.${v("id")} returning * into v_row;
  else
    insert into ${versions} (${v("ruleSet")}, ${v("version")}, ${v("rules")}, ${v("groups")}, ${v("counting")}, ${v("meta")}, ${v("effectiveFrom")})
    values (v_set.${s("id")}, coalesce((select max(y.${v("version")}) from ${versions} y where y.${v("ruleSet")} = v_set.${s("id")}), 0) + 1,
      save_rule_version.content -> 'rules', save_rule_version.content -> 'groups', v_counting, v_meta, save_rule_version.effective_from)
    returning * into v_row;
  end if;
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("save_rule_version")}(text, text, jsonb, date, text)`)}

-- Approves a draft version: freezes its content with a SHA-256 content hash and
-- records who approved it and from which date it applies. ${approvals === undefined ? "" : "The approval request (subject type deadline_rule_version, subject id the version id) must be approved. "}Service role only.
create or replace function ${fn("approve_rule_version")}(version_id uuid, approval_id uuid default null, effective_from date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${versions};
  v_status text;
  v_from date;
begin
  ${serviceOnly("approve rule set versions")}
  select * into v_row from ${versions} x where x.${v("id")} = approve_rule_version.version_id for update;
  if not found then
    ${fail("DEADLINE_RULES_NOT_FOUND", "no such rule set version", "P0002")}
  end if;
  if v_row.${v("status")} = 'approved' then
    return ${versionJson("v_row")};
  end if;
  v_from := coalesce(approve_rule_version.effective_from, v_row.${v("effectiveFrom")});
  if v_from is null then
    ${fail("DEADLINE_RULES_INVALID", "an approved version needs the date it applies from", "22023")}
  end if;
  ${approvalCheck}
  update ${versions} x set
    ${v("status")} = 'approved',
    ${v("effectiveFrom")} = v_from,
    ${v("contentHash")} = ${fn("version_content_hash")}(v_row.${v("rules")}, v_row.${v("groups")}, v_row.${v("counting")}, v_row.${v("meta")}),
    ${v("approvedBy")} = auth.uid(),
    ${v("approvedAt")} = now(),
    ${v("approvalId")} = approve_rule_version.approval_id
  where x.${v("id")} = v_row.${v("id")} returning * into v_row;
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("approve_rule_version")}(uuid, uuid, date)`)}

-- The approved version of a rule set that applies on a date: the latest one
-- that takes effect on or before it, or null.
create or replace function ${fn("rule_version_at")}(jurisdiction text, kind text, on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${versions};
begin
  select x.* into v_row from ${versions} x
  join ${sets} z on z.${s("id")} = x.${v("ruleSet")}
  where z.${s("jurisdiction")} = rule_version_at.jurisdiction and z.${s("kind")} = rule_version_at.kind
    and x.${v("status")} = 'approved' and x.${v("effectiveFrom")} <= rule_version_at.on_date
  order by x.${v("effectiveFrom")} desc, x.${v("version")} desc limit 1;
  if not found then
    return null;
  end if;
  return ${versionJson("v_row")};
end;
$$;
${userGrant(`${fn("rule_version_at")}(text, text, date)`)}

-- Stores evaluated results for a subject: one row per group and period,
-- upserted on the unique index. A satisfied row stays as it is; a pending row
-- of the groups whose results these are and that has no result any more is
-- deleted. Records deadline.computed for every row it inserts or changes, and
-- returns { rows, changed }. The callers check permissions.
create or replace function ${fn("deadline_store")}(p_tenant ${idType}, p_subject_type text, p_subject_id text, p_jurisdiction text, p_kind text, p_version_id uuid, p_facts jsonb, p_as_of date, p_results jsonb, p_group_keys text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_row ${deadlines};
  v_rows jsonb := '[]'::jsonb;
  v_changed integer := 0;
  v_missing text[];
  v_deleted integer;
begin
  for v_result in select e.value from jsonb_array_elements(p_results) e(value) loop
    v_missing := array(select jsonb_array_elements_text(v_result -> 'missing'));
    select * into v_row from ${deadlines} x
    where x.${d("tenant")} = p_tenant and x.${d("subjectType")} = p_subject_type
      and x.${d("subjectId")} = p_subject_id and x.${d("groupKey")} = v_result ->> 'group'
      and coalesce(x.${d("period")}, '') = coalesce(v_result ->> 'period', '')
    for update;
    if found and (v_row.${d("state")} = 'satisfied' or (
      v_row.${d("ruleVersion")} = p_version_id and v_row.${d("facts")} = p_facts
      and v_row.${d("ruleKey")} is not distinct from v_result ->> 'ruleKey' and v_row.${d("result")} = v_result ->> 'result'
      and v_row.${d("dueOn")} is not distinct from (v_result ->> 'dueOn')::date and v_row.${d("provisional")} = (v_result -> 'provisional')::boolean
      and v_row.${d("missing")} = v_missing and v_row.${d("exception")} is not distinct from nullif(v_result -> 'exception', 'null'::jsonb)
      and v_row.${d("review")} = v_result -> 'review' and v_row.${d("basis")} is not distinct from nullif(v_result -> 'basis', 'null'::jsonb)
      and v_row.${d("deadline")} is not distinct from nullif(v_result -> 'deadline', 'null'::jsonb) and v_row.${d("citation")} = v_result -> 'citation')) then
      v_rows := v_rows || ${json("v_row")};
      continue;
    end if;
    insert into ${deadlines} (${d("tenant")}, ${d("subjectType")}, ${d("subjectId")}, ${d("jurisdiction")}, ${d("kind")}, ${d("groupKey")}, ${d("ruleKey")}, ${d("period")},
      ${d("ruleVersion")}, ${d("facts")}, ${d("result")}, ${d("dueOn")}, ${d("provisional")}, ${d("missing")}, ${d("exception")}, ${d("review")}, ${d("basis")}, ${d("deadline")}, ${d("citation")}, ${d("asOf")})
    values (p_tenant, p_subject_type, p_subject_id, p_jurisdiction, p_kind,
      v_result ->> 'group', v_result ->> 'ruleKey', v_result ->> 'period', p_version_id, p_facts,
      v_result ->> 'result', (v_result ->> 'dueOn')::date, (v_result -> 'provisional')::boolean, v_missing,
      nullif(v_result -> 'exception', 'null'::jsonb), v_result -> 'review', nullif(v_result -> 'basis', 'null'::jsonb),
      nullif(v_result -> 'deadline', 'null'::jsonb), v_result -> 'citation', p_as_of)
    on conflict ${periodKey} do update set
      ${d("jurisdiction")} = excluded.${d("jurisdiction")}, ${d("kind")} = excluded.${d("kind")}, ${d("ruleKey")} = excluded.${d("ruleKey")},
      ${d("ruleVersion")} = excluded.${d("ruleVersion")}, ${d("facts")} = excluded.${d("facts")}, ${d("result")} = excluded.${d("result")},
      ${d("dueOn")} = excluded.${d("dueOn")}, ${d("provisional")} = excluded.${d("provisional")}, ${d("missing")} = excluded.${d("missing")},
      ${d("exception")} = excluded.${d("exception")}, ${d("review")} = excluded.${d("review")}, ${d("basis")} = excluded.${d("basis")},
      ${d("deadline")} = excluded.${d("deadline")}, ${d("citation")} = excluded.${d("citation")}, ${d("asOf")} = excluded.${d("asOf")},
      ${d("computedAt")} = now()
    returning * into v_row;
    ${record("deadline.computed", "v_row")}
    v_rows := v_rows || ${json("v_row")};
    v_changed := v_changed + 1;
  end loop;
  delete from ${deadlines} x
  where x.${d("tenant")} = p_tenant and x.${d("subjectType")} = p_subject_type
    and x.${d("subjectId")} = p_subject_id and x.${d("state")} = 'pending'
    and x.${d("groupKey")} = any (p_group_keys)
    and not exists (
      select 1 from jsonb_array_elements(p_results) r(value)
      where r.value ->> 'group' = x.${d("groupKey")} and coalesce(r.value ->> 'period', '') = coalesce(x.${d("period")}, '')
    );
  get diagnostics v_deleted = row_count;
  return jsonb_build_object('rows', v_rows, 'changed', v_changed + v_deleted);
end;
$$;
${triggerGrant(`${fn("deadline_store")}(${idType}, text, text, text, text, uuid, jsonb, date, jsonb, text[])`)}

-- Computes a subject's deadlines from its facts with the rule set version that
-- applies on as_of (today by default): every group of the version, or only
-- group_key, and stores one row per group (one per month for a periodic
-- rule). Returns the rows. A satisfied row is returned unchanged and kept as
-- history. Without group_key, a pending row of this jurisdiction and kind
-- that the evaluation no longer yields (its group was dropped or yields no
-- row) is deleted. Needs deadlines.write and read access to the subject.
create or replace function ${fn("compute_deadlines")}(tenant ${idType}, subject_type text, subject_id text, jurisdiction text, kind text, facts jsonb default '{}', as_of date default current_date, group_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_version jsonb;
  v_results jsonb;
begin
  if not ${allowed("compute_deadlines.tenant", write)} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to compute deadlines")}
  end if;
  if compute_deadlines.subject_type is null or compute_deadlines.subject_type !~ '^[a-z][a-z0-9_]{0,62}$'
    or compute_deadlines.subject_id is null or length(compute_deadlines.subject_id) not between 1 and 200
    or compute_deadlines.facts is null or jsonb_typeof(compute_deadlines.facts) <> 'object'
    or compute_deadlines.as_of is null then
    ${fail("DEADLINE_INVALID", "a deadline needs a subject type, a subject id, facts as an object and a date", "22023")}
  end if;
  if not ${visible("compute_deadlines.subject_type", "compute_deadlines.subject_id", "compute_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to compute deadlines for this subject")}
  end if;
  v_version := ${fn("rule_version_at")}(compute_deadlines.jurisdiction, compute_deadlines.kind, compute_deadlines.as_of);
  if v_version is null then
    ${fail("DEADLINE_RULES_NOT_FOUND", "no approved rule set version applies", "P0002")}
  end if;
  if compute_deadlines.group_key is not null and not exists (
    select 1 from jsonb_array_elements(v_version -> 'groups') g(value) where g.value ->> 'key' = compute_deadlines.group_key
  ) then
    ${fail("DEADLINE_RULE_NOT_FOUND", "the rule set has no group with this key", "P0002")}
  end if;
  v_results := ${fn("evaluate_deadlines")}(
    jsonb_build_object('rules', v_version -> 'rules', 'groups', v_version -> 'groups', 'counting', v_version -> 'counting'),
    compute_deadlines.facts, compute_deadlines.as_of, compute_deadlines.group_key);
  return ${fn("deadline_store")}(compute_deadlines.tenant, compute_deadlines.subject_type, compute_deadlines.subject_id,
    compute_deadlines.jurisdiction, compute_deadlines.kind, (v_version ->> 'id')::uuid, compute_deadlines.facts, compute_deadlines.as_of,
    v_results, case when compute_deadlines.group_key is null
      then array(
        select g.value ->> 'key' from jsonb_array_elements(v_version -> 'groups') g(value)
        union
        select x.${d("groupKey")} from ${deadlines} x
        where x.${d("tenant")} = compute_deadlines.tenant and x.${d("subjectType")} = compute_deadlines.subject_type
          and x.${d("subjectId")} = compute_deadlines.subject_id and x.${d("jurisdiction")} = compute_deadlines.jurisdiction
          and x.${d("kind")} = compute_deadlines.kind)
      else array[compute_deadlines.group_key] end) -> 'rows';
end;
$$;
${userGrant(`${fn("compute_deadlines")}(${idType}, text, text, text, text, jsonb, date, text)`)}

-- Re-evaluates the pending deadlines of a subject after new facts arrived,
-- against the rule set version they were computed with (never a newer one),
-- for the groups the subject has rows of, and returns how many rows changed.
-- The facts are the latest stored ones merged with p_facts. Runs without a
-- permission check; the facts trigger and recompute_deadlines call it.
create or replace function ${fn("deadline_recompute")}(tenant text, subject_type text, subject_id text, p_facts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_set record;
  v_version ${versions};
  v_facts jsonb;
  v_groups text[];
  v_results jsonb;
  v_changed integer := 0;
begin
  for v_set in
    select x.${d("tenant")} as tenant, x.${d("jurisdiction")} as jurisdiction, x.${d("kind")} as kind, x.${d("ruleVersion")} as version_id
    from ${deadlines} x
    where x.${d("tenant")}::text = deadline_recompute.tenant and x.${d("subjectType")} = deadline_recompute.subject_type
      and x.${d("subjectId")} = deadline_recompute.subject_id and x.${d("state")} = 'pending'
    group by 1, 2, 3, 4
  loop
    select * into v_version from ${versions} x where x.${v("id")} = v_set.version_id;
    select y.${d("facts")} || coalesce(deadline_recompute.p_facts, '{}'::jsonb) into v_facts from ${deadlines} y
    where y.${d("tenant")} = v_set.tenant and y.${d("subjectType")} = deadline_recompute.subject_type
      and y.${d("subjectId")} = deadline_recompute.subject_id and y.${d("ruleVersion")} = v_set.version_id
    order by y.${d("computedAt")} desc, y.${d("id")} limit 1;
    v_groups := array(
      select distinct y.${d("groupKey")} from ${deadlines} y
      where y.${d("tenant")} = v_set.tenant and y.${d("subjectType")} = deadline_recompute.subject_type
        and y.${d("subjectId")} = deadline_recompute.subject_id and y.${d("ruleVersion")} = v_set.version_id
    );
    v_results := coalesce((
      select jsonb_agg(r.value order by r.ord)
      from jsonb_array_elements(${fn("evaluate_deadlines")}(${content("v_version")}, v_facts, current_date)) with ordinality r(value, ord)
      where r.value ->> 'group' = any (v_groups)
    ), '[]'::jsonb);
    v_changed := v_changed + (${fn("deadline_store")}(v_set.tenant, deadline_recompute.subject_type, deadline_recompute.subject_id,
      v_set.jurisdiction, v_set.kind, v_set.version_id, v_facts, current_date, v_results, v_groups) ->> 'changed')::integer;
  end loop;
  return v_changed;
end;
$$;
${triggerGrant(`${fn("deadline_recompute")}(text, text, text, jsonb)`)}

-- Re-evaluates a subject's pending deadlines with extra facts. Needs
-- deadlines.write and read access to the subject.
create or replace function ${fn("recompute_deadlines")}(tenant ${idType}, subject_type text, subject_id text, facts jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${allowed("recompute_deadlines.tenant", write)} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to compute deadlines")}
  end if;
  if not ${visible("recompute_deadlines.subject_type", "recompute_deadlines.subject_id", "recompute_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to compute deadlines for this subject")}
  end if;
  return ${fn("deadline_recompute")}(recompute_deadlines.tenant::text, recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.facts);
end;
$$;
${userGrant(`${fn("recompute_deadlines")}(${idType}, text, text, jsonb)`)}

-- A trigger function for the table that holds a subject's facts, one row per
-- fact. Attach it with an after insert row trigger and pass the subject type,
-- then the column names for the organization, subject id, fact name and value.
-- A new row recomputes the pending deadlines of its subject. The value arrives
-- as text, so a condition on a boolean fact needs recompute_deadlines with
-- typed facts instead.
create or replace function ${fn("deadline_fact_trigger")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(new);
begin
  if tg_nargs <> 5 then
    ${fail("DEADLINE_INVALID", "deadline_fact_trigger takes the subject type and four column names", "22023")}
  end if;
  perform ${fn("deadline_recompute")}(v_row ->> tg_argv[1], tg_argv[0], v_row ->> tg_argv[2], jsonb_build_object(v_row ->> tg_argv[3], v_row ->> tg_argv[4]));
  return new;
end;
$$;
${triggerGrant(`${fn("deadline_fact_trigger")}()`)}

-- Records the action that satisfied a deadline (one period of a periodic rule
-- on its own). Needs deadlines.write and read access to the subject.
create or replace function ${fn("satisfy_deadline")}(deadline_id uuid, action text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${deadlines};
begin
  select * into v_row from ${deadlines} x where x.${d("id")} = satisfy_deadline.deadline_id for update;
  if not found or not ${allowed(`v_row.${d("tenant")}`, read)}
    or not ${visible(`v_row.${d("subjectType")}`, `v_row.${d("subjectId")}`, `v_row.${d("tenant")}`)} then
    ${missing}
  end if;
  if not ${allowed(`v_row.${d("tenant")}`, write)} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to satisfy deadlines")}
  end if;
  if v_row.${d("state")} = 'satisfied' then
    return ${json("v_row")};
  end if;
  update ${deadlines} x set ${d("state")} = 'satisfied', ${d("satisfiedAt")} = now(), ${d("satisfiedBy")} = auth.uid(),
    ${d("satisfiedAction")} = nullif(btrim(satisfy_deadline.action), '')
  where x.${d("id")} = v_row.${d("id")} returning * into v_row;
  ${record("deadline.satisfied", "v_row")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("satisfy_deadline")}(uuid, text)`)}

-- An organization's deadlines on the subjects the caller may read, soonest
-- first. Security invoker, so the read policy and the subject tables' own
-- policies decide which rows it returns. filters is { subjectType,
-- subjectId, groupKey, period, state, result, provisional, dueBefore, limit }.
create or replace function ${fn("list_deadlines")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_deadlines.filters, '{}'::jsonb);
begin
  if not ${allowed("list_deadlines.tenant", read)} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to read deadlines")}
  end if;
  return coalesce((
    select jsonb_agg(${json("y")} order by y.${d("dueOn")} nulls last, y.${d("createdAt")})
    from (
      select * from ${deadlines} z
      where z.${d("tenant")} = list_deadlines.tenant
        and (not v_filters ? 'subjectType' or z.${d("subjectType")} = v_filters ->> 'subjectType')
        and (not v_filters ? 'subjectId' or z.${d("subjectId")} = v_filters ->> 'subjectId')
        and (not v_filters ? 'groupKey' or z.${d("groupKey")} = v_filters ->> 'groupKey')
        and (not v_filters ? 'period' or z.${d("period")} = v_filters ->> 'period')
        and (not v_filters ? 'state' or z.${d("state")} = v_filters ->> 'state')
        and (not v_filters ? 'result' or z.${d("result")} = v_filters ->> 'result')
        and (not v_filters ? 'provisional' or z.${d("provisional")} = (v_filters ->> 'provisional')::boolean)
        and (not v_filters ? 'dueBefore' or z.${d("dueOn")} < (v_filters ->> 'dueBefore')::date)
      order by z.${d("dueOn")} nulls last, z.${d("createdAt")}
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_deadlines")}(${idType}, jsonb)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "evaluate_deadlines",
      args: ["jsonb", "jsonb", "date", "text"],
      returns: "jsonb",
    },
    { name: "validate_deadline_rules", args: ["jsonb"], returns: "text[]" },
    {
      name: "save_rule_version",
      args: ["text", "text", "jsonb", "date", "text"],
      returns: "jsonb",
    },
    {
      name: "approve_rule_version",
      args: ["uuid", "uuid", "date"],
      returns: "jsonb",
    },
    {
      name: "rule_version_at",
      args: ["text", "text", "date"],
      returns: "jsonb",
    },
    {
      name: "compute_deadlines",
      args: ["{id}", "text", "text", "text", "text", "jsonb", "date", "text"],
      returns: "jsonb",
    },
    {
      name: "recompute_deadlines",
      args: ["{id}", "text", "text", "jsonb"],
      returns: "integer",
    },
    { name: "satisfy_deadline", args: ["uuid", "text"], returns: "jsonb" },
    { name: "list_deadlines", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const DEADLINES: BlockSqlDefinition = {
  name: "deadlines",
  scopes: ["tenant"],
  title: "Deadlines",
  description:
    "Platform-owned rule sets per jurisdiction and kind, versioned and approved once with a content hash: ordered groups of rules with conditions, exceptions, a deadline grammar, a counting block with holidays and opaque meta. Each group yields a subject's deadline from its facts: due on a date (one per month for a periodic rule), unknown with the facts still missing, pending, undated, or not covered, not applicable, not required or barred; recomputed when facts arrive and satisfied by a recorded action.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "approvals"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [TO_GROUPS],
  deprecated: DEPRECATED,
  // The deprecated wrappers get no api entry point; they go in 0.58.
  internal: [
    "evaluate_deadline_rule",
    "compute_deadline",
    "deadline_subject_readable",
  ],
  names: NAMES,
  contract,
  build,
};
