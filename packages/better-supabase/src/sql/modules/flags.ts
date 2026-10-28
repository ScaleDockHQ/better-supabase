import type { FlagsEvents } from "../../blocks/flags/events.ts";
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
  insertExtraColumns,
  lockTable,
  quotedTable,
  schemaPreamble,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<FlagsEvents> = {
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
  entities: { flag: { table: "flags", singular: "flag", primary: true } },
  events: EVENTS,
  options: ["contexts", "extraColumns"],
  tables: {
    flags: {
      name: "flags",
      app: {},
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
        rolloutVariants: "rollout_variants",
        rolloutSchedule: "rollout_schedule",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "description",
        "archived",
        "rolloutPercentage",
        "rolloutVariants",
        "rolloutSchedule",
        "createdAt",
        "updatedAt",
      ],
      typed: ["type"],
    },
    revisions: {
      name: "flag_revisions",
      app: {},
      columns: {
        id: "id",
        flag: "flag_key",
        revision: "revision",
        definition: "definition",
        message: "message",
        changedBy: "changed_by",
        changedAt: "changed_at",
      },
    },
    segments: {
      name: "flag_segments",
      app: {},
      columns: {
        name: "name",
        description: "description",
        rules: "rules",
        updatedAt: "updated_at",
      },
    },
    overrides: {
      name: "flag_overrides",
      app: {},
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
      optional: ["createdAt"],
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
  const where = "blocks['flags'].options.contexts";
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

/** The columns that make an override unique: its flag and its target. */
function overrideTarget(ctx: BlockSqlContext): string {
  const o = (logical: string): string => ctx.col("overrides", logical);

  return `${o("flag")}, ${o("tenant")}, ${o("user")}, ${o("context")}, ${o("contextKey")}`;
}

/** The check and unique constraints of `flag_overrides` from version 3. */
function overrideConstraints(ctx: BlockSqlContext): {
  readonly target: string;
  readonly unique: string;
} {
  const o = (logical: string): string => ctx.col("overrides", logical);

  return {
    target: `constraint ${ctx.naming.rename("flag_overrides_target")} check (num_nonnulls(${o("tenant")}, ${o("user")}, ${o("context")}) = 1 and (${o("context")} is null) = (${o("contextKey")} is null))`,
    unique: `constraint ${ctx.naming.rename("flag_overrides_unique")} unique nulls not distinct (${overrideTarget(ctx)})`,
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
  const has = (logical: string): boolean => ctx.has("flags", logical);
  const rollout = has("rolloutPercentage") && has("rolloutVariants");
  const scheduled = rollout && has("rolloutSchedule");
  const revisions = ctx.table("revisions");
  const segments = ctx.table("segments");
  const r = (logical: string): string => ctx.col("revisions", logical);
  const s = (logical: string): string => ctx.col("segments", logical);

  const optional = (
    logical: string,
    definition: (name: string) => string,
  ): string =>
    has(logical) ? `\n  ${f(logical)} ${definition(f(logical))},` : "";

  const archived = has("archived") ? ` or flag.${f("archived")}` : "";

  // Each written column: its value for a new flag and the definition key that
  // changes it on an existing one.
  const written = (
    [
      [
        "type",
        ctx.cast("flags", "type", "coalesce(d ->> 'type', 'boolean')"),
        "type",
      ],
      ["description", "d ->> 'description'", "description"],
      [
        "variants",
        `coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb)`,
        "variants",
      ],
      [
        "defaultVariant",
        "coalesce(d ->> 'default_variant', 'off')",
        "default_variant",
      ],
      ["enabled", "coalesce((d ->> 'enabled')::boolean, true)", "enabled"],
      ["archived", "coalesce((d ->> 'archived')::boolean, false)", "archived"],
      ["rules", "coalesce(d -> 'rules', '[]'::jsonb)", "rules"],
      [
        "rolloutPercentage",
        "coalesce((d ->> 'rollout_percentage')::numeric, 0)",
        "rollout_percentage",
      ],
      [
        "rolloutVariants",
        "coalesce(d -> 'rollout_variants', '[]'::jsonb)",
        "rollout_variants",
      ],
      [
        "rolloutSchedule",
        "nullif(d -> 'rollout_schedule', 'null'::jsonb)",
        "rollout_schedule",
      ],
    ] as const
  ).filter(([logical]) => has(logical));

  const assignments = [
    ...written.map(
      ([logical, , key]) =>
        `${f(logical)} = case when d ? '${key}' then excluded.${f(logical)} else x.${f(logical)} end`,
    ),
    ...(has("updatedAt") ? [`${f("updatedAt")} = now()`] : []),
  ];

  const manage = ctx.staff(
    ctx.permission("manage", OPERATIONS["flags.manage"]),
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
  if tenant is not null and (conditions @? '$[*].contexts' or exists (
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
  ${f("type")} text not null default 'boolean' check (${f("type")} in ('boolean', 'string', 'number', 'object')),${optional("description", () => "text")}
  ${f("variants")} jsonb not null default '{"on": true, "off": false}'::jsonb check (jsonb_typeof(${f("variants")}) = 'object'),
  ${f("defaultVariant")} text not null default 'off',
  ${f("enabled")} boolean not null default true,${optional("archived", () => "boolean not null default false")}
  ${f("rules")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${f("rules")}) = 'array'),${optional("rolloutPercentage", (name) => `numeric(5, 2) not null default 0 check (${name} between 0 and 100)`)}${optional("rolloutVariants", rolloutVariantsColumn)}${optional("rolloutSchedule", rolloutScheduleColumn)}${optional("createdAt", () => "timestamptz not null default now()")}${optional("updatedAt", () => "timestamptz not null default now()")}
  check (${f("variants")} ? ${f("defaultVariant")})
);${upgradeLifecycle(ctx)}${addExtraColumns(flags, extras)}${
    ctx.owns("flags")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("flags").name}_key_key`)} on ${flags} (${f("key")});`
  }
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
  ${o("variant")} text not null,${ctx.has("overrides", "createdAt") ? `\n  ${o("createdAt")} timestamptz not null default now(),` : ""}
  ${constraints.target},
  ${constraints.unique}
);
${upgradeContexts(ctx)}
${
  ctx.owns("overrides")
    ? ""
    : `create unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("overrides").name}_target_key`)} on ${overrides} (${overrideTarget(ctx)}) nulls not distinct;\n`
}create index if not exists ${ctx.naming.rename("flag_overrides_user_idx")} on ${overrides} (${o("user")});
${lockTable(overrides)}

-- Every state save_flag leaves, numbered per flag, so staff can see what
-- changed and restore it. A deleted flag keeps its revisions.
create table if not exists ${revisions} (
  ${r("id")} bigint generated always as identity primary key,
  ${r("flag")} text not null,
  ${r("revision")} integer not null check (${r("revision")} > 0),
  ${r("definition")} jsonb not null check (jsonb_typeof(${r("definition")}) = 'object'),
  ${r("message")} text check (length(${r("message")}) <= 500),
  ${r("changedBy")} uuid references auth.users (id) on delete set null,
  ${r("changedAt")} timestamptz not null default now(),
  constraint ${ctx.naming.rename("flag_revisions_unique")} unique (${r("flag")}, ${r("revision")})
);
create index if not exists ${ctx.naming.rename("flag_revisions_changed_by_idx")} on ${revisions} (${r("changedBy")});
${lockTable(revisions)}

-- Named audiences: rules is one condition, { tenants?, users?, plans?,
-- roles?, contexts? }, and a rule's segments list matches a caller in any of
-- them.
create table if not exists ${segments} (
  ${s("name")} text primary key check (${s("name")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${s("description")} text,
  ${s("rules")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("rules")}) = 'object'),
  ${s("updatedAt")} timestamptz not null default now()
);${
    ctx.owns("segments")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("segments").name}_name_key`)} on ${segments} (${s("name")});`
  }
${lockTable(segments)}

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

-- Whether a rule's or a segment's condition matches: every list it sets must
-- contain the caller's value.
create or replace function ${fn("flag_condition_matches")}(condition jsonb, tenant text, member text, role text, plans text[], context_values jsonb)
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
create or replace function ${fn("flag_rollout_percentage")}(percentage numeric, schedule jsonb, at timestamptz default now())
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
  segment_rules jsonb := '{}'::jsonb;
  conditions jsonb;
begin
  select * into flag from ${flags} x where x.${f("key")} = flag_evaluation.key;
  if flag.${f("key")} is null then
    return null;
  end if;
  if not flag.${f("enabled")}${archived} then
    return jsonb_build_object('value', flag.${f("variants")} -> flag.${f("defaultVariant")}, 'variant', flag.${f("defaultVariant")}, 'reason', 'DISABLED');
  end if;
  if flag.${f("rules")} @? '$[*].segments' then
    select coalesce(jsonb_object_agg(g.${s("name")}, g.${s("rules")}), '{}'::jsonb) into segment_rules
    from ${segments} g
    where g.${s("name")} in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(flag.${f("rules")}) e where jsonb_typeof(e.value -> 'segments') = 'array');
  end if;
  -- The rules and the segments they name, for the lookups below.
  conditions := flag.${f("rules")} || coalesce((select jsonb_agg(v) from jsonb_each(segment_rules) as e(k, v)), '[]'::jsonb);${resolve}
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
    if tenant is not null and conditions @? '$[*].roles' then
      role := ${ctx.of("memberships").fn("organization_member_role")}(tenant, member);
    end if;
    if tenant is not null and conditions @? '$[*].plans' then
      tenant_plans := ${plans};
    end if;
    for rule in select * from jsonb_array_elements(flag.${f("rules")}) loop
      if ${fn("flag_condition_matches")}(rule, tenant::text, member::text, role, tenant_plans, context_values)
        and (not rule ? 'segments' or exists (
          select 1 from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'segments') = 'array' then rule -> 'segments' else '[]'::jsonb end) n(name)
          where segment_rules ? n.name
            and ${fn("flag_condition_matches")}(segment_rules -> n.name, tenant::text, member::text, role, tenant_plans, context_values)
        ))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;${
    rollout
      ? `
  if chosen is null and jsonb_array_length(flag.${f("rolloutVariants")}) > 0 and target is not null
    and ${fn("flag_bucket")}(flag.${f("key")}, target) < ${fn("flag_rollout_percentage")}(flag.${f("rolloutPercentage")}, ${scheduled ? `flag.${f("rolloutSchedule")}` : "null"}, now()) * 100 then
    -- A second bucket, so growing the rollout never moves a target between
    -- variants.
    select w.split ->> 'variant' into chosen
    from (
      select e.split, e.i, sum(coalesce((e.split ->> 'weight')::numeric, 0) * 100) over (order by e.i) as edge
      from jsonb_array_elements(flag.${f("rolloutVariants")}) with ordinality as e(split, i)
    ) w
    where ${fn("flag_bucket")}(flag.${f("key")} || '/split', target) < w.edge
    order by w.i
    limit 1;
    reason := 'SPLIT';
  end if;`
      : ""
  }
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
    'description', ${has("description") ? `x.${f("description")}` : "null"},
    'variants', x.${f("variants")},
    'default_variant', x.${f("defaultVariant")},
    'enabled', x.${f("enabled")},
    'archived', ${has("archived") ? `x.${f("archived")}` : "false"},
    'rules', x.${f("rules")},
    'rollout_percentage', ${rollout ? `x.${f("rolloutPercentage")}` : "0"},
    'rollout_variants', ${rollout ? `x.${f("rolloutVariants")}` : "'[]'::jsonb"},
    'rollout_schedule', ${scheduled ? `x.${f("rolloutSchedule")}` : "null"},
    'segments', case when x.${f("rules")} @? '$[*].segments' then (
      select coalesce(jsonb_object_agg(g.${s("name")}, g.${s("rules")}), '{}'::jsonb)
      from ${segments} g
      where g.${s("name")} in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(x.${f("rules")}) e where jsonb_typeof(e.value -> 'segments') = 'array')
    ) else '{}'::jsonb end,
    'created_at', ${has("createdAt") ? `x.${f("createdAt")}` : "null"},
    'updated_at', ${has("updatedAt") ? `x.${f("updatedAt")}` : "null"}${extraFieldsJson("x", extras)},
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
-- rollout_variants ([{ variant, weight }]), rollout_schedule ({ startAt,
-- steps: [{ percentage, durationSeconds }], finalPercentage }) and fields
-- (the extra columns by name); missing keys keep their value (or the default
-- for a new flag). Each save records a revision with message.
drop function if exists ${fn("save_flag")}(text, jsonb);
create or replace function ${fn("save_flag")}(key text, definition jsonb, message text default null)
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
  ${denied}
  if d ? 'rollout_variants' and jsonb_typeof(d -> 'rollout_variants') = 'array' and exists (
    select 1 from jsonb_array_elements(d -> 'rollout_variants') e
    where jsonb_typeof(e.value) <> 'object' or not (coalesce(d -> 'variants', (select x.${f("variants")} from ${flags} x where x.${f("key")} = save_flag.key), '{"on": true, "off": false}'::jsonb) ? (e.value ->> 'variant'))
      or coalesce((e.value ->> 'weight')::numeric, -1) not between 0 and 100
  ) then
    ${fail("FLAGS_ROLLOUT_VARIANTS", "Each rollout variant needs a known variant and a weight from 0 to 100", "22023")}
  end if;
  insert into ${flags} as x (${[f("key"), ...written.map(([logical]) => f(logical))].join(", ")}${insertExtraColumns(flags, extras, "coalesce(d -> 'fields', '{}'::jsonb)").columns})
  values (
    ${["save_flag.key", ...written.map(([, value]) => value)].join(",\n    ")}${insertExtraColumns(flags, extras, "coalesce(d -> 'fields', '{}'::jsonb)").values}
  )
  on conflict (${f("key")}) do update set
    ${assignments.join(",\n    ")};${writeExtraColumns(flags, extras, "d -> 'fields'", `x.${f("key")} = save_flag.key`)}
  saved := (select v from jsonb_array_elements(${fn("flag_definitions")}()) v where v ->> 'key' = save_flag.key);
  insert into ${revisions} (${r("flag")}, ${r("revision")}, ${r("definition")}, ${r("message")}, ${r("changedBy")})
  values (
    save_flag.key,
    coalesce((select max(h.${r("revision")}) from ${revisions} h where h.${r("flag")} = save_flag.key), 0) + 1,
    saved - 'overrides' - 'segments',
    save_flag.message,
    (select u.id from auth.users u where u.id = auth.uid())
  );
  ${flagEvent("flag.saved", "save_flag.key")}
  return saved;
end;
$$;

-- The revisions of a flag, newest first.
create or replace function ${fn("flag_history")}(key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  ${denied}
  return coalesce((
    select jsonb_agg(jsonb_build_object('revision', h.${r("revision")}, 'definition', h.${r("definition")}, 'message', h.${r("message")}, 'changed_by', h.${r("changedBy")}, 'changed_at', h.${r("changedAt")}) order by h.${r("revision")} desc)
    from ${revisions} h where h.${r("flag")} = flag_history.key
  ), '[]'::jsonb);
end;
$$;

-- Saves a revision again as a new one, recreating a deleted flag; null when
-- the revision doesn't exist. Overrides are not part of a revision.
create or replace function ${fn("restore_flag")}(key text, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored jsonb;
begin
  ${denied}
  select h.${r("definition")} into stored from ${revisions} h
  where h.${r("flag")} = restore_flag.key and h.${r("revision")} = restore_flag.revision;
  if stored is null then
    return null;
  end if;
  return ${fn("save_flag")}(restore_flag.key, stored - 'key' - 'created_at' - 'updated_at', 'Restored revision ' || restore_flag.revision);
end;
$$;

create or replace function ${fn("list_flag_segments")}()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  ${denied}
  return coalesce((
    select jsonb_agg(jsonb_build_object('name', g.${s("name")}, 'description', g.${s("description")}, 'rules', g.${s("rules")}) order by g.${s("name")})
    from ${segments} g
  ), '[]'::jsonb);
end;
$$;

-- Creates or replaces a segment; rules naming it see the change at once.
create or replace function ${fn("save_flag_segment")}(name text, description text, rules jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  ${denied}
  insert into ${segments} as g (${s("name")}, ${s("description")}, ${s("rules")})
  values (save_flag_segment.name, save_flag_segment.description, coalesce(save_flag_segment.rules, '{}'::jsonb))
  on conflict (${s("name")}) do update set
    ${s("description")} = excluded.${s("description")},
    ${s("rules")} = excluded.${s("rules")},
    ${s("updatedAt")} = now();
  return jsonb_build_object('name', save_flag_segment.name, 'description', save_flag_segment.description, 'rules', coalesce(save_flag_segment.rules, '{}'::jsonb));
end;
$$;

create or replace function ${fn("delete_flag_segment")}(name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${denied}
  delete from ${segments} g where g.${s("name")} = delete_flag_segment.name;
  return found;
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
as $$${ctx.owns("overrides") ? "" : "\n#variable_conflict use_column"}
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
  on conflict ${ctx.owns("overrides") ? `on constraint ${ctx.naming.rename("flag_overrides_unique")}` : `(${overrideTarget(ctx)})`} do update set ${o("variant")} = excluded.${o("variant")};
  ${overrideEvent}
  return true;
end;
$$;

revoke execute on function ${fn("list_flags")}() from public, anon;
revoke execute on function ${fn("save_flag")}(text, jsonb, text) from public, anon;
revoke execute on function ${fn("delete_flag")}(text) from public, anon;
revoke execute on function ${fn("flag_history")}(text) from public, anon;
revoke execute on function ${fn("restore_flag")}(text, integer) from public, anon;
revoke execute on function ${fn("list_flag_segments")}() from public, anon;
revoke execute on function ${fn("save_flag_segment")}(text, text, jsonb) from public, anon;
revoke execute on function ${fn("delete_flag_segment")}(text) from public, anon;
revoke execute on function ${fn("set_flag_override")}(text, text, ${id}, uuid, text, text) from public, anon;
grant execute on function ${fn("list_flags")}() to authenticated, service_role;
grant execute on function ${fn("save_flag")}(text, jsonb, text) to authenticated, service_role;
grant execute on function ${fn("delete_flag")}(text) to authenticated, service_role;
grant execute on function ${fn("flag_history")}(text) to authenticated, service_role;
grant execute on function ${fn("restore_flag")}(text, integer) to authenticated, service_role;
grant execute on function ${fn("list_flag_segments")}() to authenticated, service_role;
grant execute on function ${fn("save_flag_segment")}(text, text, jsonb) to authenticated, service_role;
grant execute on function ${fn("delete_flag_segment")}(text) to authenticated, service_role;
grant execute on function ${fn("set_flag_override")}(text, text, ${id}, uuid, text, text) to authenticated, service_role;
grant execute on function ${fn("flag_condition_matches")}(jsonb, text, text, text, text[], jsonb) to anon, authenticated, service_role;
grant execute on function ${fn("flag_rollout_percentage")}(numeric, jsonb, timestamptz) to anon, authenticated, service_role;
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
 * `flag_overrides` with the named ones. A no-op on version 3 tables, and it
 * leaves the app's tables alone.
 */
function upgradeContexts(ctx: BlockSqlContext): string {
  const flags = ctx.table("flags");
  const overrides = ctx.table("overrides");
  const o = (logical: string): string => ctx.col("overrides", logical);
  const { target, unique } = overrideConstraints(ctx);

  const archived =
    ctx.owns("flags") && ctx.has("flags", "archived")
      ? `alter table ${flags} add column if not exists ${ctx.col("flags", "archived")} boolean not null default false;\n`
      : "";

  if (!ctx.owns("overrides")) {
    return archived;
  }

  return `${archived}alter table ${overrides} add column if not exists ${o("context")} text check (${o("context")} ~ '^[a-z][a-z0-9_]{0,62}$');
