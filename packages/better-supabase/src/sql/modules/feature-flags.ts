import type { FeatureFlagsEvents } from "../../blocks/feature-flags/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsJson,
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<FeatureFlagsEvents> = {
  "flag.saved": { subject: "flags", payload: ["key"] },
  "flag.deleted": { subject: "flags", payload: ["key"] },
  "flag.override_set": {
    subject: "flags",
    payload: [
      "key",
      "variant",
      "organizationId",
      "userId",
      "context",
      "contextKey",
    ],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["contexts", "extraColumns"],
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
        archived: "archived",
        rules: "rules",
        rolloutPercentage: "rollout_percentage",
        rolloutVariant: "rollout_variant",
        updatedAt: "updated_at",
      },
    },
    overrides: {
      name: "flag_overrides",
      lifecycle: { user: "user", tenant: "tenant" },
      columns: {
        id: "id",
        flag: "flag_key",
        tenant: "organization_id",
        user: "user_id",
        context: "context",
        contextKey: "context_key",
        variant: "variant",
        createdAt: "created_at",
      },
    },
  },
};

/** A context name: what rules and overrides call it, e.g. `brand`. */
const CONTEXT_NAME = /^[a-z][a-z0-9_]{0,62}$/;

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

/** A custom context and how to read a tenant's value of it. */
interface FlagContextSource {
  readonly name: string;
  /** Quoted `schema.table`. */
  readonly table: string;
  /** Quoted column holding the value. */
  readonly column: string;
  /** Quoted column holding the tenant id. */
  readonly tenant: string;
}

/**
 * `options.contexts`: a context name to `{ table, column, tenant? }`, the table
 * and column that hold a tenant's value. `tenant` names the column with the
 * tenant id and defaults to `id`, for a column on the tenant table.
 */
