-- CentraKit's tables for the blocks better-supabase adopts, from its
-- supabase/schemas (tenant, identity, platform and automation). They live in
-- a `centrakit` schema here so the tests can create them next to the repo's
-- fixture; CentraKit itself keeps them in `public`. Columns no block reads are
-- trimmed, and the type and subject check lists are shortened. Permissions
-- belong to the authorization provider (authorization-provider.json); the
-- functions behind its templates are at the end of this file.

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

-- Organization and system roles. Which permissions a role grants is the
-- authorization provider's, compiled into centrakit.authz_role_grants().
create table centrakit.roles (
  id uuid primary key default gen_random_uuid(),
  scope centrakit.scope_type not null,
  key text not null,
  name text not null,
  system boolean not null default false,
  created_at timestamptz not null default (now() at time zone 'utc'),
  unique (scope, key)
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
  check (subject_type in ('task', 'invoice', 'approval', 'project', 'customer')),
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
  check (subject_type in ('task', 'invoice', 'approval', 'project', 'customer')),
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

create table centrakit.integration_credentials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  provider text not null,
  key text not null,
  vault_secret_id uuid,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc')
);
create unique index integration_credentials_key_idx
  on centrakit.integration_credentials (provider, key, coalesce(organization_id, '00000000-0000-0000-0000-000000000000'));

create table centrakit.inbound_webhooks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  token_digest text not null unique,
  verification text not null default 'none',
  vault_secret_id uuid,
  signature_header text,
  enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc')
);

create table centrakit.inbound_webhook_events (
  id bigint generated always as identity primary key,
  organization_id uuid references centrakit.organizations(id) on delete cascade,
  source text not null,
  external_id text not null,
  event_kind text,
  payload jsonb not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  available_at timestamptz not null default (now() at time zone 'utc'),
  locked_by text,
  locked_until timestamptz,
  last_error text,
  received_at timestamptz not null default (now() at time zone 'utc'),
  processed_at timestamptz,
  unique (source, external_id),
  check (status in ('pending', 'processing', 'processed', 'dead'))
);

-- Refactor: CentraKit's audit writers set scope and actor_kind themselves;
-- the module's audit_event leaves them to the table.
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
create function centrakit.seed_organization(organization uuid, creator uuid)
returns void
language sql
as $$
  insert into centrakit.workflow_runs (organization_id) values (organization);
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

-- Tables the eight SaaS blocks adopt. Column names match the modules' defaults.
create table centrakit.organization_number_sequences (
  tenant_id uuid not null references centrakit.organizations (id) on delete cascade,
  entity text not null,
  period text not null default '',
  last_number bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, entity, period)
);

create table centrakit.teams (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references centrakit.organizations (id) on delete cascade,
  name text not null,
  slug text not null,
  description text,
  status text not null default 'active',
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, slug)
);

create table centrakit.team_members (
  team_id uuid not null references centrakit.teams (id) on delete cascade,
  user_id uuid not null,
  tenant_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table centrakit.organization_tags (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references centrakit.organizations (id) on delete cascade,
  kind text not null,
  name text not null,
  slug text not null,
  color text,
  description text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, kind, slug)
);

create table centrakit.task_tags (
  tag_id uuid not null references centrakit.organization_tags (id) on delete cascade,
  task_id uuid not null,
  primary key (tag_id, task_id)
);

create table centrakit.status_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  from_status text,
  to_status text not null,
  actor_user_id uuid,
  reason text,
  created_at timestamptz not null default now()
);

create table centrakit.field_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  entity text not null,
  key text not null,
  label text not null,
  type text not null,
  required boolean not null default false,
  sensitive boolean not null default false,
  permission text,
  position integer not null default 0,
  unique (tenant_id, entity, key)
);

create table centrakit.field_options (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references centrakit.field_definitions (id) on delete cascade,
  value text not null,
  label text not null,
  position integer not null default 0
);

create table centrakit.field_values (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  definition_id uuid references centrakit.field_definitions (id) on delete cascade,
  subject_type text not null,
  subject_id text not null,
  value_text text,
  value_number numeric,
  value_date date,
  value_bool boolean,
  option_id uuid,
  value_json jsonb
);