alter table ${overrides} add column if not exists ${o("contextKey")} text check (length(${o("contextKey")}) between 1 and 200);
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = ${sqlString(overrides)}::regclass and c.contype in ('c', 'u')
      and cardinality(c.conkey) > 1
      and c.conname not in (${sqlString(ctx.naming.rename("flag_overrides_target"))}, ${sqlString(ctx.naming.rename("flag_overrides_unique"))})
  loop
    execute format('alter table %s drop constraint %I', ${sqlString(overrides)}, v_name);
  end loop;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = ${sqlString(overrides)}::regclass and c.conname = ${sqlString(ctx.naming.rename("flag_overrides_target"))}) then
    alter table ${overrides} add ${target};
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = ${sqlString(overrides)}::regclass and c.conname = ${sqlString(ctx.naming.rename("flag_overrides_unique"))}) then
    alter table ${overrides} add ${unique};
  end if;
end;
$$;`;
}

function rolloutVariantsColumn(name: string): string {
  return `jsonb not null default '[]'::jsonb check (jsonb_typeof(${name}) = 'array')`;
}

function rolloutScheduleColumn(name: string): string {
  return `jsonb check (${name} is null or jsonb_typeof(${name}) = 'object')`;
}

/**
 * Brings version 3 tables forward: adds the creation time, the weighted rollout
 * variants and the rollout schedule. A no-op on version 4 tables, and it leaves
 * the app's tables alone.
 */
function upgradeLifecycle(ctx: BlockSqlContext): string {
  if (!ctx.owns("flags")) {
    return "";
  }

  const flags = ctx.table("flags");

  const add = (logical: string, type: (name: string) => string): string =>
    ctx.has("flags", logical)
      ? `\nalter table ${flags} add column if not exists ${ctx.col("flags", logical)} ${type(ctx.col("flags", logical))};`
      : "";

  return [
    add("createdAt", () => "timestamptz not null default now()"),
    add("rolloutVariants", rolloutVariantsColumn),
    add("rolloutSchedule", rolloutScheduleColumn),
  ].join("");
}

/**
 * Moves version 3's single `rollout_variant` into `rollout_variants` as one
 * split of weight 100, then drops the old column. Runs before the module file,
 * so the new functions never see the old column.
 */
function upgradeRolloutVariants(ctx: BlockSqlContext): string {
  if (!(ctx.owns("flags") && ctx.has("flags", "rolloutVariants"))) {
    return "";
  }

  const flags = ctx.table("flags");
  const variants = ctx.col("flags", "rolloutVariants");

  return `do $$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(${sqlString(flags)}) and a.attname = 'rollout_variant' and not a.attisdropped
  ) then
    alter table ${flags} add column if not exists ${variants} ${rolloutVariantsColumn(variants)};
    update ${flags} set ${variants} = jsonb_build_array(jsonb_build_object('variant', rollout_variant, 'weight', 100))
    where rollout_variant is not null;
    alter table ${flags} drop column rollout_variant;
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
    { name: "save_flag", args: ["text", "jsonb", "text"], returns: "jsonb" },
    { name: "delete_flag", args: ["text"], returns: "boolean" },
    { name: "flag_history", args: ["text"], returns: "jsonb" },
    { name: "restore_flag", args: ["text", "integer"], returns: "jsonb" },
    { name: "list_flag_segments", args: [], returns: "jsonb" },
    {
      name: "save_flag_segment",
      args: ["text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_flag_segment", args: ["text"], returns: "boolean" },
    {
      name: "flag_condition_matches",
      args: ["jsonb", "text", "text", "text", "text[]", "jsonb"],
      returns: "boolean",
    },
    {
      name: "flag_rollout_percentage",
      args: ["numeric", "jsonb", "timestamptz"],
      returns: "numeric",
    },
    {
      name: "set_flag_override",
      args: ["text", "text", "{id}", "uuid", "text", "text"],
      returns: "boolean",
    },
  ];
}

export const FLAGS: BlockSqlDefinition = {
  name: "flags",
  scopes: ["tenant"],
  title: "Feature flags",
  description:
    "Feature flags with variants, targeting rules over tenant, user, plan, role, custom contexts such as brand and shared segments, overrides, and a scheduled percentage rollout split across weighted variants, bucketed by SHA-256. Every save records a revision you can restore. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature and the Flags SDK.",
  requires: ["memberships"],
  integrates: ["permissions", "entitlements"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
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
    {
      from: 3,
      description:
        "Flag lifecycle: rollout_variant becomes rollout_variants, weighted splits (an existing variant moves over with weight 100), rollouts can follow a schedule, rules can name shared segments, and every save records a revision that restore_flag() brings back. save_flag() takes a message.",
      sql: upgradeRolloutVariants,
    },
  ],
  build,
};
