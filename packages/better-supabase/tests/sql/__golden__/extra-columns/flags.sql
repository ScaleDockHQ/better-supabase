-- ==== schema supabase/schemas/900_better_supabase_032_flags.sql
-- better-supabase module: flags
-- @bsb-block flags@4 managed
-- @bsb-hash sha256:471ff88a860cd8a01a9e44bbad9c281c989e9ce77d2dd01b55b63a364fbf25c6
-- Feature flags with variants, targeting rules over tenant, user, plan, role, custom contexts such as brand and shared segments, overrides, and a scheduled percentage rollout split across weighted variants, bucketed by SHA-256. Every save records a revision you can restore. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature and the Flags SDK.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.column_default(relation text, name text, target anyelement)
returns anyelement
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
end;
$$;
revoke execute on function better_supabase.column_default(text, text, anyelement) from public, anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."flag_overrides";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."flag_overrides";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."flag_overrides";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."flag_overrides";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."flag_overrides";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Feature flags. variants maps a variant name to its value; rules is an
-- array of { variant, tenants?, users?, plans?, roles?, contexts? }, and the
-- first rule whose lists all contain the caller's value wins (contexts maps a
-- context name, such as brand, to its values). The TypeScript provider
-- evaluates the same way, so policies and the app agree. An archived flag
-- serves its default variant.
create table if not exists "better_supabase"."flags" (
  "key" text primary key check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "type" text not null default 'boolean' check ("type" in ('boolean', 'string', 'number', 'object')),
  "description" text,
  "variants" jsonb not null default '{"on": true, "off": false}'::jsonb check (jsonb_typeof("variants") = 'object'),
  "default_variant" text not null default 'off',
  "enabled" boolean not null default true,
  "archived" boolean not null default false,
  "rules" jsonb not null default '[]'::jsonb check (jsonb_typeof("rules") = 'array'),
  "rollout_percentage" numeric(5, 2) not null default 0 check ("rollout_percentage" between 0 and 100),
  "rollout_variants" jsonb not null default '[]'::jsonb check (jsonb_typeof("rollout_variants") = 'array'),
  "rollout_schedule" jsonb check ("rollout_schedule" is null or jsonb_typeof("rollout_schedule") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("variants" ? "default_variant")
);
alter table "better_supabase"."flags" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."flags" add column if not exists "rollout_variants" jsonb not null default '[]'::jsonb check (jsonb_typeof("rollout_variants") = 'array');
alter table "better_supabase"."flags" add column if not exists "rollout_schedule" jsonb check ("rollout_schedule" is null or jsonb_typeof("rollout_schedule") = 'object');
alter table "better_supabase"."flags" add column if not exists "app_note" text;
alter table "better_supabase"."flags" enable row level security;
revoke all on "better_supabase"."flags" from public, anon, authenticated;
grant all on "better_supabase"."flags" to service_role;

-- A variant for one tenant, one user or one value of a custom context (such
-- as brand acme). A user override beats a tenant one, and a tenant override
-- beats a context one.
create table if not exists "better_supabase"."flag_overrides" (
  "id" uuid primary key default gen_random_uuid(),
  "flag_key" text not null references "better_supabase"."flags" ("key") on delete cascade on update cascade,
  "organization_id" uuid,
  "user_id" uuid references auth.users (id) on delete cascade,
  "context" text check ("context" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "context_key" text check (length("context_key") between 1 and 200),
  "variant" text not null,
  "created_at" timestamptz not null default now(),
  constraint flag_overrides_target check (num_nonnulls("organization_id", "user_id", "context") = 1 and ("context" is null) = ("context_key" is null)),
  constraint flag_overrides_unique unique nulls not distinct ("flag_key", "organization_id", "user_id", "context", "context_key")
);
alter table "better_supabase"."flags" add column if not exists "archived" boolean not null default false;
alter table "better_supabase"."flag_overrides" add column if not exists "context" text check ("context" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."flag_overrides" add column if not exists "context_key" text check (length("context_key") between 1 and 200);
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."flag_overrides"'::regclass and c.contype in ('c', 'u')
      and cardinality(c.conkey) > 1
      and c.conname not in ('flag_overrides_target', 'flag_overrides_unique')
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."flag_overrides"', v_name);
  end loop;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = '"better_supabase"."flag_overrides"'::regclass and c.conname = 'flag_overrides_target') then
    alter table "better_supabase"."flag_overrides" add constraint flag_overrides_target check (num_nonnulls("organization_id", "user_id", "context") = 1 and ("context" is null) = ("context_key" is null));
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = '"better_supabase"."flag_overrides"'::regclass and c.conname = 'flag_overrides_unique') then
    alter table "better_supabase"."flag_overrides" add constraint flag_overrides_unique unique nulls not distinct ("flag_key", "organization_id", "user_id", "context", "context_key");
  end if;
end;
$$;
create index if not exists flag_overrides_user_idx on "better_supabase"."flag_overrides" ("user_id");
alter table "better_supabase"."flag_overrides" enable row level security;
revoke all on "better_supabase"."flag_overrides" from public, anon, authenticated;
grant all on "better_supabase"."flag_overrides" to service_role;

-- Every state save_flag leaves, numbered per flag, so staff can see what
-- changed and restore it. A deleted flag keeps its revisions.
create table if not exists "better_supabase"."flag_revisions" (
  "id" bigint generated always as identity primary key,
  "flag_key" text not null,
  "revision" integer not null check ("revision" > 0),
  "definition" jsonb not null check (jsonb_typeof("definition") = 'object'),
  "message" text check (length("message") <= 500),
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now(),
  constraint flag_revisions_unique unique ("flag_key", "revision")
);
create index if not exists flag_revisions_changed_by_idx on "better_supabase"."flag_revisions" ("changed_by");
alter table "better_supabase"."flag_revisions" enable row level security;
revoke all on "better_supabase"."flag_revisions" from public, anon, authenticated;
grant all on "better_supabase"."flag_revisions" to service_role;

-- Named audiences: rules is one condition, { tenants?, users?, plans?,
-- roles?, contexts? }, and a rule's segments list matches a caller in any of
-- them.
create table if not exists "better_supabase"."flag_segments" (
  "name" text primary key check ("name" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "description" text,
  "rules" jsonb not null default '{}'::jsonb check (jsonb_typeof("rules") = 'object'),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."flag_segments" enable row level security;
revoke all on "better_supabase"."flag_segments" from public, anon, authenticated;
grant all on "better_supabase"."flag_segments" to service_role;

-- The rollout bucket of target for flag: the first 32 bits of
-- SHA-256(flag || '.' || target), modulo 10000, so 0.00 to 99.99 percent.
create or replace function "better_supabase"."flag_bucket"(flag text, target text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (('x' || substr(encode(extensions.digest(flag || '.' || target, 'sha256'), 'hex'), 1, 8))::bit(32)::bigint % 10000)::integer
$$;

-- Whether a rule's or a segment's condition matches: every list it sets must
-- contain the caller's value.
create or replace function "better_supabase"."flag_condition_matches"(condition jsonb, tenant text, member text, role text, plans text[], context_values jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (not condition ? 'tenants' or condition -> 'tenants' ? coalesce(tenant, ''))
    and (not condition ? 'users' or condition -> 'users' ? coalesce(member, ''))
    and (not condition ? 'roles' or condition -> 'roles' ? coalesce(role, ''))
    and (not condition ? 'plans' or condition -> 'plans' ?| coalesce(plans, '{}'))
    and (not condition ? 'contexts' or not exists (
      select 1 from jsonb_each(condition -> 'contexts') c(name, keys)
      where not (c.keys ? coalesce(context_values ->> c.name, ''))
    ))
$$;

-- The rollout percentage at a time: percentage without a schedule; with one,
-- 0 before startAt, then each step's percentage for its durationSeconds, then
-- finalPercentage (default the last step's). rolloutPercentageAt() in
-- TypeScript computes the same number.
create or replace function "better_supabase"."flag_rollout_percentage"(percentage numeric, schedule jsonb, at timestamptz default now())
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  start timestamptz;
  elapsed numeric;
  step jsonb;
begin
  if schedule is null or jsonb_typeof(schedule) <> 'object' then
    return percentage;
  end if;
  begin
    start := (schedule ->> 'startAt')::timestamptz;
  exception when others then
    return 0;
  end;
  if start is null or at < start then
    return 0;
  end if;
  elapsed := extract(epoch from at - start);
  for step in select * from jsonb_array_elements(case when jsonb_typeof(schedule -> 'steps') = 'array' then schedule -> 'steps' else '[]'::jsonb end) loop
    if elapsed < coalesce((step ->> 'durationSeconds')::numeric, 0) then
      return coalesce((step ->> 'percentage')::numeric, 0);
    end if;
    elapsed := elapsed - coalesce((step ->> 'durationSeconds')::numeric, 0);
  end loop;
  return coalesce((schedule ->> 'finalPercentage')::numeric, (schedule -> 'steps' -> -1 ->> 'percentage')::numeric, 0);
end;
$$;

-- { value, variant, reason } of flag for a tenant and a user, or null for
-- an unknown flag. contexts holds custom context values, such as
-- {"brand": "acme"}; a declared context it leaves out is read from the
-- tenant. Reasons follow OpenFeature: DISABLED, TARGETING_MATCH, SPLIT,
-- DEFAULT.
drop function if exists "better_supabase"."flag_evaluation"(text, uuid, uuid);
create or replace function "better_supabase"."flag_evaluation"(key text, tenant uuid default null, member uuid default auth.uid(), contexts jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  flag "better_supabase"."flags";
  chosen text;
  reason text := 'DEFAULT';
  rule jsonb;
  role text;
  tenant_plans text[];
  target text := coalesce(member::text, tenant::text);
  context_values jsonb := case when jsonb_typeof(contexts) = 'object' then contexts else '{}'::jsonb end;
  segment_rules jsonb := '{}'::jsonb;
  conditions jsonb;
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" or flag."archived" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
  if flag."rules" @? '$[*].segments' then
    select coalesce(jsonb_object_agg(g."name", g."rules"), '{}'::jsonb) into segment_rules
    from "better_supabase"."flag_segments" g
    where g."name" in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(flag."rules") e where jsonb_typeof(e.value -> 'segments') = 'array');
  end if;
  -- The rules and the segments they name, for the lookups below.
  conditions := flag."rules" || coalesce((select jsonb_agg(v) from jsonb_each(segment_rules) as e(k, v)), '[]'::jsonb);
  select x."variant" into chosen from "better_supabase"."flag_overrides" x
  where x."flag_key" = flag."key"
    and ((member is not null and x."user_id" = member)
      or (tenant is not null and x."organization_id" = tenant)
      or (x."context" is not null and x."context_key" = context_values ->> x."context"))
  order by (x."user_id" is not null) desc, (x."organization_id" is not null) desc,
    array_position(array[]::text[], x."context") nulls last, x."context"
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    -- The role and plan lookups run only for flags with rules that read them.
    if tenant is not null and conditions @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and conditions @? '$[*].plans' then
      tenant_plans := '{}'::text[];
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if "better_supabase"."flag_condition_matches"(rule, tenant::text, member::text, role, tenant_plans, context_values)
        and (not rule ? 'segments' or exists (
          select 1 from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'segments') = 'array' then rule -> 'segments' else '[]'::jsonb end) n(name)
          where segment_rules ? n.name
            and "better_supabase"."flag_condition_matches"(segment_rules -> n.name, tenant::text, member::text, role, tenant_plans, context_values)
        ))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;
  if chosen is null and jsonb_array_length(flag."rollout_variants") > 0 and target is not null
    and "better_supabase"."flag_bucket"(flag."key", target) < "better_supabase"."flag_rollout_percentage"(flag."rollout_percentage", flag."rollout_schedule", now()) * 100 then
    -- A second bucket, so growing the rollout never moves a target between
    -- variants.
    select w.split ->> 'variant' into chosen
    from (
      select e.split, e.i, sum(coalesce((e.split ->> 'weight')::numeric, 0) * 100) over (order by e.i) as edge
      from jsonb_array_elements(flag."rollout_variants") with ordinality as e(split, i)
    ) w
    where "better_supabase"."flag_bucket"(flag."key" || '/split', target) < w.edge
    order by w.i
    limit 1;
    reason := 'SPLIT';
  end if;
  if chosen is null or not flag."variants" ? chosen then
    chosen := flag."default_variant";
    reason := 'DEFAULT';
  end if;
  return jsonb_build_object('value', flag."variants" -> chosen, 'variant', chosen, 'reason', reason);
end;
$$;

-- For policies on one row (tenant_ids_with_flag is the form for many rows):
--   using (better_supabase.flag_enabled('new_editor', organization_id))
create or replace function "better_supabase"."flag_enabled"(key text, tenant uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(("better_supabase"."flag_evaluation"(key, tenant) -> 'value') = 'true'::jsonb, false)
$$;

-- The caller's tenants where key is on. In a policy this evaluates the flag
-- once per tenant instead of once per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_flag('new_editor')))
create or replace function "better_supabase"."tenant_ids_with_flag"(key text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from better_supabase.member_organization_ids() as t(id)
  where "better_supabase"."flag_enabled"(tenant_ids_with_flag.key, t.id)
$$;

-- Every flag with its overrides, for the TypeScript provider's cache. The
-- overrides come in the order flag_evaluation tries them.
create or replace function "better_supabase"."flag_definitions"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', x."key",
    'type', x."type",
    'description', x."description",
    'variants', x."variants",
    'default_variant', x."default_variant",
    'enabled', x."enabled",
    'archived', x."archived",
    'rules', x."rules",
    'rollout_percentage', x."rollout_percentage",
    'rollout_variants', x."rollout_variants",
    'rollout_schedule', x."rollout_schedule",
    'segments', case when x."rules" @? '$[*].segments' then (
      select coalesce(jsonb_object_agg(g."name", g."rules"), '{}'::jsonb)
      from "better_supabase"."flag_segments" g
      where g."name" in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(x."rules") e where jsonb_typeof(e.value -> 'segments') = 'array')
    ) else '{}'::jsonb end,
    'created_at', x."created_at",
    'updated_at', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note"),
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v."organization_id", 'user_id', v."user_id", 'context', v."context", 'context_key', v."context_key", 'variant', v."variant")
        order by (v."user_id" is not null) desc, (v."organization_id" is not null) desc,
          array_position(array[]::text[], v."context") nulls last, v."context")
      from "better_supabase"."flag_overrides" v where v."flag_key" = x."key"
    ), '[]'::jsonb)
  ) order by x."key"), '[]'::jsonb)
  from "better_supabase"."flags" x