create table centrakit.share_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  token_hash text not null unique,
  role text not null default 'view',
  version integer not null default 1,
  expires_at timestamptz,
  revoked_at timestamptz,
  max_uses integer,
  created_by uuid,
  leaf_id text
);

create table centrakit.subject_views (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  version integer not null default 1,
  viewer_kind text not null,
  viewer text,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  view_count integer not null default 1
);

create table centrakit.subject_user_state (
  subject_type text not null,
  subject_id text not null,
  user_id uuid not null,
  starred_at timestamptz,
  last_opened_at timestamptz,
  primary key (subject_type, subject_id, user_id)
);

create table centrakit.recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  dtstart timestamptz not null,
  tzid text not null default 'UTC',
  rrule text,
  unique (tenant_id, subject_type, subject_id)
);

create table centrakit.reminders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  user_id uuid,
  method text not null default 'notification',
  offset_minutes integer not null default 0
);

create table centrakit.reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references centrakit.reminders (id) on delete cascade,
  occurrence_at timestamptz not null,
  sent_at timestamptz,
  unique (reminder_id, occurrence_at)
);

create table centrakit.import_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  source text not null,
  status text not null default 'pending',
  mapping jsonb not null default '{}'::jsonb,
  counts jsonb not null default '{}'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now()
);

