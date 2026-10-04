import type { KitMode, KitsConfig } from "../config/kits.ts";
import type { ClaimsMeta } from "../schema/types.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import {
  createKitContext,
  type KitContext,
  type KitContractFunction,
  type KitIdType,
  type KitNames,
} from "./context.ts";
import { ACCESS } from "./modules/access.ts";
import { AUDIT } from "./modules/audit.ts";
import { INVITATIONS } from "./modules/invitations.ts";
import { JOBS } from "./modules/jobs.ts";
import { NOTIFICATIONS } from "./modules/notifications.ts";
import { ORGANIZATIONS } from "./modules/organizations.ts";
import { OUTBOX } from "./modules/outbox.ts";
import { PROFILES } from "./modules/profiles.ts";
import { SUPPORT_SESSIONS } from "./modules/support.ts";
import { TENANT } from "./modules/tenant.ts";
import { WEBHOOKS_OUT } from "./modules/webhooks-out.ts";
import { EQUIVALENT_TRIGGERS, SCHEMA } from "./shared.ts";

export {
  isKitIdType,
  KIT_ID_TYPES,
  type KitIdType,
  kitIdType,
} from "./context.ts";

/** The step from one module version to the next, for `sql upgrade`. */
export interface KitUpgrade {
  /** The installed version this step upgrades from. */
  readonly from: number;
  readonly description: string;
  /** SQL run before the module's current file, e.g. renames and backfills. */
  readonly sql: (ctx: KitContext) => string;
}

/**
 * A renamed kit symbol. It keeps a compatibility wrapper for at least one
 * minor release, then is removed; doctor reports uses of both (BS309), and
 * the name stays reserved.
 */
export interface KitDeprecation {
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
  readonly wrapper?: (ctx: KitContext) => string;
}

/**
 * SQL kit modules for `better-supabase sql add`. Every module is idempotent
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
  /** What it needs for this layout, e.g. per `kits.access.model`; overrides both. */
  readonly dependencies?: (layout: KitLayout) => readonly string[];
  /** `schema` files go with your schemas; `test` files go to `supabase/tests`. */
  readonly target: "schema" | "test";
  /** The module with the default claim names. */
  readonly sql: string;
  /** The module for configured claim names (`config.claims`), when it reads claims. */
  readonly render?: (claims: ClaimsMeta, layout: KitLayout) => string;
  /** Bumped when installed databases need an upgrade step. Defaults to 1. */
  readonly version?: number;
  /** The modes `kits.<name>.mode` accepts. Defaults to `managed` only. */
  readonly modes?: readonly KitMode[];
  /** The logical tables and columns `kits.<name>.tables` and `columns` map. */
  readonly names?: KitNames;
  /** The functions other modules and the TypeScript side call. */
  readonly contract?: (ctx: KitContext) => readonly KitContractFunction[];
  /** Renders the module for a layout; takes precedence over `render`. */
  readonly build?: (ctx: KitContext, layout: KitLayout) => string;
  readonly upgrades?: readonly KitUpgrade[];
  readonly deprecated?: readonly KitDeprecation[];
  /**
   * Rows, role settings and calls that a schema diff doesn't capture. They
   * go to `better-supabase-data/` next to the schema folder and a migration
   * (`sql data`) instead of the schema file.
   */
  readonly data?: (ctx: KitContext, layout: KitLayout) => string;
}

export const moduleVersion = (module: SqlModule): number => module.version ?? 1;

/** A module rendered by `build`; its `sql` is the build with the defaults. */
export type KitModuleDefinition = Omit<
  SqlModule,
  "sql" | "render" | "build"
> & {
  readonly build: NonNullable<SqlModule["build"]>;
};

function built(definition: KitModuleDefinition): SqlModule {
  let cached: string | undefined;
  return {
    ...definition,
    get sql() {
      return (cached ??= definition.build(kitContext(definition.name, {}), {}));
    },
  };
}

