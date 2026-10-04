-- CentraKit's tables for the kits better-supabase adopts, from its
-- supabase/schemas (tenant, identity, platform and automation). They live in
-- a `centrakit` schema here so the tests can create them next to the repo's
-- fixture; CentraKit itself keeps them in `public`. Columns no kit reads are
-- trimmed, and the type and subject check lists are shortened.

create extension if not exists citext with schema extensions;
create schema centrakit;

create type centrakit.scope_type as enum ('organization', 'system');

create table centrakit.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug extensions.citext not null unique,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  website text,
  logo_path text,
  disabled_at timestamptz,
  default_currency text not null default 'EUR'
);

create table centrakit.roles (
  id uuid primary key default gen_random_uuid(),
  scope centrakit.scope_type not null,
  key text not null,
  name text not null,
  system boolean not null default false,
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  created_at timestamptz not null default (now() at time zone 'utc')
);

create table centrakit.permissions (
  id uuid primary key default gen_random_uuid(),
  scope centrakit.scope_type not null,
  key text not null unique,
  name text not null,
  created_at timestamptz not null default (now() at time zone 'utc')
);

create table centrakit.role_permissions (
  role_id uuid not null references centrakit.roles(id) on delete cascade,
  permission_id uuid not null references centrakit.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table centrakit.organization_permission_overrides (
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  role_id uuid not null references centrakit.roles(id) on delete cascade,
  permission_id uuid not null references centrakit.permissions(id) on delete cascade,
  granted boolean not null,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  primary key (organization_id, role_id, permission_id)
);

create table centrakit.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references centrakit.roles(id) on delete cascade,
  created_at timestamptz not null default (now() at time zone 'utc'),
  primary key (user_id, role_id)
);

create table centrakit.organization_users (
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  role_id uuid not null references centrakit.roles(id),
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  last_used_at timestamptz not null default (now() at time zone 'utc'),
  unique (user_id, organization_id)
);

create table centrakit.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null references centrakit.roles(id),
  token text not null unique,
  prefill jsonb not null default '{}'::jsonb,
  invited_by uuid references auth.users(id) on delete set null,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  declined_at timestamptz,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc')
);

create table centrakit.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  username text not null unique
    constraint profiles_username_format check (username ~ '^[a-z][a-z0-9_]{2,29}$'),
  avatar_path text,
  first_name text,
  last_name text,
  timezone text not null default 'UTC',
  active_organization_id uuid references centrakit.organizations(id) on delete set null,
  active_team_id bigint,
  disabled_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table centrakit.contact_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text
);

create table centrakit.audit_logs (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default (now() at time zone 'utc'),
  organization_id uuid,
  organization_name_snapshot text,
  scope text not null,
  actor_kind text not null,
  actor_id uuid,
  actor_display_name text,
  actor_is_platform_admin boolean not null default false,
  event_type text not null,
  category text not null,
  outcome text not null,
  source text not null,
  target_type text,
  target_id text,
  target_display_name text,
  summary text,
  request_id text,
  correlation_id text,
  safe_metadata jsonb not null default '{}'::jsonb,
  idempotency_key text,
  created_at timestamptz not null default (now() at time zone 'utc'),
  check (scope in ('organization', 'platform')),
  check (actor_kind in ('user', 'platform_admin', 'system', 'api_key', 'integration', 'workflow', 'webhook')),
  check (category in ('authentication', 'users', 'permissions', 'billing', 'data', 'settings', 'integrations', 'security', 'system')),
  check (outcome in ('success', 'failure', 'denied', 'attempted')),
  check (source in ('saas', 'api', 'mcp', 'ai', 'workflow', 'webhook', 'database', 'system')),
  check (event_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'),
  check (jsonb_typeof(safe_metadata) = 'object'),
  check (organization_id is not null or scope = 'platform')
);

create table centrakit.audit_log_restricted_details (
  event_id uuid primary key,
  ip_address inet,
  user_agent text,
  session_id text,
  restricted_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default (now() at time zone 'utc'),
  check (jsonb_typeof(restricted_metadata) = 'object')
);

create table centrakit.workflow_events (
  id uuid primary key default gen_random_uuid(),
  -- Refactor: the outbox reads events in the order of a growing bigint.
  position bigint generated always as identity unique,
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  kind text not null,
  source text not null,
  idempotency_key text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default (now() at time zone 'utc'),
  check (source in ('domain', 'api', 'mcp', 'channel', 'system'))
);
create unique index workflow_events_idempotency_idx
  on centrakit.workflow_events (organization_id, idempotency_key)
  where idempotency_key is not null;

create table centrakit.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references centrakit.organizations(id) on delete cascade
);

