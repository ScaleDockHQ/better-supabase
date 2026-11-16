-- ==== alone: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:7080d25ad4260511cafe079fe2c9faae91b750a2f6379d0ae01fb3eccc94f0de
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
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "better_supabase"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

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

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "better_supabase"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:7bb3d67cac37ff57a8feeca9628ba838ad7c796b58366102143ba20751c9b9c8
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

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "better_supabase"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

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

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "better_supabase"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:95037077263d3da2e0c3f96a1a27bad8290db5fa6bf64cf4616e77d30efaec6e
-- Input and output policies per agent (prompt-injection heuristics, PII redaction, topic deny lists, a tool depth limit) and a decision log; a blocked check records guardrail.blocked. Only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Input and output policies per agent, and the log of what the checks decided.
-- A policy row holds the config the TypeScript check reads (injection
-- heuristics, PII handling, deny topics, the deepest tool chain); tenant is
-- null for a policy that applies to every tenant. The log keeps a hash of the
-- checked content, never the content. Only the service role reads and writes
-- these tables.
create table "app_private"."guardrail_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "agent" text not null constraint bsb_guardrail_policies_agent_check check ("agent" ~ '^(\*|[a-z0-9][a-z0-9_.:/-]{0,127})$'),
  "stage" text not null constraint bsb_guardrail_policies_stage_check check ("stage" in ('input', 'output')),
  "config" jsonb not null default '{}'::jsonb constraint bsb_guardrail_policies_config_check check (jsonb_typeof("config") = 'object'),
  "enabled" boolean not null default true,
  "updated_at" timestamptz not null default now()
);
create unique index "bsb_guardrail_policies_key" on "app_private"."guardrail_policies" ((coalesce("tenant_id"::text, '')), "agent", "stage");
alter table "app_private"."guardrail_policies" enable row level security;
revoke all on "app_private"."guardrail_policies" from public, anon, authenticated;
grant all on "app_private"."guardrail_policies" to service_role;

create table "app_private"."guardrail_decisions" (
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
create index "guardrail_decisions_agent_idx" on "app_private"."guardrail_decisions" ("agent", "created_at" desc);
create index "guardrail_decisions_tenant_idx" on "app_private"."guardrail_decisions" ("tenant_id", "created_at" desc, "id" desc);
alter table "app_private"."guardrail_decisions" enable row level security;
revoke all on "app_private"."guardrail_decisions" from public, anon, authenticated;
grant all on "app_private"."guardrail_decisions" to service_role;

-- Saves the policy of an agent (or * for every agent) at a stage, replacing the
-- earlier one for the same tenant.
create or replace function "app_private"."set_guardrail_policy"(agent text, stage text, config jsonb, tenant uuid default null, enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."guardrail_policies"%rowtype;
begin
  if jsonb_typeof(set_guardrail_policy.config) is distinct from 'object' then
    raise exception 'config must be a JSON object' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  insert into "app_private"."guardrail_policies" ("tenant_id", "agent", "stage", "config", "enabled")
  values (set_guardrail_policy.tenant, set_guardrail_policy.agent, set_guardrail_policy.stage, set_guardrail_policy.config, coalesce(set_guardrail_policy.enabled, true))
  on conflict ((coalesce("tenant_id"::text, '')), "agent", "stage") do update set
    "config" = excluded."config", "enabled" = excluded."enabled", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) from public, anon, authenticated;
grant execute on function "app_private"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) to service_role;