function contextsOf(ctx: BlockSqlContext): readonly FlagContextSource[] {
  const where = "blocks['feature-flags'].options.contexts";
  const option = ctx.option("contexts");

  if (option === undefined) {
    return [];
  }

  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must map a context name to { table, column, tenant? }`,
    );
  }

  return Object.entries(option).map(
    ([name, source]: [string, unknown]): FlagContextSource => {
      if (!CONTEXT_NAME.test(name)) {
        throw new TypeError(
          `${where}: "${name}" must be a lowercase identifier, such as brand`,
        );
      }

      if (typeof source !== "object" || source === null) {
        throw new TypeError(
          `${where}.${name} must be { table, column, tenant? }`,
        );
      }

      const entries = new Map<string, unknown>(Object.entries(source));

      const ident = (key: string, fallback?: string): string => {
        const value = entries.get(key) ?? fallback;

        if (typeof value !== "string" || !IDENT.test(value)) {
          throw new TypeError(
            `${where}.${name}.${key} must be a lowercase identifier`,
          );
        }

        return sqlIdent(value);
      };

      const table = entries.get("table");

      if (
        typeof table !== "string" ||
        table.split(".").length > 2 ||
        !table.split(".").every((part) => IDENT.test(part))
      ) {
        throw new TypeError(
          `${where}.${name}.table must be "table" or "schema.table"`,
        );
      }

      return {
        name,
        table: quotedTable(table),
        column: ident("column"),
        tenant: ident("tenant", "id"),
      };
    },
  );
}

/** The check and unique constraints of `flag_overrides` from version 3. */
function overrideConstraints(ctx: BlockSqlContext): {
  readonly target: string;
  readonly unique: string;
} {
  const o = (logical: string): string => ctx.col("overrides", logical);

  return {
    target: `constraint flag_overrides_target check (num_nonnulls(${o("tenant")}, ${o("user")}, ${o("context")}) = 1 and (${o("context")} is null) = (${o("contextKey")} is null))`,
    unique: `constraint flag_overrides_unique unique nulls not distinct (${o("flag")}, ${o("tenant")}, ${o("user")}, ${o("context")}, ${o("contextKey")})`,
  };
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const flags = ctx.table("flags");
  const overrides = ctx.table("overrides");
  const f = (logical: string): string => ctx.col("flags", logical);
  const o = (logical: string): string => ctx.col("overrides", logical);
  const fn = (name: string): string => ctx.fn(name);

  const manage = ctx.staff(
    ctx.permission("manage", OPERATIONS["feature-flags.manage"]),
  );

  const denied = `if not ${manage} then
    ${fail("FLAGS_FORBIDDEN", "Not allowed to manage feature flags")}
  end if;`;

  const flagEvent = (type: string, key: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('key', ${key})`,
      subject: `'flags/' || ${key}`,
      audit: { category: "configuration", targetType: "flag", recordId: key },
    });

  const overrideEvent = ctx.record({
    type: "flag.override_set",
    payload:
      "jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)",
    subject: "'flags/' || set_flag_override.key",
    tenant: "set_flag_override.tenant",
    audit: {
      category: "configuration",
      targetType: "flag",
      recordId: "set_flag_override.key",
    },
  });

  const plans = ctx.entitlements("tenant", "'{}'::text[]");
  const extras = ctx.extraColumns("flags");
  const contexts = contextsOf(ctx);
  const constraints = overrideConstraints(ctx);
  const order = `array[${contexts.map((c) => sqlString(c.name)).join(", ")}]::text[]`;

  // Each declared context missing from the caller's values is read from the
  // tenant, and only for a flag whose rules or overrides name a context.
  const resolve = contexts.length
    ? `
  if tenant is not null and (flag.${f("rules")} @? '$[*].contexts' or exists (
    select 1 from ${overrides} x where x.${o("flag")} = flag.${f("key")} and x.${o("context")} is not null
  )) then${contexts
    .map(
      (c) => `
    if not context_values ? ${sqlString(c.name)} then
      context_values := context_values || jsonb_build_object(${sqlString(c.name)}, (select t.${c.column}::text from ${c.table} t where t.${c.tenant} = flag_evaluation.tenant limit 1));
    end if;`,
    )
    .join("")}
  end if;`
    : "";

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- Feature flags. variants maps a variant name to its value; rules is an
-- array of { variant, tenants?, users?, plans?, roles?, contexts? }, and the
-- first rule whose lists all contain the caller's value wins (contexts maps a
-- context name, such as brand, to its values). The TypeScript provider
-- evaluates the same way, so policies and the app agree. An archived flag
-- serves its default variant.
create table if not exists ${flags} (
  ${f("key")} text primary key check (${f("key")} ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  ${f("type")} text not null default 'boolean' check (${f("type")} in ('boolean', 'string', 'number', 'object')),
  ${f("description")} text,
  ${f("variants")} jsonb not null default '{"on": true, "off": false}'::jsonb check (jsonb_typeof(${f("variants")}) = 'object'),
  ${f("defaultVariant")} text not null default 'off',
  ${f("enabled")} boolean not null default true,
  ${f("archived")} boolean not null default false,
  ${f("rules")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${f("rules")}) = 'array'),
  ${f("rolloutPercentage")} numeric(5, 2) not null default 0 check (${f("rolloutPercentage")} between 0 and 100),
  ${f("rolloutVariant")} text,
  ${f("updatedAt")} timestamptz not null default now(),
  check (${f("variants")} ? ${f("defaultVariant")}),
  check (${f("rolloutVariant")} is null or ${f("variants")} ? ${f("rolloutVariant")})
);${addExtraColumns(flags, extras)}
${lockTable(flags)}

