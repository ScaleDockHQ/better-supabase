import type { EntitlementPlansSource } from "../config/config.ts";
import type {
  AccessModuleConfig,
  DisabledRow,
  ModuleMode,
  ModulesConfig,
} from "../config/modules.ts";
import type { ClaimsMeta } from "../schema/types.ts";
import type { AuditedTable } from "./audit-registrations.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import { apiWrappers } from "./api-schema.ts";
import {
  createModuleContext,
  type ModuleContext,
  type ModuleContractFunction,
  type ModuleIdType,
  type ModuleNames,
} from "./context.ts";
import { migrationOptionUses } from "./migration-options.ts";
import {
  hasPlatformRoles,
  MODULE_PERMISSION_SCOPES,
  MODULE_PERMISSIONS,
} from "./modules/access-model.ts";
import { ACCESS } from "./modules/access.ts";
import { ANNOUNCEMENTS } from "./modules/announcements.ts";
import { API_KEYS } from "./modules/api-keys.ts";
import { ATTACHMENTS } from "./modules/attachments.ts";
import { AUDIT } from "./modules/audit.ts";
import { BILLING } from "./modules/billing.ts";
import { COMMENTS } from "./modules/comments.ts";
import { DATA_LIFECYCLE } from "./modules/data-lifecycle.ts";
import { FLAGS } from "./modules/flags.ts";
import { INVITATIONS } from "./modules/invitations.ts";
import { JOBS } from "./modules/jobs.ts";
import { NOTIFICATIONS } from "./modules/notifications.ts";
import { ONBOARDING } from "./modules/onboarding.ts";
import { ORGANIZATIONS } from "./modules/organizations.ts";
import { OUTBOX } from "./modules/outbox.ts";
import { PROFILES } from "./modules/profiles.ts";
import { SETTINGS } from "./modules/settings.ts";
import { SSO } from "./modules/sso.ts";
import { SUPPORT_SESSIONS } from "./modules/support.ts";
import { TENANT } from "./modules/tenant.ts";
import { USAGE } from "./modules/usage.ts";
import { WAITLIST } from "./modules/waitlist.ts";
import { WEBHOOKS_IN } from "./modules/webhooks-in.ts";
import { WEBHOOKS_OUT } from "./modules/webhooks-out.ts";
import { tableGlobs } from "./schema-scan.ts";
import {
  EQUIVALENT_TRIGGERS,
  type JsonSchemaCheck,
  jsonSchemaChecks,
  SCHEMA,
  serviceOnly,
} from "./shared.ts";

export {
  isModuleIdType,
  MODULE_ID_TYPES,
  type ModuleIdType,
  moduleIdType,
} from "./context.ts";

/** The step from one module version to the next, for `sql upgrade`. */
export interface ModuleUpgrade {
  /** The installed version this step upgrades from. */
  readonly from: number;
  readonly description: string;
  /** SQL run before the module's current file, e.g. renames and backfills. */
  readonly sql: (ctx: ModuleContext) => string;
}

/**
 * A renamed module symbol. It keeps a compatibility wrapper for at least one
 * minor release, then is removed; doctor reports uses of both (BS309), and
 * the name stays reserved.
 */
export interface ModuleDeprecation {
  readonly kind: "function" | "claim" | "table" | "column";
  /** The old name: `schema.function`, a claim name, `schema.table` or `table.column`. */
  readonly symbol: string;
  /** What to use instead. */
  readonly use: string;
  /** The package version that deprecated it. */
  readonly since: string;
  /** The package version that removed it; until then `wrapper` is written. */
  readonly removed?: string;
  /**
   * The compatibility wrapper the module file keeps, e.g. a function with the
   * old name that calls the new one and a `comment on function ... is
   * 'deprecated: use X'`.
   */
  readonly wrapper?: (ctx: ModuleContext) => string;
}

/**
 * SQL modules for `better-supabase sql add`. Every module is idempotent
 * (`create or replace`, `if not exists`), so re-running it upgrades in place.
 */
export interface SqlModule {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  /** Modules this one needs, added along with it. */
  readonly requires: readonly string[];
  /** What it needs instead when the layout has `permdock`. */
  readonly permdockRequires?: readonly string[];
  /** What it needs for this layout, e.g. per `sql.modules.access.model`; overrides both. */
  readonly dependencies?: (layout: ModuleLayout) => readonly string[];
  /** `schema` files go with your schemas; `test` files go to `supabase/tests`. */
  readonly target: "schema" | "test";
  /** The module with the default claim names. */
  readonly sql: string;
  /** The module for configured claim names (`config.claims`), when it reads claims. */
  readonly render?: (claims: ClaimsMeta, layout: ModuleLayout) => string;
  /** Bumped when installed databases need an upgrade step. Defaults to 1. */
  readonly version?: number;
  /** The modes `sql.modules.<name>.mode` accepts. Defaults to `managed` only. */
  readonly modes?: readonly ModuleMode[];
  /** The logical tables and columns `sql.modules.<name>.tables` and `columns` map. */
  readonly names?: ModuleNames;
  /** The functions other modules and the TypeScript side call. */
  readonly contract?: (ctx: ModuleContext) => readonly ModuleContractFunction[];
  /** Renders the module for a layout; takes precedence over `render`. */
  readonly build?: (ctx: ModuleContext, layout: ModuleLayout) => string;
  readonly upgrades?: readonly ModuleUpgrade[];
  readonly deprecated?: readonly ModuleDeprecation[];
  /**
   * Rows, role settings and calls that a schema diff doesn't capture. They
   * go to `better-supabase-data/` next to the schema folder and a migration
   * (`sql data`) instead of the schema file.
   */
  readonly data?: (ctx: ModuleContext, layout: ModuleLayout) => string;
  /** pgTAP files for this layout, written to the tests folder next to the `pgtap` module's. */
  readonly tests?: (
    ctx: ModuleContext,
    layout: ModuleLayout,
  ) => readonly ModuleTestFile[];
  readonly topics?: (ctx: ModuleContext) => readonly string[];
}

/** A pgTAP file a module writes for the layout, e.g. one per audited table. */
export interface ModuleTestFile {
  /** The file name's suffix, after the module's slug. */
  readonly name: string;
  readonly sql: string;
}

export const moduleVersion = (module: SqlModule): number => module.version ?? 1;

/** A module rendered by `build`; its `sql` is the build with the defaults. */
export type ModuleDefinition = Omit<SqlModule, "sql" | "render" | "build"> & {
  readonly build: NonNullable<SqlModule["build"]>;
};

function built(definition: ModuleDefinition): SqlModule {
  let cached: string | undefined;
  return {
    ...definition,
    get sql() {
      return (cached ??= definition.build(
        moduleContext(definition.name, {}),
        {},
      ));
    },
  };
}

const requiresOf = (
  module: SqlModule,
  layout: ModuleLayout,
): readonly string[] =>
  module.dependencies?.(layout) ??
  (layout.permdock && module.permdockRequires
    ? module.permdockRequires
    : module.requires);

const UPDATED_AT: SqlModule = {
  name: "updated-at",
  title: "updated_at triggers",
  description: "Keeps an updated_at column current on every update.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

create or replace function better_supabase.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new := jsonb_populate_record(
    new,
    jsonb_build_object(coalesce(tg_argv[0], 'updated_at'), now())
  );
  return new;
end;
$$;

${EQUIVALENT_TRIGGERS}

drop function if exists better_supabase.track_updated_at(regclass, text);

-- select better_supabase.track_updated_at('public.customers');
-- replace_trigger => true drops another trigger that sets updated_at (moddatetime, touch_*).
create or replace function better_supabase.track_updated_at(
  target regclass,
  column_name text default 'updated_at',
  replace_trigger boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bs_updated_at on %s', target);
  execute format(
    'create trigger bs_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$$;

revoke execute on function better_supabase.track_updated_at(regclass, text, boolean) from public, anon, authenticated;`,
};

const ACTOR: SqlModule = {
  name: "actor",
  title: "Actor stamping",
  description:
    "Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

drop function if exists better_supabase.track_actor(regclass, text, text);

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_actor on %s', target);
  execute format(
    'create trigger bs_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;`,
};

const MFA: SqlModule = {
  name: "mfa",
  title: "MFA enforcement",
  description:
    "mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

-- authenticated can't read auth.mfa_factors, so the check runs as the owner.
create or replace function better_supabase.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    )
$$;

revoke execute on function better_supabase.mfa_satisfied() from public, anon;
grant execute on function better_supabase.mfa_satisfied() to authenticated;

-- Restrictive, so it applies on top of the table's other policies:
-- create policy mfa_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.mfa_satisfied()))
--   with check ((select better_supabase.mfa_satisfied()));`,
};

/**
 * `sql.modules.sessions.options.policies`: a restrictive session policy on
 * every table the schema files create in `schemas`, except `exclude`.
 */
function sessionPolicies(ctx: ModuleContext, layout: ModuleLayout): string {
  if (!ctx.flag("policies", false)) return "";
  const exclude = tableGlobs(ctx.list("exclude", []));
  const tables = (layout.declaredTables ?? []).filter(
    (table) => !exclude.some((pattern) => pattern.test(table)),
  );
  if (tables.length === 0) return "";
  const statements = tables.map((table) => {
    const target = qualifiedTable(table);
    return `drop policy if exists bs_session_active on ${target};
create policy bs_session_active on ${target} as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));`;
  });
  return `

-- sql.modules.sessions.options.policies: every table in the schema files,
-- except sql.modules.sessions.options.exclude. \`sql sync\` rewrites these.
${statements.join("\n")}`;
}

const SESSIONS: ModuleDefinition = {
  name: "sessions",
  names: { tables: {}, options: ["exclude", "policies"] },
  title: "Session revocation",
  description:
    "session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.",
  requires: [],
  target: "schema",
  build: (ctx, layout) => `${SCHEMA}

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));${sessionPolicies(ctx, layout)}`,
};

/** The tenant module's memberships table and columns, for the entitlement lookups. */
interface Memberships {
  readonly table: string;
  readonly tenant: string;
  readonly user: string;
  readonly idType: ModuleIdType;
}

function memberships(layout: ModuleLayout): Memberships {
  const ctx = moduleContext("tenant", layout);
  return {
    table: ctx.table("memberships"),
    tenant: ctx.col("memberships", "tenant"),
    user: ctx.col("memberships", "user"),
    idType: ctx.idType,
  };
}

/** `entitlements.claim`: what `feature_claims` puts in the token. */
export type FeatureClaimOption =
  | false
  | {
      /** At most this many tenants, the lowest ids first. */
      readonly maxTenants?: number;
      /** Short codes written instead of the feature keys: `{ exports: "x" }`. */
      readonly keys?: Readonly<Record<string, string>>;
    };

/**
 * The body of `feature_claims` over `rows`, a query of (tenant text, keys
 * text[]) rows, shaped by `entitlements.claim`.
 */
function featureClaimsBody(
  rows: string,
  claim: FeatureClaimOption | undefined,
): string {
  if (claim === false) return "  select '{}'::jsonb";
  const max = claim?.maxTenants;
  if (max !== undefined && (!Number.isInteger(max) || max < 1)) {
    throw new TypeError(
      "entitlements.claim.maxTenants must be a positive integer",
    );
  }
  const keys = claim?.keys ?? {};
  const mapped =
    Object.keys(keys).length === 0
      ? "to_jsonb(r.keys)"
      : `to_jsonb(array(select coalesce(${sqlString(JSON.stringify(keys))}::jsonb ->> k, k) from unnest(r.keys) as k))`;
  return `  select coalesce(jsonb_object_agg(r.tenant, ${mapped}), '{}'::jsonb)
  from (
${rows}
    order by 1${max === undefined ? "" : `\n    limit ${String(max)}`}
  ) r`;
}

