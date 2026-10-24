-- better-supabase module: sessions
-- @bsb-block sessions@1 managed
-- @bsb-hash sha256:169c5069000e95f066e83e5788f6c33a81bf4a0cea5651e2983a0c5f93e55d7d
-- session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.
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

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));

-- blocks['sessions'].options.policies: every table in the schema files,
-- except blocks['sessions'].options.exclude. `upgrade` rewrites these.
drop policy if exists bsb_session_active on "centrakit"."organizations";
create policy bsb_session_active on "centrakit"."organizations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."user_roles";
create policy bsb_session_active on "centrakit"."user_roles" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."organization_users";
create policy bsb_session_active on "centrakit"."organization_users" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."organization_invitations";
create policy bsb_session_active on "centrakit"."organization_invitations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."profiles";
create policy bsb_session_active on "centrakit"."profiles" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."contact_profiles";
create policy bsb_session_active on "centrakit"."contact_profiles" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."audit_logs";
create policy bsb_session_active on "centrakit"."audit_logs" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."audit_log_restricted_details";
create policy bsb_session_active on "centrakit"."audit_log_restricted_details" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."workflow_events";
create policy bsb_session_active on "centrakit"."workflow_events" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."workflow_runs";
create policy bsb_session_active on "centrakit"."workflow_runs" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."notification_events";
create policy bsb_session_active on "centrakit"."notification_events" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."notification_recipients";
create policy bsb_session_active on "centrakit"."notification_recipients" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."notification_subscriptions";
create policy bsb_session_active on "centrakit"."notification_subscriptions" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."notification_preferences";
create policy bsb_session_active on "centrakit"."notification_preferences" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."notification_deliveries";
create policy bsb_session_active on "centrakit"."notification_deliveries" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."webhook_destinations";
create policy bsb_session_active on "centrakit"."webhook_destinations" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."webhook_destination_secrets";
create policy bsb_session_active on "centrakit"."webhook_destination_secrets" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."webhook_deliveries";
create policy bsb_session_active on "centrakit"."webhook_deliveries" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."integration_credentials";
create policy bsb_session_active on "centrakit"."integration_credentials" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."inbound_webhooks";
create policy bsb_session_active on "centrakit"."inbound_webhooks" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."inbound_webhook_events";
create policy bsb_session_active on "centrakit"."inbound_webhook_events" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."organization_number_sequences";
create policy bsb_session_active on "centrakit"."organization_number_sequences" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."teams";
create policy bsb_session_active on "centrakit"."teams" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."team_members";
create policy bsb_session_active on "centrakit"."team_members" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."organization_tags";
create policy bsb_session_active on "centrakit"."organization_tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."task_tags";
create policy bsb_session_active on "centrakit"."task_tags" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."status_history";
create policy bsb_session_active on "centrakit"."status_history" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."field_definitions";
create policy bsb_session_active on "centrakit"."field_definitions" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."field_options";
create policy bsb_session_active on "centrakit"."field_options" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."field_values";
create policy bsb_session_active on "centrakit"."field_values" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."share_links";
create policy bsb_session_active on "centrakit"."share_links" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."subject_views";
create policy bsb_session_active on "centrakit"."subject_views" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."subject_user_state";
create policy bsb_session_active on "centrakit"."subject_user_state" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."recurrence_rules";
create policy bsb_session_active on "centrakit"."recurrence_rules" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."reminders";
create policy bsb_session_active on "centrakit"."reminders" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."reminder_deliveries";
create policy bsb_session_active on "centrakit"."reminder_deliveries" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."import_runs";
create policy bsb_session_active on "centrakit"."import_runs" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."file_node";
create policy bsb_session_active on "centrakit"."file_node" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."file_node_grant";
create policy bsb_session_active on "centrakit"."file_node_grant" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."customers";
create policy bsb_session_active on "centrakit"."customers" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."customer_contacts";
create policy bsb_session_active on "centrakit"."customer_contacts" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."employees";
create policy bsb_session_active on "centrakit"."employees" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."projects";
create policy bsb_session_active on "centrakit"."projects" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."project_members";
create policy bsb_session_active on "centrakit"."project_members" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));
drop policy if exists bsb_session_active on "centrakit"."tasks";
create policy bsb_session_active on "centrakit"."tasks" as restrictive
  for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));

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