-- A variant for one tenant, one user or one value of a custom context (such
-- as brand acme). A user override beats a tenant one, and a tenant override
-- beats a context one.
create table if not exists ${overrides} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("flag")} text not null references ${flags} (${f("key")}) on delete cascade on update cascade,
  ${o("tenant")} ${id},
  ${o("user")} uuid references auth.users (id) on delete cascade,
  ${o("context")} text check (${o("context")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${o("contextKey")} text check (length(${o("contextKey")}) between 1 and 200),
  ${o("variant")} text not null,
  ${o("createdAt")} timestamptz not null default now(),
  ${constraints.target},
  ${constraints.unique}
);
${upgradeContexts(ctx)}
create index if not exists flag_overrides_user_idx on ${overrides} (${o("user")});
${lockTable(overrides)}

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
-- an unknown flag. contexts holds custom context values, such as
-- {"brand": "acme"}; a declared context it leaves out is read from the
-- tenant. Reasons follow OpenFeature: DISABLED, TARGETING_MATCH, SPLIT,
-- DEFAULT.
drop function if exists ${fn("flag_evaluation")}(text, ${id}, uuid);
create or replace function ${fn("flag_evaluation")}(key text, tenant ${id} default null, member uuid default auth.uid(), contexts jsonb default null)
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
  context_values jsonb := case when jsonb_typeof(contexts) = 'object' then contexts else '{}'::jsonb end;
begin
  select * into flag from ${flags} x where x.${f("key")} = flag_evaluation.key;
  if flag.${f("key")} is null then
    return null;
  end if;
  if not flag.${f("enabled")} or flag.${f("archived")} then
    return jsonb_build_object('value', flag.${f("variants")} -> flag.${f("defaultVariant")}, 'variant', flag.${f("defaultVariant")}, 'reason', 'DISABLED');
  end if;${resolve}
  select x.${o("variant")} into chosen from ${overrides} x
  where x.${o("flag")} = flag.${f("key")}
    and ((member is not null and x.${o("user")} = member)
      or (tenant is not null and x.${o("tenant")} = tenant)
      or (x.${o("context")} is not null and x.${o("contextKey")} = context_values ->> x.${o("context")}))
  order by (x.${o("user")} is not null) desc, (x.${o("tenant")} is not null) desc,
    array_position(${order}, x.${o("context")}) nulls last, x.${o("context")}
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    -- The role and plan lookups run only for flags with rules that read them.
    if tenant is not null and flag.${f("rules")} @? '$[*].roles' then
      role := ${ctx.of("memberships").fn("organization_member_role")}(tenant, member);
    end if;
    if tenant is not null and flag.${f("rules")} @? '$[*].plans' then
      tenant_plans := ${plans};
    end if;
    for rule in select * from jsonb_array_elements(flag.${f("rules")}) loop
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

-- For policies on one row (tenant_ids_with_flag is the form for many rows):
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

-- The caller's tenants where key is on. In a policy this evaluates the flag
-- once per tenant instead of once per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_flag('new_editor')))
create or replace function ${fn("tenant_ids_with_flag")}(key text)
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from ${ctx.of("memberships").fn("member_organization_ids")}() as t(id)
  where ${fn("flag_enabled")}(tenant_ids_with_flag.key, t.id)
$$;

-- Every flag with its overrides, for the TypeScript provider's cache. The
-- overrides come in the order flag_evaluation tries them.
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
    'description', x.${f("description")},
    'variants', x.${f("variants")},
    'default_variant', x.${f("defaultVariant")},
    'enabled', x.${f("enabled")},
    'archived', x.${f("archived")},
    'rules', x.${f("rules")},
    'rollout_percentage', x.${f("rolloutPercentage")},
    'rollout_variant', x.${f("rolloutVariant")},
    'updated_at', x.${f("updatedAt")}${extraFieldsJson("x", extras)},
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v.${o("tenant")}, 'user_id', v.${o("user")}, 'context', v.${o("context")}, 'context_key', v.${o("contextKey")}, 'variant', v.${o("variant")})
        order by (v.${o("user")} is not null) desc, (v.${o("tenant")} is not null) desc,
          array_position(${order}, v.${o("context")}) nulls last, v.${o("context")})
      from ${overrides} v where v.${o("flag")} = x.${f("key")}
    ), '[]'::jsonb)
  ) order by x.${f("key")}), '[]'::jsonb)
  from ${flags} x
$$;

-- Staff management, for an admin page over the Data API: platform staff with
-- flags.manage${ctx.installed("permissions") ? "" : " (with the access module)"} or the service role.
create or replace function ${fn("list_flags")}()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  ${denied}
  return ${fn("flag_definitions")}();
end;
$$;