const requiresOf = (module: SqlModule, layout: KitLayout): readonly string[] =>
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

/** `has_entitlement` and `feature_claims` on the kit's `better_supabase.memberships`. */
const tenantEntitlementChecks = (claims: ClaimsMeta): string => `
-- using ((select better_supabase.has_entitlement(organization_id, 'exports')))
create or replace function better_supabase.has_entitlement(tenant uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select better_supabase.has_org_role(tenant)
    and key = any (better_supabase.tenant_entitlements(tenant))
$$;

revoke execute on function better_supabase.has_entitlement(uuid, text) from public, anon;
grant execute on function better_supabase.has_entitlement(uuid, text) to authenticated, service_role;

-- Every tenant of the caller with \`key\`, for one set check per query instead of
-- one call per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_entitlement('exports')))
create or replace function better_supabase.tenant_ids_with_entitlement(key text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from better_supabase.member_org_ids() as t(id)
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
  select coalesce(jsonb_object_agg(m.org_id::text, to_jsonb(e.keys)), '{}'::jsonb)
  from better_supabase.memberships m
  cross join lateral (select better_supabase.tenant_entitlements(m.org_id) as keys) e
  where m.user_id = feature_claims.user_id
    and cardinality(e.keys) > 0
$$;`;

/** `has_entitlement` and `feature_claims` on PermDock's `member_<scope>_ids` helpers. */
const permdockEntitlementChecks = (
  claims: ClaimsMeta,
  permdock: KitPermdock,
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
  select coalesce(jsonb_object_agg(t.id::text, to_jsonb(e.keys)), '{}'::jsonb)
  from ${memberFor}(feature_claims.user_id) as t(id)
  cross join lateral (select better_supabase.tenant_entitlements(t.id) as keys) e
  where cardinality(e.keys) > 0
$$;`;
};

const entitlementsSql = (
  claims: ClaimsMeta,
  layout: KitLayout = {},
): string => {
  const id = layout.permdock?.idType ?? "uuid";
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
${layout.permdock ? permdockEntitlementChecks(claims, layout.permdock) : tenantEntitlementChecks(claims)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;
};

const ENTITLEMENTS: SqlModule = {
  name: "entitlements",
  title: "Stripe entitlements",
  description:
    "Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.",
  requires: ["tenant"],
  permdockRequires: [],
  target: "schema",
  sql: entitlementsSql(DEFAULT_CLAIMS),
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

const RESERVED_SLUGS: SqlModule = {
  name: "reserved-slugs",
  data: () => RESERVED_SLUGS_SEED,
  title: "Reserved slugs",
  description:
    "A slug format check and a list of reserved words (admin, api, www, ...), enforced by a trigger.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
grant select on better_supabase.reserved_slugs to anon, authenticated;
drop policy if exists bs_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bs_reserved_slugs_read on better_supabase.reserved_slugs for select using (true);

create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
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
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;`,
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

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'begin_idempotent(text, text, text, interval, interval)',
    'complete_idempotent(text, text, integer, jsonb)',
    'release_idempotent(text, text)',
    'purge_idempotency_keys()'
  ] loop
    execute format('revoke execute on function better_supabase.%s from public, anon, authenticated', fn);
    execute format('grant execute on function better_supabase.%s to service_role', fn);
  end loop;