/** `has_entitlement` and `feature_claims` on the tenant module's memberships. */
const tenantEntitlementChecks = (
  claims: ClaimsMeta,
  m: Memberships,
  claim?: FeatureClaimOption,
): string => `
-- using ((select better_supabase.has_entitlement(organization_id, 'exports')))
create or replace function better_supabase.has_entitlement(tenant ${m.idType}, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select better_supabase.has_organization_role(tenant)
    and key = any (better_supabase.tenant_entitlements(tenant))
$$;

revoke execute on function better_supabase.has_entitlement(${m.idType}, text) from public, anon;
grant execute on function better_supabase.has_entitlement(${m.idType}, text) to authenticated, service_role;

-- Every tenant of the caller with \`key\`, for one set check per query instead of
-- one call per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_entitlement('exports')))
create or replace function better_supabase.tenant_ids_with_entitlement(key text)
returns setof ${m.idType}
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from better_supabase.member_organization_ids() as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id))
$$;

revoke execute on function better_supabase.tenant_ids_with_entitlement(text) from public, anon;
grant execute on function better_supabase.tenant_ids_with_entitlement(text) to authenticated, service_role;

-- The \`${claims.features}\` claim: { [tenant id]: lookup keys }, read by
-- hasEntitlement(). Tenants without entitlements are left out. Call it from
-- your custom access token hook:
--   return jsonb_set(event, '{claims,${claims.features}}',
--     better_supabase.feature_claims((event ->> 'user_id')::uuid));
create or replace function better_supabase.feature_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
${featureClaimsBody(
  `    select m.${m.tenant}::text as tenant, e.keys
    from ${m.table} m
    cross join lateral (select better_supabase.tenant_entitlements(m.${m.tenant}) as keys) e
    where m.${m.user} = feature_claims.user_id
      and cardinality(e.keys) > 0`,
  claim,
)}
$$;`;

/** `has_entitlement` and `feature_claims` on PermDock's `member_<scope>_ids` helpers. */
const permdockEntitlementChecks = (
  claims: ClaimsMeta,
  permdock: ModulePermdock,
  claim?: FeatureClaimOption,
): string => {
  const member = `${sqlIdent(permdock.schema)}.${sqlIdent(`member_${permdock.scope}_ids`)}`;
  const memberFor = `${sqlIdent(permdock.schema)}.${sqlIdent(`member_${permdock.scope}_ids_for`)}`;
  const id = permdock.idType;
  return `
-- PermDock mode: memberships come from PermDock's ${permdock.scope} scope
-- (${member}() and ${memberFor}(uuid), from \`permdock rls generate\`).

-- using ((select better_supabase.has_entitlement(organization_id, 'exports')))
create or replace function better_supabase.has_entitlement(tenant ${id}, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select tenant in (select ${member}())
    and key = any (better_supabase.tenant_entitlements(tenant))
$$;

revoke execute on function better_supabase.has_entitlement(${id}, text) from public, anon;
grant execute on function better_supabase.has_entitlement(${id}, text) to authenticated, service_role;

-- Every tenant of the caller with \`key\`, for one set check per query instead of
-- one call per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_entitlement('exports')))
create or replace function better_supabase.tenant_ids_with_entitlement(key text)
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from ${member}() as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id))
$$;

revoke execute on function better_supabase.tenant_ids_with_entitlement(text) from public, anon;
grant execute on function better_supabase.tenant_ids_with_entitlement(text) to authenticated, service_role;

-- The \`${claims.features}\` claim: { [${permdock.scope} id]: lookup keys }, read by
-- hasEntitlement(). Register it with PermDock instead of writing a hook:
--   supabase: { hook: { claims: { ${claims.features}: 'better_supabase.feature_claims' } } }
-- \`permdock supabase hook generate --grants-out\` then grants ${memberFor}
-- to supabase_auth_admin.
create or replace function better_supabase.feature_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
${featureClaimsBody(
  `    select t.id::text as tenant, e.keys
    from ${memberFor}(feature_claims.user_id) as t(id)
    cross join lateral (select better_supabase.tenant_entitlements(t.id) as keys) e
    where cardinality(e.keys) > 0`,
  claim,
)}
$$;`;
};

const entitlementsSql = (
  claims: ClaimsMeta,
  layout: ModuleLayout = {},
): string => {
  const m = memberships(layout);
  const id = layout.permdock?.idType ?? m.idType;
  const source = layout.entitlements?.source ?? "stripe-sync";
  if (source === "custom") {
    return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

-- entitlements.source is "custom": your better_supabase.tenant_entitlements(tenant ${id})
-- returns the tenant's feature keys (text[]); the checks below call it.
set check_function_bodies = off;
${layout.permdock ? permdockEntitlementChecks(claims, layout.permdock, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;`;
  }
  if (typeof source === "object") {
    return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;
${planEntitlements(source.plans, id)}
${layout.permdock ? permdockEntitlementChecks(claims, layout.permdock, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;
  }
  return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

-- Lookup keys of the tenant's active entitlements, from the Stripe Sync
-- Engine's stripe.active_entitlements. Empty before the engine is installed.
create or replace function better_supabase.tenant_entitlements(tenant ${id})
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer_id text := better_supabase.tenant_stripe_customer(tenant);
begin
  if customer_id is null or to_regclass('stripe.active_entitlements') is null then
    return '{}';
  end if;
  return coalesce((
    select array_agg(distinct e.lookup_key order by e.lookup_key)
    from stripe.active_entitlements e
    where e.customer = customer_id
      and e.lookup_key is not null
  ), '{}');
end
$$;

revoke execute on function better_supabase.tenant_entitlements(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(${id}) to service_role, supabase_auth_admin;
${layout.permdock ? permdockEntitlementChecks(claims, layout.permdock, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;
};

const qualified = (table: string): string => {
  const [schema, name] = table.includes(".")
    ? table.split(".", 2)
    : ["public", table];
  return `${sqlIdent(schema!)}.${sqlIdent(name!)}`;
};

/** `tenant_entitlements` over a plan catalog: the active subscription's plan features. */
function planEntitlements(
  plans: EntitlementPlansSource["plans"],
  id: string,
): string {
  const subs = plans.subscriptions;
  const features = plans.features;
  const active = subs.activeStatuses ?? ["active", "trialing"];
  const status = subs.status
    ? `\n      and s.${sqlIdent(subs.status)}::text = any (array[${active.map(sqlString).join(", ")}]::text[])`
    : "";
  const included = features.included
    ? `\n      and f.${sqlIdent(features.included)}`
    : "";
  return `
-- Feature keys of the tenant's active plan (entitlements.source.plans):
-- ${subs.table} gives the plan, ${features.table} its features.
create or replace function better_supabase.tenant_entitlements(tenant ${id})
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct f.${sqlIdent(features.feature)}::text order by f.${sqlIdent(features.feature)}::text), '{}')
    from ${qualified(subs.table)} s
    join ${qualified(features.table)} f on f.${sqlIdent(features.plan)}::text = s.${sqlIdent(subs.plan)}::text
    where s.${sqlIdent(subs.tenant)} = tenant_entitlements.tenant${status}${included}
      and f.${sqlIdent(features.feature)} is not null
$$;

revoke execute on function better_supabase.tenant_entitlements(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(${id}) to service_role, supabase_auth_admin;

-- The tenant's active plan keys, so other modules (usage quotas) can match a
-- plan by its key as well as by its features.
create or replace function better_supabase.tenant_plans(tenant ${id})
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct s.${sqlIdent(subs.plan)}::text order by s.${sqlIdent(subs.plan)}::text), '{}')
    from ${qualified(subs.table)} s
    where s.${sqlIdent(subs.tenant)} = tenant_plans.tenant${status}
      and s.${sqlIdent(subs.plan)} is not null
$$;

revoke execute on function better_supabase.tenant_plans(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_plans(${id}) to service_role;`;
}

const ENTITLEMENTS: SqlModule = {
  name: "entitlements",
  title: "Stripe entitlements",
  description:
    "Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.",
  requires: ["tenant"],
  permdockRequires: [],
  target: "schema",
  get sql() {
    return entitlementsSql(DEFAULT_CLAIMS);
  },
  render: entitlementsSql,
};

const RESERVED_SLUGS_SEED = `insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;`;

const RATE_LIMIT_HOOK = `-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';`;

const RATE_LIMIT_NO_HOOK = `-- sql.modules.rate-limit.options.preRequest is false: the app calls
-- better_supabase.check_request() from its own pre-request function, or not
-- at all. Removes the setting when it still points at check_request.
do $$
begin
  if exists (
    select 1
    from pg_catalog.pg_db_role_setting s
    join pg_catalog.pg_roles r on r.oid = s.setrole
    cross join lateral unnest(s.setconfig) setting
    where r.rolname = 'authenticator' and s.setdatabase = 0
      and setting = 'pgrst.db_pre_request=better_supabase.check_request'
  ) then
    alter role authenticator reset pgrst.db_pre_request;
  end if;
end
$$;
notify pgrst, 'reload config';`;

const SLUG_PATTERN = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$";

/** `minLength` and `maxLength` of `sql.modules["reserved-slugs"].options`. */
function slugLengths(ctx: ModuleContext): {
  readonly min: number;
  readonly max: number;
} {
  const min = ctx.number("minLength", 1);
  const max = ctx.number("maxLength", 63);
  if (
    !Number.isInteger(min) ||
    !Number.isInteger(max) ||
    min < 1 ||
    max < min
  ) {
    throw new TypeError(
      "sql.modules.reserved-slugs.options.minLength and maxLength must be whole numbers with 1 <= minLength <= maxLength",
    );
  }
  return { min, max };
}

/** `sql.modules["reserved-slugs"].options.slugs`: the app's own words, such as its route names. */
function appSlugs(ctx: ModuleContext): string {
  const slugs = ctx.list("slugs", []);
  for (const slug of slugs) {
    if (!new RegExp(SLUG_PATTERN).test(slug) || slug.includes("--")) {
      throw new TypeError(
        `sql.modules.reserved-slugs.options.slugs: "${slug}" is not a slug (lowercase letters, digits and inner hyphens)`,
      );
    }
  }
  if (slugs.length === 0) return "";
  return `

-- sql.modules.reserved-slugs.options.slugs
insert into better_supabase.reserved_slugs (slug, reason)
select value, 'app'
from unnest(array[${slugs.map(sqlString).join(", ")}]) as value
on conflict (slug) do nothing;`;
}

const RESERVED_SLUGS: ModuleDefinition = {
  name: "reserved-slugs",
  names: { tables: {}, options: ["maxLength", "minLength", "slugs"] },
  data: (ctx) => `${RESERVED_SLUGS_SEED}${appSlugs(ctx)}`,
  title: "Reserved slugs",
  description:
    "A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.",
  requires: [],
  target: "schema",
  build: (ctx) => {
    const { min, max } = slugLengths(ctx);
    return `${SCHEMA}

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bs_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bs_reserved_slugs_read on better_supabase.reserved_slugs for select using (true);

-- 'invalid' for a malformed slug or one outside ${String(min)} to ${String(max)} characters
-- (sql.modules.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ ${sqlString(SLUG_PATTERN)} then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < ${String(min)} or length(slug) > ${String(max)} then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_slug on %s', target);
  execute format(
    'create trigger bs_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;`;
  },
};

const IDEMPOTENCY: SqlModule = {
  name: "idempotency",
  title: "Idempotency keys",
  description:
    "Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

create table if not exists better_supabase.idempotency_keys (
  scope text not null default '',
  key text not null,
  request_hash text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  status_code integer,
  response jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (scope, key)
);
create index if not exists idempotency_keys_expiry_idx on better_supabase.idempotency_keys (expires_at);

alter table better_supabase.idempotency_keys enable row level security;
revoke all on better_supabase.idempotency_keys from anon, authenticated;
grant all on better_supabase.idempotency_keys to service_role;

-- state: 'started' (run it), 'replay' (send the stored response),
-- 'running' (another request holds the key) or 'mismatch' (same key, different request).
create or replace function better_supabase.begin_idempotent(
  scope text,
  key text,
  request_hash text,
  ttl interval default '24 hours',
  lock interval default '1 minute'
)
returns table (state text, status_code integer, response jsonb)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  existing better_supabase.idempotency_keys;
begin
  delete from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key and k.expires_at < now();

  insert into better_supabase.idempotency_keys (scope, key, request_hash, locked_until, expires_at)
  values (scope, key, request_hash, now() + lock, now() + ttl)
  on conflict on constraint idempotency_keys_pkey do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb;
    return;
  end if;

  select * into existing from better_supabase.idempotency_keys k
  where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key
  for update;
  if existing.request_hash <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb;
  elsif existing.status = 'completed' then
    return query select 'replay'::text, existing.status_code, existing.response;
  elsif existing.locked_until < now() then
    update better_supabase.idempotency_keys k set locked_until = now() + lock
    where k.scope = begin_idempotent.scope and k.key = begin_idempotent.key;
    return query select 'started'::text, null::integer, null::jsonb;
  else
    return query select 'running'::text, null::integer, null::jsonb;
  end if;
end;
$$;

create or replace function better_supabase.complete_idempotent(
  scope text,
  key text,
  status_code integer,
  response jsonb
)
returns void
language sql
set search_path = ''
as $$
  update better_supabase.idempotency_keys k
  set status = 'completed', status_code = complete_idempotent.status_code,
      response = complete_idempotent.response, locked_until = null
  where k.scope = complete_idempotent.scope and k.key = complete_idempotent.key
$$;

-- On failure: forget the key so the client can retry.
create or replace function better_supabase.release_idempotent(scope text, key text)
returns void
language sql
set search_path = ''
as $$
  delete from better_supabase.idempotency_keys k
  where k.scope = release_idempotent.scope and k.key = release_idempotent.key and k.status = 'running'
$$;

create or replace function better_supabase.purge_idempotency_keys()
returns integer
language sql
set search_path = ''
as $$
  with purged as (
    delete from better_supabase.idempotency_keys where expires_at < now() returning 1
  )
  select count(*)::integer from purged
$$;

${serviceOnly([
  "begin_idempotent(text, text, text, interval, interval)",
  "complete_idempotent(text, text, integer, jsonb)",
  "release_idempotent(text, text)",
  "purge_idempotency_keys()",
])}`,
};

const WEBHOOK_INBOX: SqlModule = {
  name: "webhook-inbox",
  title: "Webhook inbox",
  description:
    "Stores verified webhooks once per message id, per tenant when given, then processes them with leases, retries and checkpoints.",
  requires: [],
  target: "schema",
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Messages record a tenant and a checkpoint; receive_webhook and purge_webhooks take a tenant, and checkpoint_webhook and list_webhooks are new.",
      sql: () =>
        "drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);\ndrop function if exists better_supabase.purge_webhooks(interval, boolean, integer);",
    },
    {
      from: 2,
      description:
        "receive_webhook takes the source's max_attempts; claims mark a message whose last attempt lost its worker as dead.",
      sql: () =>
        "drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);",
    },
  ],
  sql: `${SCHEMA}

create table if not exists better_supabase.webhook_inbox (
  id bigint generated always as identity primary key,
  source text not null,
  message_id text not null,
  event_type text,
  payload jsonb not null,
  headers jsonb not null default '{}',
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'processed', 'dead')),
  attempts integer not null default 0,
  max_attempts integer not null default 8,
  available_at timestamptz not null default now(),
  locked_by text,
  locked_until timestamptz,
  last_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (source, message_id)
);
-- The tenant a message belongs to (a per-tenant integration), and progress a
-- handler saved mid-processing (checkpoint_webhook), such as a provider cursor.
alter table better_supabase.webhook_inbox add column if not exists tenant text;
alter table better_supabase.webhook_inbox add column if not exists checkpoint jsonb not null default '{}';
create index if not exists webhook_inbox_ready_idx
  on better_supabase.webhook_inbox (source, available_at, id) where status in ('pending', 'processing');
create index if not exists webhook_inbox_tenant_idx
  on better_supabase.webhook_inbox (tenant, received_at) where tenant is not null;

alter table better_supabase.webhook_inbox enable row level security;
revoke all on better_supabase.webhook_inbox from anon, authenticated;
grant all on better_supabase.webhook_inbox to service_role;

-- The signatures before messages had a tenant, and before a source set its attempts.
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb);
drop function if exists better_supabase.purge_webhooks(interval, boolean, integer);
drop function if exists better_supabase.receive_webhook(text, text, text, jsonb, jsonb, text);