-- CentraKit's file tree: folders and files with an object path, shared with
-- users or teams. The drive module adopts both tables.
create table centrakit.file_node (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations (id) on delete cascade,
  parent_id uuid references centrakit.file_node (id) on delete cascade,
  kind text not null check (kind in ('folder', 'file')),
  name text not null,
  storage_path text,
  mime_type text,
  size_bytes bigint,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table centrakit.file_node_grant (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations (id) on delete cascade,
  file_node_id uuid not null references centrakit.file_node (id) on delete cascade,
  user_id uuid,
  team_id uuid references centrakit.teams (id) on delete cascade,
  role text not null check (role in ('viewer', 'commenter', 'editor')),
  created_at timestamptz not null default now(),
  check ((user_id is null) <> (team_id is null))
);

grant usage on schema centrakit to anon, authenticated, service_role;

-- Every table is RLS-protected; members read through the block policies and
-- CentraKit's own (990_centrakit_policies.sql).
alter table centrakit.organizations enable row level security;
alter table centrakit.roles enable row level security;
alter table centrakit.user_roles enable row level security;
alter table centrakit.organization_users enable row level security;
alter table centrakit.organization_invitations enable row level security;
alter table centrakit.profiles enable row level security;
alter table centrakit.contact_profiles enable row level security;
alter table centrakit.audit_logs enable row level security;
alter table centrakit.audit_log_restricted_details enable row level security;
alter table centrakit.workflow_events enable row level security;
alter table centrakit.workflow_runs enable row level security;
alter table centrakit.notification_events enable row level security;
alter table centrakit.notification_recipients enable row level security;
alter table centrakit.notification_subscriptions enable row level security;
alter table centrakit.notification_preferences enable row level security;
alter table centrakit.notification_deliveries enable row level security;
alter table centrakit.webhook_destinations enable row level security;
alter table centrakit.webhook_destination_secrets enable row level security;
alter table centrakit.webhook_deliveries enable row level security;
alter table centrakit.integration_credentials enable row level security;
alter table centrakit.inbound_webhooks enable row level security;
alter table centrakit.inbound_webhook_events enable row level security;
alter table centrakit.organization_number_sequences enable row level security;
alter table centrakit.teams enable row level security;
alter table centrakit.team_members enable row level security;
alter table centrakit.organization_tags enable row level security;
alter table centrakit.task_tags enable row level security;
alter table centrakit.status_history enable row level security;
alter table centrakit.field_definitions enable row level security;
alter table centrakit.field_options enable row level security;
alter table centrakit.field_values enable row level security;
alter table centrakit.share_links enable row level security;
alter table centrakit.subject_views enable row level security;
alter table centrakit.subject_user_state enable row level security;
alter table centrakit.recurrence_rules enable row level security;
alter table centrakit.reminders enable row level security;
alter table centrakit.reminder_deliveries enable row level security;
alter table centrakit.import_runs enable row level security;
alter table centrakit.file_node enable row level security;
alter table centrakit.file_node_grant enable row level security;

grant select on centrakit.organizations to authenticated;
grant all on centrakit.organizations to service_role;
grant select on centrakit.roles to authenticated;
grant all on centrakit.roles to service_role;
grant select on centrakit.user_roles to authenticated;
grant all on centrakit.user_roles to service_role;
grant select on centrakit.organization_users to authenticated;
grant all on centrakit.organization_users to service_role;
grant select on centrakit.organization_invitations to authenticated;
grant all on centrakit.organization_invitations to service_role;
grant select on centrakit.profiles to authenticated;
grant all on centrakit.profiles to service_role;
grant select on centrakit.contact_profiles to authenticated;
grant all on centrakit.contact_profiles to service_role;
grant select on centrakit.audit_logs to authenticated;
grant all on centrakit.audit_logs to service_role;
grant select on centrakit.audit_log_restricted_details to authenticated;
grant all on centrakit.audit_log_restricted_details to service_role;
grant select on centrakit.workflow_events to authenticated;
grant all on centrakit.workflow_events to service_role;
grant select on centrakit.workflow_runs to authenticated;
grant all on centrakit.workflow_runs to service_role;
grant select on centrakit.notification_events to authenticated;
grant all on centrakit.notification_events to service_role;
grant select on centrakit.notification_recipients to authenticated;
grant all on centrakit.notification_recipients to service_role;
grant select on centrakit.notification_subscriptions to authenticated;
grant all on centrakit.notification_subscriptions to service_role;
grant select on centrakit.notification_preferences to authenticated;
grant all on centrakit.notification_preferences to service_role;
grant select on centrakit.notification_deliveries to authenticated;
grant all on centrakit.notification_deliveries to service_role;
grant select on centrakit.webhook_destinations to authenticated;
grant all on centrakit.webhook_destinations to service_role;
grant select on centrakit.webhook_destination_secrets to authenticated;
grant all on centrakit.webhook_destination_secrets to service_role;
grant select on centrakit.webhook_deliveries to authenticated;
grant all on centrakit.webhook_deliveries to service_role;
grant select on centrakit.integration_credentials to authenticated;
grant all on centrakit.integration_credentials to service_role;
grant select on centrakit.inbound_webhooks to authenticated;
grant all on centrakit.inbound_webhooks to service_role;
grant select on centrakit.inbound_webhook_events to authenticated;
grant all on centrakit.inbound_webhook_events to service_role;
grant select on centrakit.organization_number_sequences to authenticated;
grant all on centrakit.organization_number_sequences to service_role;
grant select on centrakit.teams to authenticated;
grant all on centrakit.teams to service_role;
grant select on centrakit.team_members to authenticated;
grant all on centrakit.team_members to service_role;
grant select on centrakit.organization_tags to authenticated;
grant all on centrakit.organization_tags to service_role;
grant select on centrakit.task_tags to authenticated;
grant all on centrakit.task_tags to service_role;
grant select on centrakit.status_history to authenticated;
grant all on centrakit.status_history to service_role;
grant select on centrakit.field_definitions to authenticated;
grant all on centrakit.field_definitions to service_role;
grant select on centrakit.field_options to authenticated;
grant all on centrakit.field_options to service_role;
grant select on centrakit.field_values to authenticated;
grant all on centrakit.field_values to service_role;
grant select on centrakit.share_links to authenticated;
grant all on centrakit.share_links to service_role;
grant select on centrakit.subject_views to authenticated;
grant all on centrakit.subject_views to service_role;
grant select on centrakit.subject_user_state to authenticated;
grant all on centrakit.subject_user_state to service_role;
grant select on centrakit.recurrence_rules to authenticated;
grant all on centrakit.recurrence_rules to service_role;
grant select on centrakit.reminders to authenticated;
grant all on centrakit.reminders to service_role;
grant select on centrakit.reminder_deliveries to authenticated;
grant all on centrakit.reminder_deliveries to service_role;
grant select on centrakit.import_runs to authenticated;
grant all on centrakit.import_runs to service_role;
grant select on centrakit.file_node to authenticated;
grant all on centrakit.file_node to service_role;
grant select on centrakit.file_node_grant to authenticated;
grant all on centrakit.file_node_grant to service_role;
-- Members manage webhook destinations through RLS, as in CentraKit.
grant insert, update, delete on centrakit.webhook_destinations to authenticated;

-- CRM: customers (companies) and their contacts, with bigint ids as in
-- CentraKit. Deals point at them through config.subjects.
create table centrakit.customers (
  id bigint generated always as identity primary key,
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  company_name text not null,
  status text not null default 'prospect'
);
alter table centrakit.customers enable row level security;
-- The tenant column decides who sees a customer's comments and files, so
-- members can't move a customer to another organization.
grant select on centrakit.customers to authenticated;
grant insert (company_name, status), update (company_name, status)
  on centrakit.customers to authenticated;
grant all on centrakit.customers to service_role;

create table centrakit.customer_contacts (
  id bigint generated always as identity primary key,
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  customer_id bigint not null references centrakit.customers(id) on delete cascade,
  name text not null
);
alter table centrakit.customer_contacts enable row level security;
grant select, insert, update on centrakit.customer_contacts to authenticated;
grant all on centrakit.customer_contacts to service_role;

-- People: CentraKit's employees in a bigint-free shape the employees block
-- adopts. Teams have uuid ids here and kind and status are text; the
-- contracts (numeric pay) and private details stay CentraKit's own.
create table centrakit.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  kind text not null default 'employee',
  status text not null default 'active',
  first_name text not null check (char_length(trim(first_name)) between 1 and 120),
  last_name text check (last_name is null or char_length(last_name) <= 120),
  work_email text check (work_email is null or char_length(work_email) <= 320),
  job_title text check (job_title is null or char_length(job_title) <= 160),
  department_team_id uuid references centrakit.teams(id) on delete set null,
  reports_to_employee_id uuid references centrakit.employees(id) on delete set null,
  start_date date,
  end_date date,
  archived_at timestamptz,
  anonymized_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default (now() at time zone 'utc'),
  updated_at timestamptz not null default (now() at time zone 'utc'),
  check (reports_to_employee_id is null or reports_to_employee_id <> id),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create unique index employees_organization_user_idx
  on centrakit.employees (organization_id, user_id)
  where user_id is not null;
alter table centrakit.employees enable row level security;
grant select on centrakit.employees to authenticated;
grant all on centrakit.employees to service_role;

-- Projects belong to a customer; tasks belong to a project. The tenant
-- module's sameTenant entries keep every reference inside one organization.
create table centrakit.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  customer_id bigint references centrakit.customers(id) on delete set null,
  name text not null
);
alter table centrakit.projects enable row level security;
grant select on centrakit.projects to authenticated;
grant all on centrakit.projects to service_role;

