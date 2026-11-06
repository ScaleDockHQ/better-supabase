import type { DeadlinesEvents } from "../../blocks/deadlines/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

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
import { evaluatorSql } from "./deadlines-evaluator.ts";
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
  "ruleKey",
  "result",
  "dueOn",
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
        ruleKey: "rule_key",
        ruleVersion: "rule_version_id",
        facts: "facts",
        result: "result",
        dueOn: "due_on",
        missing: "missing",
        citation: "citation",
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

function build(ctx: BlockSqlContext): string {
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
  const read = ctx.permission("read", OPERATIONS["deadlines.read"]);
  const write = ctx.permission("write", OPERATIONS["deadlines.write"]);

  const approvals = ctx.installed("approvals")
    ? ctx.of("approvals")
    : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const serviceOnly = (what: string): string =>
    `if not ${SERVICE_CALLER} then
    ${fail("DEADLINE_FORBIDDEN", `only the service role may ${what}`)}
  end if;`;

  const missing = fail("DEADLINE_NOT_FOUND", "no such deadline", "P0002");

  const versionJson = (row: string, sets_ = sets): string =>
    `jsonb_build_object('id', ${row}.${v("id")}, 'jurisdiction', (select z.${s("jurisdiction")} from ${sets_} z where z.${s("id")} = ${row}.${v("ruleSet")}), 'kind', (select z.${s("kind")} from ${sets_} z where z.${s("id")} = ${row}.${v("ruleSet")}), 'version', ${row}.${v("version")}, 'status', ${row}.${v("status")}, 'rules', ${row}.${v("rules")}, 'contentHash', ${row}.${v("contentHash")}, 'effectiveFrom', ${row}.${v("effectiveFrom")}, 'approvedBy', ${row}.${v("approvedBy")}, 'approvedAt', ${row}.${v("approvedAt")}, 'createdAt', ${row}.${v("createdAt")})`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'subjectType', ${row}.${d("subjectType")}, 'subjectId', ${row}.${d("subjectId")}, 'jurisdiction', ${row}.${d("jurisdiction")}, 'kind', ${row}.${d("kind")}, 'ruleKey', ${row}.${d("ruleKey")}, 'ruleVersionId', ${row}.${d("ruleVersion")}, 'ruleVersion', (select x.${v("version")} from ${versions} x where x.${v("id")} = ${row}.${d("ruleVersion")}), 'facts', ${row}.${d("facts")}, 'result', ${row}.${d("result")}, 'dueOn', ${row}.${d("dueOn")}, 'missing', to_jsonb(${row}.${d("missing")}), 'citation', ${row}.${d("citation")}, 'state', ${row}.${d("state")}, 'satisfiedAt', ${row}.${d("satisfiedAt")}, 'satisfiedBy', ${row}.${d("satisfiedBy")}, 'satisfiedAction', ${row}.${d("satisfiedAction")}, 'computedAt', ${row}.${d("computedAt")}, 'createdAt', ${row}.${d("createdAt")})`;

  const record = (
    type: "deadline.computed" | "deadline.satisfied",
    row: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${d("tenant")}, 'id', ${row}.${d("id")}, 'subjectType', ${row}.${d("subjectType")}, 'subjectId', ${row}.${d("subjectId")}, 'ruleKey', ${row}.${d("ruleKey")}, 'result', ${row}.${d("result")}, 'dueOn', ${row}.${d("dueOn")})`,
      subject: `'deadlines/' || ${row}.${d("id")}::text`,
      tenant: `${row}.${d("tenant")}`,
      audit: {
        category: "data",
        targetType: "deadline",
        recordId: `${row}.${d("id")}::text`,
        targetLabel: `${row}.${d("ruleKey")} || ' ' || ${row}.${d("subjectType")} || '/' || ${row}.${d("subjectId")}`,
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

  const readPolicy = renderPolicy(
    makePolicy({
      table: deadlines,
      name: sqlIdent(`${ctx.tableName("deadlines").name}_read`),
      command: "select",
      roles: ["authenticated"],
      using: ctx.scope.check(d("tenant"), read),
    }),
    { target: deadlines },
  );

  const appKey = ctx.owns("deadlines")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("deadlines").name}_tenant_id_key`)} on ${deadlines} (${d("tenant")}, ${d("id")});`;

  // Re-evaluates one pending row against the stored rule version.
  const recomputeRow = `
  select x.* into v_version from ${versions} x where x.${v("id")} = v_row.${d("ruleVersion")};
  select e.value into v_rule from jsonb_array_elements(v_version.${v("rules")}) e(value)
  where e.value ->> 'key' = v_row.${d("ruleKey")};
  v_facts := v_row.${d("facts")} || coalesce(p_facts, '{}'::jsonb);
  v_result := ${fn("evaluate_deadline_rule")}(v_rule, v_facts);`;

  return `${schemaPreamble(ctx)}
-- Deadlines: rule sets owned by the platform (no tenant), versioned and approved
-- once, and the deadlines computed from a subject's facts. A rule is data: an
-- anchor fact, an offset, a weekend adjustment, the facts it requires and a
-- citation. A deadline is either due on a date or unknown, naming the facts it
-- still waits for.
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
  ${d("ruleKey")} text not null,
  ${d("ruleVersion")} uuid not null references ${versions} (${v("id")}) on delete restrict,
  ${d("facts")} jsonb not null default '{}'::jsonb,
  ${d("result")} text not null check (${d("result")} in (${quoted(DEADLINE_RESULTS)})),
  ${d("dueOn")} date,
  ${d("missing")} text[] not null default '{}',
  ${d("citation")} jsonb not null,
  ${d("state")} text not null default 'pending' check (${d("state")} in (${quoted(DEADLINE_STATES)})),
  ${d("satisfiedAt")} timestamptz,
  ${d("satisfiedBy")} uuid,
  ${d("satisfiedAction")} text check (${d("satisfiedAction")} is null or length(${d("satisfiedAction")}) <= 200),
  ${d("computedAt")} timestamptz not null default now(),
  ${d("createdAt")} timestamptz not null default now(),
  check ((${d("result")} = 'due') = (${d("dueOn")} is not null)),
  constraint ${sqlIdent(`${ctx.tableName("deadlines").name}_subject_rule_key`)} unique (${d("tenant")}, ${d("subjectType")}, ${d("subjectId")}, ${d("ruleKey")})
);${appKey}
create index if not exists ${sqlIdent(`${ctx.tableName("deadlines").name}_version_idx`)} on ${deadlines} (${d("ruleVersion")});
create index if not exists ${sqlIdent(`${ctx.tableName("deadlines").name}_due_idx`)} on ${deadlines} (${d("tenant")}, ${d("dueOn")}) where ${d("state")} = 'pending';
${lockTable(deadlines, { read: true })}
${readPolicy}
${evaluatorSql(fn, userGrant)}
-- Saves the rules of a rule set as a new draft version, creating the rule set
-- on first use. A draft is replaced by the next save until it is approved.
-- Service role only.
create or replace function ${fn("save_rule_version")}(jurisdiction text, kind text, rules jsonb, effective_from date default null, title text default null)
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
begin
  ${serviceOnly("save rule set versions")}
  if save_rule_version.jurisdiction is null or save_rule_version.jurisdiction !~ '^[a-z][a-z0-9_-]{0,62}$'
    or save_rule_version.kind is null or save_rule_version.kind !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${fail("DEADLINE_RULES_INVALID", "a rule set has a lower case jurisdiction and kind", "22023")}
  end if;
  v_issues := ${fn("validate_deadline_rules")}(save_rule_version.rules);
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
    update ${versions} x set ${v("rules")} = save_rule_version.rules, ${v("effectiveFrom")} = save_rule_version.effective_from
    where x.${v("id")} = v_row.${v("id")} returning * into v_row;
  else
    insert into ${versions} (${v("ruleSet")}, ${v("version")}, ${v("rules")}, ${v("effectiveFrom")})
    values (v_set.${s("id")}, coalesce((select max(y.${v("version")}) from ${versions} y where y.${v("ruleSet")} = v_set.${s("id")}), 0) + 1, save_rule_version.rules, save_rule_version.effective_from)
    returning * into v_row;
  end if;
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("save_rule_version")}(text, text, jsonb, date, text)`)}

