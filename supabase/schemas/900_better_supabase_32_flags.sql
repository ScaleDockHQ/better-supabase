-- better-supabase module: flags (0.5.1)
-- @bs-module flags@2 managed
-- Feature flags with variants, targeting rules over tenant, user, plan and role, overrides and a percentage rollout bucketed by SHA-256. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Feature flags. variants maps a variant name to its value; rules is an
-- array of { variant, tenants?, users?, plans?, roles? }, and the first rule
-- whose lists all contain the caller's value wins. The TypeScript provider
-- evaluates the same way, so policies and the app agree.
create table if not exists "better_supabase"."flags" (
  "key" text primary key check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "type" text not null default 'boolean' check ("type" in ('boolean', 'string', 'number', 'object')),
  "description" text,
  "variants" jsonb not null default '{"on": true, "off": false}'::jsonb check (jsonb_typeof("variants") = 'object'),
  "default_variant" text not null default 'off',
  "enabled" boolean not null default true,
  "rules" jsonb not null default '[]'::jsonb check (jsonb_typeof("rules") = 'array'),
  "rollout_percentage" numeric(5, 2) not null default 0 check ("rollout_percentage" between 0 and 100),
  "rollout_variant" text,
  "updated_at" timestamptz not null default now(),
  check ("variants" ? "default_variant"),
  check ("rollout_variant" is null or "variants" ? "rollout_variant")
);
alter table "better_supabase"."flags" enable row level security;
revoke all on "better_supabase"."flags" from anon, authenticated;
grant all on "better_supabase"."flags" to service_role;

-- A variant for one tenant or one user; a user override beats a tenant one.
create table if not exists "better_supabase"."flag_overrides" (
  "id" uuid primary key default gen_random_uuid(),
  "flag_key" text not null references "better_supabase"."flags" ("key") on delete cascade on update cascade,
  "organization_id" uuid,
  "user_id" uuid references auth.users (id) on delete cascade,
  "variant" text not null,
  "created_at" timestamptz not null default now(),
  check (("organization_id" is null) <> ("user_id" is null)),
  unique nulls not distinct ("flag_key", "organization_id", "user_id")
);
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
-- an unknown flag. Reasons follow OpenFeature: DISABLED, TARGETING_MATCH,
-- SPLIT, DEFAULT.
create or replace function "better_supabase"."flag_evaluation"(key text, tenant uuid default null, member uuid default auth.uid())
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
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
  select x."variant" into chosen from "better_supabase"."flag_overrides" x
  where x."flag_key" = flag."key"
    and ((member is not null and x."user_id" = member) or (tenant is not null and x."organization_id" = tenant))
  order by (x."user_id" is not null) desc
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    -- The role and plan lookups run only for flags with rules that read them.
    if tenant is not null and flag."rules" @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and flag."rules" @? '$[*].plans' then
      tenant_plans := better_supabase.tenant_entitlements(tenant);
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if (not rule ? 'tenants' or rule -> 'tenants' ? coalesce(tenant::text, ''))
        and (not rule ? 'users' or rule -> 'users' ? coalesce(member::text, ''))
        and (not rule ? 'roles' or rule -> 'roles' ? coalesce(role, ''))
        and (not rule ? 'plans' or rule -> 'plans' ?| coalesce(tenant_plans, '{}'))
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

-- Every flag with its overrides, for the TypeScript provider's cache.
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
    'variants', x."variants",
    'default_variant', x."default_variant",
    'enabled', x."enabled",
    'rules', x."rules",
    'rollout_percentage', x."rollout_percentage",
    'rollout_variant', x."rollout_variant",
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v."organization_id", 'user_id', v."user_id", 'variant', v."variant"))
      from "better_supabase"."flag_overrides" v where v."flag_key" = x."key"
    ), '[]'::jsonb)
  ) order by x."key"), '[]'::jsonb)
  from "better_supabase"."flags" x
$$;

-- Staff management, for an admin page over the Data API: platform staff with
-- flags.manage or the service role.
create or replace function "better_supabase"."list_flags"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return "better_supabase"."flag_definitions"();
end;
$$;