-- Creates or updates a flag from definition: type, description, variants,
-- default_variant, enabled, archived, rules, rollout_percentage,
-- rollout_variant and fields (the extra columns by name); missing keys keep
-- their value (or the default for a new flag).
create or replace function ${fn("save_flag")}(key text, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  ${denied}
  insert into ${flags} as x (${f("key")}, ${f("type")}, ${f("description")}, ${f("variants")}, ${f("defaultVariant")}, ${f("enabled")}, ${f("archived")}, ${f("rules")}, ${f("rolloutPercentage")}, ${f("rolloutVariant")})
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
  on conflict (${f("key")}) do update set
    ${f("type")} = case when d ? 'type' then excluded.${f("type")} else x.${f("type")} end,
    ${f("description")} = case when d ? 'description' then excluded.${f("description")} else x.${f("description")} end,
    ${f("variants")} = case when d ? 'variants' then excluded.${f("variants")} else x.${f("variants")} end,
    ${f("defaultVariant")} = case when d ? 'default_variant' then excluded.${f("defaultVariant")} else x.${f("defaultVariant")} end,
    ${f("enabled")} = case when d ? 'enabled' then excluded.${f("enabled")} else x.${f("enabled")} end,
    ${f("archived")} = case when d ? 'archived' then excluded.${f("archived")} else x.${f("archived")} end,
    ${f("rules")} = case when d ? 'rules' then excluded.${f("rules")} else x.${f("rules")} end,
    ${f("rolloutPercentage")} = case when d ? 'rollout_percentage' then excluded.${f("rolloutPercentage")} else x.${f("rolloutPercentage")} end,
    ${f("rolloutVariant")} = case when d ? 'rollout_variant' then excluded.${f("rolloutVariant")} else x.${f("rolloutVariant")} end,
    ${f("updatedAt")} = now();${writeExtraColumns(flags, extras, "d -> 'fields'", `x.${f("key")} = save_flag.key`)}
  ${flagEvent("flag.saved", "save_flag.key")}
  return (select v from jsonb_array_elements(${fn("flag_definitions")}()) v where v ->> 'key' = save_flag.key);
end;
$$;

create or replace function ${fn("delete_flag")}(key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${denied}
  delete from ${flags} x where x.${f("key")} = delete_flag.key;
  if not found then
    return false;
  end if;
  ${flagEvent("flag.deleted", "delete_flag.key")}
  return true;
end;
$$;

-- Sets the variant of flag for one tenant, one user, or one context value
-- (context and context_key together); pass exactly one target. A null
-- variant removes the override. Returns whether a row changed.
drop function if exists ${fn("set_flag_override")}(text, text, ${id}, uuid);
create or replace function ${fn("set_flag_override")}(key text, variant text, tenant ${id} default null, member uuid default null, context text default null, context_key text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${denied}
  if num_nonnulls(tenant, member, context) <> 1 or (context is null) <> (context_key is null) then
    ${fail("FLAGS_OVERRIDE_TARGET", "Pass one target: a tenant, a member, or a context with its key", "22023")}
  end if;
  if variant is null then
    delete from ${overrides} v
    where v.${o("flag")} = set_flag_override.key
      and v.${o("tenant")} is not distinct from set_flag_override.tenant
      and v.${o("user")} is not distinct from set_flag_override.member
      and v.${o("context")} is not distinct from set_flag_override.context
      and v.${o("contextKey")} is not distinct from set_flag_override.context_key;
    if not found then
      return false;
    end if;
    ${overrideEvent}
    return true;
  end if;
  insert into ${overrides} (${o("flag")}, ${o("tenant")}, ${o("user")}, ${o("context")}, ${o("contextKey")}, ${o("variant")})
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.context, set_flag_override.context_key, set_flag_override.variant)
  on conflict on constraint flag_overrides_unique do update set ${o("variant")} = excluded.${o("variant")};
  ${overrideEvent}
  return true;
end;
$$;

revoke execute on function ${fn("list_flags")}() from public, anon;
revoke execute on function ${fn("save_flag")}(text, jsonb) from public, anon;
revoke execute on function ${fn("delete_flag")}(text) from public, anon;
revoke execute on function ${fn("set_flag_override")}(text, text, ${id}, uuid, text, text) from public, anon;
grant execute on function ${fn("list_flags")}() to authenticated, service_role;
grant execute on function ${fn("save_flag")}(text, jsonb) to authenticated, service_role;
grant execute on function ${fn("delete_flag")}(text) to authenticated, service_role;
grant execute on function ${fn("set_flag_override")}(text, text, ${id}, uuid, text, text) to authenticated, service_role;
revoke execute on function ${fn("flag_evaluation")}(text, ${id}, uuid, jsonb) from public, anon, authenticated;
revoke execute on function ${fn("flag_enabled")}(text, ${id}) from public, anon;
revoke execute on function ${fn("flag_definitions")}() from public, anon, authenticated;
revoke execute on function ${fn("tenant_ids_with_flag")}(text) from public, anon;
grant execute on function ${fn("tenant_ids_with_flag")}(text) to authenticated, service_role;
grant execute on function ${fn("flag_bucket")}(text, text) to anon, authenticated, service_role;
grant execute on function ${fn("flag_evaluation")}(text, ${id}, uuid, jsonb) to service_role;
grant execute on function ${fn("flag_enabled")}(text, ${id}) to authenticated, service_role;
grant execute on function ${fn("flag_definitions")}() to service_role;`;
}

/**
 * Brings version 2 tables forward: adds the context columns and the archived
 * flag, and replaces the unnamed tenant-or-user check and unique constraint of
 * `flag_overrides` with the named ones. A no-op on version 3 tables.
 */
function upgradeContexts(ctx: BlockSqlContext): string {
  const flags = ctx.table("flags");
  const overrides = ctx.table("overrides");
  const o = (logical: string): string => ctx.col("overrides", logical);
  const { target, unique } = overrideConstraints(ctx);

  return `alter table ${flags} add column if not exists ${ctx.col("flags", "archived")} boolean not null default false;
alter table ${overrides} add column if not exists ${o("context")} text check (${o("context")} ~ '^[a-z][a-z0-9_]{0,62}$');
alter table ${overrides} add column if not exists ${o("contextKey")} text check (length(${o("contextKey")}) between 1 and 200);
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = ${sqlString(overrides)}::regclass and c.contype in ('c', 'u')
      and cardinality(c.conkey) > 1
      and c.conname not in ('flag_overrides_target', 'flag_overrides_unique')
  loop
    execute format('alter table %s drop constraint %I', ${sqlString(overrides)}, v_name);
  end loop;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = ${sqlString(overrides)}::regclass and c.conname = 'flag_overrides_target') then
    alter table ${overrides} add ${target};
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = ${sqlString(overrides)}::regclass and c.conname = 'flag_overrides_unique') then
    alter table ${overrides} add ${unique};
  end if;