$$;

-- Staff management, for an admin page over the Data API: platform staff with
-- flags.manage (with the access module) or the service role.
create or replace function "better_supabase"."list_flags"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return "better_supabase"."flag_definitions"();
end;
$$;

-- Creates or updates a flag from definition: type, description, variants,
-- default_variant, enabled, archived, rules, rollout_percentage,
-- rollout_variants ([{ variant, weight }]), rollout_schedule ({ startAt,
-- steps: [{ percentage, durationSeconds }], finalPercentage }) and fields
-- (the extra columns by name); missing keys keep their value (or the default
-- for a new flag). Each save records a revision with message.
drop function if exists "better_supabase"."save_flag"(text, jsonb);
create or replace function "better_supabase"."save_flag"(key text, definition jsonb, message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
  saved jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if d ? 'rollout_variants' and jsonb_typeof(d -> 'rollout_variants') = 'array' and exists (
    select 1 from jsonb_array_elements(d -> 'rollout_variants') e
    where jsonb_typeof(e.value) <> 'object' or not (coalesce(d -> 'variants', (select x."variants" from "better_supabase"."flags" x where x."key" = save_flag.key), '{"on": true, "off": false}'::jsonb) ? (e.value ->> 'variant'))
      or coalesce((e.value ->> 'weight')::numeric, -1) not between 0 and 100
  ) then
    raise exception 'Each rollout variant needs a known variant and a weight from 0 to 100' using errcode = '22023', hint = 'FLAGS_ROLLOUT_VARIANTS';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variants", "rollout_schedule", "app_note")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce((d ->> 'archived')::boolean, false),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    coalesce(d -> 'rollout_variants', '[]'::jsonb),
    nullif(d -> 'rollout_schedule', 'null'::jsonb), case when coalesce(d -> 'fields', '{}'::jsonb) ? 'app_note' then (jsonb_populate_record(null::"better_supabase"."flags", jsonb_build_object('app_note', coalesce(d -> 'fields', '{}'::jsonb) -> 'app_note')))."app_note" else better_supabase.column_default('"better_supabase"."flags"', 'app_note', (null::"better_supabase"."flags")."app_note") end
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "archived" = case when d ? 'archived' then excluded."archived" else x."archived" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variants" = case when d ? 'rollout_variants' then excluded."rollout_variants" else x."rollout_variants" end,
    "rollout_schedule" = case when d ? 'rollout_schedule' then excluded."rollout_schedule" else x."rollout_schedule" end,
    "updated_at" = now();
  update "better_supabase"."flags" x set "app_note" = case when d -> 'fields' ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."flags", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(d -> 'fields') e where e.key in ('app_note'))) r
  where x."key" = save_flag.key;
  saved := (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
  insert into "better_supabase"."flag_revisions" ("flag_key", "revision", "definition", "message", "changed_by")
  values (
    save_flag.key,
    coalesce((select max(h."revision") from "better_supabase"."flag_revisions" h where h."flag_key" = save_flag.key), 0) + 1,
    saved - 'overrides' - 'segments',
    save_flag.message,
    (select u.id from auth.users u where u.id = auth.uid())
  );
  null;
  return saved;
end;
$$;

-- The revisions of a flag, newest first.
create or replace function "better_supabase"."flag_history"(key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('revision', h."revision", 'definition', h."definition", 'message', h."message", 'changed_by', h."changed_by", 'changed_at', h."changed_at") order by h."revision" desc)
    from "better_supabase"."flag_revisions" h where h."flag_key" = flag_history.key
  ), '[]'::jsonb);
