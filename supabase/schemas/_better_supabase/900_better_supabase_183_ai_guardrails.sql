-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:4916ec654b77e50daa6b903e52cfb1b58d70bd3180756e41168241914eb1f174
-- Input and output policies per agent (prompt-injection heuristics, PII redaction, topic deny lists, a tool depth limit) and a decision log; a blocked check records guardrail.blocked. Only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Input and output policies per agent, and the log of what the checks decided.
-- A policy row holds the config the TypeScript check reads (injection
-- heuristics, PII handling, deny topics, the deepest tool chain); tenant is
-- null for a policy that applies to every tenant. The log keeps a hash of the
-- checked content, never the content. Only the service role reads and writes
-- these tables.
create table "better_supabase"."guardrail_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "agent" text not null constraint bsb_guardrail_policies_agent_check check ("agent" ~ '^(\*|[a-z0-9][a-z0-9_.:/-]{0,127})$'),
  "stage" text not null constraint bsb_guardrail_policies_stage_check check ("stage" in ('input', 'output')),
  "config" jsonb not null default '{}'::jsonb constraint bsb_guardrail_policies_config_check check (jsonb_typeof("config") = 'object'),
  "enabled" boolean not null default true,
  "updated_at" timestamptz not null default now()
);
create unique index "bsb_guardrail_policies_key" on "better_supabase"."guardrail_policies" ((coalesce("tenant_id"::text, '')), "agent", "stage");
alter table "better_supabase"."guardrail_policies" enable row level security;
revoke all on "better_supabase"."guardrail_policies" from public, anon, authenticated;
grant all on "better_supabase"."guardrail_policies" to service_role;

create table "better_supabase"."guardrail_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "agent" text not null,
  "stage" text not null constraint bsb_guardrail_decisions_stage_check check ("stage" in ('input', 'output')),
  "decision" text not null constraint bsb_guardrail_decisions_decision_check check ("decision" in ('allow', 'redact', 'block')),
  "reasons" jsonb not null default '[]'::jsonb constraint bsb_guardrail_decisions_reasons_check check (jsonb_typeof("reasons") = 'array'),
  "chat_id" text,
  "content_hash" text,
  "created_at" timestamptz not null default now()
);
create index "guardrail_decisions_agent_idx" on "better_supabase"."guardrail_decisions" ("agent", "created_at" desc);
create index "guardrail_decisions_tenant_idx" on "better_supabase"."guardrail_decisions" ("tenant_id", "created_at" desc, "id" desc);
alter table "better_supabase"."guardrail_decisions" enable row level security;
revoke all on "better_supabase"."guardrail_decisions" from public, anon, authenticated;
grant all on "better_supabase"."guardrail_decisions" to service_role;

-- Saves the policy of an agent (or * for every agent) at a stage, replacing the
-- earlier one for the same tenant.
create or replace function "better_supabase"."set_guardrail_policy"(agent text, stage text, config jsonb, tenant uuid default null, enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_policies"%rowtype;
begin
  if jsonb_typeof(set_guardrail_policy.config) is distinct from 'object' then
    raise exception 'config must be a JSON object' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  insert into "better_supabase"."guardrail_policies" ("tenant_id", "agent", "stage", "config", "enabled")
  values (set_guardrail_policy.tenant, set_guardrail_policy.agent, set_guardrail_policy.stage, set_guardrail_policy.config, coalesce(set_guardrail_policy.enabled, true))
  on conflict ((coalesce("tenant_id"::text, '')), "agent", "stage") do update set
    "config" = excluded."config", "enabled" = excluded."enabled", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) to service_role;