end;
$$;`,
};

const WEBHOOK_INBOX: SqlModule = {
  name: "webhook-inbox",
  title: "Webhook inbox",
  description:
    "Stores verified webhooks once per message id, then processes them with leases and retries.",
  requires: [],
  target: "schema",
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
create index if not exists webhook_inbox_ready_idx
  on better_supabase.webhook_inbox (source, available_at, id) where status in ('pending', 'processing');

alter table better_supabase.webhook_inbox enable row level security;
revoke all on better_supabase.webhook_inbox from anon, authenticated;
grant all on better_supabase.webhook_inbox to service_role;

-- duplicate = true when the message id was seen before (the sender retried).
create or replace function better_supabase.receive_webhook(
  source text,
  message_id text,
  event_type text,
  payload jsonb,
  headers jsonb default '{}'
)
returns table (id bigint, duplicate boolean)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
  insert into better_supabase.webhook_inbox (source, message_id, event_type, payload, headers)
  values (source, message_id, event_type, payload, headers)
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

-- Deletes up to batch processed messages (and dead ones with include_dead)
-- older than older_than. A sender that retries a purged message id gets it
-- stored again, so keep older_than above the sender's retry window.
-- Nightly with pg_cron: select cron.schedule('purge-webhooks', '30 3 * * *', 'select better_supabase.purge_webhooks()');
create or replace function better_supabase.purge_webhooks(
  older_than interval default '30 days',
  include_dead boolean default false,
  batch integer default 10000
)
returns integer
language sql
set search_path = ''
as $$
  with purged as (
    delete from better_supabase.webhook_inbox
    where id in (
      select w.id from better_supabase.webhook_inbox w
      where (w.status = 'processed' and w.processed_at < now() - older_than)
        or (include_dead and w.status = 'dead' and w.received_at < now() - older_than)
      order by w.id
      limit batch
    )
    returning 1
  )
  select count(*)::integer from purged
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'receive_webhook(text, text, text, jsonb, jsonb)',
    'claim_webhooks(text, text, integer, interval)',
    'complete_webhook(bigint, text)',
    'fail_webhook(bigint, text, text, interval)',
    'purge_webhooks(interval, boolean, integer)'
  ] loop
    execute format('revoke execute on function better_supabase.%s from public, anon, authenticated', fn);
    execute format('grant execute on function better_supabase.%s to service_role', fn);
  end loop;
end;
$$;`,
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
};

const JSONB_SCHEMAS: SqlModule = {
  name: "jsonb-schemas",
  title: "JSON Schema checks for jsonb",
  description:
    "pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types.",
  requires: [],
  target: "schema",
  sql: `create extension if not exists pg_jsonschema with schema extensions;`,
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
  title: "Data API grants",
  description:
    "Grants the tables in the `expose` config to anon and authenticated. Supabase no longer grants new tables to the Data API roles automatically.",
  requires: [],
  target: "schema",
  sql: `-- List tables in \`expose\` (better-supabase.config.ts); \`sql sync\` rewrites the grants below.
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
  data: () => RATE_LIMIT_HOOK,
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
-- by a replica), so only writes count. The service role is never limited.
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
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;`,
};

const VECTOR_SEARCH: SqlModule = {
  name: "vector-search",
  title: "Vector search",
  description:
    "search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.",
  requires: [],
  target: "schema",
  sql: `create extension if not exists vector with schema extensions;

-- Functions for the tables in \`vectorSearch\` (better-supabase.config.ts); \`sql sync\` rewrites them.
-- They are security invoker, so RLS (a tenant policy, say) filters inside the
-- index scan. hnsw.iterative_scan keeps scanning until k visible rows are found
-- (pgvector 0.8+) instead of returning fewer.`,
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
      RESERVED_SLUGS,
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
    ].map((module) => [module.name, module]),
  );

const ORDER = Object.keys(SQL_MODULES);