-- duplicate = true when the message id was seen before (the sender retried).
-- max_attempts is the source's limit, 8 when null.
create or replace function better_supabase.receive_webhook(
  source text,
  message_id text,
  event_type text,
  payload jsonb,
  headers jsonb default '{}',
  tenant text default null,
  max_attempts integer default null
)
returns table (id bigint, duplicate boolean)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
  insert into better_supabase.webhook_inbox (source, message_id, event_type, payload, headers, tenant, max_attempts)
  values (source, message_id, event_type, payload, headers, receive_webhook.tenant, greatest(coalesce(receive_webhook.max_attempts, 8), 1))
  on conflict on constraint webhook_inbox_source_message_id_key do nothing
  returning webhook_inbox.id into inbox_id;
  if inbox_id is not null then
    return query select inbox_id, false;
    return;
  end if;
  return query
    select w.id, true from better_supabase.webhook_inbox w
    where w.source = receive_webhook.source and w.message_id = receive_webhook.message_id;
end;
$$;

-- A message whose lease ran out on its last attempt lost its worker
-- (fail_webhook marks it dead otherwise), so the claim marks it dead.
create or replace function better_supabase.claim_webhooks(
  source text,
  worker text,
  batch integer default 10,
  lease interval default '5 minutes'
)
returns setof better_supabase.webhook_inbox
language sql
set search_path = ''
as $$
  update better_supabase.webhook_inbox d
  set status = 'dead', last_error = 'The lease ran out on the last attempt', locked_by = null, locked_until = null
  where d.source = claim_webhooks.source and d.status = 'processing'
    and d.locked_until < now() and d.attempts >= d.max_attempts;
  with next as materialized (
    select c.id from better_supabase.webhook_inbox c
    where c.source = claim_webhooks.source
      and (
        (c.status = 'pending' and c.available_at <= now())
        or (c.status = 'processing' and c.locked_until < now())
      )
    order by c.available_at, c.id
    for update skip locked
    limit batch
  )
  update better_supabase.webhook_inbox w
  set status = 'processing', attempts = w.attempts + 1, locked_by = worker, locked_until = now() + lease
  from next
  where w.id = next.id
  returning w.*
$$;

create or replace function better_supabase.complete_webhook(inbox_id bigint, worker text)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update better_supabase.webhook_inbox
    set status = 'processed', processed_at = now(), locked_by = null, locked_until = null, last_error = null
    where id = inbox_id and locked_by = worker and status = 'processing'
    returning 1
  )
  select exists (select 1 from done)
$$;

create or replace function better_supabase.fail_webhook(
  inbox_id bigint,
  worker text,
  error text,
  retry_in interval default null
)
returns text
language sql
set search_path = ''
as $$
  update better_supabase.webhook_inbox
  set status = case when attempts >= max_attempts then 'dead' else 'pending' end,
      available_at = now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, attempts))),
      last_error = left(error, 4000),
      locked_by = null,
      locked_until = null
  where id = inbox_id and locked_by = worker and status = 'processing'
  returning status
$$;

-- Saves progress for a message the worker still holds, merged into its
-- checkpoint, so a retry resumes there. False when the lease was lost.
create or replace function better_supabase.checkpoint_webhook(inbox_id bigint, worker text, fields jsonb)
returns boolean
language sql
set search_path = ''
as $$
  with saved as (
    update better_supabase.webhook_inbox
    set checkpoint = checkpoint || coalesce(fields, '{}')
    where id = inbox_id and locked_by = worker and status = 'processing'
    returning 1
  )
  select exists (select 1 from saved)
$$;

-- A tenant's messages, newest first, optionally of one source or status.
create or replace function better_supabase.list_webhooks(
  for_tenant text,
  for_source text default null,
  for_status text default null,
  max_rows integer default 100
)
returns setof better_supabase.webhook_inbox
language sql
stable
set search_path = ''
as $$
  select w.* from better_supabase.webhook_inbox w
  where w.tenant = for_tenant
    and (for_source is null or w.source = for_source)
    and (for_status is null or w.status = for_status)
  order by w.received_at desc, w.id desc
  limit least(greatest(max_rows, 1), 1000)
$$;