-- The provider's project scope: who works on which project.
create table centrakit.project_members (
  project_id uuid not null references centrakit.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (project_id, user_id)
);
alter table centrakit.project_members enable row level security;
grant select on centrakit.project_members to authenticated;
grant all on centrakit.project_members to service_role;

create table centrakit.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations(id) on delete cascade,
  project_id uuid references centrakit.projects(id) on delete cascade,
  customer_id bigint references centrakit.customers(id) on delete set null,
  contact_id bigint references centrakit.customer_contacts(id) on delete set null,
  label_id uuid references centrakit.organization_tags(id) on delete set null,
  title text not null
);
alter table centrakit.tasks enable row level security;
grant select on centrakit.tasks to authenticated;
grant insert (project_id, customer_id, contact_id, label_id, title),
  update (project_id, customer_id, contact_id, label_id, title)
  on centrakit.tasks to authenticated;
grant all on centrakit.tasks to service_role;

-- The functions behind the provider's templates (authorization-provider.json),
-- as the provider generates them. Role grants are compiled into one function,
-- so no table holds them.
create function centrakit.authz_role_grants(role_scope centrakit.scope_type, role_key text)
returns text[]
language sql immutable set search_path = ''
as $$
  select case
    when role_scope = 'system' and role_key = 'system-support' then array['platform.users.manage', 'support.revoke']
    when role_scope <> 'organization' then '{}'::text[]
    when role_key = 'owner' then array[
      'crm.read',
      'pipelines.read',
      'deals.read',
      'deals.write',
      'work_items.read',
      'work_items.write',
      'people.read',
      'pipelines.manage',
      'deals.manage',
      'work_items.manage',
      'people.manage',
      'people.view-sensitive',
      'activity.read',
      'api_keys.manage',
      'api_keys.own',
      'attachments.manage',
      'attachments.read',
      'attachments.upload',
      'audit.revert',
      'audit.view',
      'comments.create',
      'comments.moderate',
      'comments.read',
      'custom_fields.manage',
      'custom_fields.read',
      'custom_fields.sensitive.read',
      'drive.create',
      'drive.manage',
      'drive.read',
      'imports.manage',
      'members.invite',
      'members.remove',
      'members.update_role',
      'notifications.read',
      'notifications.send',
      'number_sequences.assign',
      'organization.delete',
      'organization.export',
      'organization.transfer_ownership',
      'organization.update',
      'reminders.manage',
      'reminders.read',
      'settings.read',
      'settings.update',
      'share_links.create',
      'share_links.read',
      'tags.manage',
      'tags.read',
      'teams.manage',
      'teams.read',
      'webhook.manage',
      'webhook.view'
    ]
    when role_key = 'admin' then array[
      'crm.read',
      'pipelines.read',
      'deals.read',
      'deals.write',
      'work_items.read',
      'work_items.write',
      'people.read',
      'pipelines.manage',
      'deals.manage',
      'work_items.manage',
      'people.manage',
      'people.view-sensitive',
      'activity.read',
      'api_keys.manage',
      'api_keys.own',
      'attachments.manage',
      'attachments.read',
      'attachments.upload',
      'audit.revert',
      'audit.view',
      'comments.create',
      'comments.moderate',
      'comments.read',
      'custom_fields.manage',
      'custom_fields.read',
      'custom_fields.sensitive.read',
      'drive.create',
      'drive.manage',
      'drive.read',
      'imports.manage',
      'members.invite',
      'members.remove',
      'members.update_role',
      'notifications.read',
      'notifications.send',
      'number_sequences.assign',
      'organization.export',
      'organization.update',
      'reminders.manage',
      'reminders.read',
      'settings.read',
      'settings.update',
      'share_links.create',
      'share_links.read',
      'tags.manage',
      'tags.read',
      'teams.manage',
      'teams.read',
      'webhook.manage',
      'webhook.view'
    ]
    when role_key = 'member' then array[
      'crm.read',
      'pipelines.read',
      'deals.read',
      'deals.write',
      'work_items.read',
      'work_items.write',
      'people.read',
      'activity.read',
      'api_keys.own',
      'attachments.read',
      'attachments.upload',
      'comments.create',
      'comments.read',
      'custom_fields.read',
      'drive.create',
      'drive.read',
      'notifications.read',
      'notifications.send',
      'reminders.read',
      'settings.read',
      'share_links.read',
      'tags.read',
      'teams.read'
    ]
    else '{}'::text[]
  end
