import type { ClaimsMeta } from '../schema/types.ts';

import { DEFAULT_CLAIMS } from '../core/claims.ts';
import { sqlIdent, sqlString } from '../core/template.ts';

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
  /** `schema` files go with your schemas; `test` files go to `supabase/tests`. */
  readonly target: 'schema' | 'test';
  /** The module with the default claim names. */
  readonly sql: string;
  /** The module for configured claim names (`config.claims`), when it reads claims. */
  readonly render?: (claims: ClaimsMeta) => string;
}

function jwtClaim(name: string): string {
  return `coalesce(auth.jwt() ->> ${sqlString(name)}, auth.jwt() -> 'app_metadata' ->> ${sqlString(name)})`;
}

const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

const UPDATED_AT: SqlModule = {
  name: 'updated-at',
  title: 'updated_at triggers',
  description: 'Keeps an updated_at column current on every update.',
  requires: [],
  target: 'schema',
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

-- select better_supabase.track_updated_at('public.customers');
create or replace function better_supabase.track_updated_at(
  target regclass,
  column_name text default 'updated_at'
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_updated_at on %s', target);
  execute format(
    'create trigger bs_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$$;`,
};

const ACTOR: SqlModule = {
  name: 'actor',
  title: 'Actor stamping',
  description:
    'Sets created_by on insert and updated_by on update from auth.uid(). Service writes keep the values they send.',
  requires: [],
  target: 'schema',
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
  if tg_op = 'INSERT' and tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], actor));
  end if;
  if tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim), null otherwise.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[2], auth.jwt() -> 'act' ->> 'sub'));
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
$$;`,
};

const AUDIT: SqlModule = {
  name: 'audit',
  title: 'Audit log',
  description:
    'Records inserts, updates and deletes with the actor and changed columns, for tables you register.',
  requires: [],
  target: 'schema',
  sql: `${SCHEMA}

create table if not exists better_supabase.audited_tables (
  target regclass primary key,
  ignore text[] not null default '{}'
);

create table if not exists better_supabase.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id text,
  op text not null check (op in ('insert', 'update', 'delete')),
  old_record jsonb,
  new_record jsonb,
  changed text[],
  actor_id uuid,
  actor_role text,
  org_id uuid,
  at timestamptz not null default now()
);
-- Set when an admin acted as the user (the act claim).
alter table better_supabase.audit_log add column if not exists impersonated_by uuid;
alter table better_supabase.audit_log add column if not exists impersonation_reason text;
create index if not exists audit_log_record_idx on better_supabase.audit_log (table_name, record_id, at desc);
create index if not exists audit_log_org_idx on better_supabase.audit_log (org_id, at desc);

alter table better_supabase.audited_tables enable row level security;
alter table better_supabase.audit_log enable row level security;
revoke all on better_supabase.audited_tables, better_supabase.audit_log from anon, authenticated;
grant select on better_supabase.audit_log to service_role;

create or replace function better_supabase.audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ignored text[];
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
begin
  select a.ignore into ignored
  from better_supabase.audited_tables a
  where a.target = tg_relid::regclass;
  ignored := coalesce(ignored, '{}');
  old_row := old_row - ignored;
  new_row := new_row - ignored;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  insert into better_supabase.audit_log
    (table_name, record_id, op, old_record, new_record, changed, actor_id, actor_role, org_id,
     impersonated_by, impersonation_reason)
  values (
    tg_table_schema || '.' || tg_table_name,
    row_data ->> 'id',
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    auth.uid(),
    coalesce(auth.jwt() ->> 'role', current_user),
    case
      when row_data ->> 'organization_id' ~ '^[0-9a-f-]{36}$'
        then (row_data ->> 'organization_id')::uuid
    end,
    case
      when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$'
        then (auth.jwt() -> 'act' ->> 'sub')::uuid
    end,
    auth.jwt() -> 'act' ->> 'reason'
  );
  return null;
end;
$$;

-- select better_supabase.audit('public.customers', ignore => '{updated_at}');
create or replace function better_supabase.audit(target regclass, ignore text[] default '{}')
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into better_supabase.audited_tables as a (target, ignore) values (audit.target, audit.ignore)
  on conflict on constraint audited_tables_pkey do update set ignore = excluded.ignore;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_trigger()',
    target
  );
end;
$$;