-- Deletes up to batch processed messages (and dead ones with include_dead)
-- older than older_than, of one tenant when for_tenant is set (all of that
-- tenant's messages, whatever their status, with older_than '0'). A sender
-- that retries a purged message id gets it stored again, so keep older_than
-- above the sender's retry window.
-- Nightly with pg_cron: select cron.schedule('purge-webhooks', '30 3 * * *', 'select better_supabase.purge_webhooks()');
create or replace function better_supabase.purge_webhooks(
  older_than interval default '30 days',
  include_dead boolean default false,
  batch integer default 10000,
  for_tenant text default null
)
returns integer
language sql
set search_path = ''
as $$
  with purged as (
    delete from better_supabase.webhook_inbox
    where id in (
      select w.id from better_supabase.webhook_inbox w
      where ((w.status = 'processed' and w.processed_at < now() - older_than)
        or (include_dead and w.status = 'dead' and w.received_at < now() - older_than))
        and (for_tenant is null or w.tenant = for_tenant)
      order by w.id
      limit batch
    )
    returning 1
  )
  select count(*)::integer from purged
$$;

${serviceOnly([
  "receive_webhook(text, text, text, jsonb, jsonb, text, integer)",
  "claim_webhooks(text, text, integer, interval)",
  "complete_webhook(bigint, text)",
  "fail_webhook(bigint, text, text, interval)",
  "checkpoint_webhook(bigint, text, jsonb)",
  "list_webhooks(text, text, text, integer)",
  "purge_webhooks(interval, boolean, integer, text)",
])}`,
};

const realtimeTablesSql = (claims: ClaimsMeta): string => `${SCHEMA}

-- Clients refetch through RLS, so the payload carries no row data.
create or replace function better_supabase.broadcast_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base text := 'bs:t:' || tg_table_schema || '.' || tg_table_name;
  payload jsonb := jsonb_build_object('schema', tg_table_schema, 'table', tg_table_name, 'operation', tg_op);
  source text;
  tenant text;
begin
  if tg_nargs = 0 or tg_argv[0] = '' then
    perform realtime.send(payload, 'change', base, true);
    return null;
  end if;
  source := case tg_op
    when 'INSERT' then format('select %1$I from new_rows', tg_argv[0])
    when 'DELETE' then format('select %1$I from old_rows', tg_argv[0])
    else format('select %1$I from new_rows union select %1$I from old_rows', tg_argv[0])
  end;
  for tenant in execute format('select distinct t.v::text from (%s) as t(v) where t.v is not null', source) loop
    perform realtime.send(payload, 'change', base || ':' || tenant, true);
  end loop;
  return null;
end;
$$;

-- select better_supabase.track_realtime('public.customers', 'organization_id');
-- tenant_column => null broadcasts on one topic every signed-in user receives;
-- a tenant column the table lacks is an error, so no tenant table goes global.
create or replace function better_supabase.track_realtime(target regclass, tenant_column text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if tenant_column is not null and not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
  ) then
    raise exception '% has no column %', target, tenant_column
      using errcode = '42703',
        hint = 'Add the tenant column, or list the table in realtime.global to broadcast it to every signed-in user';
  end if;
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
  if tenant_column is null then
    execute format(
      'create trigger bs_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bs_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
end;
$$;

create or replace function better_supabase.untrack_realtime(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
end;
$$;

revoke execute on function better_supabase.track_realtime(regclass, text) from public, anon, authenticated;
revoke execute on function better_supabase.untrack_realtime(regclass) from public, anon, authenticated;

-- Signed-in users receive unscoped topics, and topics of their active tenant.
-- Anonymous users (signInAnonymously()) are authenticated too, but receive nothing.
drop policy if exists bs_realtime_tables_receive on realtime.messages;
create policy bs_realtime_tables_receive on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'bs:t:%'
    and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
    and (
      split_part((select realtime.topic()), ':', 4) = ''
      or split_part((select realtime.topic()), ':', 4) = coalesce(
        (select auth.jwt()) ->> ${sqlString(claims.tenant)},
        (select auth.jwt()) -> 'app_metadata' ->> ${sqlString(claims.tenant)},
        ''
      )
    )
  );`;

const REALTIME_TABLES: SqlModule = {
  name: "realtime-tables",
  title: "Realtime table changes",
  description:
    "Broadcasts a change signal (no row data) once per statement on bs:t:<schema>.<table>[:<tenant>] for live queries.",
  requires: [],
  target: "schema",
  sql: realtimeTablesSql(DEFAULT_CLAIMS),
  render: realtimeTablesSql,
  topics: () => ["bs:t:*"],
};

const JSONB_SCHEMAS: SqlModule = {
  name: "jsonb-schemas",
  title: "JSON Schema checks for jsonb",
  description:
    "pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.",
  requires: [],
  target: "schema",
  sql: `create extension if not exists pg_jsonschema with schema extensions;

${SCHEMA}

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;`,
};

const PGTAP: SqlModule = {
  name: "pgtap",
  title: "pgTAP helpers",
  description:
    "tests.create_user, tests.authenticate_as and tests.rls_enabled for `supabase test db`. Written to supabase/tests, never to your schema.",
  requires: [],
  target: "test",
  sql: `-- Runs first (000_) and commits, so later test files can use the helpers.
create extension if not exists pgtap with schema extensions;
create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

create or replace function tests.create_user(
  email text,
  app_metadata jsonb default '{}',
  user_metadata jsonb default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  user_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    email, '', now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb || app_metadata,
    user_metadata, now(), now()
  );
  return user_id;
end;
$$;

-- Runs the rest of the transaction as this user, like PostgREST does. Extra claims (tenant_id, ...) go in the JWT.
create or replace function tests.authenticate_as(user_id uuid, claims jsonb default '{}')
returns void
language plpgsql
as $$
declare
  user_email text;
begin
  select u.email into user_email from auth.users u where u.id = user_id;
  perform set_config(
    'request.jwt.claims',
    (jsonb_build_object('sub', user_id, 'role', 'authenticated', 'email', user_email, 'aud', 'authenticated') || claims)::text,
    true
  );
  set local role authenticated;
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  set local role anon;
end;
$$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  reset role;
end;
$$;

-- select tests.rls_enabled('public');
create or replace function tests.rls_enabled(schema_name text)
returns text
language sql
set search_path = extensions, pg_catalog
as $$
  select extensions.is(
    (
      select coalesce(array_agg(c.relname::text order by c.relname), '{}')
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = schema_name and c.relkind in ('r', 'p') and not c.relrowsecurity
    ),
    '{}'::text[],
    format('every table in %I has row level security enabled', schema_name)
  )
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
-- create_user writes auth.users as its definer; tests call it as postgres
-- before switching roles, so no API role can mint users.
revoke execute on function tests.create_user(text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function tests.create_user(text, jsonb, jsonb) to postgres, service_role;

select extensions.plan(1);
select extensions.pass('better-supabase test helpers installed');
select * from extensions.finish();`,
};

const GRANTS: SqlModule = {
  name: "grants",
  names: { tables: {}, options: ["fromPolicies"] },
  title: "Data API grants",
  description:
    "Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. Supabase no longer grants new tables to the Data API roles automatically.",
  requires: [],
  target: "schema",
  sql: `-- List tables and functions in \`expose\` (better-supabase.config.ts); \`sql sync\` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.`,
};

const READ_SETS: SqlModule = {
  name: "read-sets",
  title: "Read sets",
  description:
    "One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.",
  requires: [],
  target: "schema",
  sql: `-- Functions for the read sets in \`readSets\` (better-supabase.config.ts); \`gen\` and \`sql sync\` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.`,
};

const RATE_LIMIT: SqlModule = {
  name: "rate-limit",
  names: { tables: {}, options: ["preRequest"] },
  data: (ctx) =>
    ctx.flag("preRequest", true) ? RATE_LIMIT_HOOK : RATE_LIMIT_NO_HOOK,
  title: "Write rate limits",
  description:
    "Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists better_supabase.rate_limit_rules (
  scope text primary key,
  max_requests integer not null check (max_requests > 0),
  period interval not null check (period > interval '0'),
  key_claim text not null default 'sub'
);

create unlogged table if not exists better_supabase.rate_limits (
  scope text not null,
  key text not null,
  window_start timestamptz not null,
  hits integer not null,
  primary key (scope, key)
);

alter table better_supabase.rate_limit_rules enable row level security;
alter table better_supabase.rate_limits enable row level security;
revoke all on table better_supabase.rate_limit_rules from anon, authenticated;
revoke all on table better_supabase.rate_limits from anon, authenticated;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if max_requests is null then
    delete from better_supabase.rate_limit_rules r where r.scope = set_rate_limit.scope;
    delete from better_supabase.rate_limits l where l.scope = set_rate_limit.scope;
    return;
  end if;
  insert into better_supabase.rate_limit_rules as r (scope, max_requests, period, key_claim)
  values (scope, max_requests, period, key_claim)
  on conflict on constraint rate_limit_rules_pkey do update
    set max_requests = excluded.max_requests, period = excluded.period, key_claim = excluded.key_claim;
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule better_supabase.rate_limit_rules;
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from better_supabase.rate_limit_rules r where r.scope in ('*', path) order by r.scope
  loop
    caller := coalesce(
      claims ->> rule.key_claim,
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
    values (rule.scope, caller, now(), 1)
    on conflict on constraint rate_limits_pkey do update set
      window_start = case when l.window_start + rule.period <= now() then now() else l.window_start end,
      hits = case when l.window_start + rule.period <= now() then 1 else l.hits + 1 end
    returning l.hits, l.window_start into used, started;
    if used > rule.max_requests then
      retry := greatest(1, ceil(extract(epoch from started + rule.period - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule.scope, rule.max_requests, rule.period),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule better_supabase.rate_limit_rules;
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from better_supabase.rate_limit_rules r where r.scope = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule.max_requests);
  limit_period := coalesce(period, rule.period);
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
  values (scope, key, now(), 1)
  on conflict on constraint rate_limits_pkey do update set
    window_start = case when l.window_start + limit_period <= now() then now() else l.window_start end,
    hits = case when l.window_start + limit_period <= now() then 1 else l.hits + 1 end
  returning l.hits, l.window_start into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

-- Deletes up to batch counters whose window has ended, and counters without
-- a rule (removed rules, hit_rate_limit with its own limit) after a day.
-- Every caller keeps a row until then, so schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
set search_path = ''
as $$
  with expired as (
    select l.scope, l.key from better_supabase.rate_limits l
    left join better_supabase.rate_limit_rules r on r.scope = l.scope
    where (r.scope is null and l.window_start < now() - interval '1 day')
      or l.window_start + r.period <= now()
    limit batch
  ),
  purged as (
    delete from better_supabase.rate_limits l
    using expired e
    where l.scope = e.scope and l.key = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;`,
};

const vectorSearchSql = (schema: string): string =>
  `create extension if not exists vector with schema ${schema};

-- Functions for the tables in \`vectorSearch\` (better-supabase.config.ts); \`sql sync\` rewrites them.
-- They are security invoker, so RLS (a tenant policy, say) filters inside the
-- index scan. hnsw.iterative_scan keeps scanning until k visible rows are found
-- (pgvector 0.8+) instead of returning fewer.`;

const VECTOR_SCHEMA = /^[a-z_][a-z0-9_]{0,62}$/;

function vectorSchemaOf(layout: ModuleLayout): string {
  const option = layout.modules?.["vector-search"]?.options?.["schema"];
  const schema =
    option === undefined ? (layout.vectorSchema ?? "extensions") : option;
  if (typeof schema !== "string" || !VECTOR_SCHEMA.test(schema)) {
    throw new TypeError(
      "sql.modules.vector-search.options.schema must be the lowercase name of the schema pgvector is installed in",
    );
  }
  return schema;
}

const VECTOR_SEARCH: SqlModule = {
  name: "vector-search",
  title: "Vector search",
  description:
    "search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.",
  requires: [],
  target: "schema",
  names: { tables: {}, options: ["schema"] },
  sql: vectorSearchSql("extensions"),
  build: (_ctx, layout) => vectorSearchSql(vectorSchemaOf(layout)),
};

/** Schemas whose tables Supabase or Postgres own; the event trigger leaves them alone. */
const ENSURE_RLS_SKIPPED_SCHEMAS = [
  "auth",
  "storage",
  "realtime",
  "_realtime",
  "_analytics",
  "extensions",
  "graphql",
  "graphql_public",
  "vault",
  "pgsodium",
  "pgsodium_masks",
  "net",
  "cron",
  "pgbouncer",
  "supabase_functions",
  "supabase_migrations",
  "information_schema",
];

const ENSURE_RLS: SqlModule = {
  name: "ensure-rls",
  title: "RLS on every new table",
  description:
    "An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO. A table without
-- policies then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  loop
    continue when command.schema_name in (${ENSURE_RLS_SKIPPED_SCHEMAS.map((name) => `'${name}'`).join(", ")})
      or command.schema_name like 'pg\\_%';
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();`,
};

/** New modules go at the end: the position is part of the file name. */
export const SQL_MODULES: Readonly<Record<string, SqlModule>> =
  Object.fromEntries(
    [
      UPDATED_AT,
      ACTOR,
      built(AUDIT),
      built(TENANT),
      built(INVITATIONS),
      built(RESERVED_SLUGS),
      built(JOBS),
      IDEMPOTENCY,
      WEBHOOK_INBOX,
      REALTIME_TABLES,
      JSONB_SCHEMAS,
      PGTAP,
      GRANTS,
      READ_SETS,
      MFA,
      ENTITLEMENTS,
      RATE_LIMIT,
      VECTOR_SEARCH,
      built(ACCESS),
      built(SUPPORT_SESSIONS),
      built(ORGANIZATIONS),
      built(PROFILES),
      built(OUTBOX),
      built(NOTIFICATIONS),
      built(WEBHOOKS_OUT),
      built(SESSIONS),
      built(WEBHOOKS_IN),
      built(API_KEYS),
      built(SETTINGS),
      built(USAGE),
      built(BILLING),
      built(FLAGS),
      built(COMMENTS),
      built(ATTACHMENTS),
      built(DATA_LIFECYCLE),
      built(SSO),
      built(ONBOARDING),
      built(WAITLIST),
      built(ANNOUNCEMENTS),
      ENSURE_RLS,
    ].map((module) => [module.name, module]),
  );

const ORDER = Object.keys(SQL_MODULES);

/** The modules to install for `names`, dependencies first. Throws on an unknown name. */
export function resolveModules(
  names: readonly string[],
  layout: ModuleLayout = {},
): SqlModule[] {
  const ordered: SqlModule[] = [];
  const visit = (name: string, from?: string): void => {
    const module = SQL_MODULES[name];
    if (!module) {
      throw new TypeError(
        `Unknown SQL module "${name}"${from ? ` (required by ${from})` : ""}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
      );
    }
    if (ordered.includes(module)) return;
    for (const dependency of requiresOf(module, layout))
      visit(dependency, name);
    ordered.push(module);
  };
  for (const name of names) visit(name);
  return ordered.sort((a, b) => ORDER.indexOf(a.name) - ORDER.indexOf(b.name));
}

export interface ModuleFile {
  readonly module: string;
  /** `schema` and `test` files are diffed; `data` files go in a migration too. */
  readonly kind: "schema" | "data" | "test";
  readonly path: string;
  readonly contents: string;
}

export interface ModuleLayout {
  /** Directory for schema modules. Defaults to `supabase/schemas`. */
  readonly dir?: string;
  /** The declarative schema folder the diff engine loads. Defaults to `supabase/schemas`. */
  readonly schemasDir?: string;
  /** File prefix. Defaults to `900_better_supabase`. */
  readonly prefix?: string;
  /** Directory for pgTAP files. Defaults to `supabase/tests`. */
  readonly testsDir?: string;
  /** The `better_supabase.audit(...)` calls in the SQL files: the `audit` module writes a pgTAP file per table. */
  readonly auditedTables?: readonly AuditedTable[];
  /** Version stamped into the header. */
  readonly version?: string;
  /** `config.realtime.tables`: registered at the end of the `realtime-tables` module. */
  readonly realtimeTables?: readonly string[];
  /** `config.realtime.global`: tables registered with `tenant_column => null`. */
  readonly realtimeGlobal?: readonly string[];
  /** Tenant column passed to `track_realtime` for the other tables. */
  readonly tenantColumn?: string;
  /** Check constraints for the `jsonb-schemas` module. */
  readonly jsonSchemas?: readonly JsonSchemaCheck[];
  /** `config.expose`: the grants the `grants` module writes. */
  readonly grants?: readonly TableGrant[];
  /** `config.expose` functions: the roles that may execute each one. */
  readonly functionGrants?: readonly FunctionGrant[];
  /**
   * Grants the permissive policies in the schema files imply, for
   * `sql.modules.grants.options.fromPolicies`. Tables in `grants` keep
   * their listed privileges.
   */
  readonly policyGrants?: readonly TableGrant[];
  /** The tables the schema files create, for `sql.modules.sessions.options.policies`. */
  readonly declaredTables?: readonly string[];
  /** `config.readSets`, compiled: the functions the `read-sets` module writes. */
  readonly readSets?: readonly {
    readonly name: string;
    readonly sql: string;
  }[];
  /** `config.entitlements`: where the `entitlements` module finds each tenant's Stripe customer. */
  readonly entitlements?: EntitlementsSource;
  /** `config.vectorSearch`: the tables the `vector-search` module writes a search function for. */
  readonly vectorSearch?: readonly VectorSearchTable[];
  readonly vectorSchema?: string;
  /** `config.claims`: claim names the modules read and write. */
  readonly claims?: ClaimsMeta;
  /** PermDock's helpers and membership sources, from its manifest: `entitlements` reads them instead of `tenant`. */
  readonly permdock?: ModulePermdock;
  /** PermDock's permission helpers for the `access` module's `permdock` model, from its manifest. */
  readonly accessPermdock?: ModuleAccessPermdock;
  /** `config.sql.modules`: modes, names and permission keys per module. */
  readonly modules?: ModulesConfig;
  /** The keys of PermDock's permission catalog, when the project has one. */
  readonly permissionCatalog?: readonly string[];
}

/** One PermDock membership source, from the manifest's `memberships`. */
interface ModuleMembershipSource {
  /** `schema.table`. */
  readonly table: string;
  readonly userColumn: string;
  readonly scope: { readonly column: string } | { readonly value: string };
  readonly idColumn: string;
}

/** Where PermDock's `member_<scope>_ids` helpers live, and the tables behind them. */
export interface ModulePermdock {
  /** PermDock's `rls.schema`. */
  readonly schema: string;
  /** The PermDock scope tenants map to, e.g. `organization`. */
  readonly scope: string;
  /** The scope's id type, from the manifest's `rls.scopes[].type`. */
  readonly idType: ModuleIdType;
  readonly memberships: readonly ModuleMembershipSource[];
}

/** Where the `permdock` access model finds `permitted_<scope>_ids` and `permdock_has`. */
export interface ModuleAccessPermdock {
  /** PermDock's `rls.schema`. */
  readonly schema: string;
  /** The PermDock scope tenants are: the manifest's root scope unless set. */
  readonly scope: string;
  /** The scope's id type, from the manifest's `rls.scopes[].type`. */
  readonly idType: ModuleIdType;
  /**
   * PermDock's helpers for a named user (`database` mode) the manifest's
   * `rls.helpers` lists: `permdock_has_for`, `permitted_<scope>_ids_for` and
   * `permdock_can_assign_for`.
   */
  readonly forUser?: {
    readonly has: boolean;
    readonly permitted: boolean;
    readonly canAssign: boolean;
  };
  /**
   * Membership tables of the scope whose role column points into a roles
   * table (the manifest's `through` roles). An adopted `tenant` module on
   * one of them reads role names the same way.
   */
  /**
   * The manifest's `rls.suspension` rows for users and for the tenant scope.
   * The `access` module's `disabled` setting defaults to them.
   */
  readonly suspension?: {
    readonly users?: DisabledRow;
    readonly tenant?: DisabledRow;
  };
  readonly roleSources?: readonly {
    /** `schema.table` of the memberships. */
    readonly table: string;
    readonly role: {
      readonly column: string;
      readonly through: {
        readonly table: string;
        readonly id: string;
        readonly column: string;
      };
    };
  }[];
}

/** An embedding column `db.$search` can query. */
interface VectorSearchTable {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly distance: "cosine" | "l2" | "inner_product";
  /** The column's type: pgvector's `vector` (default) or `halfvec`. */
  readonly type?: "vector" | "halfvec";
  /** The primary key column the scores function returns. Defaults to `id`. */
  readonly key?: string;
  /** Full-text ranking fused with the vector ranking (reciprocal rank fusion). */
  readonly hybrid?: {
    readonly tsvector: string;
    /** The text search configuration of the query. Defaults to `simple`. */
    readonly config?: string;
    /** The RRF constant. Defaults to 60. */
    readonly k?: number;
  };
  /** A SQL expression over the row `t` the score is multiplied by, such as `t.priority`. */
  readonly boost?: string;
  /** Columns `filter` narrows before ranking, such as `organization_id`. */
  readonly prefilter?: readonly string[];
  /** A SQL condition over the row `t` every candidate must meet. */
  readonly predicate?: string;
  /** How `boost` combines with the score. Defaults to `multiply`. */
  readonly boostMode?: "multiply" | "add";
  /** A SQL `order by` list over the row `t` that breaks score ties. */
  readonly order?: string;
}

const DISTANCE_OPERATORS: Readonly<
  Record<VectorSearchTable["distance"], string>
> = {
  cosine: "<=>",
  l2: "<->",
  inner_product: "<#>",
};

/** Similarity from a distance, higher is nearer. */
const SIMILARITY: Readonly<Record<VectorSearchTable["distance"], string>> = {
  cosine: "1 - v.distance",
  l2: "1 / (1 + v.distance)",
  inner_product: "-v.distance",
};

const REGCONFIG = /^[a-z_][a-z0-9_]*$/;

/** `vectorSearch.<table>.boost`: one expression, no statement separators or comments. */
function boostExpression(
  where: string,
  boost: string,
  example = '"t.priority"',
): string {
  if (/;|--|\/\*|\$\$/.test(boost)) {
    throw new TypeError(
      `${where} must be one SQL expression over the row t, such as ${example}`,
    );
  }
  return boost;
}

/** The ranked ids and scores of one search, as a SQL query over `query`, `k`, `filter` and `text_query`. */
function vectorRanking(
  entry: VectorSearchTable,
  target: string,
  advanced: boolean,
  vector: string,
): string {
  const where = `vectorSearch.${entry.table}`;
  const key = `t.${sqlIdent(entry.key ?? "id")}`;
  const column = `t.${sqlIdent(entry.column)}`;
  const operator = `operator(${vector}.${DISTANCE_OPERATORS[entry.distance]})`;
  const prefilter = (entry.prefilter ?? [])
    .map((name) => {
      const quoted = sqlIdent(name);
      const values = `case jsonb_typeof(filter -> ${sqlString(name)}) when 'array' then filter -> ${sqlString(name)} else jsonb_build_array(filter -> ${sqlString(name)}) end`;
      return `
      and (not filter ? ${sqlString(name)} or exists (
        select 1 from jsonb_array_elements(${values}) f(v)
        where (f.v = 'null'::jsonb and t.${quoted} is null) or t.${quoted}::text = f.v #>> '{}'
      ))`;
    })
    .join("");
  const predicate =
    advanced && entry.predicate !== undefined
      ? `\n      and (${boostExpression(`${where}.predicate`, entry.predicate, '"t.expires_at > now()"')})`
      : "";
  const order =
    advanced && entry.order !== undefined
      ? boostExpression(`${where}.order`, entry.order, '"t.created_at desc"')
      : undefined;
  const widened =
    advanced &&
    (entry.hybrid !== undefined ||
      entry.boost !== undefined ||
      entry.predicate !== undefined);
  const candidates = widened
    ? "least(greatest(k, 1) * 4, 1000)"
    : "least(greatest(k, 1), 1000)";
  const hybrid = entry.hybrid;
  let text = "";
  let fused = `select v.id, ${SIMILARITY[entry.distance]} as score from vector_ranked v`;
  if (advanced && hybrid) {
    const config = hybrid.config ?? "simple";
    if (!REGCONFIG.test(config)) {
      throw new TypeError(
        `${where}.hybrid.config must be a text search configuration name, such as "english"`,
      );
    }
    const rrf = hybrid.k ?? 60;
    if (!Number.isInteger(rrf) || rrf < 1) {
      throw new TypeError(`${where}.hybrid.k must be a positive integer`);
    }
    const tsv = `t.${sqlIdent(hybrid.tsvector)}`;
    text = `,
  text_hits as materialized (
    select ${key} as id, ts_rank_cd(${tsv}, q) as text_score
    from ${target} t, websearch_to_tsquery(${sqlString(config)}::regconfig, text_query) q
    where text_query is not null and ${tsv} @@ q${prefilter}${predicate}
    order by text_score desc
    limit ${candidates}
  ),
  text_ranked as (
    select x.id, row_number() over (order by x.text_score desc) as rank from text_hits x
  )`;
    fused = `select coalesce(v.id, x.id) as id,
      coalesce(1.0 / (${String(rrf)} + v.rank), 0) + coalesce(1.0 / (${String(rrf)} + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.id = v.id`;
  }
  const boost =
    advanced && entry.boost !== undefined
      ? boostExpression(`${where}.boost`, entry.boost)
      : undefined;
  const boostMode = entry.boostMode ?? "multiply";
  const modes: readonly string[] = ["multiply", "add"];
  if (!modes.includes(boostMode)) {
    throw new TypeError(`${where}.boostMode must be "multiply" or "add"`);
  }
  const score = boost
    ? boostMode === "add"
      ? `(f.score + coalesce((${boost})::double precision, 0))::double precision`
      : `(f.score * coalesce((${boost})::double precision, 1))::double precision`
    : "f.score::double precision";
  const scored =
    boost || order
      ? `select f.id, ${score} as score, row_number() over (order by ${score} desc${order ? `, ${order}` : ""}) as ord
  from fused f join ${target} t on ${key} = f.id`
      : `select f.id, ${score} as score, row_number() over (order by ${score} desc) as ord from fused f`;
  return `with vector_hits as materialized (
    select ${key} as id, ${column} ${operator} query as distance
    from ${target} t
    where ${column} is not null${advanced ? `${prefilter}${predicate}\n      and query is not null` : ""}
    order by ${column} ${operator} query
    limit ${candidates}
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  )${text},
  fused as (
    ${fused}
  )
  ${scored}
  order by ord
  limit least(greatest(k, 1), 1000)`;
}

const ITERATIVE_SCAN = `#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);`;

const RESTORE_SCAN = `  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;`;

function vectorSearchFunctions(
  tables: readonly VectorSearchTable[],
  vector: string,
): string {
  if (tables.length === 0) return "";
  const functions = tables.map((entry) => {
    const [schema, table] = entry.table.includes(".")
      ? entry.table.split(".", 2)
      : ["public", entry.table];
    const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
    const fn = `${sqlIdent(schema!)}.${sqlIdent(`search_${table!}`)}`;
    const scores = `${sqlIdent(schema!)}.${sqlIdent(`search_${table!}_scores`)}`;
    const column = `t.${sqlIdent(entry.column)}`;
    const operator = DISTANCE_OPERATORS[entry.distance];
    const type = entry.type ?? "vector";
    const advanced =
      entry.hybrid !== undefined ||
      entry.boost !== undefined ||
      entry.predicate !== undefined ||
      entry.order !== undefined ||
      (entry.prefilter?.length ?? 0) > 0;
    const params = advanced
      ? `query ${vector}.${type}, k integer default 10, filter jsonb default '{}', text_query text default null`
      : `query ${vector}.${type}, k integer default 10`;
    const types = advanced
      ? `${vector}.${type}, integer, jsonb, text`
      : `${vector}.${type}, integer`;
    const options = [
      entry.distance,
      type === "halfvec" ? "halfvec" : "",
      entry.hybrid ? `hybrid with ${entry.hybrid.tsvector}` : "",
      entry.boost ? `boost ${entry.boost}` : "",
      entry.prefilter?.length ? `prefilter ${entry.prefilter.join(", ")}` : "",
      entry.predicate ? `predicate ${entry.predicate}` : "",
      entry.boostMode === "add" ? "additive boost" : "",
      entry.order ? `ties by ${entry.order}` : "",
    ]
      .filter(Boolean)
      .join(", ");
    const main = advanced
      ? `create or replace function ${fn}(${params})
returns setof ${target}
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select t.* from (
  ${vectorRanking(entry, target, true, vector)}
  ) r
  join ${target} t on t.${sqlIdent(entry.key ?? "id")} = r.id
  order by r.ord;
${RESTORE_SCAN}
$$;`
      : `create or replace function ${fn}(${params})
returns setof ${target}
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select t.* from ${target} t
  where ${column} is not null
  order by ${column} operator(${vector}.${operator}) query
  limit least(greatest(k, 1), 1000);
${RESTORE_SCAN}
$$;`;
    const other = advanced
      ? `${vector}.${type}, integer`
      : `${vector}.${type}, integer, jsonb, text`;
    return `-- ${entry.table}.${entry.column} (${options})
drop function if exists ${fn}(${other});
drop function if exists ${scores}(${other});
${main}
revoke execute on function ${fn}(${types}) from public, anon;
grant execute on function ${fn}(${types}) to authenticated, service_role;

-- The ids and scores of the same search, best first, for db.$search({ score: true }).
create or replace function ${scores}(${params})
returns table (id jsonb, score double precision)
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select to_jsonb(r.id), r.score from (
  ${vectorRanking(entry, target, advanced, vector)}
  ) r
  order by r.ord;
${RESTORE_SCAN}
$$;
revoke execute on function ${scores}(${types}) from public, anon;
grant execute on function ${scores}(${types}) to authenticated, service_role;`;
  });
  return `\n-- config.vectorSearch\n${functions.join("\n\n")}\n`;
}

/** The table holding each tenant's Stripe customer id. */
interface EntitlementsSource {
  /** `table` or `schema.table`; unset uses the `organizations` module's. */
  readonly table?: string;
  /** Column with the Stripe customer id (`cus_...`). */
  readonly column?: string;
  /** Column with the tenant id. */
  readonly key: string;
  /** Where entitlements come from; the customer lookups are for `stripe-sync` only. */
  readonly source?: "stripe-sync" | "custom" | EntitlementPlansSource;
  readonly claim?: FeatureClaimOption;
}

/** Privileges one role gets on a table or view. */
interface TableGrant {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly role: "anon" | "authenticated" | "service_role";
  readonly privileges: readonly string[];
}

const privilegeSql = (privilege: string): string => {
  const open = privilege.indexOf("(");
  if (open === -1) return privilege;
  const columns = privilege
    .slice(open + 1, privilege.lastIndexOf(")"))
    .split(",")
    .map((column) => sqlIdent(column.trim()));
  return `${privilege.slice(0, open).trim()} (${columns.join(", ")})`;
};

/** The roles that may execute a function. */
interface FunctionGrant {
  /** `name(argument types)` or `schema.name(argument types)`. */
  readonly function: string;
  readonly roles: readonly ("anon" | "authenticated" | "service_role")[];
}

const qualifiedTable = (name: string): string => {
  const [schema, table] = name.includes(".")
    ? name.split(".", 2)
    : ["public", name];
  return `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
};

function qualifiedFunction(signature: string): string {
  const open = signature.indexOf("(");
  const name = signature.slice(0, open).trim();
  const args = signature.slice(open);
  if (open <= 0 || !/^\([\w\s,.[\]"]*\)$/.test(args)) {
    throw new TypeError(
      `expose: "${signature}" is not a function signature such as search_notes(text, integer)`,
    );
  }
  return `${qualifiedTable(name)}${args}`;
}

const keyOf = (name: string): string =>
  name.includes(".") ? name : `public.${name}`;

/**
 * Each listed table's complete privilege set: everything is revoked from
 * the API roles first, then the listed privileges are granted. Policy
 * grants fill tables `expose` doesn't list, with every privilege for
 * `service_role`.
 */
function tableGrants(layout: ModuleLayout): string {
  const listed = layout.grants ?? [];
  const named = new Set(listed.map((grant) => keyOf(grant.table)));
  const derived = (layout.policyGrants ?? []).filter(
    (grant) => !named.has(keyOf(grant.table)),
  );
  const derivedTables = [...new Set(derived.map((grant) => grant.table))];
  const grants = [
    ...listed,
    ...derived,
    ...derivedTables.map((table): TableGrant => ({
      table,
      role: "service_role",
      privileges: ["select", "insert", "update", "delete"],
    })),
  ];
  const tables = [...new Set(grants.map((grant) => keyOf(grant.table)))];
  const statements = tables.flatMap((table) => [
    `revoke all on table ${qualifiedTable(table)} from public, anon, authenticated, service_role;`,
    ...grants
      .filter(
        (grant) => keyOf(grant.table) === table && grant.privileges.length > 0,
      )
      .map(
        (grant) =>
          `grant ${grant.privileges.map(privilegeSql).join(", ")} on table ${qualifiedTable(table)} to ${grant.role};`,
      ),
  ]);
  const functions = (layout.functionGrants ?? []).flatMap((grant) => {
    const target = qualifiedFunction(grant.function);
    return [
      `revoke execute on function ${target} from public, anon, authenticated, service_role;`,
      ...(grant.roles.length > 0
        ? [`grant execute on function ${target} to ${grant.roles.join(", ")};`]
        : []),
    ];
  });
  const all = [...statements, ...functions];
  if (all.length === 0) return "";
  return `\n-- config.expose${derived.length > 0 ? " and the policies (sql.modules.grants.options.fromPolicies)" : ""}\n${all.join("\n")}\n`;
}

/** A jsonb column and the JSON Schema its values must match. */
/** Users with a membership in a tenant of `customer`, from PermDock's membership sources. */
function permdockEntitlementMembers(permdock: ModulePermdock): string {
  const sources = permdock.memberships.flatMap((source) => {
    const scoped =
      "value" in source.scope
        ? source.scope.value === permdock.scope
          ? ""
          : undefined
        : `\n    and m.${sqlIdent(source.scope.column)}::text = ${sqlString(permdock.scope)}`;
    if (scoped === undefined) return [];
    const [schema, table] = source.table.split(".", 2);
    return [
      `  select distinct m.${sqlIdent(source.userColumn)}::uuid
  from ${sqlIdent(schema!)}.${sqlIdent(table!)} m
  where m.${sqlIdent(source.idColumn)}::text in (select t::text from better_supabase.stripe_customer_tenants(customer) t)${scoped}`,
    ];
  });
  return sources.length > 0
    ? sources.join("\n  union\n")
    : "  select null::uuid where false";
}

/**
 * `config.entitlements.customer`, or the `stripe_customer_id` column the
 * managed `organizations` module adds when both modules are installed.
 */
function customerSource(
  layout: ModuleLayout,
  installed: readonly string[],
): Required<Omit<EntitlementsSource, "source" | "claim">> & {
  readonly deferred: boolean;
} {
  const configured = layout.entitlements;
  if (configured?.table !== undefined && configured.column !== undefined) {
    return {
      table: configured.table,
      column: configured.column,
      key: configured.key,
      deferred: false,
    };
  }
  if (
    installed.includes("billing") &&
    moduleContext("billing", layout, installed).manages
  ) {
    const customers = moduleContext("billing", layout, installed).tableName(
      "customers",
    );
    return {
      table: `${customers.schema}.${customers.name}`,
      column: "stripe_customer_id",
      key: "organization_id",
      deferred: true,
    };
  }
  if (
    installed.includes("organizations") &&
    moduleContext("organizations", layout, installed).manages
  ) {
    return {
      table: "better_supabase.organizations",
      column: "stripe_customer_id",
      key: "id",
      deferred: true,
    };
  }
  throw new TypeError(
    "The entitlements module needs entitlements.customer: the table.column with each tenant's Stripe customer id. With the managed organizations module it defaults to better_supabase.organizations.stripe_customer_id.",
  );
}

function entitlementsSource(
  source: Required<Omit<EntitlementsSource, "source" | "claim">> & {
    readonly deferred: boolean;
  },
  layout: ModuleLayout,
): string {
  const permdock = layout.permdock;
  const m = memberships(layout);
  const [schema, table] = source.table.includes(".")
    ? source.table.split(".", 2)
    : ["public", source.table];
  const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
  const key = `t.${sqlIdent(source.key)}`;
  const column = `t.${sqlIdent(source.column)}`;
  const id = permdock?.idType ?? m.idType;
  const definer =
    "language sql\nstable\nsecurity definer\nset search_path = ''";
  // plpgsql checks the body when it runs, which the organizations default
  // needs: that module's file adds the column and is applied after this one.
  // language sql checks the body now, so a missing configured column fails
  // the file instead of every request.
  const lookups = source.deferred
    ? `create or replace function better_supabase.tenant_stripe_customer(tenant ${id})
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select ${column} from ${target} t where ${key} = tenant);
end
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof ${id}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select ${key} from ${target} t where ${column} = customer;
end
$$;`
    : `create or replace function better_supabase.tenant_stripe_customer(tenant ${id})
returns text
${definer}
as $$
  select ${column} from ${target} t where ${key} = tenant
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof ${id}
${definer}
as $$
  select ${key} from ${target} t where ${column} = customer
$$;`;
  return `
-- config.entitlements: ${source.table}.${source.column}
${lookups}

-- Users whose features claim carries the customer's entitlements, for
-- invalidating their sessions after entitlements.active_entitlement_summary.updated.
create or replace function better_supabase.entitlement_members(customer text)
returns setof uuid
${definer}
as $$
${
  permdock
    ? permdockEntitlementMembers(permdock)
    : `  select distinct m.${m.user}
  from ${m.table} m
  where m.${m.tenant} in (select better_supabase.stripe_customer_tenants(customer))`
}
$$;

revoke execute on function better_supabase.tenant_stripe_customer(${id}) from public, anon, authenticated;
revoke execute on function better_supabase.stripe_customer_tenants(text) from public, anon, authenticated;
revoke execute on function better_supabase.entitlement_members(text) from public, anon, authenticated;
grant execute on function better_supabase.entitlement_members(text) to service_role;
`;
}

function moduleExtras(
  module: SqlModule,
  layout: ModuleLayout,
  installed: readonly string[],
): string {
  if (module.name === "entitlements") {
    const source = layout.entitlements?.source ?? "stripe-sync";
    return source === "stripe-sync"
      ? entitlementsSource(customerSource(layout, installed), layout)
      : "";
  }
  if (module.name === "realtime-tables")
    return realtimeRegistrations(
      layout.realtimeTables ?? [],
      layout.realtimeGlobal ?? [],
      layout.tenantColumn,
    );
  if (module.name === "jsonb-schemas")
    return jsonSchemaChecks(layout.jsonSchemas ?? []);
  if (module.name === "grants") return tableGrants(layout);
  if (module.name === "vector-search")
    return vectorSearchFunctions(
      layout.vectorSearch ?? [],
      vectorSchemaOf(layout),
    );
  if (module.name === "read-sets") {
    const sets = layout.readSets ?? [];
    if (sets.length === 0) return "";
    return `\n-- config.readSets\n${sets.map((set) => `-- ${set.name}\n${set.sql}`).join("\n\n")}\n`;
  }
  return "";
}

/** Whether an installed file matches, ignoring the version stamped in its header. */
export function sameModuleFile(
  current: string | undefined,
  expected: string,
): boolean {
  if (current === undefined) return false;
  const strip = (text: string): string =>
    text.replace(
      /^(-- better-supabase module: [^\n(]*?)(?: \([^)]*\))?\n/,
      "$1\n",
    );
  return strip(current) === strip(expected);
}

/** The context a module renders with for `layout`. */
export function moduleContext(
  name: string,
  layout: ModuleLayout = {},
  installed?: readonly string[],
): ModuleContext {
  const modules = withManifestDefaults(layout);
  return createModuleContext(name, (module) => SQL_MODULES[module]?.names, {
    ...(modules ? { modules } : {}),
    ...(layout.claims ? { claims: layout.claims } : {}),
    ...(installed ? { installed } : {}),
    ...permdockIdType(layout),
  });
}

/**
 * `sql.modules` with what PermDock's manifest already says: an adopted
 * `tenant` module on a membership table whose role PermDock reads through a
 * roles table gets the same `roleThrough`, unless the config sets one.
 */
function withManifestDefaults(layout: ModuleLayout): ModulesConfig | undefined {
  return withManifestRoles(layout, withManifestSuspension(layout));
}

/**
 * `sql.modules.access.disabled` from the manifest's `rls.suspension` under
 * the `permdock` model, per subject, unless the config sets that subject.
 */
function withManifestSuspension(
  layout: ModuleLayout,
): ModulesConfig | undefined {
  const modules = layout.modules;
  const suspension = layout.accessPermdock?.suspension;
  const access = modules?.access;
  if (!modules || !suspension || access?.model !== "permdock") return modules;
  const configured = access.disabled ?? {};
  const disabled: NonNullable<AccessModuleConfig["disabled"]> = {
    ...configured,
    ...(configured.tenant === undefined && suspension.tenant
      ? { tenant: suspension.tenant }
      : {}),
    ...(configured.user === undefined && suspension.users
      ? { user: suspension.users }
      : {}),
  };
  if (
    disabled.tenant === configured.tenant &&
    disabled.user === configured.user
  )
    return modules;
  return { ...modules, access: { ...access, disabled } };
}

function withManifestRoles(
  layout: ModuleLayout,
  modules: ModulesConfig | undefined,
): ModulesConfig | undefined {
  const sources = layout.accessPermdock?.roleSources;
  const tenant = modules?.["tenant"];
  if (!modules || !sources || tenant?.mode !== "adopt") return modules;
  if (tenant.options?.["roleThrough"] !== undefined) return modules;
  const mapped = tenant.tables?.["memberships"];
  if (typeof mapped !== "string") return modules;
  const table = mapped.includes(".")
    ? mapped
    : `${tenant.schema ?? "better_supabase"}.${mapped}`;
  const role = tenant.columns?.["memberships"]?.["role"] ?? "role";
  const source = sources.find(
    (entry) => entry.table === table && entry.role.column === role,
  );
  if (!source) return modules;
  return {
    ...modules,
    tenant: {
      ...tenant,
      options: { ...tenant.options, roleThrough: source.role.through },
    },
  };
}

/** The tenant id type PermDock's manifest gives, preferring the access model's scope. */
function permdockIdType(layout: ModuleLayout): {
  permdockIdType?: ModuleIdType;
} {
  const idType = layout.accessPermdock?.idType ?? layout.permdock?.idType;
  return idType ? { permdockIdType: idType } : {};
}

/** Throws on a `sql.modules` key that names no module, or a mode a module doesn't support. */
export function checkModules(
  config: ModulesConfig = {},
  registry: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): void {
  for (const [name, entry] of Object.entries(config)) {
    const module = registry[name];
    if (!module) {
      throw new TypeError(
        `sql.modules.${name}: there is no SQL module "${name}". Modules: ${Object.keys(registry).join(", ")}`,
      );
    }
    const mode = entry?.mode ?? "managed";
    const modes = module.modes ?? ["managed"];
    if (!modes.includes(mode)) {
      throw new TypeError(
        `sql.modules.${name}.mode: the ${name} module supports ${modes.join(", ")}, not ${mode}`,
      );
    }
  }
  for (const use of migrationOptionUses(config)) {
    if (!use.adopted) {
      throw new TypeError(
        `${use.message} Only adopt mode accepts it: set sql.modules.${use.module}.mode to "adopt" while you migrate an existing schema, or remove the option.`,
      );
    }
  }
}

/** The `@bs-module` line: module, version and mode, read by `sql upgrade`. */
const MODULE_MARKER: RegExp =
  /^-- @bs-module ([a-z0-9-]+)@(\d+) (managed|adopt)$/m;

/** The installed version of a module file, from its `@bs-module` line. */
export function moduleFileVersion(
  contents: string,
): { readonly module: string; readonly version: number } | undefined {
  const match = MODULE_MARKER.exec(contents);
  return match ? { module: match[1]!, version: Number(match[2]) } : undefined;
}

function moduleSql(
  module: SqlModule,
  ctx: ModuleContext,
  layout: ModuleLayout,
) {
  if (module.build) return module.build(ctx, layout);
  if (
    module.render &&
    (layout.claims ||
      layout.permdock ||
      layout.tenantColumn ||
      (layout.entitlements?.source ?? "stripe-sync") !== "stripe-sync")
  )
    return module.render(layout.claims ?? DEFAULT_CLAIMS, layout);
  return module.sql;
}

/** A module's SQL for `layout`, without header; `undefined` in custom mode. */
export function moduleBody(
  name: string,
  layout: ModuleLayout = {},
): string | undefined {
  checkModules(layout.modules);
  const modules = resolveModules([name], layout);
  const module = modules.find((entry) => entry.name === name)!;
  const ctx = moduleContext(
    name,
    layout,
    modules.map((entry) => entry.name),
  );
  return ctx.mode === "custom" ? undefined : moduleSql(module, ctx, layout);
}

function modulePath(module: SqlModule, layout: ModuleLayout): string {
  const dir = (layout.dir ?? "supabase/schemas").replace(/\/$/, "");
  const prefix = layout.prefix ?? "900_better_supabase";
  const testsDir = (layout.testsDir ?? "supabase/tests").replace(/\/$/, "");
  const slug = module.name.replaceAll("-", "_");
  return module.target === "test"
    ? `${testsDir}/000_better_supabase_${slug}.test.sql`
    : `${dir}/${prefix}_${String(ORDER.indexOf(module.name) + 1).padStart(2, "0")}_${slug}.sql`;
}

/**
 * The schema or test file `renderModules` writes for each of `names` and the
 * modules they pull in, without rendering: modules in custom mode have none.
 */
export function moduleFilePaths(
  names: readonly string[],
  layout: ModuleLayout = {},
): ReadonlyMap<string, string> {
  checkModules(layout.modules);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return new Map(
    modules
      .filter(
        (module) =>
          moduleContext(module.name, layout, installed).mode !== "custom",
      )
      .map((module) => [module.name, modulePath(module, layout)]),
  );
}

/** A permission key a SQL module checks, from `modulePermissionKeys`. */
export interface ModulePermissionKey {
  readonly module: string;
  /** The action in `sql.modules.<module>.permissions` that overrides the key. */
  readonly action: string;
  readonly key: string;
  /**
   * `tenant` for keys checked in a tenant (`member_can`, `can`,
   * `tenant_ids_with`), `platform` for `is_platform` and `platform_can`.
   */
  readonly scope: "tenant" | "platform";
}

/** Actions a module checks only when `sql.modules.<module>.permissions` names a key. */
const OPTIONAL_MODULE_PERMISSIONS: Readonly<
  Record<string, Readonly<Record<string, "tenant" | "platform">>>
> = {
  organizations: {
    create: "platform",
    updatePlatform: "platform",
    deletePlatform: "platform",
  },
  audit: { reveal: "tenant" },
  "data-lifecycle": { deletePlatform: "platform" },
};

const isPermissionModule = (
  name: string,
): name is keyof typeof MODULE_PERMISSIONS =>
  Object.hasOwn(MODULE_PERMISSIONS, name);

/**
 * Every permission key the modules `names` install (with what they pull
 * in) check, after `sql.modules.<module>.permissions` overrides. Modules in custom
 * mode are skipped, and so is `invitations.invitePlatform` without platform
 * roles. PermDock's doctor runs the same catalog check from its side.
 */
export function modulePermissionKeys(
  config: ModulesConfig,
  names: readonly string[],
): ModulePermissionKey[] {
  const layout: ModuleLayout = { modules: config };
  checkModules(config);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module): ModulePermissionKey[] => {
    const name = module.name;
    if (!isPermissionModule(name)) return [];
    const ctx = moduleContext(name, layout, installed);
    if (ctx.mode === "custom") return [];
    const scopes: Readonly<Record<string, "tenant" | "platform">> =
      MODULE_PERMISSION_SCOPES[name];
    const optional = Object.entries(
      OPTIONAL_MODULE_PERMISSIONS[name] ?? {},
    ).flatMap(([action, scope]): ModulePermissionKey[] => {
      const key = ctx.permissionKey(action, "");
      return key === "" ? [] : [{ module: name, action, key, scope }];
    });
    return [
      ...Object.entries(MODULE_PERMISSIONS[name]).flatMap(
        ([action, fallback]): ModulePermissionKey[] =>
          action === "invitePlatform" && !hasPlatformRoles(ctx)
            ? []
            : [
                {
                  module: name,
                  action,
                  key: ctx.permissionKey(action, fallback),
                  scope: scopes[action]!,
                },
              ],
      ),
      ...optional,
    ];
  });
}

/** The table `moduleRow` writes to, created by every schema module's file. */
const MODULE_MODULES_TABLE = `
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
`;

/** Records the module in `better_supabase.modules`, which `sql upgrade` and doctor read. */
function moduleRow(module: SqlModule, mode: ModuleMode): string {
  return `insert into better_supabase.modules (name, version, mode)
values (${sqlString(module.name)}, ${String(moduleVersion(module))}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`;
}

/**
 * Where a module's data statements go: `better-supabase-data/` next to the
 * declarative schema folder, or next to `dir` when `dir` is outside it.
 * pg-delta loads every file under the schema folder, nested folders
 * included, and rejects a managed table that has rows afterwards.
 */
function moduleDataPath(module: SqlModule, layout: ModuleLayout): string {
  const path = modulePath(module, layout);
  const file = path.slice(path.lastIndexOf("/"));
  const dir = path.slice(0, path.lastIndexOf("/"));
  const bare = (value: string) => value.replace(/^\.\//, "").replace(/\/$/, "");
  const schemas = bare(layout.schemasDir ?? "supabase/schemas");
  const inside = bare(dir) === schemas || bare(dir).startsWith(`${schemas}/`);
  const base = inside ? `${dir.startsWith("./") ? "./" : ""}${schemas}` : dir;
  const parent = base.lastIndexOf("/");
  return `${parent < 0 ? "" : base.slice(0, parent + 1)}better-supabase-data${file}`;
}

/** The `@bs-module-data` line of a data file. */
const MODULE_DATA_MARKER: RegExp = /^-- @bs-module-data ([a-z0-9-]+)$/m;

const CREATE_EXTENSION =
  /^create extension if not exists "?([a-z_][a-z0-9_]*)"?(?: with schema "?([a-z_][a-z0-9_]*)"?)?;/gim;

/**
 * The extensions a module's schema file creates, again for its data file. A
 * schema diff can leave an extension out of the migration (pg-delta skips
 * one in a schema it doesn't manage, such as `extensions` or pgmq's own),
 * and `sql data` then still puts it in one.
 */
function moduleExtensions(body: string): string {
  return extensionsOf([body])
    .map((extension) => extension.statement)
    .join("\n");
}

export interface ModuleExtension {
  readonly name: string;
  readonly statement: string;
}

function extensionsOf(bodies: readonly string[]): ModuleExtension[] {
  const seen = new Set<string>();
  return bodies.flatMap((body) =>
    [...body.matchAll(CREATE_EXTENSION)].flatMap(
      ([, name = "", schema]): ModuleExtension[] => {
        const key = name.toLowerCase();
        if (seen.has(key)) return [];
        seen.add(key);
        return [
          {
            name: key,
            statement: `create extension if not exists ${sqlIdent(name)}${schema === undefined ? "" : ` with schema ${sqlIdent(schema)}`};`,
          },
        ];
      },
    ),
  );
}

export const moduleSchemaExtensions = (
  files: readonly ModuleFile[],
): ModuleExtension[] =>
  extensionsOf(
    files.filter((file) => file.kind === "schema").map((file) => file.contents),
  );

/** Whether `contents` is a data file `renderModules` wrote. */
export const isModuleDataFile = (contents: string): boolean =>
  MODULE_DATA_MARKER.test(contents);

/**
 * The files `sql add` writes for these modules. Modules in `custom` mode
 * write nothing: the app implements their contract. A schema module's rows,
 * role settings and other statements a schema diff can't capture go to a
 * second file in `better-supabase-data/` (`kind: 'data'`), which
 * `sql data` writes into a migration.
 */
export function renderModules(
  names: readonly string[],
  layout: ModuleLayout = {},
): ModuleFile[] {
  checkModules(layout.modules);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module): ModuleFile[] => {
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode === "custom") return [];
    const title = `-- better-supabase module: ${module.name}${layout.version ? ` (${layout.version})` : ""}`;
    const managed = [
      "-- Managed by `better-supabase sql add`; re-running it overwrites this file.",
      "-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.",
    ];
    const header = [
      title,
      `-- @bs-module ${module.name}@${String(moduleVersion(module))} ${ctx.mode}`,
      `-- ${module.description}`,
      ...managed,
    ].join("\n");
    const extra = moduleExtras(module, layout, installed);
    const wrappers = deprecationWrappers(module, ctx);
    const body = moduleSql(module, ctx, layout).trim();
    const api = ctx.config.api
      ? apiWrappers(body, ctx.schemaName, ctx.config.api, module.name)
      : "";
    if (module.target === "test") {
      return [
        {
          module: module.name,
          kind: "test",
          path: modulePath(module, layout),
          contents: `${header}\n\n${body}\n${extra}${wrappers}`,
        },
      ];
    }
    const data = [
      moduleExtensions(body),
      module.data?.(ctx, layout).trim() ?? "",
      moduleRow(module, ctx.mode),
    ]
      .filter((part) => part !== "")
      .join("\n\n");
    const dataHeader = [
      title,
      `-- @bs-module-data ${module.name}`,
      "-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`",
      "-- after the schema migration to put them in a migration.",
      ...managed,
    ].join("\n");
    const testsDir = (layout.testsDir ?? "supabase/tests").replace(/\/$/, "");
    const slug = module.name.replaceAll("-", "_");
    const testHeader = [
      title,
      `-- @bs-module-test ${module.name}`,
      ...managed,
    ].join("\n");
    return [
      {
        module: module.name,
        kind: "schema",
        path: modulePath(module, layout),
        contents: `${header}\n\n${body}\n${extra}${wrappers}${api}${MODULE_MODULES_TABLE}`,
      },
      {
        module: module.name,
        kind: "data",
        path: moduleDataPath(module, layout),
        contents: `${dataHeader}\n\n${data}\n`,
      },
      ...(module.tests?.(ctx, layout) ?? []).map((test): ModuleFile => ({
        module: module.name,
        kind: "test",
        path: `${testsDir}/900_better_supabase_${slug}_${test.name}.test.sql`,
        contents: `${testHeader}\n\n${test.sql.trim()}\n`,
      })),
    ];
  });
}

