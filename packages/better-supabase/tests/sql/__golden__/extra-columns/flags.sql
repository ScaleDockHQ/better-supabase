-- ==== schema supabase/schemas/900_better_supabase_032_flags.sql
-- better-supabase module: flags
-- @bsb-block flags@3 managed
-- @bsb-hash sha256:87dd38bef3098cd1dbe5cf673942f5fc0a89d40b326f5e5c2f6c4c3e8542b7b3
-- Feature flags with variants, targeting rules over tenant, user, plan, role and custom contexts such as brand, overrides and a percentage rollout bucketed by SHA-256. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature and the Flags SDK.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
  "rollout_variant" text,
  "updated_at" timestamptz not null default now(),
  check ("variants" ? "default_variant"),
  check ("rollout_variant" is null or "variants" ? "rollout_variant")
);
alter table "better_supabase"."flags" add column if not exists "app_note" text;
alter table "better_supabase"."flags" enable row level security;
revoke all on "better_supabase"."flags" from anon, authenticated;
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
revoke all on "better_supabase"."flag_overrides" from anon, authenticated;
grant all on "better_supabase"."flag_overrides" to service_role;

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
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" or flag."archived" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
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
    if tenant is not null and flag."rules" @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and flag."rules" @? '$[*].plans' then
      tenant_plans := '{}'::text[];
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if (not rule ? 'tenants' or rule -> 'tenants' ? coalesce(tenant::text, ''))
        and (not rule ? 'users' or rule -> 'users' ? coalesce(member::text, ''))
        and (not rule ? 'roles' or rule -> 'roles' ? coalesce(role, ''))
        and (not rule ? 'plans' or rule -> 'plans' ?| coalesce(tenant_plans, '{}'))
        and (not rule ? 'contexts' or not exists (
          select 1 from jsonb_each(rule -> 'contexts') c(name, keys)
          where not (c.keys ? coalesce(context_values ->> c.name, ''))
        ))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;
  if chosen is null and flag."rollout_variant" is not null and target is not null
    and "better_supabase"."flag_bucket"(flag."key", target) < flag."rollout_percentage" * 100 then
    chosen := flag."rollout_variant";
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
    'rollout_variant', x."rollout_variant",
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
-- rollout_variant and fields (the extra columns by name); missing keys keep
-- their value (or the default for a new flag).
create or replace function "better_supabase"."save_flag"(key text, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variant")
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
    d ->> 'rollout_variant'
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
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  update "better_supabase"."flags" x set "app_note" = case when d -> 'fields' ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."flags", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(d -> 'fields') e where e.key in ('app_note'))) r
  where x."key" = save_flag.key;
  null;
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
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
revoke execute on function "better_supabase"."save_flag"(text, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_flag"(text) from public, anon;
revoke execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_flags"() to authenticated, service_role;
grant execute on function "better_supabase"."save_flag"(text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_flag"(text) to authenticated, service_role;
grant execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) to authenticated, service_role;
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_032_flags.sql
-- better-supabase module: flags
-- @bsb-block-data flags
-- @bsb-hash sha256:dd7928d2963deeab4895d76f169e49059e0970aca9ed1646755d04f7bfa49a57
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('flags', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