end;
$$;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "flag_bucket", args: ["text", "text"], returns: "integer" },
    {
      name: "flag_evaluation",
      args: ["text", "{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "flag_enabled", args: ["text", "{id}"], returns: "boolean" },
    { name: "flag_definitions", args: [], returns: "jsonb" },
    { name: "tenant_ids_with_flag", args: ["text"], returns: "{id}" },
    { name: "list_flags", args: [], returns: "jsonb" },
    { name: "save_flag", args: ["text", "jsonb"], returns: "jsonb" },
    { name: "delete_flag", args: ["text"], returns: "boolean" },
    {
      name: "set_flag_override",
      args: ["text", "text", "{id}", "uuid", "text", "text"],
      returns: "boolean",
    },
  ];
}

export const FLAGS: BlockSqlDefinition = {
  name: "feature-flags",
  scopes: ["tenant"],
  title: "Feature flags",
  description:
    "Feature flags with variants, targeting rules over tenant, user, plan, role and custom contexts such as brand, overrides and a percentage rollout bucketed by SHA-256. flag_enabled() goes in policies; createFeatureFlagsProvider() evaluates the same way for OpenFeature and the Flags SDK.",
  requires: ["memberships"],
  integrates: ["permissions", "entitlements"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  names: NAMES,
  contract,
  upgrades: [
    {
      from: 1,
      description:
        "tenant_ids_with_flag() lists the caller's tenants where a flag is on, for policies; flag_evaluation looks up the role and plans only when a rule reads them.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "Custom contexts: rules and overrides can target a context value such as a brand, read from the tenant through options.contexts. Flags gain an archived state that serves the default variant.",
      sql: () => "",
    },
  ],
  build,
};