export interface ModuleTopic {
  readonly module: string;
  readonly topic: string;
}

export function moduleTopics(
  names: readonly string[],
  layout: ModuleLayout = {},
): ModuleTopic[] {
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module) => {
    if (module.topics === undefined) return [];
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode === "custom") return [];
    return module.topics(ctx).map((topic) => ({ module: module.name, topic }));
  });
}

/** The compatibility wrappers of a module's deprecated symbols that are not removed yet. */
export function deprecationWrappers(
  module: SqlModule,
  ctx: ModuleContext,
): string {
  return (module.deprecated ?? [])
    .flatMap((entry) =>
      entry.removed === undefined && entry.wrapper
        ? [
            `\n-- Deprecated since ${entry.since}: use ${entry.use}.\n${entry.wrapper(ctx).trim()}\n`,
          ]
        : [],
    )
    .join("");
}

/** An installed module, from its file's `@bs-module` line or `modules`. */
export interface InstalledModule {
  readonly module: string;
  readonly version: number;
}

/** What `sql upgrade` runs for one module behind the current version. */
export interface ModuleUpgradePlan {
  readonly module: string;
  readonly from: number;
  readonly to: number;
  readonly steps: readonly {
    readonly from: number;
    readonly description: string;
    readonly sql: string;
  }[];
}

