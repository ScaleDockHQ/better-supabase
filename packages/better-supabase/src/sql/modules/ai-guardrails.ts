import type { AiGuardrailsEvents } from "../../blocks/ai-guardrails/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, raise, schemaPreamble, serviceGrant } from "../shared.ts";

const POLICIES = {
  id: "id",
  tenant: "organization_id",
  agent: "agent",
  stage: "stage",
  config: "config",
  enabled: "enabled",
  updatedAt: "updated_at",
} as const;

const DECISIONS = {
  id: "id",
  tenant: "organization_id",
  agent: "agent",
  stage: "stage",
  decision: "decision",
  reasons: "reasons",
  chat: "chat_id",
  contentHash: "content_hash",
  createdAt: "created_at",
} as const;

const EVENTS: BlockSqlEvents<AiGuardrailsEvents> = {
  "guardrail.blocked": {
    subject: "guardrail-decisions",
    payload: ["organizationId", "decisionId", "agent", "stage", "reasons"],
  },
};

const NAMES: BlockSqlNames = {
  options: ["retention"],
  events: EVENTS,
  tables: {
    policies: {
      name: "guardrail_policies",
      columns: POLICIES,
      lifecycle: { tenant: "tenant" },
      app: {},
    },
    decisions: {
      name: "guardrail_decisions",
      columns: DECISIONS,
      lifecycle: { tenant: "tenant" },
      app: {},
    },
  },
};

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const p = (column: keyof typeof POLICIES): string =>
    ctx.col("policies", column);

  const d = (column: keyof typeof DECISIONS): string =>
    ctx.col("decisions", column);

  const policies = ctx.table("policies");
  const decisions = ctx.table("decisions");
  const policiesName = ctx.tableName("policies").name;
  const decisionsName = ctx.tableName("decisions").name;

  // SAFETY: keys come from Object.entries of the same column map.
  const json = (
    columns: Readonly<Record<string, string>>,
    column: (key: never) => string,
    alias: string,
  ): string =>
    `jsonb_build_object(${Object.entries(columns)
      .map(([key, name]) => `'${name}', ${alias}.${column(key as never)}`)
      .join(", ")})`;

  const policyJson = (alias: string): string => json(POLICIES, p, alias);

  const decisionJson = (alias: string): string => json(DECISIONS, d, alias);

  const blocked = ctx.record({
    type: "guardrail.blocked",
    payload: `jsonb_build_object('organizationId', v_row.${d("tenant")}::text, 'decisionId', v_row.${d("id")}, 'agent', v_row.${d("agent")}, 'stage', v_row.${d("stage")}, 'reasons', v_row.${d("reasons")})`,
    subject: `'guardrail-decisions/' || v_row.${d("id")}::text`,
    tenant: `v_row.${d("tenant")}`,
    audit: {
      category: "ai",
      targetType: "guardrail_decision",
      recordId: `v_row.${d("id")}::text`,
      targetLabel: `v_row.${d("agent")} || '/' || v_row.${d("stage")}`,
    },
  });

  const retention = ctx.text("retention", "90 days");

  if (!/^\d+ (minutes?|hours?|days?)$/.test(retention)) {
    throw new TypeError(
      'blocks.ai-guardrails.options.retention must be an interval such as "90 days"',
    );
  }

  return `${schemaPreamble(ctx)}
-- Input and output policies per agent, and the log of what the checks decided.
-- A policy row holds the config the TypeScript check reads (injection
-- heuristics, PII handling, deny topics, the deepest tool chain); tenant is
-- null for a policy that applies to every tenant. The log keeps a hash of the
-- checked content, never the content. Only the service role reads and writes
-- these tables.
create table if not exists ${policies} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${id},
  ${p("agent")} text not null check (${p("agent")} ~ '^(\\*|[a-z0-9][a-z0-9_.:/-]{0,127})$'),
  ${p("stage")} text not null check (${p("stage")} in ('input', 'output')),
  ${p("config")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${p("config")}) = 'object'),
  ${p("enabled")} boolean not null default true,
  ${p("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${sqlIdent(`bsb_${policiesName}_key`)} on ${policies} ((coalesce(${p("tenant")}::text, '')), ${p("agent")}, ${p("stage")});
${lockTable(policies)}

create table if not exists ${decisions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${id},
  ${d("agent")} text not null,
  ${d("stage")} text not null check (${d("stage")} in ('input', 'output')),
  ${d("decision")} text not null check (${d("decision")} in ('allow', 'redact', 'block')),
  ${d("reasons")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${d("reasons")}) = 'array'),
  ${d("chat")} text,
  ${d("contentHash")} text,
  ${d("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${decisionsName}_agent_idx`)} on ${decisions} (${d("agent")}, ${d("createdAt")} desc);
create index if not exists ${sqlIdent(`${decisionsName}_tenant_idx`)} on ${decisions} (${d("tenant")}, ${d("createdAt")} desc);
${lockTable(decisions)}