end;
$$;

-- Saves a revision again as a new one, recreating a deleted flag; null when
-- the revision doesn't exist. Overrides are not part of a revision.
create or replace function "better_supabase"."restore_flag"(key text, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored jsonb;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  select h."definition" into stored from "better_supabase"."flag_revisions" h
  where h."flag_key" = restore_flag.key and h."revision" = restore_flag.revision;
  if stored is null then
    return null;
  end if;
  return "better_supabase"."save_flag"(restore_flag.key, stored - 'key' - 'created_at' - 'updated_at', 'Restored revision ' || restore_flag.revision);
end;
$$;

create or replace function "better_supabase"."list_flag_segments"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('name', g."name", 'description', g."description", 'rules', g."rules") order by g."name")
    from "better_supabase"."flag_segments" g
  ), '[]'::jsonb);
end;
$$;

-- Creates or replaces a segment; rules naming it see the change at once.
create or replace function "better_supabase"."save_flag_segment"(name text, description text, rules jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flag_segments" as g ("name", "description", "rules")
  values (save_flag_segment.name, save_flag_segment.description, coalesce(save_flag_segment.rules, '{}'::jsonb))
  on conflict ("name") do update set
    "description" = excluded."description",
    "rules" = excluded."rules",
    "updated_at" = now();
  return jsonb_build_object('name', save_flag_segment.name, 'description', save_flag_segment.description, 'rules', coalesce(save_flag_segment.rules, '{}'::jsonb));
end;
$$;

create or replace function "better_supabase"."delete_flag_segment"(name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flag_segments" g where g."name" = delete_flag_segment.name;
  return found;
end;
$$;

create or replace function "better_supabase"."delete_flag"(key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;

-- Sets the variant of flag for one tenant, one user, or one context value
-- (context and context_key together); pass exactly one target. A null
-- variant removes the override. Returns whether a row changed.
drop function if exists "better_supabase"."set_flag_override"(text, text, uuid, uuid);
create or replace function "better_supabase"."set_flag_override"(key text, variant text, tenant uuid default null, member uuid default null, context text default null, context_key text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if num_nonnulls(tenant, member, context) <> 1 or (context is null) <> (context_key is null) then
    raise exception 'Pass one target: a tenant, a member, or a context with its key' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member
      and v."context" is not distinct from set_flag_override.context
      and v."context_key" is not distinct from set_flag_override.context_key;
    if not found then
      return false;
    end if;
    null;
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "context", "context_key", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.context, set_flag_override.context_key, set_flag_override.variant)
  on conflict on constraint flag_overrides_unique do update set "variant" = excluded."variant";
  null;
  return true;
end;
$$;

revoke execute on function "better_supabase"."list_flags"() from public, anon;
revoke execute on function "better_supabase"."save_flag"(text, jsonb, text) from public, anon;
revoke execute on function "better_supabase"."delete_flag"(text) from public, anon;
revoke execute on function "better_supabase"."flag_history"(text) from public, anon;
revoke execute on function "better_supabase"."restore_flag"(text, integer) from public, anon;
revoke execute on function "better_supabase"."list_flag_segments"() from public, anon;
revoke execute on function "better_supabase"."save_flag_segment"(text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_flag_segment"(text) from public, anon;
revoke execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_flags"() to authenticated, service_role;
grant execute on function "better_supabase"."save_flag"(text, jsonb, text) to authenticated, service_role;
grant execute on function "better_supabase"."delete_flag"(text) to authenticated, service_role;
grant execute on function "better_supabase"."flag_history"(text) to authenticated, service_role;
grant execute on function "better_supabase"."restore_flag"(text, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_flag_segments"() to authenticated, service_role;
grant execute on function "better_supabase"."save_flag_segment"(text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_flag_segment"(text) to authenticated, service_role;
grant execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."flag_condition_matches"(jsonb, text, text, text, text[], jsonb) to anon, authenticated, service_role;
grant execute on function "better_supabase"."flag_rollout_percentage"(numeric, jsonb, timestamptz) to anon, authenticated, service_role;
revoke execute on function "better_supabase"."flag_evaluation"(text, uuid, uuid, jsonb) from public, anon, authenticated;
revoke execute on function "better_supabase"."flag_enabled"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."flag_definitions"() from public, anon, authenticated;
revoke execute on function "better_supabase"."tenant_ids_with_flag"(text) from public, anon;
grant execute on function "better_supabase"."tenant_ids_with_flag"(text) to authenticated, service_role;
grant execute on function "better_supabase"."flag_bucket"(text, text) to anon, authenticated, service_role;
grant execute on function "better_supabase"."flag_evaluation"(text, uuid, uuid, jsonb) to service_role;
grant execute on function "better_supabase"."flag_enabled"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."flag_definitions"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_032_flags.sql
-- better-supabase module: flags
-- @bsb-block-data flags
-- @bsb-hash sha256:4036cb86aa3b85d73b2ac180acf313c89af7cdb5b89f3c1de52a83f004a060dd
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('flags', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