/**
 * The upgrade steps for modules installed at an older version. A version
 * without a step needs none: the module file upgrades in place. Modules in
 * custom mode belong to the app and are skipped.
 */
export function upgradePlan(
  installed: readonly InstalledModule[],
  layout: ModuleLayout = {},
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): ModuleUpgradePlan[] {
  checkModules(layout.modules, modules);
  const names = installed.map((entry) => entry.module);
  return installed.flatMap((entry): ModuleUpgradePlan[] => {
    const module = modules[entry.module];
    if (!module) return [];
    const to = moduleVersion(module);
    if (entry.version >= to) return [];
    const ctx = createModuleContext(
      entry.module,
      (name) => modules[name]?.names,
      {
        ...(layout.modules ? { modules: layout.modules } : {}),
        ...(layout.claims ? { claims: layout.claims } : {}),
        installed: names,
        ...permdockIdType(layout),
      },
    );
    if (ctx.mode === "custom") return [];
    const steps = (module.upgrades ?? [])
      .filter((step) => step.from >= entry.version && step.from < to)
      .toSorted((a, b) => a.from - b.from)
      .map((step) => ({
        from: step.from,
        description: step.description,
        sql: step.sql(ctx).trim(),
      }));
    return [{ module: module.name, from: entry.version, to, steps }];
  });
}

