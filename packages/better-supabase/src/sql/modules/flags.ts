import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { schemaPreamble } from "../shared.ts";

const NAMES: ModuleNames = {
  options: [],
  tables: {
    flags: {
      name: "flags",
      columns: {
        key: "key",
        type: "type",
        description: "description",
        variants: "variants",
        defaultVariant: "default_variant",
        enabled: "enabled",
        rules: "rules",
        rolloutPercentage: "rollout_percentage",
        rolloutVariant: "rollout_variant",
        updatedAt: "updated_at",
      },
    },
    overrides: {
      name: "flag_overrides",
      columns: {
        id: "id",
        flag: "flag_key",
        tenant: "organization_id",
        user: "user_id",
        variant: "variant",
        createdAt: "created_at",
      },
    },
  },
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const flags = ctx.table("flags");
  const overrides = ctx.table("overrides");
  const f = (logical: string): string => ctx.col("flags", logical);
  const o = (logical: string): string => ctx.col("overrides", logical);
  const fn = (name: string): string => ctx.fn(name);
  const plans = ctx.installed("entitlements")
    ? "better_supabase.tenant_entitlements(tenant)"
    : "'{}'::text[]";

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- Feature flags. variants maps a variant name to its value; rules is an
-- array of { variant, tenants?, users?, plans?, roles? }, and the first rule
-- whose lists all contain the caller's value wins. The TypeScript provider
-- evaluates the same way, so policies and the app agree.
create table if not exists ${flags} (
  ${f("key")} text primary key check (${f("key")} ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  ${f("type")} text not null default 'boolean' check (${f("type")} in ('boolean', 'string', 'number', 'object')),
  ${f("description")} text,
  ${f("variants")} jsonb not null default '{"on": true, "off": false}'::jsonb check (jsonb_typeof(${f("variants")}) = 'object'),
  ${f("defaultVariant")} text not null default 'off',
  ${f("enabled")} boolean not null default true,
  ${f("rules")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${f("rules")}) = 'array'),
  ${f("rolloutPercentage")} numeric(5, 2) not null default 0 check (${f("rolloutPercentage")} between 0 and 100),
  ${f("rolloutVariant")} text,
  ${f("updatedAt")} timestamptz not null default now(),
  check (${f("variants")} ? ${f("defaultVariant")}),
  check (${f("rolloutVariant")} is null or ${f("variants")} ? ${f("rolloutVariant")})
);
alter table ${flags} enable row level security;
revoke all on ${flags} from anon, authenticated;
grant all on ${flags} to service_role;

-- A variant for one tenant or one user; a user override beats a tenant one.
create table if not exists ${overrides} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("flag")} text not null references ${flags} (${f("key")}) on delete cascade on update cascade,
  ${o("tenant")} ${id},
  ${o("user")} uuid references auth.users (id) on delete cascade,
  ${o("variant")} text not null,
  ${o("createdAt")} timestamptz not null default now(),
  check ((${o("tenant")} is null) <> (${o("user")} is null)),
  unique nulls not distinct (${o("flag")}, ${o("tenant")}, ${o("user")})
);
create index if not exists flag_overrides_user_idx on ${overrides} (${o("user")});
alter table ${overrides} enable row level security;
revoke all on ${overrides} from anon, authenticated;
grant all on ${overrides} to service_role;

-- The rollout bucket of target for flag: the first 32 bits of
-- SHA-256(flag || '.' || target), modulo 10000, so 0.00 to 99.99 percent.
create or replace function ${fn("flag_bucket")}(flag text, target text)
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
create or replace function ${fn("flag_evaluation")}(key text, tenant ${id} default null, member uuid default auth.uid())
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  flag ${flags};
  chosen text;
  reason text := 'DEFAULT';
  rule jsonb;
  role text;
  tenant_plans text[];
  target text := coalesce(member::text, tenant::text);
begin
  select * into flag from ${flags} x where x.${f("key")} = flag_evaluation.key;
  if flag.${f("key")} is null then
    return null;
  end if;
  if not flag.${f("enabled")} then
    return jsonb_build_object('value', flag.${f("variants")} -> flag.${f("defaultVariant")}, 'variant', flag.${f("defaultVariant")}, 'reason', 'DISABLED');
  end if;
  select x.${o("variant")} into chosen from ${overrides} x
  where x.${o("flag")} = flag.${f("key")}
    and ((member is not null and x.${o("user")} = member) or (tenant is not null and x.${o("tenant")} = tenant))
  order by (x.${o("user")} is not null) desc
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    if tenant is not null then
      role := better_supabase.organization_member_role(tenant, member);
      tenant_plans := ${plans};
    end if;
    for rule in select * from jsonb_array_elements(flag.${f("rules")}) loop
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
  if chosen is null and flag.${f("rolloutVariant")} is not null and target is not null
    and ${fn("flag_bucket")}(flag.${f("key")}, target) < flag.${f("rolloutPercentage")} * 100 then
    chosen := flag.${f("rolloutVariant")};
    reason := 'SPLIT';
  end if;
  if chosen is null or not flag.${f("variants")} ? chosen then
    chosen := flag.${f("defaultVariant")};
    reason := 'DEFAULT';
  end if;
  return jsonb_build_object('value', flag.${f("variants")} -> chosen, 'variant', chosen, 'reason', reason);
end;
$$;

-- For policies:
--   using (better_supabase.flag_enabled('new_editor', organization_id))
create or replace function ${fn("flag_enabled")}(key text, tenant ${id} default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((${fn("flag_evaluation")}(key, tenant) -> 'value') = 'true'::jsonb, false)
$$;

-- Every flag with its overrides, for the TypeScript provider's cache.
create or replace function ${fn("flag_definitions")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', x.${f("key")},
    'type', x.${f("type")},
    'variants', x.${f("variants")},
    'default_variant', x.${f("defaultVariant")},
    'enabled', x.${f("enabled")},
    'rules', x.${f("rules")},
    'rollout_percentage', x.${f("rolloutPercentage")},
    'rollout_variant', x.${f("rolloutVariant")},
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v.${o("tenant")}, 'user_id', v.${o("user")}, 'variant', v.${o("variant")}))
      from ${overrides} v where v.${o("flag")} = x.${f("key")}
    ), '[]'::jsonb)
  ) order by x.${f("key")}), '[]'::jsonb)
  from ${flags} x
$$;

revoke execute on function ${fn("flag_evaluation")}(text, ${id}, uuid) from public, anon, authenticated;
revoke execute on function ${fn("flag_enabled")}(text, ${id}) from public, anon;
revoke execute on function ${fn("flag_definitions")}() from public, anon, authenticated;
grant execute on function ${fn("flag_bucket")}(text, text) to anon, authenticated, service_role;
grant execute on function ${fn("flag_evaluation")}(text, ${id}, uuid) to service_role;
grant execute on function ${fn("flag_enabled")}(text, ${id}) to authenticated, service_role;
grant execute on function ${fn("flag_definitions")}() to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "flag_bucket", args: ["text", "text"], returns: "integer" },
    {
      name: "flag_evaluation",
      args: ["text", "{id}", "uuid"],
      returns: "jsonb",
    },
    { name: "flag_enabled", args: ["text", "{id}"], returns: "boolean" },
    { name: "flag_definitions", args: [], returns: "jsonb" },
  ];
}

export const FLAGS: ModuleDefinition = {
  name: "flags",
  title: "Feature flags",
  description:
    "Feature flags with variants, targeting rules over tenant, user, plan and role, overrides and a percentage rollout bucketed by SHA-256. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature.",
  requires: ["tenant"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