-- Saves the policy of an agent (or * for every agent) at a stage, replacing the
-- earlier one for the same tenant.
create or replace function ${fn("set_guardrail_policy")}(agent text, stage text, config jsonb, tenant ${id} default null, enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${policies}%rowtype;
begin
  if jsonb_typeof(set_guardrail_policy.config) is distinct from 'object' then
    ${raise("config must be a JSON object", "22023", "GUARDRAIL_INVALID")}
  end if;
  insert into ${policies} (${p("tenant")}, ${p("agent")}, ${p("stage")}, ${p("config")}, ${p("enabled")})
  values (set_guardrail_policy.tenant, set_guardrail_policy.agent, set_guardrail_policy.stage, set_guardrail_policy.config, coalesce(set_guardrail_policy.enabled, true))
  on conflict ((coalesce(${p("tenant")}::text, '')), ${p("agent")}, ${p("stage")}) do update set
    ${p("config")} = excluded.${p("config")}, ${p("enabled")} = excluded.${p("enabled")}, ${p("updatedAt")} = now()
  returning * into v_row;
  return ${policyJson("v_row")};
end;
$$;
${serviceGrant(`${fn("set_guardrail_policy")}(text, text, jsonb, ${id}, boolean)`)}

-- The policy that applies to an agent at a stage: the tenant's own for the
-- agent, then the tenant's for *, then the system's for the agent, then the
-- system's for *. Null when none is enabled.
create or replace function ${fn("get_guardrail_policy")}(agent text, stage text, tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${policies}%rowtype;
begin
  select x.* into v_row from ${policies} x
  where x.${p("stage")} = get_guardrail_policy.stage
    and x.${p("agent")} in (get_guardrail_policy.agent, '*')
    and (x.${p("tenant")} is null or x.${p("tenant")} = get_guardrail_policy.tenant)
  order by (x.${p("tenant")} is null), (x.${p("agent")} = '*')
  limit 1;
  if not found or not v_row.${p("enabled")} then
    return null;
  end if;
  return ${policyJson("v_row")};
end;
$$;
${serviceGrant(`${fn("get_guardrail_policy")}(text, text, ${id})`)}

-- Logs one decision (allow, redact or block) with the reasons and a hash of
-- the content, and records guardrail.blocked for a block.
create or replace function ${fn("record_guardrail_decision")}(agent text, stage text, decision text, reasons jsonb default '[]'::jsonb, tenant ${id} default null, chat text default null, content_hash text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${decisions}%rowtype;
begin
  insert into ${decisions} (${d("tenant")}, ${d("agent")}, ${d("stage")}, ${d("decision")}, ${d("reasons")}, ${d("chat")}, ${d("contentHash")})
  values (record_guardrail_decision.tenant, record_guardrail_decision.agent, record_guardrail_decision.stage, record_guardrail_decision.decision, coalesce(record_guardrail_decision.reasons, '[]'::jsonb), record_guardrail_decision.chat, record_guardrail_decision.content_hash)
  returning * into v_row;
  if v_row.${d("decision")} = 'block' then
    ${blocked}
  end if;
  return ${decisionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("record_guardrail_decision")}(text, text, text, jsonb, ${id}, text, text)`)}

-- The decision log, newest first, optionally for one agent or one decision.
create or replace function ${fn("list_guardrail_decisions")}(agent text default null, decision text default null, tenant ${id} default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(${decisionJson("q")} order by q.${d("createdAt")} desc), '[]'::jsonb)
    from (
      select x.* from ${decisions} x
      where (list_guardrail_decisions.agent is null or x.${d("agent")} = list_guardrail_decisions.agent)
        and (list_guardrail_decisions.decision is null or x.${d("decision")} = list_guardrail_decisions.decision)
        and (list_guardrail_decisions.tenant is null or x.${d("tenant")} = list_guardrail_decisions.tenant)
      order by x.${d("createdAt")} desc
      limit least(greatest(coalesce(list_guardrail_decisions.max_rows, 100), 1), 1000)
    ) q
  );
end;
$$;
${serviceGrant(`${fn("list_guardrail_decisions")}(text, text, ${id}, integer)`)}

-- Deletes decisions older than the retention (${retention}) and returns how many.
create or replace function ${fn("purge_guardrail_decisions")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${decisions} x where x.${d("createdAt")} < now() - interval '${retention}';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_guardrail_decisions")}()`)}`;
}

export const AI_GUARDRAILS: BlockSqlDefinition = {
  name: "ai-guardrails",
  title: "AI guardrails",
  description:
    "Input and output policies per agent (prompt-injection heuristics, PII redaction, topic deny lists, a tool depth limit) and a decision log; a blocked check records guardrail.blocked. Only the service role reads and writes them.",
  requires: [],
  integrates: ["outbox", "audit"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