/** The modules to install for `names`, dependencies first. Throws on an unknown name. */
export function resolveModules(
  names: readonly string[],
  layout: KitLayout = {},
): SqlModule[] {
  const ordered: SqlModule[] = [];
  const visit = (name: string, from?: string): void => {
    const module = SQL_MODULES[name];
    if (!module) {
      throw new TypeError(
        `Unknown SQL kit module "${name}"${from ? ` (required by ${from})` : ""}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
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

export interface KitFile {
  readonly module: string;
  /** `schema` and `test` files are diffed; `data` files go in a migration too. */
  readonly kind: "schema" | "data" | "test";
  readonly path: string;
  readonly contents: string;
}

export interface KitLayout {
  /** Directory for schema modules. Defaults to `supabase/schemas`. */
  readonly dir?: string;
  /** File prefix. Defaults to `900_better_supabase`. */
  readonly prefix?: string;
  /** Directory for pgTAP files. Defaults to `supabase/tests`. */
  readonly testsDir?: string;
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
  /** `config.readSets`, compiled: the functions the `read-sets` module writes. */
  readonly readSets?: readonly {
    readonly name: string;
    readonly sql: string;
  }[];
  /** `config.entitlements`: where the `entitlements` module finds each tenant's Stripe customer. */
  readonly entitlements?: EntitlementsSource;
  /** `config.vectorSearch`: the tables the `vector-search` module writes a search function for. */
  readonly vectorSearch?: readonly VectorSearchTable[];
  /** `config.claims`: claim names the modules read and write. */
  readonly claims?: ClaimsMeta;
  /** PermDock's helpers and membership sources, from its manifest: `entitlements` reads them instead of `tenant`. */
  readonly permdock?: KitPermdock;
  /** `config.kits`: modes, names and permission keys per module. */
  readonly kits?: KitsConfig;
}

/** One PermDock membership source, from the manifest's `memberships`. */
interface KitMembershipSource {
  /** `schema.table`. */
  readonly table: string;
  readonly userColumn: string;
  readonly scope: { readonly column: string } | { readonly value: string };
  readonly idColumn: string;
}

/** Where PermDock's `member_<scope>_ids` helpers live, and the tables behind them. */
export interface KitPermdock {
  /** PermDock's `rls.schema`. */
  readonly schema: string;
  /** The PermDock scope tenants map to, e.g. `organization`. */
  readonly scope: string;
  /** The scope's id type, from the manifest's `rls.scopes[].type`. */
  readonly idType: KitIdType;
  readonly memberships: readonly KitMembershipSource[];
}

/** An embedding column `db.$search` can query. */
interface VectorSearchTable {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly distance: "cosine" | "l2" | "inner_product";
}

const DISTANCE_OPERATORS: Readonly<
  Record<VectorSearchTable["distance"], string>
> = {
  cosine: "<=>",
  l2: "<->",
  inner_product: "<#>",
};

function vectorSearchFunctions(tables: readonly VectorSearchTable[]): string {
  if (tables.length === 0) return "";
  const functions = tables.map((entry) => {
    const [schema, table] = entry.table.includes(".")
      ? entry.table.split(".", 2)
      : ["public", entry.table];
    const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
    const fn = `${sqlIdent(schema!)}.${sqlIdent(`search_${table!}`)}`;
    const column = `t.${sqlIdent(entry.column)}`;
    const operator = DISTANCE_OPERATORS[entry.distance];
    const signature = `${fn}(extensions.vector, integer)`;
    return `-- ${entry.table}.${entry.column} (${entry.distance})
create or replace function ${fn}(query extensions.vector, k integer default 10)
returns setof ${target}
language sql
stable
security invoker
set search_path = ''
set hnsw.iterative_scan = 'strict_order'
as $$
  select t.* from ${target} t
  where ${column} is not null
  order by ${column} operator(extensions.${operator}) query
  limit least(greatest(k, 1), 1000)
$$;

revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;
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
}

/** Privileges one Data API role gets on a table or view. */
interface TableGrant {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly role: "anon" | "authenticated";
  readonly privileges: readonly ("select" | "insert" | "update" | "delete")[];
}

function tableGrants(grants: readonly TableGrant[]): string {
  const statements = grants
    .filter((grant) => grant.privileges.length > 0)
    .map((grant) => {
      const [schema, table] = grant.table.includes(".")
        ? grant.table.split(".", 2)
        : ["public", grant.table];
      return `grant ${grant.privileges.join(", ")} on table ${sqlIdent(schema!)}.${sqlIdent(table!)} to ${grant.role};`;
    });
  if (statements.length === 0) return "";
  return `\n-- config.expose\n${statements.join("\n")}\n`;
}

/** A jsonb column and the JSON Schema its values must match. */
interface JsonSchemaCheck {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly schema: Readonly<Record<string, unknown>>;
}

function jsonSchemaChecks(checks: readonly JsonSchemaCheck[]): string {
  if (checks.length === 0) return "";
  const statements = checks.map((check) => {
    const [schema, table] = check.table.includes(".")
      ? check.table.split(".", 2)
      : ["public", check.table];
    const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
    const name = sqlIdent(`bs_json_${check.column}`.slice(0, 63));
    return [
      `alter table ${target} drop constraint if exists ${name};`,
      `alter table ${target} add constraint ${name}`,
      `  check (extensions.jsonb_matches_schema(${sqlString(JSON.stringify(check.schema))}::json, ${sqlIdent(check.column)}));`,
    ].join("\n");
  });
  return `\n-- config.json schemas\n${statements.join("\n\n")}\n`;
}

/** Users with a membership in a tenant of `customer`, from PermDock's membership sources. */
function permdockEntitlementMembers(permdock: KitPermdock): string {
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
  layout: KitLayout,
  installed: readonly string[],
): Required<EntitlementsSource> & { readonly deferred: boolean } {
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
    installed.includes("organizations") &&
    kitContext("organizations", layout, installed).manages
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
  source: Required<EntitlementsSource> & { readonly deferred: boolean },
  permdock: KitPermdock | undefined,
): string {
  const [schema, table] = source.table.includes(".")
    ? source.table.split(".", 2)
    : ["public", source.table];
  const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
  const key = `t.${sqlIdent(source.key)}`;
  const column = `t.${sqlIdent(source.column)}`;
  const id = permdock?.idType ?? "uuid";
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
    : `  select distinct m.user_id
  from better_supabase.memberships m
  where m.org_id in (select better_supabase.stripe_customer_tenants(customer))`
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
  layout: KitLayout,
  installed: readonly string[],
): string {
  if (module.name === "entitlements")
    return entitlementsSource(
      customerSource(layout, installed),
      layout.permdock,
    );
  if (module.name === "realtime-tables")
    return realtimeRegistrations(
      layout.realtimeTables ?? [],
      layout.realtimeGlobal ?? [],
      layout.tenantColumn,
    );
  if (module.name === "jsonb-schemas")
    return jsonSchemaChecks(layout.jsonSchemas ?? []);
  if (module.name === "grants") return tableGrants(layout.grants ?? []);
  if (module.name === "vector-search")
    return vectorSearchFunctions(layout.vectorSearch ?? []);
  if (module.name === "read-sets") {
    const sets = layout.readSets ?? [];
    if (sets.length === 0) return "";
    return `\n-- config.readSets\n${sets.map((set) => `-- ${set.name}\n${set.sql}`).join("\n\n")}\n`;
  }
  return "";
}

/** Whether an installed file matches, ignoring the version stamped in its header. */
export function sameKitFile(
  current: string | undefined,
  expected: string,
): boolean {
  if (current === undefined) return false;
  const strip = (text: string): string =>
    text.replace(
      /^(-- better-supabase SQL kit: [^\n(]*?)(?: \([^)]*\))?\n/,
      "$1\n",
    );
  return strip(current) === strip(expected);
}

/** The context a module renders with for `layout`. */
export function kitContext(
  name: string,
  layout: KitLayout = {},
  installed?: readonly string[],
): KitContext {
  return createKitContext(name, (module) => SQL_MODULES[module]?.names, {
    ...(layout.kits ? { kits: layout.kits } : {}),
    ...(layout.claims ? { claims: layout.claims } : {}),
    ...(installed ? { installed } : {}),
    ...(layout.permdock ? { permdockIdType: layout.permdock.idType } : {}),
  });
}

/** Throws on a `kits` key that names no module, or a mode a module doesn't support. */
export function checkKits(
  kits: KitsConfig = {},
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): void {
  for (const [name, entry] of Object.entries(kits)) {
    const module = modules[name];
    if (!module) {
      throw new TypeError(
        `kits.${name}: there is no SQL kit module "${name}". Modules: ${Object.keys(modules).join(", ")}`,
      );
    }
    const mode = entry?.mode ?? "managed";
    const modes = module.modes ?? ["managed"];
    if (!modes.includes(mode)) {
      throw new TypeError(
        `kits.${name}.mode: the ${name} module supports ${modes.join(", ")}, not ${mode}`,
      );
    }
  }
}

/** The `@bs-kit` line: module, version and mode, read by `sql upgrade`. */
const KIT_MARKER: RegExp = /^-- @bs-kit ([a-z0-9-]+)@(\d+) (managed|adopt)$/m;

/** The installed version of a kit file, from its `@bs-kit` line. */
export function kitFileVersion(
  contents: string,
): { readonly module: string; readonly version: number } | undefined {
  const match = KIT_MARKER.exec(contents);
  return match ? { module: match[1]!, version: Number(match[2]) } : undefined;
}

function moduleSql(module: SqlModule, ctx: KitContext, layout: KitLayout) {
  if (module.build) return module.build(ctx, layout);
  if (
    module.render &&
    (layout.claims || layout.permdock || layout.tenantColumn)
  )
    return module.render(layout.claims ?? DEFAULT_CLAIMS, layout);
  return module.sql;
}

/** A module's SQL for `layout`, without header; `undefined` in custom mode. */
export function moduleBody(
  name: string,
  layout: KitLayout = {},
): string | undefined {
  checkKits(layout.kits);
  const modules = resolveModules([name], layout);
  const module = modules.find((entry) => entry.name === name)!;
  const ctx = kitContext(
    name,
    layout,
    modules.map((entry) => entry.name),
  );
  return ctx.mode === "custom" ? undefined : moduleSql(module, ctx, layout);
}

function kitPath(module: SqlModule, layout: KitLayout): string {
  const dir = (layout.dir ?? "supabase/schemas").replace(/\/$/, "");
  const prefix = layout.prefix ?? "900_better_supabase";
  const testsDir = (layout.testsDir ?? "supabase/tests").replace(/\/$/, "");
  const slug = module.name.replaceAll("-", "_");
  return module.target === "test"
    ? `${testsDir}/000_better_supabase_${slug}.test.sql`
    : `${dir}/${prefix}_${String(ORDER.indexOf(module.name) + 1).padStart(2, "0")}_${slug}.sql`;
}

/** The table `kitModuleRow` writes to, created by every schema module's file. */
const KIT_MODULES_TABLE = `
create schema if not exists better_supabase;
create table if not exists better_supabase.kit_modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.kit_modules enable row level security;
revoke all on better_supabase.kit_modules from anon, authenticated;
grant select on better_supabase.kit_modules to service_role;
`;

/** Records the module in `better_supabase.kit_modules`, which `sql upgrade` and doctor read. */
function kitModuleRow(module: SqlModule, mode: KitMode): string {
  return `insert into better_supabase.kit_modules (name, version, mode)
values (${sqlString(module.name)}, ${String(moduleVersion(module))}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`;
}

/**
 * Where a module's data statements go: `better-supabase-data/` next to the
 * schema folder. pg-delta loads every file under the schema folder, `_custom/`
 * included, and rejects a managed table that has rows afterwards.
 */
function kitDataPath(module: SqlModule, layout: KitLayout): string {
  const path = kitPath(module, layout);
  const slash = path.lastIndexOf("/");
  const parent = path.slice(0, slash).lastIndexOf("/");
  return `${parent < 0 ? "" : path.slice(0, parent + 1)}better-supabase-data${path.slice(slash)}`;
}

/** The `@bs-kit-data` line of a data file. */
const KIT_DATA_MARKER: RegExp = /^-- @bs-kit-data ([a-z0-9-]+)$/m;

/** Whether `contents` is a data file `renderKit` wrote. */
export const isKitDataFile = (contents: string): boolean =>
  KIT_DATA_MARKER.test(contents);

/**
 * The files `sql add` writes for these modules. Modules in `custom` mode
 * write nothing: the app implements their contract. A schema module's rows,
 * role settings and other statements a schema diff can't capture go to a
 * second file in `better-supabase-data/` (`kind: 'data'`), which
 * `sql data` writes into a migration.
 */
export function renderKit(
  names: readonly string[],
  layout: KitLayout = {},
): KitFile[] {
  checkKits(layout.kits);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module): KitFile[] => {
    const ctx = kitContext(module.name, layout, installed);
    if (ctx.mode === "custom") return [];
    const title = `-- better-supabase SQL kit: ${module.name}${layout.version ? ` (${layout.version})` : ""}`;
    const managed = [
      "-- Managed by `better-supabase sql add`; re-running it overwrites this file.",
      "-- Change it through `kits` in better-supabase.config.ts and the module's SQL hooks.",
    ];
    const header = [
      title,
      `-- @bs-kit ${module.name}@${String(moduleVersion(module))} ${ctx.mode}`,
      `-- ${module.description}`,
      ...managed,
    ].join("\n");
    const extra = moduleExtras(module, layout, installed);
    const wrappers = deprecationWrappers(module, ctx);
    if (module.target === "test") {
      return [
        {
          module: module.name,
          kind: "test",
          path: kitPath(module, layout),
          contents: `${header}\n\n${moduleSql(module, ctx, layout).trim()}\n${extra}${wrappers}`,
        },
      ];
    }
    const data = [
      module.data?.(ctx, layout).trim() ?? "",
      kitModuleRow(module, ctx.mode),
    ]
      .filter((part) => part !== "")
      .join("\n\n");
    const dataHeader = [
      title,
      `-- @bs-kit-data ${module.name}`,
      "-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`",
      "-- after the schema migration to put them in a migration.",
      ...managed,
    ].join("\n");
    return [
      {
        module: module.name,
        kind: "schema",
        path: kitPath(module, layout),
        contents: `${header}\n\n${moduleSql(module, ctx, layout).trim()}\n${extra}${wrappers}${KIT_MODULES_TABLE}`,
      },
      {
        module: module.name,
        kind: "data",
        path: kitDataPath(module, layout),
        contents: `${dataHeader}\n\n${data}\n`,
      },
    ];
  });
}

/** The compatibility wrappers of a module's deprecated symbols that are not removed yet. */
export function deprecationWrappers(
  module: SqlModule,
  ctx: KitContext,
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

/** An installed module, from its file's `@bs-kit` line or `kit_modules`. */
export interface InstalledKitModule {
  readonly module: string;
  readonly version: number;
}

/** What `sql upgrade` runs for one module behind the current version. */
export interface KitUpgradePlan {
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
  installed: readonly InstalledKitModule[],
  layout: KitLayout = {},
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): KitUpgradePlan[] {
  checkKits(layout.kits, modules);
  const names = installed.map((entry) => entry.module);
  return installed.flatMap((entry): KitUpgradePlan[] => {
    const module = modules[entry.module];
    if (!module) return [];
    const to = moduleVersion(module);
    if (entry.version >= to) return [];
    const ctx = createKitContext(entry.module, (name) => modules[name]?.names, {
      ...(layout.kits ? { kits: layout.kits } : {}),
      ...(layout.claims ? { claims: layout.claims } : {}),
      installed: names,
      ...(layout.permdock ? { permdockIdType: layout.permdock.idType } : {}),
    });
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

/** Every deprecated or removed kit symbol, with its module. */
export function kitDeprecations(
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): readonly (KitDeprecation & { readonly module: string })[] {
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
  layout: KitLayout = {},
): {
  readonly module: string;
  readonly schema: string;
  readonly idType: KitIdType;
  readonly functions: readonly KitContractFunction[];
}[] {
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module) => {
    const ctx = kitContext(module.name, layout, installed);
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