/** Every deprecated or removed module symbol, with its module. */
export function moduleDeprecations(
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): readonly (ModuleDeprecation & { readonly module: string })[] {
  return Object.values(modules).flatMap((module) =>
    (module.deprecated ?? []).map((entry) => ({
      ...entry,
      module: module.name,
    })),
  );
}

/** The contract functions of the modules in `custom` mode, for doctor. */
export function customContracts(
  names: readonly string[],
  layout: ModuleLayout = {},
): {
  readonly module: string;
  readonly schema: string;
  readonly idType: ModuleIdType;
  readonly functions: readonly ModuleContractFunction[];
}[] {
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module) => {
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode !== "custom" || !module.contract) return [];
    return [
      {
        module: module.name,
        schema: ctx.schemaName,
        idType: ctx.idType,
        functions: module.contract(ctx),
      },
    ];
  });
}

function realtimeRegistrations(
  tables: readonly string[],
  global: readonly string[],
  tenantColumn: string | undefined,
): string {
  if (tables.length === 0) return "";
  const qualify = (table: string): string =>
    table.includes(".") ? table : `public.${table}`;
  const unscoped = new Set(global.map(qualify));
  const lines = tables.map((table) => {
    const target = qualify(table);
    const tenant =
      tenantColumn && !unscoped.has(target) ? sqlString(tenantColumn) : "null";
    return `select better_supabase.track_realtime(${sqlString(target)}, tenant_column => ${tenant});`;
  });
  return `\n-- config.realtime.tables\n${lines.join("\n")}\n`;
}