create or replace function better_supabase.unaudit(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_audit on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$$;`,
};

const tenantSql = (claims: ClaimsMeta): string => `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

create table if not exists better_supabase.memberships (
  org_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index if not exists memberships_user_idx on better_supabase.memberships (user_id);

alter table better_supabase.memberships enable row level security;
grant select on better_supabase.memberships to authenticated;
grant all on better_supabase.memberships to service_role;

-- The tenant of the current request: the top-level \`${claims.tenant}\` claim
-- (custom access token hook) or \`app_metadata.${claims.tenant}\` (Auth admin API).
-- Never user_metadata: users can write it.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(${jwtClaim(claims.tenant)}, '')::uuid
$$;

-- using ((select better_supabase.has_org_role(organization_id, '{owner,admin}')))
create or replace function better_supabase.has_org_role(org uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from better_supabase.memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and (roles is null or m.role = any (roles))
  )
$$;

drop policy if exists bs_memberships_read on better_supabase.memberships;
create policy bs_memberships_read on better_supabase.memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or (select better_supabase.has_org_role(org_id)));

-- The memberships claim in PermDock's shape: [{ scope, id, roles }]. With
-- PermDock, \`permdock supabase hook generate\` writes the hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', ${sqlString(claims.scope)},
      'id', m.org_id,
      'roles', jsonb_build_array(m.role)
    ) order by m.created_at, m.org_id), '[]'::jsonb)
  from better_supabase.memberships m
  where m.user_id = membership_claims.user_id
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;`;

const TENANT: SqlModule = {
  name: 'tenant',
  title: 'Tenant memberships and permission helper',
  description:
    'Memberships with roles, has_org_role() for RLS policies and membership_claims() for the access token hook. A template: edit the roles to fit your app.',
  requires: [],
  target: 'schema',
  sql: tenantSql(DEFAULT_CLAIMS),
  render: tenantSql,
};

const MFA: SqlModule = {
  name: 'mfa',
  title: 'MFA enforcement',
  description:
    'mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).',
  requires: [],
  target: 'schema',
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

const entitlementsSql = (claims: ClaimsMeta): string => `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

-- Lookup keys of the tenant's active entitlements, from the Stripe Sync
-- Engine's stripe.active_entitlements. Empty before the engine is installed.
create or replace function better_supabase.tenant_entitlements(tenant uuid)
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

revoke execute on function better_supabase.tenant_entitlements(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(uuid) to service_role, supabase_auth_admin;

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
$$;

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;

const ENTITLEMENTS: SqlModule = {
  name: 'entitlements',
  title: 'Stripe entitlements',
  description:
    'Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() for RLS.',
  requires: ['tenant'],
  target: 'schema',
  sql: entitlementsSql(DEFAULT_CLAIMS),
  render: entitlementsSql,
};

const INVITATIONS: SqlModule = {
  name: 'invitations',
  title: 'Invitations',
  description:
    'Owners and admins invite by email; the invitee accepts with a one-time token and becomes a member.',
  requires: ['tenant'],
  target: 'schema',
  sql: `${SCHEMA}

create table if not exists better_supabase.invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  email text not null,
  role text not null default 'member',
  token_hash text not null unique,
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users (id) on delete set null
);
create unique index if not exists invitations_open_idx
  on better_supabase.invitations (org_id, lower(email)) where accepted_at is null;
create index if not exists invitations_invited_by_idx
  on better_supabase.invitations (invited_by);
create index if not exists invitations_accepted_by_idx
  on better_supabase.invitations (accepted_by);

alter table better_supabase.invitations enable row level security;
revoke all on better_supabase.invitations from anon, authenticated;
grant select on better_supabase.invitations to authenticated;
grant all on better_supabase.invitations to service_role;

drop policy if exists bs_invitations_read on better_supabase.invitations;
create policy bs_invitations_read on better_supabase.invitations
  for select to authenticated
  using ((select better_supabase.has_org_role(org_id, '{owner,admin}')));

-- Returns the token to send; only its hash is stored.
create or replace function better_supabase.create_invitation(
  org uuid,
  invitee_email text,
  invitee_role text default 'member',
  valid_for interval default '7 days'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  if auth.role() <> 'service_role' and not better_supabase.has_org_role(org, '{owner,admin}') then
    raise exception 'Only owners and admins can invite' using errcode = '42501';
  end if;
  delete from better_supabase.invitations i
  where i.org_id = org and lower(i.email) = lower(invitee_email) and i.accepted_at is null;
  insert into better_supabase.invitations (org_id, email, role, token_hash, invited_by, expires_at)
  values (
    org,
    invitee_email,
    invitee_role,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    auth.uid(),
    now() + valid_for
  );
  return token;
end;
$$;

create or replace function better_supabase.accept_invitation(token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite better_supabase.invitations;
begin
  if auth.uid() is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501';
  end if;
  select * into invite
  from better_supabase.invitations i
  where i.token_hash = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite.id is null or invite.accepted_at is not null or invite.expires_at < now() then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if lower(invite.email) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  insert into better_supabase.memberships (org_id, user_id, role)
  values (invite.org_id, auth.uid(), invite.role)
  on conflict (org_id, user_id) do update set role = excluded.role;
  update better_supabase.invitations
  set accepted_at = now(), accepted_by = auth.uid()
  where id = invite.id;
  return invite.org_id;
end;
$$;

revoke execute on function better_supabase.create_invitation(uuid, text, text, interval) from public, anon;
revoke execute on function better_supabase.accept_invitation(text) from public, anon;
grant execute on function better_supabase.create_invitation(uuid, text, text, interval) to authenticated, service_role;
grant execute on function better_supabase.accept_invitation(text) to authenticated;`,
};

const RESERVED_SLUGS: SqlModule = {
  name: 'reserved-slugs',
  title: 'Reserved slugs',
  description:
    'A slug format check and a list of reserved words (admin, api, www, ...), enforced by a trigger.',
  requires: [],
  target: 'schema',
  sql: `${SCHEMA}

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
grant select on better_supabase.reserved_slugs to anon, authenticated;
drop policy if exists bs_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bs_reserved_slugs_read on better_supabase.reserved_slugs for select using (true);

insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;

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
$$;`,
};

const JOBS: SqlModule = {
  name: 'jobs',
  title: 'Job queue',
  description:
    'Typed jobs on Supabase Queues (pgmq): leases, retries with backoff, dead letters, deduplication keys, and pg_cron schedules.',
  requires: [],
  target: 'schema',
  sql: `${SCHEMA}

-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).
drop function if exists better_supabase.enqueue_job(text, jsonb, timestamptz, integer, text, integer);
drop function if exists better_supabase.claim_jobs(text, text, integer, interval);
drop function if exists better_supabase.complete_job(bigint, text);
drop function if exists better_supabase.fail_job(bigint, text, text, interval);
drop function if exists better_supabase.extend_job_lease(bigint, text, interval);

-- Queue names: lowercase letters, digits and underscores (pgmq's rule).
create or replace function better_supabase.ensure_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from pgmq.list_queues() q where q.queue_name = queue) then
    perform pgmq.create(queue);
  end if;
end;
$$;

-- While a message with dedupe_key is waiting or running, enqueueing again returns its id.
create or replace function better_supabase.enqueue_job(
  queue text,
  payload jsonb default '{}',
  delay integer default 0,
  max_attempts integer default 5,
  dedupe_key text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing bigint;
begin
  perform better_supabase.ensure_job_queue(queue);
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    execute format('select msg_id from pgmq.%I where message ->> ''dedupe_key'' = $1 limit 1', 'q_' || queue)
      into existing using dedupe_key;
    if existing is not null then
      return existing;
    end if;
  end if;
  return (
    select pgmq.send(
      queue,
      jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
        || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
      greatest(delay, 0)
    )
  );
end;
$$;

create or replace function better_supabase.claim_jobs(queue text, lease integer default 300, batch integer default 1)
returns table (id bigint, attempts integer, enqueued_at timestamptz, visible_until timestamptz, message jsonb)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.ensure_job_queue(queue);
  return query
    select r.msg_id, r.read_ct, r.enqueued_at, r.vt, r.message
    from pgmq.read(queue, lease, batch) r;
end;
$$;

-- Each claim bumps read_ct, so a stale worker (its lease expired and another
-- worker claimed the message) no longer matches and gets false / null.
create or replace function better_supabase.complete_job(queue text, job_id bigint, attempt integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  return pgmq.archive(queue, job_id);
end;
$$;

-- Retries with exponential backoff (10s, 20s, 40s, ... at most an hour) until
-- max_attempts, then archives the message with dead = true.
create or replace function better_supabase.fail_job(
  queue text,
  job_id bigint,
  attempt integer,
  error text,
  retry_in integer default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg jsonb;
begin
  execute format('select message from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into msg using job_id, attempt;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text, ''dead'', true) where msg_id = $1', 'q_' || queue)
      using job_id, left(error, 4000);
    perform pgmq.archive(queue, job_id);
    return 'dead';
  end if;
  execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text), vt = clock_timestamp() + make_interval(secs => $3) where msg_id = $1', 'q_' || queue)
    using job_id, left(error, 4000), coalesce(retry_in, least(3600, 10 * power(2, attempt - 1)::integer));
  return 'queued';
end;
$$;

create or replace function better_supabase.extend_job_lease(queue text, job_id bigint, attempt integer, lease integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  hit bigint;
begin
  execute format('update pgmq.%I set vt = clock_timestamp() + make_interval(secs => $3) where msg_id = $1 and read_ct = $2 returning msg_id', 'q_' || queue)
    into hit using job_id, attempt, lease;
  return hit is not null;
end;
$$;

-- Recurring jobs with pg_cron: select better_supabase.schedule_job('nightly-digest', '0 3 * * *', 'emails', '{"kind": "digest"}');
create or replace function better_supabase.schedule_job(job_name text, schedule text, queue text, payload jsonb default '{}')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regnamespace('cron') is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog';
  end if;
  perform better_supabase.ensure_job_queue(queue);
  return cron.schedule(job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text));
end;
$$;

create or replace function better_supabase.unschedule_job(job_name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regnamespace('cron') is null then
    return false;
  end if;
  return cron.unschedule(job_name);
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'ensure_job_queue(text)',
    'enqueue_job(text, jsonb, integer, integer, text)',
    'claim_jobs(text, integer, integer)',
    'complete_job(text, bigint, integer)',
    'fail_job(text, bigint, integer, text, integer)',
    'extend_job_lease(text, bigint, integer, integer)',
    'schedule_job(text, text, text, jsonb)',
    'unschedule_job(text)'
  ] loop
    execute format('revoke execute on function better_supabase.%s from public, anon, authenticated', fn);
    execute format('grant execute on function better_supabase.%s to service_role', fn);
  end loop;
end;
$$;`,
};

const IDEMPOTENCY: SqlModule = {
  name: 'idempotency',
  title: 'Idempotency keys',
  description:
    'Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.',
  requires: [],
  target: 'schema',
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
  name: 'webhook-inbox',
  title: 'Webhook inbox',
  description:
    'Stores verified webhooks once per message id, then processes them with leases and retries.',
  requires: [],
  target: 'schema',
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

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'receive_webhook(text, text, text, jsonb, jsonb)',
    'claim_webhooks(text, text, integer, interval)',
    'complete_webhook(bigint, text)',
    'fail_webhook(bigint, text, text, interval)'
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
-- A tenant column the table lacks is ignored: the table broadcasts on one topic.
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
    tenant_column := null;
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
drop policy if exists bs_realtime_tables_receive on realtime.messages;
create policy bs_realtime_tables_receive on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'bs:t:%'
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
  name: 'realtime-tables',
  title: 'Realtime table changes',
  description:
    'Broadcasts a change signal (no row data) once per statement on bs:t:<schema>.<table>[:<tenant>] for live queries.',
  requires: [],
  target: 'schema',
  sql: realtimeTablesSql(DEFAULT_CLAIMS),
  render: realtimeTablesSql,
};

const JSONB_SCHEMAS: SqlModule = {
  name: 'jsonb-schemas',
  title: 'JSON Schema checks for jsonb',
  description:
    'pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types.',
  requires: [],
  target: 'schema',
  sql: `create extension if not exists pg_jsonschema with schema extensions;`,
};

const PGTAP: SqlModule = {
  name: 'pgtap',
  title: 'pgTAP helpers',
  description:
    'tests.create_user, tests.authenticate_as and tests.rls_enabled for `supabase test db`. Written to supabase/tests, never to your schema.',
  requires: [],
  target: 'test',
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

select extensions.plan(1);
select extensions.pass('better-supabase test helpers installed');
select * from extensions.finish();`,
};

const GRANTS: SqlModule = {
  name: 'grants',
  title: 'Data API grants',
  description:
    'Grants the tables in the `expose` config to anon and authenticated. Supabase no longer grants new tables to the Data API roles automatically.',
  requires: [],
  target: 'schema',
  sql: `-- List tables in \`expose\` (better-supabase.config.ts); \`sql sync\` rewrites the grants below.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.`,
};

const READ_SETS: SqlModule = {
  name: 'read-sets',
  title: 'Read sets',
  description:
    'One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.',
  requires: [],
  target: 'schema',
  sql: `-- Functions for the read sets in \`readSets\` (better-supabase.config.ts); \`gen\` and \`sql sync\` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.`,
};

const RATE_LIMIT: SqlModule = {
  name: 'rate-limit',
  title: 'Write rate limits',
  description:
    'Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.',
  requires: [],
  target: 'schema',
  sql: `${SCHEMA}

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by their first x-forwarded-for hop.
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
      'ip:' || coalesce(nullif(trim(split_part(headers ->> 'x-forwarded-for', ',', 1)), ''), 'unknown')
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

-- supabase db diff doesn't capture role settings: put this block in a
-- migration too. It keeps an existing pre-request function; chain from it.
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
notify pgrst, 'reload config';`,
};

const VECTOR_SEARCH: SqlModule = {
  name: 'vector-search',
  title: 'Vector search',
  description:
    'search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.',
  requires: [],
  target: 'schema',
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
      AUDIT,
      TENANT,
      INVITATIONS,
      RESERVED_SLUGS,
      JOBS,
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
    ].map((module) => [module.name, module]),
  );

const ORDER = Object.keys(SQL_MODULES);

/** The modules to install for `names`, dependencies first. Throws on an unknown name. */
export function resolveModules(names: readonly string[]): SqlModule[] {
  const ordered: SqlModule[] = [];
  const visit = (name: string, from?: string): void => {
    const module = SQL_MODULES[name];
    if (!module) {
      throw new TypeError(
        `Unknown SQL kit module "${name}"${from ? ` (required by ${from})` : ''}. Available: ${Object.keys(SQL_MODULES).join(', ')}`,
      );
    }
    if (ordered.includes(module)) return;
    for (const dependency of module.requires) visit(dependency, name);
    ordered.push(module);
  };
  for (const name of names) visit(name);
  return ordered.sort((a, b) => ORDER.indexOf(a.name) - ORDER.indexOf(b.name));
}

export interface KitFile {
  readonly module: string;
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
  /** Tenant column passed to `track_realtime`; tables without it broadcast unscoped. */
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
}

/** An embedding column `db.$search` can query. */
export interface VectorSearchTable {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly distance: 'cosine' | 'l2' | 'inner_product';
}

const DISTANCE_OPERATORS: Readonly<
  Record<VectorSearchTable['distance'], string>
> = {
  cosine: '<=>',
  l2: '<->',
  inner_product: '<#>',
};

function vectorSearchFunctions(tables: readonly VectorSearchTable[]): string {
  if (tables.length === 0) return '';
  const functions = tables.map((entry) => {
    const [schema, table] = entry.table.includes('.')
      ? entry.table.split('.', 2)
      : ['public', entry.table];
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
  return `\n-- config.vectorSearch\n${functions.join('\n\n')}\n`;
}

/** The table holding each tenant's Stripe customer id. */
export interface EntitlementsSource {
  /** `table` or `schema.table`. */
  readonly table: string;
  /** Column with the Stripe customer id (`cus_...`). */
  readonly column: string;
  /** Column with the tenant id. */
  readonly key: string;
}

/** Privileges one Data API role gets on a table or view. */
export interface TableGrant {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly role: 'anon' | 'authenticated';
  readonly privileges: readonly ('select' | 'insert' | 'update' | 'delete')[];
}

function tableGrants(grants: readonly TableGrant[]): string {
  const statements = grants
    .filter((grant) => grant.privileges.length > 0)
    .map((grant) => {
      const [schema, table] = grant.table.includes('.')
        ? grant.table.split('.', 2)
        : ['public', grant.table];
      return `grant ${grant.privileges.join(', ')} on table ${sqlIdent(schema!)}.${sqlIdent(table!)} to ${grant.role};`;
    });
  if (statements.length === 0) return '';
  return `\n-- config.expose\n${statements.join('\n')}\n`;
}

/** A jsonb column and the JSON Schema its values must match. */
export interface JsonSchemaCheck {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly schema: Readonly<Record<string, unknown>>;
}

function jsonSchemaChecks(checks: readonly JsonSchemaCheck[]): string {
  if (checks.length === 0) return '';
  const statements = checks.map((check) => {
    const [schema, table] = check.table.includes('.')
      ? check.table.split('.', 2)
      : ['public', check.table];
    const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
    const name = sqlIdent(`bs_json_${check.column}`.slice(0, 63));
    return [
      `alter table ${target} drop constraint if exists ${name};`,
      `alter table ${target} add constraint ${name}`,
      `  check (extensions.jsonb_matches_schema(${sqlString(JSON.stringify(check.schema))}::json, ${sqlIdent(check.column)}));`,
    ].join('\n');
  });
  return `\n-- config.json schemas\n${statements.join('\n\n')}\n`;
}

function entitlementsSource(source: EntitlementsSource): string {
  const [schema, table] = source.table.includes('.')
    ? source.table.split('.', 2)
    : ['public', source.table];
  const target = `${sqlIdent(schema!)}.${sqlIdent(table!)}`;
  const key = `t.${sqlIdent(source.key)}`;
  const column = `t.${sqlIdent(source.column)}`;
  const definer =
    "language sql\nstable\nsecurity definer\nset search_path = ''";
  return `
-- config.entitlements: ${source.table}.${source.column}
create or replace function better_supabase.tenant_stripe_customer(tenant uuid)
returns text
${definer}
as $$
  select ${column} from ${target} t where ${key} = tenant
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof uuid
${definer}
as $$
  select ${key} from ${target} t where ${column} = customer
$$;

-- Users whose features claim carries the customer's entitlements, for
-- invalidating their sessions after entitlements.active_entitlement_summary.updated.
create or replace function better_supabase.entitlement_members(customer text)
returns setof uuid
${definer}
as $$
  select distinct m.user_id
  from better_supabase.memberships m
  where m.org_id in (select better_supabase.stripe_customer_tenants(customer))
$$;

revoke execute on function better_supabase.tenant_stripe_customer(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.stripe_customer_tenants(text) from public, anon, authenticated;
revoke execute on function better_supabase.entitlement_members(text) from public, anon, authenticated;
grant execute on function better_supabase.entitlement_members(text) to service_role;
`;
}

function moduleExtras(module: SqlModule, layout: KitLayout): string {
  if (module.name === 'entitlements')
    return entitlementsSource(
      layout.entitlements ?? {
        table: 'organizations',
        column: 'stripe_customer_id',
        key: 'id',
      },
    );
  if (module.name === 'realtime-tables')
    return realtimeRegistrations(
      layout.realtimeTables ?? [],
      layout.tenantColumn,
    );
  if (module.name === 'jsonb-schemas')
    return jsonSchemaChecks(layout.jsonSchemas ?? []);
  if (module.name === 'grants') return tableGrants(layout.grants ?? []);
  if (module.name === 'vector-search')
    return vectorSearchFunctions(layout.vectorSearch ?? []);
  if (module.name === 'read-sets') {
    const sets = layout.readSets ?? [];
    if (sets.length === 0) return '';
    return `\n-- config.readSets\n${sets.map((set) => `-- ${set.name}\n${set.sql}`).join('\n\n')}\n`;
  }
  return '';
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
      '$1\n',
    );
  return strip(current) === strip(expected);
}

/** The files `sql add` writes for these modules. */
export function renderKit(
  names: readonly string[],
  layout: KitLayout = {},
): KitFile[] {
  const dir = (layout.dir ?? 'supabase/schemas').replace(/\/$/, '');
  const prefix = layout.prefix ?? '900_better_supabase';
  const testsDir = (layout.testsDir ?? 'supabase/tests').replace(/\/$/, '');
  return resolveModules(names).map((module) => {
    const slug = module.name.replace(/-/g, '_');
    const path =
      module.target === 'test'
        ? `${testsDir}/000_better_supabase_${slug}.test.sql`
        : `${dir}/${prefix}_${String(ORDER.indexOf(module.name) + 1).padStart(2, '0')}_${slug}.sql`;
    const header = [
      `-- better-supabase SQL kit: ${module.name}${layout.version ? ` (${layout.version})` : ''}`,
      `-- ${module.description}`,
      '-- Managed by `better-supabase sql add`; re-running it overwrites this file.',
    ].join('\n');
    const extra = moduleExtras(module, layout);
    const sql =
      module.render && layout.claims
        ? module.render(layout.claims)
        : module.sql;
    return {
      module: module.name,
      path,
      contents: `${header}\n\n${sql.trim()}\n${extra}`,
    };
  });
}

function realtimeRegistrations(
  tables: readonly string[],
  tenantColumn: string | undefined,
): string {
  if (tables.length === 0) return '';
  const tenant = tenantColumn ? `, ${sqlString(tenantColumn)}` : '';
  const lines = tables.map((table) => {
    const target = table.includes('.') ? table : `public.${table}`;
    return `select better_supabase.track_realtime(${sqlString(target)}${tenant});`;
  });
  return `\n-- config.realtime.tables\n${lines.join('\n')}\n`;
}