$$;

-- The rank a role may assign up to: owners assign every role, admins admins
-- and members, members nobody.
create function centrakit.authz_role_rank(role_key text)
returns integer
language sql immutable set search_path = ''
as $$
  select case role_key when 'owner' then 3 when 'admin' then 2 when 'member' then 1 else 0 end
$$;

create function centrakit.authz_organization_ids_with_for(p_user uuid, p_permission text)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select ou.organization_id
  from centrakit.organization_users ou
  join centrakit.roles r on r.id = ou.role_id
  where ou.user_id = p_user
    and p_permission = any(centrakit.authz_role_grants(r.scope, r.key))
$$;

create function centrakit.authz_organization_ids_with(p_permission text)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select centrakit.authz_organization_ids_with_for((select auth.uid()), p_permission)
$$;

-- A project member may read and comment on its project's records; an
-- organization member with the key holds it on every project there.
create function centrakit.authz_project_ids_with_for(p_user uuid, p_permission text)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select pm.project_id
  from centrakit.project_members pm
  where pm.user_id = p_user
    and p_permission in ('comments.read', 'comments.create', 'attachments.read')
  union
  select p.id
  from centrakit.projects p
  where p.organization_id in (select centrakit.authz_organization_ids_with_for(p_user, p_permission))
$$;