-- The policy that applies to an agent at a stage: the tenant's own for the
-- agent, then the tenant's for *, then the system's for the agent, then the
-- system's for *. Null when none is enabled.
create or replace function "better_supabase"."get_guardrail_policy"(agent text, stage text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_policies"%rowtype;
begin
  select x.* into v_row from "better_supabase"."guardrail_policies" x
  where x."stage" = get_guardrail_policy.stage
    and x."agent" in (get_guardrail_policy.agent, '*')
    and (x."tenant_id" is null or x."tenant_id" = get_guardrail_policy.tenant)
  order by (x."tenant_id" is null), (x."agent" = '*')
  limit 1;
  if not found or not v_row."enabled" then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_guardrail_policy"(text, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy"(text, text, uuid) to service_role;

-- Logs one decision (allow, redact or block) with the reasons and a hash of
-- the content, and records guardrail.blocked for a block.
create or replace function "better_supabase"."record_guardrail_decision"(agent text, stage text, decision text, reasons jsonb default '[]'::jsonb, tenant uuid default null, chat text default null, content_hash text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_decisions"%rowtype;
begin
  insert into "better_supabase"."guardrail_decisions" ("tenant_id", "agent", "stage", "decision", "reasons", "chat_id", "content_hash")
  values (record_guardrail_decision.tenant, record_guardrail_decision.agent, record_guardrail_decision.stage, record_guardrail_decision.decision, coalesce(record_guardrail_decision.reasons, '[]'::jsonb), record_guardrail_decision.chat, record_guardrail_decision.content_hash)
  returning * into v_row;
  if v_row."decision" = 'block' then
    perform "better_supabase".emit_event('guardrail.blocked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'decisionId', v_row."id", 'agent', v_row."agent", 'stage', v_row."stage", 'reasons', v_row."reasons"), 'guardrail-decisions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ai-guardrails');
  perform better_supabase.audit_event(
    event_type => 'guardrail.blocked',
    category => 'ai',
    target_type => 'guardrail_decision',
    record_id => v_row."id"::text,
    target_label => v_row."agent" || '/' || v_row."stage",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'decisionId', v_row."id", 'agent', v_row."agent", 'stage', v_row."stage", 'reasons', v_row."reasons")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- The decision log, newest first, optionally for one agent or one decision.
create or replace function "better_supabase"."list_guardrail_decisions"(agent text default null, decision text default null, tenant uuid default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'tenant_id', q."tenant_id", 'agent', q."agent", 'stage', q."stage", 'decision', q."decision", 'reasons', q."reasons", 'chat_id', q."chat_id", 'content_hash', q."content_hash", 'created_at', q."created_at") order by q."created_at" desc), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."guardrail_decisions" x
      where (list_guardrail_decisions.agent is null or x."agent" = list_guardrail_decisions.agent)
        and (list_guardrail_decisions.decision is null or x."decision" = list_guardrail_decisions.decision)
        and (list_guardrail_decisions.tenant is null or x."tenant_id" = list_guardrail_decisions.tenant)
      order by x."created_at" desc
      limit least(greatest(coalesce(list_guardrail_decisions.max_rows, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) to service_role;

-- Deletes decisions older than the retention (90 days) and returns how many.
create or replace function "better_supabase"."purge_guardrail_decisions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."guardrail_decisions" x where x."created_at" < now() - interval '90 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_guardrail_decisions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_guardrail_decisions"() to service_role;

-- blocks.ai-guardrails.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."set_guardrail_policy"(agent text, stage text, config jsonb, tenant uuid default null, enabled boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_guardrail_policy"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) from public, anon, authenticated;
grant execute on function "api"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) to service_role;

create or replace function "api"."get_guardrail_policy"(agent text, stage text, tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_guardrail_policy"($1, $2, $3) $$;
revoke execute on function "api"."get_guardrail_policy"(text, text, uuid) from public, anon, authenticated;
grant execute on function "api"."get_guardrail_policy"(text, text, uuid) to service_role;

create or replace function "api"."record_guardrail_decision"(agent text, stage text, decision text, reasons jsonb default '[]'::jsonb, tenant uuid default null, chat text default null, content_hash text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_guardrail_decision"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

create or replace function "api"."list_guardrail_decisions"(agent text default null, decision text default null, tenant uuid default null, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_guardrail_decisions"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_guardrail_decisions"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."list_guardrail_decisions"(text, text, uuid, integer) to service_role;

create or replace function "api"."purge_guardrail_decisions"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_guardrail_decisions"() $$;
revoke execute on function "api"."purge_guardrail_decisions"() from public, anon, authenticated;
grant execute on function "api"."purge_guardrail_decisions"() to service_role;