-- Approves a draft version: freezes its rules with a SHA-256 content hash and
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
    ${v("contentHash")} = ${sha256HexSql(`convert_to(v_row.${v("rules")}::text, 'UTF8')`)},
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

-- Computes the deadline of one rule for a subject from its facts, with the rule
-- set version that applies on as_of (today by default), and stores it. The
-- result is due on a date or unknown with the facts it waits for. A satisfied
-- deadline is returned unchanged. Needs deadlines.write.
create or replace function ${fn("compute_deadline")}(tenant ${idType}, subject_type text, subject_id text, jurisdiction text, kind text, rule_key text, facts jsonb default '{}', as_of date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_version jsonb;
  v_rule jsonb;
  v_result jsonb;
  v_row ${deadlines};
begin
  if not ${allowed("compute_deadline.tenant", write)} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to compute deadlines")}
  end if;
  if compute_deadline.subject_type is null or compute_deadline.subject_type !~ '^[a-z][a-z0-9_]{0,62}$'
    or compute_deadline.subject_id is null or length(compute_deadline.subject_id) not between 1 and 200
    or compute_deadline.facts is null or jsonb_typeof(compute_deadline.facts) <> 'object' then
    ${fail("DEADLINE_INVALID", "a deadline needs a subject type, a subject id and facts as an object", "22023")}
  end if;
  v_version := ${fn("rule_version_at")}(compute_deadline.jurisdiction, compute_deadline.kind, compute_deadline.as_of);
  if v_version is null then
    ${fail("DEADLINE_RULES_NOT_FOUND", "no approved rule set version applies", "P0002")}
  end if;
  select e.value into v_rule from jsonb_array_elements(v_version -> 'rules') e(value)
  where e.value ->> 'key' = compute_deadline.rule_key;
  if v_rule is null then
    ${fail("DEADLINE_RULE_NOT_FOUND", "the rule set has no rule with this key", "P0002")}
  end if;
  select * into v_row from ${deadlines} x
  where x.${d("tenant")} = compute_deadline.tenant and x.${d("subjectType")} = compute_deadline.subject_type
    and x.${d("subjectId")} = compute_deadline.subject_id and x.${d("ruleKey")} = compute_deadline.rule_key
  for update;
  if found and v_row.${d("state")} = 'satisfied' then
    return ${json("v_row")};
  end if;
  v_result := ${fn("evaluate_deadline_rule")}(v_rule, compute_deadline.facts);
  insert into ${deadlines} (${d("tenant")}, ${d("subjectType")}, ${d("subjectId")}, ${d("jurisdiction")}, ${d("kind")}, ${d("ruleKey")}, ${d("ruleVersion")}, ${d("facts")}, ${d("result")}, ${d("dueOn")}, ${d("missing")}, ${d("citation")})
  values (compute_deadline.tenant, compute_deadline.subject_type, compute_deadline.subject_id, compute_deadline.jurisdiction, compute_deadline.kind, compute_deadline.rule_key,
    (v_version ->> 'id')::uuid, compute_deadline.facts, case v_result ->> 'status' when 'due' then 'due' else 'unknown' end,
    nullif(v_result ->> 'dueOn', '')::date,
    coalesce(array(select jsonb_array_elements_text(coalesce(v_result -> 'missing', '[]'::jsonb))), '{}'),
    v_rule -> 'citation')
  on conflict on constraint ${sqlIdent(`${ctx.tableName("deadlines").name}_subject_rule_key`)} do update set
    ${d("ruleVersion")} = excluded.${d("ruleVersion")}, ${d("facts")} = excluded.${d("facts")}, ${d("result")} = excluded.${d("result")},
    ${d("dueOn")} = excluded.${d("dueOn")}, ${d("missing")} = excluded.${d("missing")}, ${d("citation")} = excluded.${d("citation")},
    ${d("computedAt")} = now()
  returning * into v_row;
  ${record("deadline.computed", "v_row")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("compute_deadline")}(${idType}, text, text, text, text, text, jsonb, date)`)}

-- Re-evaluates the pending deadlines of a subject after new facts arrived,
-- against the rule set version each one was computed with, and returns how many
-- changed. Runs without a permission check; the facts trigger and
-- recompute_deadlines call it.
create or replace function ${fn("deadline_recompute")}(tenant text, subject_type text, subject_id text, p_facts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${deadlines};
  v_version ${versions};
  v_rule jsonb;
  v_facts jsonb;
  v_result jsonb;
  v_changed integer := 0;
  v_due date;
  v_missing text[];
begin
  for v_row in
    select * from ${deadlines} x
    where x.${d("tenant")}::text = deadline_recompute.tenant and x.${d("subjectType")} = deadline_recompute.subject_type
      and x.${d("subjectId")} = deadline_recompute.subject_id and x.${d("state")} = 'pending'
    for update
  loop${recomputeRow}
    v_due := nullif(v_result ->> 'dueOn', '')::date;
    v_missing := coalesce(array(select jsonb_array_elements_text(coalesce(v_result -> 'missing', '[]'::jsonb))), '{}');
    if v_facts is distinct from v_row.${d("facts")} or v_due is distinct from v_row.${d("dueOn")} or v_missing is distinct from v_row.${d("missing")} then
      update ${deadlines} x set ${d("facts")} = v_facts,
        ${d("result")} = case v_result ->> 'status' when 'due' then 'due' else 'unknown' end,
        ${d("dueOn")} = v_due, ${d("missing")} = v_missing, ${d("computedAt")} = now()
      where x.${d("id")} = v_row.${d("id")} returning * into v_row;
      ${record("deadline.computed", "v_row")}
      v_changed := v_changed + 1;
    end if;
  end loop;
  return v_changed;
end;
$$;
${triggerGrant(`${fn("deadline_recompute")}(text, text, text, jsonb)`)}

-- Re-evaluates a subject's pending deadlines with extra facts. Needs
-- deadlines.write.
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
  return ${fn("deadline_recompute")}(recompute_deadlines.tenant::text, recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.facts);
end;
$$;
${userGrant(`${fn("recompute_deadlines")}(${idType}, text, text, jsonb)`)}

-- A trigger function for the table that holds a subject's facts, one row per
-- fact. Attach it with an after insert row trigger and pass the subject type,
-- then the column names for the organization, subject id, fact name and value.
-- A new row recomputes the pending deadlines of its subject.
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

-- Records the action that satisfied a deadline. Needs deadlines.write.
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
  if not found or not ${allowed(`v_row.${d("tenant")}`, read)} then
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

-- An organization's deadlines, soonest first. filters is { subjectType,
-- subjectId, state, result, dueBefore, limit }.
create or replace function ${fn("list_deadlines")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
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
        and (not v_filters ? 'state' or z.${d("state")} = v_filters ->> 'state')
        and (not v_filters ? 'result' or z.${d("result")} = v_filters ->> 'result')
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
      name: "evaluate_deadline_rule",
      args: ["jsonb", "jsonb"],
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
      name: "compute_deadline",
      args: ["{id}", "text", "text", "text", "text", "text", "jsonb", "date"],
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
    "Platform-owned rule sets per jurisdiction and kind, versioned and approved once with a content hash and a citation per rule, and the deadlines computed from a subject's facts: due on a date or unknown with the facts still missing, recomputed when facts arrive and satisfied by a recorded action.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "approvals"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