-- The policy that applies to an agent at a stage: the tenant's own for the
-- agent, then the tenant's for *, then the system's for the agent, then the
-- system's for *. Null when none is enabled.
create or replace function "app_private"."get_guardrail_policy"(agent text, stage text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."guardrail_policies"%rowtype;
begin
  select x.* into v_row from "app_private"."guardrail_policies" x
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
revoke execute on function "app_private"."get_guardrail_policy"(text, text, uuid) from public, anon, authenticated;
grant execute on function "app_private"."get_guardrail_policy"(text, text, uuid) to service_role;

-- Logs one decision (allow, redact or block) with the reasons and a hash of
-- the content, and records guardrail.blocked for a block.
create or replace function "app_private"."record_guardrail_decision"(agent text, stage text, decision text, reasons jsonb default '[]'::jsonb, tenant uuid default null, chat text default null, content_hash text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."guardrail_decisions"%rowtype;
begin
  insert into "app_private"."guardrail_decisions" ("tenant_id", "agent", "stage", "decision", "reasons", "chat_id", "content_hash")
  values (record_guardrail_decision.tenant, record_guardrail_decision.agent, record_guardrail_decision.stage, record_guardrail_decision.decision, coalesce(record_guardrail_decision.reasons, '[]'::jsonb), record_guardrail_decision.chat, record_guardrail_decision.content_hash)
  returning * into v_row;
  if v_row."decision" = 'block' then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "app_private"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "app_private"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "app_private"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

-- The decision log, newest first, optionally for one agent or one decision.
create or replace function "app_private"."list_guardrail_decisions"(agent text default null, decision text default null, tenant uuid default null, max_rows integer default 100)
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
      select x.* from "app_private"."guardrail_decisions" x
      where (list_guardrail_decisions.agent is null or x."agent" = list_guardrail_decisions.agent)
        and (list_guardrail_decisions.decision is null or x."decision" = list_guardrail_decisions.decision)
        and (list_guardrail_decisions.tenant is null or x."tenant_id" = list_guardrail_decisions.tenant)
      order by x."created_at" desc
      limit least(greatest(coalesce(list_guardrail_decisions.max_rows, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_guardrail_decisions"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "app_private"."list_guardrail_decisions"(text, text, uuid, integer) to service_role;

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "app_private"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "app_private"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "app_private"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "app_private"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "app_private"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."get_guardrail_policy_by_id"(uuid) to service_role;

-- Deletes decisions older than the retention (90 days) and returns how many.
create or replace function "app_private"."purge_guardrail_decisions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "app_private"."guardrail_decisions" x where x."created_at" < now() - interval '90 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."purge_guardrail_decisions"() from public, anon, authenticated;
grant execute on function "app_private"."purge_guardrail_decisions"() to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:d10366c61efbf9fdb4871bb48b499f564014ae60cd2b41a798f1d22a776f34d8
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
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "better_supabase"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

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

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "better_supabase"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) to service_role;

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

create or replace function "api"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_guardrail_policies"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "api"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

create or replace function "api"."list_guardrail_decisions"(agent text default null, decision text default null, tenant uuid default null, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_guardrail_decisions"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_guardrail_decisions"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."list_guardrail_decisions"(text, text, uuid, integer) to service_role;

create or replace function "api"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_guardrail_policies"($1, $2) $$;
revoke execute on function "api"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."page_guardrail_policies"(uuid, jsonb) to service_role;

create or replace function "api"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_guardrail_decisions"($1, $2) $$;
revoke execute on function "api"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."page_guardrail_decisions"(uuid, jsonb) to service_role;

create or replace function "api"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_guardrail_policy_by_id"($1) $$;
revoke execute on function "api"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "api"."get_guardrail_policy_by_id"(uuid) to service_role;

create or replace function "api"."purge_guardrail_decisions"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_guardrail_decisions"() $$;
revoke execute on function "api"."purge_guardrail_decisions"() from public, anon, authenticated;
grant execute on function "api"."purge_guardrail_decisions"() to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:20ab282d771ba73cf45dce592b3ab844d14e56b261c674f46fb7ec2f436af93d
-- Input and output policies per agent (prompt-injection heuristics, PII redaction, topic deny lists, a tool depth limit) and a decision log; a blocked check records guardrail.blocked. Only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Input and output policies per agent, and the log of what the checks decided.
-- A policy row holds the config the TypeScript check reads (injection
-- heuristics, PII handling, deny topics, the deepest tool chain); tenant is
-- null for a policy that applies to every tenant. The log keeps a hash of the
-- checked content, never the content. Only the service role reads and writes
-- these tables.
-- better_supabase.guardrail_policies is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."guardrail_policies" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."guardrail_policies" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."guardrail_policies" add column if not exists "agent" text constraint bsb_guardrail_policies_agent_check check ("agent" ~ '^(\*|[a-z0-9][a-z0-9_.:/-]{0,127})$');
alter table "better_supabase"."guardrail_policies" add column if not exists "stage" text constraint bsb_guardrail_policies_stage_check check ("stage" in ('input', 'output'));
alter table "better_supabase"."guardrail_policies" add column if not exists "config" jsonb not null default '{}'::jsonb constraint bsb_guardrail_policies_config_check check (jsonb_typeof("config") = 'object');
alter table "better_supabase"."guardrail_policies" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."guardrail_policies" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_guardrail_policies_key" on "better_supabase"."guardrail_policies" ((coalesce("tenant_id"::text, '')), "agent", "stage");
alter table "better_supabase"."guardrail_policies" enable row level security;
grant all on "better_supabase"."guardrail_policies" to service_role;

-- better_supabase.guardrail_decisions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."guardrail_decisions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."guardrail_decisions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."guardrail_decisions" add column if not exists "agent" text;
alter table "better_supabase"."guardrail_decisions" add column if not exists "stage" text constraint bsb_guardrail_decisions_stage_check check ("stage" in ('input', 'output'));
alter table "better_supabase"."guardrail_decisions" add column if not exists "decision" text constraint bsb_guardrail_decisions_decision_check check ("decision" in ('allow', 'redact', 'block'));
alter table "better_supabase"."guardrail_decisions" add column if not exists "reasons" jsonb not null default '[]'::jsonb constraint bsb_guardrail_decisions_reasons_check check (jsonb_typeof("reasons") = 'array');
alter table "better_supabase"."guardrail_decisions" add column if not exists "chat_id" text;
alter table "better_supabase"."guardrail_decisions" add column if not exists "content_hash" text;
alter table "better_supabase"."guardrail_decisions" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "guardrail_decisions_agent_idx" on "better_supabase"."guardrail_decisions" ("agent", "created_at" desc);
create index if not exists "guardrail_decisions_tenant_idx" on "better_supabase"."guardrail_decisions" ("tenant_id", "created_at" desc, "id" desc);
alter table "better_supabase"."guardrail_decisions" enable row level security;
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
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "better_supabase"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

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

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "better_supabase"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) to service_role;

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block ai-guardrails@1 managed
-- @bsb-hash sha256:fb499333bd228a1cd054161be1f5c856b98d1e22b6c14e82f55254040d721658
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
  "org_id" uuid,
  "agent" text not null constraint bsb_guardrail_policies_agent_check check ("agent" ~ '^(\*|[a-z0-9][a-z0-9_.:/-]{0,127})$'),
  "stage" text not null constraint bsb_guardrail_policies_stage_check check ("stage" in ('input', 'output')),
  "config" jsonb not null default '{}'::jsonb constraint bsb_guardrail_policies_config_check check (jsonb_typeof("config") = 'object'),
  "enabled" boolean not null default true,
  "updated_at" timestamptz not null default now()
);
create unique index "bsb_guardrail_policies_key" on "better_supabase"."guardrail_policies" ((coalesce("org_id"::text, '')), "agent", "stage");
alter table "better_supabase"."guardrail_policies" enable row level security;
revoke all on "better_supabase"."guardrail_policies" from public, anon, authenticated;
grant all on "better_supabase"."guardrail_policies" to service_role;

create table "better_supabase"."guardrail_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid,
  "agent" text not null,
  "stage" text not null constraint bsb_guardrail_decisions_stage_check check ("stage" in ('input', 'output')),
  "decision" text not null constraint bsb_guardrail_decisions_decision_check check ("decision" in ('allow', 'redact', 'block')),
  "reasons" jsonb not null default '[]'::jsonb constraint bsb_guardrail_decisions_reasons_check check (jsonb_typeof("reasons") = 'array'),
  "chat_id" text,
  "content_hash" text,
  "created_at" timestamptz not null default now()
);
create index "guardrail_decisions_agent_idx" on "better_supabase"."guardrail_decisions" ("agent", "created_at" desc);
create index "guardrail_decisions_tenant_idx" on "better_supabase"."guardrail_decisions" ("org_id", "created_at" desc, "id" desc);
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
  insert into "better_supabase"."guardrail_policies" ("org_id", "agent", "stage", "config", "enabled")
  values (set_guardrail_policy.tenant, set_guardrail_policy.agent, set_guardrail_policy.stage, set_guardrail_policy.config, coalesce(set_guardrail_policy.enabled, true))
  on conflict ((coalesce("org_id"::text, '')), "agent", "stage") do update set
    "config" = excluded."config", "enabled" = excluded."enabled", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
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
    and (x."org_id" is null or x."org_id" = get_guardrail_policy.tenant)
  order by (x."org_id" is null), (x."agent" = '*')
  limit 1;
  if not found or not v_row."enabled" then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
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
  insert into "better_supabase"."guardrail_decisions" ("org_id", "agent", "stage", "decision", "reasons", "chat_id", "content_hash")
  values (record_guardrail_decision.tenant, record_guardrail_decision.agent, record_guardrail_decision.stage, record_guardrail_decision.decision, coalesce(record_guardrail_decision.reasons, '[]'::jsonb), record_guardrail_decision.chat, record_guardrail_decision.content_hash)
  returning * into v_row;
  if v_row."decision" = 'block' then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) to service_role;

-- One page of the policies a tenant has saved (the system's when tenant is
-- null), ordered by agent and stage, optionally for one agent. after_agent and
-- after_stage are the last agent and stage of the previous page. It runs as
-- invoker: only the service role may call it and it reads the table directly.
create or replace function "better_supabase"."list_guardrail_policies"(tenant uuid default null, agent text default null, after_agent text default null, after_stage text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."org_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) to service_role;

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
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'tenant_id', q."org_id", 'agent', q."agent", 'stage', q."stage", 'decision', q."decision", 'reasons', q."reasons", 'chat_id', q."chat_id", 'content_hash', q."content_hash", 'created_at', q."created_at") order by q."created_at" desc), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."guardrail_decisions" x
      where (list_guardrail_decisions.agent is null or x."agent" = list_guardrail_decisions.agent)
        and (list_guardrail_decisions.decision is null or x."decision" = list_guardrail_decisions.decision)
        and (list_guardrail_decisions.tenant is null or x."org_id" = list_guardrail_decisions.tenant)
      order by x."created_at" desc
      limit least(greatest(coalesce(list_guardrail_decisions.max_rows, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) to service_role;

-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_policies"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."org_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_policies"(uuid, jsonb) to service_role;

-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_guardrail_decisions"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."org_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or (x."agent")::text = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or (x."decision")::text = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or (x."stage")::text = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_guardrail_decisions"(uuid, jsonb) to service_role;

-- One saved policy by id, or null.
create or replace function "better_supabase"."get_guardrail_policy_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$$;
revoke execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_guardrail_policy_by_id"(uuid) to service_role;

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_183_ai_guardrails.sql
-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