-- Creates or updates a flag from definition: type, description, variants,
-- default_variant, enabled, rules, rollout_percentage and rollout_variant;
-- missing keys keep their value (or the default for a new flag).
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
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
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  return found;
end;
$$;

-- Sets the variant of flag for one tenant or one user (pass exactly one);
-- a null variant removes the override. Returns whether a row changed.
create or replace function "better_supabase"."set_flag_override"(key text, variant text, tenant uuid default null, member uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if (tenant is null) = (member is null) then
    raise exception 'Pass a tenant or a member, not both' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member;
    return found;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.variant)
  on conflict ("flag_key", "organization_id", "user_id") do update set "variant" = excluded."variant";
  return true;
end;
$$;

revoke execute on function "better_supabase"."list_flags"() from public, anon;
revoke execute on function "better_supabase"."save_flag"(text, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_flag"(text) from public, anon;
revoke execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_flags"() to authenticated, service_role;
grant execute on function "better_supabase"."save_flag"(text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_flag"(text) to authenticated, service_role;
grant execute on function "better_supabase"."set_flag_override"(text, text, uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."flag_evaluation"(text, uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."flag_enabled"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."flag_definitions"() from public, anon, authenticated;
revoke execute on function "better_supabase"."tenant_ids_with_flag"(text) from public, anon;
grant execute on function "better_supabase"."tenant_ids_with_flag"(text) to authenticated, service_role;
grant execute on function "better_supabase"."flag_bucket"(text, text) to anon, authenticated, service_role;
grant execute on function "better_supabase"."flag_evaluation"(text, uuid, uuid) to service_role;
grant execute on function "better_supabase"."flag_enabled"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."flag_definitions"() to service_role;

-- sql.modules.flags.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."list_flags"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_flags"() $$;
revoke execute on function "api"."list_flags"() from public, anon;
grant execute on function "api"."list_flags"() to authenticated, service_role;

create or replace function "api"."save_flag"(key text, definition jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_flag"($1, $2) $$;
revoke execute on function "api"."save_flag"(text, jsonb) from public, anon;
grant execute on function "api"."save_flag"(text, jsonb) to authenticated, service_role;

create or replace function "api"."delete_flag"(key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_flag"($1) $$;
revoke execute on function "api"."delete_flag"(text) from public, anon;
grant execute on function "api"."delete_flag"(text) to authenticated, service_role;

create or replace function "api"."set_flag_override"(key text, variant text, tenant uuid default null, member uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_flag_override"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_flag_override"(text, text, uuid, uuid) from public, anon;
grant execute on function "api"."set_flag_override"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "api"."tenant_ids_with_flag"(key text)
returns setof uuid
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."tenant_ids_with_flag"($1) $$;
revoke execute on function "api"."tenant_ids_with_flag"(text) from public, anon;
grant execute on function "api"."tenant_ids_with_flag"(text) to authenticated, service_role;

create or replace function "api"."flag_bucket"(flag text, target text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."flag_bucket"($1, $2) $$;
revoke execute on function "api"."flag_bucket"(text, text) from public;
grant execute on function "api"."flag_bucket"(text, text) to anon, authenticated, service_role;

create or replace function "api"."flag_evaluation"(key text, tenant uuid default null, member uuid default auth.uid())
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."flag_evaluation"($1, $2, $3) $$;
revoke execute on function "api"."flag_evaluation"(text, uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."flag_evaluation"(text, uuid, uuid) to service_role;

create or replace function "api"."flag_enabled"(key text, tenant uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."flag_enabled"($1, $2) $$;
revoke execute on function "api"."flag_enabled"(text, uuid) from public, anon;
grant execute on function "api"."flag_enabled"(text, uuid) to authenticated, service_role;

create or replace function "api"."flag_definitions"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."flag_definitions"() $$;
revoke execute on function "api"."flag_definitions"() from public, anon, authenticated;
grant execute on function "api"."flag_definitions"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