create function centrakit.authz_project_ids_with(p_permission text)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select centrakit.authz_project_ids_with_for((select auth.uid()), p_permission)
$$;

create function centrakit.authz_is_platform_for(p_user uuid, p_permission text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from centrakit.user_roles ur
    join centrakit.roles r on r.id = ur.role_id
    where ur.user_id = p_user
      and p_permission = any(centrakit.authz_role_grants(r.scope, r.key))
  )
$$;

create function centrakit.authz_is_platform(p_permission text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select centrakit.authz_is_platform_for((select auth.uid()), p_permission)
$$;

create function centrakit.authz_organization_member_ids_for(p_user uuid)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select ou.organization_id from centrakit.organization_users ou where ou.user_id = p_user
$$;

create function centrakit.authz_organization_member_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select centrakit.authz_organization_member_ids_for((select auth.uid()))
$$;

create function centrakit.authz_permissions_for(p_user uuid, p_organization uuid)
returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct g.key order by g.key), '{}'::text[])
  from centrakit.organization_users ou
  join centrakit.roles r on r.id = ou.role_id
  cross join lateral unnest(centrakit.authz_role_grants(r.scope, r.key)) as g(key)
  where ou.user_id = p_user and ou.organization_id = p_organization
$$;

create function centrakit.authz_can_assign_for(p_user uuid, p_organization uuid, p_role text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from centrakit.organization_users ou
    join centrakit.roles r on r.id = ou.role_id
    where ou.user_id = p_user
      and ou.organization_id = p_organization
      and 'members.update_role' = any(centrakit.authz_role_grants(r.scope, r.key))
      and centrakit.authz_role_rank(r.key) >= centrakit.authz_role_rank(p_role)
      and centrakit.authz_role_rank(p_role) > 0
  )
$$;

create function centrakit.authz_can_assign(p_organization uuid, p_role text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select centrakit.authz_can_assign_for((select auth.uid()), p_organization, p_role)
$$;

create function centrakit.authz_organization_users_with(p_permission text, p_organization uuid)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select ou.user_id
  from centrakit.organization_users ou
  join centrakit.roles r on r.id = ou.role_id
  where ou.organization_id = p_organization
    and p_permission = any(centrakit.authz_role_grants(r.scope, r.key))
$$;

-- Support sessions honour read_only; an agent writes unless it is read-only;
-- impersonation and unknown kinds never write.
create function centrakit.authz_actor_may_write()
returns boolean
language sql stable set search_path = ''
as $$
  select case
    when auth.jwt() is null or auth.jwt() -> 'act' is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    else false
  end
$$;

revoke execute on function
  centrakit.authz_organization_ids_with_for(uuid, text),
  centrakit.authz_project_ids_with_for(uuid, text),
  centrakit.authz_is_platform_for(uuid, text),
  centrakit.authz_organization_member_ids_for(uuid),
  centrakit.authz_permissions_for(uuid, uuid),
  centrakit.authz_can_assign_for(uuid, uuid, text),
  centrakit.authz_organization_users_with(text, uuid)
  from public, anon, authenticated;
grant execute on function
  centrakit.authz_organization_ids_with_for(uuid, text),
  centrakit.authz_project_ids_with_for(uuid, text),
  centrakit.authz_is_platform_for(uuid, text),
  centrakit.authz_organization_member_ids_for(uuid),
  centrakit.authz_permissions_for(uuid, uuid),
  centrakit.authz_can_assign_for(uuid, uuid, text),
  centrakit.authz_organization_users_with(text, uuid)
  to service_role, supabase_auth_admin;

-- The record types comments attach to, as @bsb subject tags.
comment on table centrakit.tasks is '@bsb subject type=task id-type=uuid';
comment on table centrakit.projects is '@bsb subject type=project id-type=uuid scope=project';
comment on table centrakit.customers is '@bsb subject type=customer id-type=bigint';