create table centrakit.notification_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  subject_type text not null,
  subject_id text not null,
  subject_label text not null,
  summary text,
  action_path text,
  priority text not null default 'normal',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default (now() at time zone 'utc'),
  check (type in ('task.assigned', 'task.comment', 'approval.requested', 'invoice.paid')),
  check (subject_type in ('task', 'invoice', 'approval')),
  check (priority in ('low', 'normal', 'high', 'urgent'))
);

create table centrakit.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references centrakit.notification_events(id) on delete cascade,
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz,
  dismissed_at timestamptz,
  resolved_at timestamptz,
  delivered_at timestamptz not null default (now() at time zone 'utc'),
  created_at timestamptz not null default (now() at time zone 'utc'),
  unique (event_id, recipient_user_id),
  foreign key (recipient_user_id, organization_id)
    references centrakit.organization_users(user_id, organization_id)
    on delete cascade
);

create table centrakit.notification_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_type text not null,
  subject_id text not null,
  level text not null default 'participating',
  created_at timestamptz not null default (now() at time zone 'utc'),
  unique (organization_id, user_id, subject_type, subject_id),
  foreign key (user_id, organization_id)
    references centrakit.organization_users(user_id, organization_id)
    on delete cascade,
  check (subject_type in ('task', 'invoice', 'approval')),
  check (level in ('participating', 'all', 'ignore'))
);

create table centrakit.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  type text not null,
  channel text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default (now() at time zone 'utc'),
  unique nulls not distinct (user_id, organization_id, type, channel),
  check (type = '*' or type in ('task.assigned', 'task.comment', 'approval.requested', 'invoice.paid')),
  check (channel in ('in_app', 'email', 'push'))
);

create table centrakit.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references centrakit.notification_recipients(id) on delete cascade,
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  channel text not null,
  status text not null,
  provider text,
  provider_message_id text,
  error text,
  attempted_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default (now() at time zone 'utc'),
  unique (recipient_id, channel),
  check (channel in ('in_app', 'email', 'push')),
  check (status in ('pending', 'sent', 'failed', 'skipped'))
);

create table centrakit.webhook_destinations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  url text not null check (url ~* '^https://'),
  enabled boolean not null default true,
  event_kinds text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc')
);

create table centrakit.webhook_destination_secrets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  destination_id uuid not null references centrakit.webhook_destinations(id) on delete cascade,
  secret text not null check (length(secret) between 16 and 200),
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  unique (destination_id)
);

create table centrakit.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  destination_id uuid not null references centrakit.webhook_destinations(id) on delete cascade,
  event_id uuid references centrakit.workflow_events(id) on delete set null,
  workflow_run_id uuid references centrakit.workflow_runs(id) on delete set null,
  event_kind text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempt integer not null default 0 check (attempt >= 0),
  available_at timestamptz not null default (now() at time zone 'utc'),
  leased_until timestamptz,
  response_status integer,
  response_body text,
  duration_ms integer,
  last_error text,
  processed_at timestamptz,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  check (status in ('pending', 'processing', 'completed', 'failed', 'dead_lettered', 'canceled'))
);
-- Refactor: publish_webhook_event deduplicates on (destination, event).
create unique index webhook_deliveries_destination_event_idx
  on centrakit.webhook_deliveries (destination_id, event_id)
  where event_id is not null;

-- Refactor: CentraKit's audit writers set scope and actor_kind themselves;
-- the kit's audit_event leaves them to the table.
create function centrakit.audit_log_defaults()
returns trigger
language plpgsql
as $$
begin
  new.scope := coalesce(new.scope, case when new.organization_id is null then 'platform' else 'organization' end);
  new.actor_kind := coalesce(new.actor_kind, case when new.actor_id is null then 'system' else 'user' end);
  return new;
end;
$$;
create trigger audit_log_defaults before insert on centrakit.audit_logs
  for each row execute function centrakit.audit_log_defaults();

-- CentraKit seeds each new organization (templates, VAT rates).
create function centrakit.seed_organization(org uuid, creator uuid)
returns void
language sql
as $$
  insert into centrakit.workflow_runs (organization_id) values (org);
$$;

-- CentraKit keeps a contact profile next to each profile.
create function centrakit.create_contact_profile(profile_user uuid)
returns void
language sql
as $$
  insert into centrakit.contact_profiles (user_id, display_name)
  select p.user_id, nullif(concat_ws(' ', p.first_name, p.last_name), '')
  from centrakit.profiles p
  where p.user_id = profile_user
  on conflict (user_id) do update set display_name = excluded.display_name;
$$;

do $$
declare
  t text;
begin
  for t in select tablename from pg_tables where schemaname = 'centrakit' loop
    execute format('alter table centrakit.%I enable row level security', t);
  end loop;
end;
$$;

grant usage on schema centrakit to anon, authenticated, service_role;
grant all on all tables in schema centrakit to service_role;
grant select on all tables in schema centrakit to authenticated;
-- Members manage webhook destinations through RLS, as in CentraKit.
grant insert, update, delete on centrakit.webhook_destinations to authenticated;
