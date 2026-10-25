-- ==== alone: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:cdceccb2b06b3b07e3240c84bc7350fefbb7989f281d551c509ddc743bc56b49
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."notification_events" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "subject_label" text,
  "summary" text,
  "action_path" text,
  "actions" jsonb,
  "priority" text not null default 'normal',
  "data" jsonb not null default '{}',
  "idempotency_key" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists notification_events_key_idx on "better_supabase"."notification_events" ("idempotency_key", "organization_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "better_supabase"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "better_supabase"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "better_supabase"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "better_supabase"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"better_supabase"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table "better_supabase"."notification_events" drop constraint "notification_events_priority_check";
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    alter table "better_supabase"."notification_events" add constraint "notification_events_priority_check"
      check ("priority" in ('low', 'normal', 'high', 'urgent')) not valid;
    begin
      alter table "better_supabase"."notification_events" validate constraint "notification_events_priority_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."notification_events"', 'notification_events_priority_check', '"better_supabase"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."notification_events" enable row level security;
revoke all on "better_supabase"."notification_events" from anon, authenticated;
grant select on "better_supabase"."notification_events" to authenticated;
grant all on "better_supabase"."notification_events" to service_role;

create table if not exists "better_supabase"."notification_recipients" (
  "id" uuid primary key default gen_random_uuid(),
  "event_id" uuid not null references "better_supabase"."notification_events" ("id") on delete cascade,
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "read_at" timestamptz,
  "dismissed_at" timestamptz,
  "resolved_at" timestamptz,
  "resolution" jsonb,
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
revoke all on "better_supabase"."notification_recipients" from anon, authenticated;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "better_supabase"."notification_events";
create policy "bsb_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "recipient_id" uuid not null references "better_supabase"."notification_recipients" ("id") on delete cascade,
  "organization_id" uuid,
  "channel" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped')),
  "provider" text,
  "provider_message_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "attempted_at" timestamptz,
  "next_attempt_at" timestamptz not null default now(),
  "delivered_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("recipient_id", "channel")
);
create index if not exists notification_deliveries_pending_idx on "better_supabase"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "better_supabase"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "better_supabase"."notification_deliveries" enable row level security;
revoke all on "better_supabase"."notification_deliveries" from anon, authenticated;
grant select on "better_supabase"."notification_deliveries" to authenticated;
grant all on "better_supabase"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore')),
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("organization_id", "user_id", "subject_type", "subject_id")
);
create index if not exists notification_subscriptions_user_idx on "better_supabase"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "better_supabase"."notification_subscriptions" ("organization_id", "subject_type", "subject_id");
alter table "better_supabase"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_subscriptions";
create trigger bsb_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
revoke all on "better_supabase"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "type" text not null,
  "channel" text not null,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "organization_id", "type", "channel")
);
alter table "better_supabase"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_preferences";
create trigger bsb_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
revoke all on "better_supabase"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "better_supabase"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "better_supabase"."notification_suppressions" ("user_id");
alter table "better_supabase"."notification_suppressions" enable row level security;
revoke all on "better_supabase"."notification_suppressions" from anon, authenticated;
grant select on "better_supabase"."notification_suppressions" to authenticated;
grant all on "better_supabase"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "better_supabase"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "better_supabase"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "organization_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "better_supabase"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "better_supabase"."notification_delivery_events" enable row level security;
revoke all on "better_supabase"."notification_delivery_events" from anon, authenticated;
grant select on "better_supabase"."notification_delivery_events" to authenticated;
grant all on "better_supabase"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "better_supabase"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "better_supabase"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null then
    raise exception 'This project has no permission audience' using errcode = '0A000', hint = 'NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE';
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "better_supabase"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "better_supabase"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notification"(jsonb) to service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."notify"(jsonb) to service_role;
revoke execute on function "better_supabase"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notifications"(jsonb) to service_role;

drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "better_supabase"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "better_supabase"."mark_notifications_read"(uuid[], uuid);
drop function if exists "better_supabase"."dismiss_notifications"(uuid[]);
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."organization_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."organization_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "better_supabase"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."organization_id" = notification_counts.tenant)
$$;

create or replace function "better_supabase"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_counts(uuid, text[]) from public, anon;
grant execute on function "better_supabase".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "better_supabase".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "better_supabase".get_notification(uuid) from public, anon;
grant execute on function "better_supabase".get_notification(uuid) to authenticated, service_role;
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "better_supabase"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "better_supabase"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."organization_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "better_supabase"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."organization_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "better_supabase"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', null::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "better_supabase"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "better_supabase"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "better_supabase"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "better_supabase"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "better_supabase"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "better_supabase"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."organization_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "better_supabase"."notification_delivery_events" ("delivery_id", "organization_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "better_supabase"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "better_supabase"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "better_supabase"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "better_supabase"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."organization_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "better_supabase"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
create policy bsb_tenant_scope on "better_supabase"."notification_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
create policy bsb_tenant_scope on "better_supabase"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
create policy bsb_tenant_scope on "better_supabase"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
create policy bsb_tenant_scope on "better_supabase"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
create policy bsb_tenant_scope on "better_supabase"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
create policy bsb_tenant_scope on "better_supabase"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:8ec114ddc4aba46e40c32c75da614653c16763ad5ebfbfa19542cea64eb8172e
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."notification_events" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "subject_label" text,
  "summary" text,
  "action_path" text,
  "actions" jsonb,
  "priority" text not null default 'normal',
  "data" jsonb not null default '{}',
  "idempotency_key" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists notification_events_key_idx on "better_supabase"."notification_events" ("idempotency_key", "organization_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "better_supabase"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "better_supabase"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "better_supabase"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "better_supabase"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"better_supabase"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table "better_supabase"."notification_events" drop constraint "notification_events_priority_check";
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    alter table "better_supabase"."notification_events" add constraint "notification_events_priority_check"
      check ("priority" in ('low', 'normal', 'high', 'urgent')) not valid;
    begin
      alter table "better_supabase"."notification_events" validate constraint "notification_events_priority_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."notification_events"', 'notification_events_priority_check', '"better_supabase"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."notification_events" enable row level security;
revoke all on "better_supabase"."notification_events" from anon, authenticated;
grant select on "better_supabase"."notification_events" to authenticated;
grant all on "better_supabase"."notification_events" to service_role;

create table if not exists "better_supabase"."notification_recipients" (
  "id" uuid primary key default gen_random_uuid(),
  "event_id" uuid not null references "better_supabase"."notification_events" ("id") on delete cascade,
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "read_at" timestamptz,
  "dismissed_at" timestamptz,
  "resolved_at" timestamptz,
  "resolution" jsonb,
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
revoke all on "better_supabase"."notification_recipients" from anon, authenticated;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "better_supabase"."notification_events";
create policy "bsb_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "recipient_id" uuid not null references "better_supabase"."notification_recipients" ("id") on delete cascade,
  "organization_id" uuid,
  "channel" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped')),
  "provider" text,
  "provider_message_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "attempted_at" timestamptz,
  "next_attempt_at" timestamptz not null default now(),
  "delivered_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("recipient_id", "channel")
);
create index if not exists notification_deliveries_pending_idx on "better_supabase"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "better_supabase"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "better_supabase"."notification_deliveries" enable row level security;
revoke all on "better_supabase"."notification_deliveries" from anon, authenticated;
grant select on "better_supabase"."notification_deliveries" to authenticated;
grant all on "better_supabase"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore')),
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("organization_id", "user_id", "subject_type", "subject_id")
);
create index if not exists notification_subscriptions_user_idx on "better_supabase"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "better_supabase"."notification_subscriptions" ("organization_id", "subject_type", "subject_id");
alter table "better_supabase"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_subscriptions";
create trigger bsb_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
revoke all on "better_supabase"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read')))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read')))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "type" text not null,
  "channel" text not null,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "organization_id", "type", "channel")
);
alter table "better_supabase"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_preferences";
create trigger bsb_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
revoke all on "better_supabase"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "better_supabase"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read')))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read')))) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "better_supabase"."notification_suppressions" ("user_id");
alter table "better_supabase"."notification_suppressions" enable row level security;
revoke all on "better_supabase"."notification_suppressions" from anon, authenticated;
grant select on "better_supabase"."notification_suppressions" to authenticated;
grant all on "better_supabase"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "better_supabase"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "better_supabase"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "organization_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "better_supabase"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "better_supabase"."notification_delivery_events" enable row level security;
revoke all on "better_supabase"."notification_delivery_events" from anon, authenticated;
grant select on "better_supabase"."notification_delivery_events" to authenticated;
grant all on "better_supabase"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "better_supabase"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "better_supabase"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, 'notifications.send'), false) then
      raise exception 'Not allowed to send notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
    end if;
    v_actor := auth.uid();
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null and v_tenant is null then
    raise exception 'A permission audience needs a tenant' using errcode = '22023', hint = 'NOTIFICATION_PERMISSION_NEEDS_TENANT';
  end if;
  if nullif(notification ->> 'permission', '') is not null then
    v_recipients := v_recipients || coalesce(array(
      select m."user_id"
      from "better_supabase"."memberships" m
      where m."organization_id" = v_tenant
        and coalesce(better_supabase.can_user(m."user_id", 'tenant', v_tenant, notification ->> 'permission'), false)
      
    ), '{}');
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  if v_tenant is not null then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where coalesce(better_supabase.member_can(x, v_tenant, 'notifications.read'), false)
    );
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  perform "better_supabase".emit_event('notification.created', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'recipientIds', to_jsonb(v_recipients)), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.created:' || v_event::text, 'better-supabase/notifications');
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "better_supabase"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "better_supabase"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon;
grant execute on function "better_supabase"."send_notification"(jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon;
grant execute on function "better_supabase"."notify"(jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."send_notifications"(jsonb) from public, anon;
grant execute on function "better_supabase"."send_notifications"(jsonb) to authenticated, service_role;

drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "better_supabase"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "better_supabase"."mark_notifications_read"(uuid[], uuid);
drop function if exists "better_supabase"."dismiss_notifications"(uuid[]);
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."organization_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."organization_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "better_supabase"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."organization_id" = notification_counts.tenant)
$$;

create or replace function "better_supabase"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, 'notifications.send'), false)) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;

-- The public profile fields of the actors behind the caller's notifications,
-- keyed by user id, for list({ include: ['actor'] }). Only actors of the
-- caller's own notifications.
create or replace function "better_supabase"."notification_actors"(ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(pr."id"::text, jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url", 'avatarPath', pr."avatar_path")), '{}')
  from "better_supabase"."profiles" pr
  where pr."id" = any(notification_actors.ids)
    and exists (
      select 1 from "better_supabase"."notification_recipients" rc
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where rc."user_id" = auth.uid() and ev."actor_id" = pr."id"
    )
$$;
revoke execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_counts(uuid, text[]) from public, anon;
grant execute on function "better_supabase".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "better_supabase".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "better_supabase".get_notification(uuid) from public, anon;
grant execute on function "better_supabase".get_notification(uuid) to authenticated, service_role;
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase".notification_actors(uuid[]) from public, anon;
grant execute on function "better_supabase".notification_actors(uuid[]) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "better_supabase"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not (
    coalesce(set_notification_subscription.if_absent, false) and set_notification_subscription.level is not null and set_notification_subscription.tenant is not null
    and coalesce(better_supabase.member_can(auth.uid(), set_notification_subscription.tenant, 'notifications.send'), false)
    and coalesce(better_supabase.member_can(v_user, set_notification_subscription.tenant, 'notifications.read'), false)
  ) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if set_notification_subscription.tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.member_can(auth.uid(), set_notification_subscription.tenant, 'notifications.read'), false) then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "better_supabase"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_preference.tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.member_can(auth.uid(), set_notification_preference.tenant, 'notifications.read'), false) then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."organization_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "better_supabase"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."organization_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "better_supabase"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', pr."locale"::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."profiles" pr on pr."id" = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "better_supabase"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "better_supabase"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "better_supabase"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "better_supabase"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "better_supabase"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "better_supabase"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."organization_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "better_supabase"."notification_delivery_events" ("delivery_id", "organization_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "better_supabase"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "better_supabase"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
    if v_kind = 'delayed' then
      perform "better_supabase".emit_event('notification.delayed', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.delayed:' || v_row::text, 'better-supabase/notifications');
    elsif v_kind = 'delivered' then
      perform "better_supabase".emit_event('notification.delivered', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.delivered:' || v_row::text, 'better-supabase/notifications');
    elsif v_kind = 'opened' then
      perform "better_supabase".emit_event('notification.opened', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.opened:' || v_row::text, 'better-supabase/notifications');
    elsif v_kind = 'clicked' then
      perform "better_supabase".emit_event('notification.clicked', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.clicked:' || v_row::text, 'better-supabase/notifications');
    elsif v_kind = 'bounced' then
      perform "better_supabase".emit_event('notification.bounced', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.bounced:' || v_row::text, 'better-supabase/notifications');
    elsif v_kind = 'complained' then
      perform "better_supabase".emit_event('notification.complained', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', record_delivery_event.provider, 'providerEventId', record_delivery_event.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.complained:' || v_row::text, 'better-supabase/notifications');
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "better_supabase"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or (list_subject_deliveries.tenant is not null and coalesce(better_supabase.member_can(auth.uid(), list_subject_deliveries.tenant, 'notifications.send'), false))) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "better_supabase"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."organization_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to authenticated, service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where (ev."created_at" < now() - least(coalesce(older_than, '90 days'), "better_supabase"."retention_floor"('notifications'))
      and ev."created_at" < now() - coalesce("better_supabase"."retention_for"('notifications', (ev."organization_id")::text), coalesce(older_than, '90 days'))
      and not "better_supabase"."is_held"('notifications', (ev."organization_id")::text))
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "better_supabase"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
create policy bsb_tenant_scope on "better_supabase"."notification_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
create policy bsb_tenant_scope on "better_supabase"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
create policy bsb_tenant_scope on "better_supabase"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
create policy bsb_tenant_scope on "better_supabase"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
create policy bsb_tenant_scope on "better_supabase"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read'))))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
create policy bsb_tenant_scope on "better_supabase"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read'))))
  );

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:0ed99bb85feb044ddf61748491e647d88828f961e49bb9e16732d4fb714d9287
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."notification_events" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "subject_label" text,
  "summary" text,
  "action_path" text,
  "actions" jsonb,
  "priority" text not null default 'normal',
  "data" jsonb not null default '{}',
  "idempotency_key" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists notification_events_key_idx on "app_private"."notification_events" ("idempotency_key", "organization_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "app_private"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "app_private"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "app_private"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "app_private"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"app_private"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table "app_private"."notification_events" drop constraint "notification_events_priority_check";
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"app_private"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    alter table "app_private"."notification_events" add constraint "notification_events_priority_check"
      check ("priority" in ('low', 'normal', 'high', 'urgent')) not valid;
    begin
      alter table "app_private"."notification_events" validate constraint "notification_events_priority_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"app_private"."notification_events"', 'notification_events_priority_check', '"app_private"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "app_private"."notification_events" enable row level security;
revoke all on "app_private"."notification_events" from anon, authenticated;
grant select on "app_private"."notification_events" to authenticated;
grant all on "app_private"."notification_events" to service_role;

create table if not exists "app_private"."notification_recipients" (
  "id" uuid primary key default gen_random_uuid(),
  "event_id" uuid not null references "app_private"."notification_events" ("id") on delete cascade,
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "read_at" timestamptz,
  "dismissed_at" timestamptz,
  "resolved_at" timestamptz,
  "resolution" jsonb,
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
alter table "app_private"."notification_events" add column if not exists "actions" jsonb;
alter table "app_private"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "app_private"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "app_private"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "app_private"."notification_recipients" ("user_id");
alter table "app_private"."notification_recipients" enable row level security;
revoke all on "app_private"."notification_recipients" from anon, authenticated;
grant select on "app_private"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "app_private"."notification_recipients" to authenticated;
grant all on "app_private"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "app_private"."notification_recipients";
create policy "bsb_notification_recipients_read" on "app_private"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "app_private"."notification_recipients";
create policy "bsb_notification_recipients_update" on "app_private"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "app_private"."notification_events";
create policy "bsb_notification_events_read" on "app_private"."notification_events" for select to authenticated using (
  exists (
    select 1 from "app_private"."notification_recipients" r
    where r."event_id" = "app_private"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "app_private"."notification_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "recipient_id" uuid not null references "app_private"."notification_recipients" ("id") on delete cascade,
  "organization_id" uuid,
  "channel" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped')),
  "provider" text,
  "provider_message_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "attempted_at" timestamptz,
  "next_attempt_at" timestamptz not null default now(),
  "delivered_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("recipient_id", "channel")
);
create index if not exists notification_deliveries_pending_idx on "app_private"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "app_private"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "app_private"."notification_deliveries" enable row level security;
revoke all on "app_private"."notification_deliveries" from anon, authenticated;
grant select on "app_private"."notification_deliveries" to authenticated;
grant all on "app_private"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "app_private"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "app_private"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "app_private"."notification_recipients" r
    where r."id" = "app_private"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "app_private"."notification_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore')),
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("organization_id", "user_id", "subject_type", "subject_id")
);
create index if not exists notification_subscriptions_user_idx on "app_private"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "app_private"."notification_subscriptions" ("organization_id", "subject_type", "subject_id");
alter table "app_private"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."notification_subscriptions";
create trigger bsb_updated_at before update on "app_private"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."notification_subscriptions" enable row level security;
revoke all on "app_private"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "app_private"."notification_subscriptions" to authenticated;
grant all on "app_private"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "app_private"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "app_private"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "app_private"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "app_private"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "app_private"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "app_private"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "app_private"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "app_private"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "app_private"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "app_private"."notification_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "type" text not null,
  "channel" text not null,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "organization_id", "type", "channel")
);
alter table "app_private"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."notification_preferences";
create trigger bsb_updated_at before update on "app_private"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."notification_preferences" enable row level security;
revoke all on "app_private"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "app_private"."notification_preferences" to authenticated;
grant all on "app_private"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "app_private"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "app_private"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "app_private"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "app_private"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "app_private"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "app_private"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "app_private"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "app_private"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "app_private"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "app_private"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "app_private"."notification_suppressions" ("user_id");
alter table "app_private"."notification_suppressions" enable row level security;
revoke all on "app_private"."notification_suppressions" from anon, authenticated;
grant select on "app_private"."notification_suppressions" to authenticated;
grant all on "app_private"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "app_private"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "app_private"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "app_private"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "app_private"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "app_private"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "app_private"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "app_private"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "app_private"."notification_deliveries" ("id") on delete cascade,
  "organization_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "app_private"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "app_private"."notification_delivery_events" enable row level security;
revoke all on "app_private"."notification_delivery_events" from anon, authenticated;
grant select on "app_private"."notification_delivery_events" to authenticated;
grant all on "app_private"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "app_private"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "app_private"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "app_private"."notification_deliveries" d
    join "app_private"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "app_private"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "app_private"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "app_private"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "app_private"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "app_private"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "app_private"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "app_private"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null then
    raise exception 'This project has no permission audience' using errcode = '0A000', hint = 'NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE';
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "app_private"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "app_private"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "app_private"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "app_private"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "app_private"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "app_private"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "app_private"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "app_private"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("app_private"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "app_private"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "app_private"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "app_private"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."send_notification"(jsonb) to service_role;
revoke execute on function "app_private"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."notify"(jsonb) to service_role;
revoke execute on function "app_private"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."send_notifications"(jsonb) to service_role;

drop function if exists "app_private"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "app_private"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "app_private"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "app_private"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "app_private"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "app_private"."mark_notifications_read"(uuid[], uuid);
drop function if exists "app_private"."dismiss_notifications"(uuid[]);
drop function if exists "app_private"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "app_private"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "app_private"."notification_recipients" rc
    join "app_private"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."organization_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "app_private"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "app_private"."notification_recipients" rc
    join "app_private"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."organization_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "app_private"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "app_private"."notification_recipients" rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."organization_id" = notification_counts.tenant)
$$;

create or replace function "app_private"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "app_private"."notification_recipients" rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "app_private"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "app_private"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "app_private"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "app_private"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "app_private"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "app_private"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "app_private"."resolve_notifications"(text, text, text, uuid);
create or replace function "app_private"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "app_private"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "app_private"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "app_private"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;
revoke execute on function "app_private".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "app_private".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "app_private".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "app_private".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "app_private".notification_counts(uuid, text[]) from public, anon;
grant execute on function "app_private".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "app_private".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "app_private".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "app_private".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "app_private".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "app_private".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "app_private".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "app_private".get_notification(uuid) from public, anon;
grant execute on function "app_private".get_notification(uuid) to authenticated, service_role;
revoke execute on function "app_private".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "app_private".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "app_private"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "app_private"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "app_private"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "app_private"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "app_private"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "app_private"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "app_private"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "app_private"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "app_private"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "app_private"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "app_private"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "app_private"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "app_private"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "app_private"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."organization_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "app_private"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."organization_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "app_private"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "app_private"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "app_private"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "app_private"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "app_private"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "app_private"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "app_private"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "app_private"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "app_private"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "app_private"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "app_private"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "app_private"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', null::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "app_private"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "app_private"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "app_private"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "app_private"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "app_private"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "app_private"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "app_private"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "app_private"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "app_private"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "app_private"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "app_private"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "app_private"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "app_private"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "app_private"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "app_private"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "app_private"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "app_private"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "app_private"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "app_private"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "app_private"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."organization_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "app_private"."notification_deliveries" d
  join "app_private"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "app_private"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "app_private"."notification_delivery_events" ("delivery_id", "organization_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "app_private"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "app_private"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "app_private"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "app_private"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "app_private"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "app_private"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "app_private"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "app_private"."notification_deliveries" d
      join "app_private"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "app_private"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."organization_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "app_private"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "app_private"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "app_private"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "app_private"."notification_events"
  where "id" in (
    select ev."id" from "app_private"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "app_private"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "app_private"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "app_private"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "app_private"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "app_private"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "app_private"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "app_private"."notification_recipients"
  for each row execute function "app_private"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "app_private"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "app_private"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."notification_events";
create policy bsb_tenant_scope on "app_private"."notification_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "app_private"."notification_recipients" r
    where r."event_id" = "app_private"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."notification_recipients";
create policy bsb_tenant_scope on "app_private"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "app_private"."notification_deliveries";
create policy bsb_tenant_scope on "app_private"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "app_private"."notification_recipients" r
    where r."id" = "app_private"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."notification_delivery_events";
create policy bsb_tenant_scope on "app_private"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "app_private"."notification_deliveries" d
    join "app_private"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "app_private"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."notification_subscriptions";
create policy bsb_tenant_scope on "app_private"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "app_private"."notification_preferences";
create policy bsb_tenant_scope on "app_private"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:59582e841228bea59577d12605740f6e7365fd6e79b09429d6baabfe3f2ed030
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."notification_events" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "subject_label" text,
  "summary" text,
  "action_path" text,
  "actions" jsonb,
  "priority" text not null default 'normal',
  "data" jsonb not null default '{}',
  "idempotency_key" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists notification_events_key_idx on "better_supabase"."notification_events" ("idempotency_key", "organization_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "better_supabase"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "better_supabase"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "better_supabase"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "better_supabase"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"better_supabase"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table "better_supabase"."notification_events" drop constraint "notification_events_priority_check";
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    alter table "better_supabase"."notification_events" add constraint "notification_events_priority_check"
      check ("priority" in ('low', 'normal', 'high', 'urgent')) not valid;
    begin
      alter table "better_supabase"."notification_events" validate constraint "notification_events_priority_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."notification_events"', 'notification_events_priority_check', '"better_supabase"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."notification_events" enable row level security;
revoke all on "better_supabase"."notification_events" from anon, authenticated;
grant select on "better_supabase"."notification_events" to authenticated;
grant all on "better_supabase"."notification_events" to service_role;

create table if not exists "better_supabase"."notification_recipients" (
  "id" uuid primary key default gen_random_uuid(),
  "event_id" uuid not null references "better_supabase"."notification_events" ("id") on delete cascade,
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "read_at" timestamptz,
  "dismissed_at" timestamptz,
  "resolved_at" timestamptz,
  "resolution" jsonb,
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
revoke all on "better_supabase"."notification_recipients" from anon, authenticated;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "better_supabase"."notification_events";
create policy "bsb_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "recipient_id" uuid not null references "better_supabase"."notification_recipients" ("id") on delete cascade,
  "organization_id" uuid,
  "channel" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped')),
  "provider" text,
  "provider_message_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "attempted_at" timestamptz,
  "next_attempt_at" timestamptz not null default now(),
  "delivered_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("recipient_id", "channel")
);
create index if not exists notification_deliveries_pending_idx on "better_supabase"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "better_supabase"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "better_supabase"."notification_deliveries" enable row level security;
revoke all on "better_supabase"."notification_deliveries" from anon, authenticated;
grant select on "better_supabase"."notification_deliveries" to authenticated;
grant all on "better_supabase"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore')),
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("organization_id", "user_id", "subject_type", "subject_id")
);
create index if not exists notification_subscriptions_user_idx on "better_supabase"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "better_supabase"."notification_subscriptions" ("organization_id", "subject_type", "subject_id");
alter table "better_supabase"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_subscriptions";
create trigger bsb_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
revoke all on "better_supabase"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "type" text not null,
  "channel" text not null,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "organization_id", "type", "channel")
);
alter table "better_supabase"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_preferences";
create trigger bsb_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
revoke all on "better_supabase"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "better_supabase"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "better_supabase"."notification_suppressions" ("user_id");
alter table "better_supabase"."notification_suppressions" enable row level security;
revoke all on "better_supabase"."notification_suppressions" from anon, authenticated;
grant select on "better_supabase"."notification_suppressions" to authenticated;
grant all on "better_supabase"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "better_supabase"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "better_supabase"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "organization_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "better_supabase"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "better_supabase"."notification_delivery_events" enable row level security;
revoke all on "better_supabase"."notification_delivery_events" from anon, authenticated;
grant select on "better_supabase"."notification_delivery_events" to authenticated;
grant all on "better_supabase"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "better_supabase"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "better_supabase"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null then
    raise exception 'This project has no permission audience' using errcode = '0A000', hint = 'NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE';
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "better_supabase"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "better_supabase"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notification"(jsonb) to service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."notify"(jsonb) to service_role;
revoke execute on function "better_supabase"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notifications"(jsonb) to service_role;

drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "better_supabase"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "better_supabase"."mark_notifications_read"(uuid[], uuid);
drop function if exists "better_supabase"."dismiss_notifications"(uuid[]);
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."organization_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."organization_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "better_supabase"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."organization_id" = notification_counts.tenant)
$$;

create or replace function "better_supabase"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_counts(uuid, text[]) from public, anon;
grant execute on function "better_supabase".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "better_supabase".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "better_supabase".get_notification(uuid) from public, anon;
grant execute on function "better_supabase".get_notification(uuid) to authenticated, service_role;
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "better_supabase"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "better_supabase"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."organization_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "better_supabase"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."organization_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "better_supabase"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', null::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "better_supabase"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "better_supabase"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "better_supabase"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "better_supabase"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "better_supabase"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "better_supabase"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."organization_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "better_supabase"."notification_delivery_events" ("delivery_id", "organization_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "better_supabase"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "better_supabase"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "better_supabase"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "better_supabase"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."organization_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "better_supabase"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
create policy bsb_tenant_scope on "better_supabase"."notification_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
create policy bsb_tenant_scope on "better_supabase"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
create policy bsb_tenant_scope on "better_supabase"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
create policy bsb_tenant_scope on "better_supabase"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
create policy bsb_tenant_scope on "better_supabase"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
create policy bsb_tenant_scope on "better_supabase"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );

-- blocks.notifications.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "api"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "api"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "api"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "api"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "api"."mark_notifications_read"(uuid[], uuid);
drop function if exists "api"."dismiss_notifications"(uuid[]);
drop function if exists "api"."resolve_notifications"(text, text, text, uuid);
drop function if exists "api"."set_notification_subscription"(text, text, text, uuid, uuid);
drop function if exists "api"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "api"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "api"."complete_notification_delivery"(uuid, text, text, text, text, integer);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notification_enabled"($1, $2, $3, $4) $$;
revoke execute on function "api"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."notification_enabled"(uuid, uuid, text, text) to service_role;

create or replace function "api"."send_notification"(notification jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_notification"($1) $$;
revoke execute on function "api"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "api"."send_notification"(jsonb) to service_role;

create or replace function "api"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify"($1) $$;
revoke execute on function "api"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "api"."notify"(jsonb) to service_role;

create or replace function "api"."send_notifications"(events jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_notifications"($1) $$;
revoke execute on function "api"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "api"."send_notifications"(jsonb) to service_role;

create or replace function "api"."list_notifications"(tenant uuid default null, status text default 'all', types text[] default null, before timestamptz default null, max_items integer default 50, before_id uuid default null, subject_types text[] default null, search text default null, read boolean default null, resolved boolean default null, dismissed boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_notifications"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $$;
revoke execute on function "api"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "api"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;

create or replace function "api"."notification_page"(tenant uuid default null, status text default 'all', types text[] default null, subject_types text[] default null, search text default null, max_items integer default 50, skip integer default 0, read boolean default null, resolved boolean default null, dismissed boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notification_page"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;

create or replace function "api"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notification_counts"($1, $2) $$;
revoke execute on function "api"."notification_counts"(uuid, text[]) from public, anon;
grant execute on function "api"."notification_counts"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_notifications_unread"($1, $2) $$;
revoke execute on function "api"."mark_notifications_unread"(uuid[], uuid) from public, anon;
grant execute on function "api"."mark_notifications_unread"(uuid[], uuid) to authenticated, service_role;

create or replace function "api"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_notifications_read"($1, $2) $$;
revoke execute on function "api"."mark_notifications_read"(uuid[], uuid) from public, anon;
grant execute on function "api"."mark_notifications_read"(uuid[], uuid) to authenticated, service_role;

create or replace function "api"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dismiss_notifications"($1) $$;
revoke execute on function "api"."dismiss_notifications"(uuid[]) from public, anon;
grant execute on function "api"."dismiss_notifications"(uuid[]) to authenticated, service_role;

create or replace function "api"."get_notification"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_notification"($1) $$;
revoke execute on function "api"."get_notification"(uuid) from public, anon;
grant execute on function "api"."get_notification"(uuid) to authenticated, service_role;

create or replace function "api"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_notifications"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."resolve_notifications"(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "api"."resolve_notifications"(text, text, text, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_notification_subscription"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "api"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_notification_preference"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "api"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "api"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_notification_subscriptions"($1, $2, $3) $$;
revoke execute on function "api"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "api"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_notification_preferences"($1) $$;
revoke execute on function "api"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "api"."list_notification_preferences"(uuid) to authenticated, service_role;

create or replace function "api"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_notification_deliveries"($1, $2, $3, $4) $$;
revoke execute on function "api"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "api"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;

create or replace function "api"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_notification_delivery"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "api"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

create or replace function "api"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suppress_notification_address"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "api"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unsuppress_notification_address"($1, $2) $$;
revoke execute on function "api"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "api"."unsuppress_notification_address"(text, text) to service_role;

create or replace function "api"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_notification_suppressions"($1) $$;
revoke execute on function "api"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "api"."list_notification_suppressions"(integer) to authenticated, service_role;

create or replace function "api"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_delivery_event"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "api"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

create or replace function "api"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_subject_deliveries"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

create or replace function "api"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_notifications"($1, $2) $$;
revoke execute on function "api"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_notifications"(interval, integer) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:41bbeece9739250ade6278ef69fd57175081da11a3e1293071621545c3d9acf6
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.notification_events is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."notification_events" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."notification_events" add column if not exists "organization_id" uuid;
alter table "better_supabase"."notification_events" add column if not exists "type" text;
alter table "better_supabase"."notification_events" add column if not exists "actor_id" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."notification_events" add column if not exists "subject_type" text;
alter table "better_supabase"."notification_events" add column if not exists "subject_id" text;
alter table "better_supabase"."notification_events" add column if not exists "subject_label" text;
alter table "better_supabase"."notification_events" add column if not exists "summary" text;
alter table "better_supabase"."notification_events" add column if not exists "action_path" text;
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_events" add column if not exists "priority" text not null default 'normal';
alter table "better_supabase"."notification_events" add column if not exists "data" jsonb not null default '{}';
alter table "better_supabase"."notification_events" add column if not exists "idempotency_key" text;
alter table "better_supabase"."notification_events" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."notification_events" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists notification_events_key_idx on "better_supabase"."notification_events" ("idempotency_key", "organization_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "better_supabase"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "better_supabase"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "better_supabase"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "better_supabase"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"better_supabase"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."notification_events"', 'notification_events_priority_check', '"better_supabase"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."notification_events" enable row level security;
grant select on "better_supabase"."notification_events" to authenticated;
grant all on "better_supabase"."notification_events" to service_role;

-- better_supabase.notification_recipients is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."notification_recipients" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."notification_recipients" add column if not exists "event_id" uuid references "better_supabase"."notification_events" ("id") on delete cascade;
alter table "better_supabase"."notification_recipients" add column if not exists "organization_id" uuid;
alter table "better_supabase"."notification_recipients" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."notification_recipients" add column if not exists "read_at" timestamptz;
alter table "better_supabase"."notification_recipients" add column if not exists "dismissed_at" timestamptz;
alter table "better_supabase"."notification_recipients" add column if not exists "resolved_at" timestamptz;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "delivered_at" timestamptz not null default now();
alter table "better_supabase"."notification_recipients" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "better_supabase"."notification_events";
create policy "bsb_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

-- better_supabase.notification_deliveries is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."notification_deliveries" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."notification_deliveries" add column if not exists "recipient_id" uuid references "better_supabase"."notification_recipients" ("id") on delete cascade;
alter table "better_supabase"."notification_deliveries" add column if not exists "organization_id" uuid;
alter table "better_supabase"."notification_deliveries" add column if not exists "channel" text;
alter table "better_supabase"."notification_deliveries" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider" text;
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_message_id" text;
alter table "better_supabase"."notification_deliveries" add column if not exists "error" text;
alter table "better_supabase"."notification_deliveries" add column if not exists "attempts" integer not null default 0;
alter table "better_supabase"."notification_deliveries" add column if not exists "attempted_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "next_attempt_at" timestamptz not null default now();
alter table "better_supabase"."notification_deliveries" add column if not exists "delivered_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "created_at" timestamptz not null default now();
create index if not exists notification_deliveries_pending_idx on "better_supabase"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "better_supabase"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "better_supabase"."notification_deliveries" enable row level security;
grant select on "better_supabase"."notification_deliveries" to authenticated;
grant all on "better_supabase"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

-- better_supabase.notification_subscriptions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."notification_subscriptions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."notification_subscriptions" add column if not exists "organization_id" uuid;
alter table "better_supabase"."notification_subscriptions" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."notification_subscriptions" add column if not exists "subject_type" text;
alter table "better_supabase"."notification_subscriptions" add column if not exists "subject_id" text;
alter table "better_supabase"."notification_subscriptions" add column if not exists "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore'));
alter table "better_supabase"."notification_subscriptions" add column if not exists "created_at" timestamptz not null default now();
create index if not exists notification_subscriptions_user_idx on "better_supabase"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "better_supabase"."notification_subscriptions" ("organization_id", "subject_type", "subject_id");
alter table "better_supabase"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_subscriptions";
create trigger bsb_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- better_supabase.notification_preferences is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."notification_preferences" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."notification_preferences" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."notification_preferences" add column if not exists "organization_id" uuid;
alter table "better_supabase"."notification_preferences" add column if not exists "type" text;
alter table "better_supabase"."notification_preferences" add column if not exists "channel" text;
alter table "better_supabase"."notification_preferences" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."notification_preferences" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_preferences";
create trigger bsb_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "better_supabase"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "better_supabase"."notification_suppressions" ("user_id");
alter table "better_supabase"."notification_suppressions" enable row level security;
revoke all on "better_supabase"."notification_suppressions" from anon, authenticated;
grant select on "better_supabase"."notification_suppressions" to authenticated;
grant all on "better_supabase"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "better_supabase"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "better_supabase"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "organization_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "better_supabase"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "better_supabase"."notification_delivery_events" enable row level security;
revoke all on "better_supabase"."notification_delivery_events" from anon, authenticated;
grant select on "better_supabase"."notification_delivery_events" to authenticated;
grant all on "better_supabase"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "better_supabase"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "better_supabase"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null then
    raise exception 'This project has no permission audience' using errcode = '0A000', hint = 'NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE';
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "better_supabase"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "better_supabase"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notification"(jsonb) to service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."notify"(jsonb) to service_role;
revoke execute on function "better_supabase"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notifications"(jsonb) to service_role;

drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "better_supabase"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "better_supabase"."mark_notifications_read"(uuid[], uuid);
drop function if exists "better_supabase"."dismiss_notifications"(uuid[]);
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."organization_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."organization_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "better_supabase"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."organization_id" = notification_counts.tenant)
$$;

create or replace function "better_supabase"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_counts(uuid, text[]) from public, anon;
grant execute on function "better_supabase".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "better_supabase".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "better_supabase".get_notification(uuid) from public, anon;
grant execute on function "better_supabase".get_notification(uuid) to authenticated, service_role;
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "better_supabase"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "better_supabase"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."organization_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "better_supabase"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."organization_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "better_supabase"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', null::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "better_supabase"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "better_supabase"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "better_supabase"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "better_supabase"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "better_supabase"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "better_supabase"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."organization_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "better_supabase"."notification_delivery_events" ("delivery_id", "organization_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "better_supabase"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "better_supabase"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "better_supabase"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "better_supabase"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."organization_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "better_supabase"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
create policy bsb_tenant_scope on "better_supabase"."notification_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
create policy bsb_tenant_scope on "better_supabase"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
create policy bsb_tenant_scope on "better_supabase"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
create policy bsb_tenant_scope on "better_supabase"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
create policy bsb_tenant_scope on "better_supabase"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
create policy bsb_tenant_scope on "better_supabase"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block notifications@9 managed
-- @bsb-hash sha256:96da8a5f83e555b856e6d8caa1401453438334f988e86cc03f156e7afb1847c6
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."notification_events" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "subject_label" text,
  "summary" text,
  "action_path" text,
  "actions" jsonb,
  "priority" text not null default 'normal',
  "data" jsonb not null default '{}',
  "idempotency_key" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists notification_events_key_idx on "better_supabase"."notification_events" ("idempotency_key", "org_id") nulls not distinct where "idempotency_key" is not null;
create index if not exists notification_events_subject_idx on "better_supabase"."notification_events" ("subject_type", "subject_id");
create index if not exists notification_events_actor_idx on "better_supabase"."notification_events" ("actor_id");
create index if not exists notification_events_created_by_idx on "better_supabase"."notification_events" ("created_by");
create index if not exists notification_events_created_at_idx on "better_supabase"."notification_events" ("created_at");
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array['low', 'normal', 'high', 'urgent']::text[]) p
    where k.conrelid = '"better_supabase"."notification_events"'::regclass and k.conname = 'notification_events_priority_check'
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table "better_supabase"."notification_events" drop constraint "notification_events_priority_check";
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."notification_events"'::regclass and conname = 'notification_events_priority_check'
  ) then
    alter table "better_supabase"."notification_events" add constraint "notification_events_priority_check"
      check ("priority" in ('low', 'normal', 'high', 'urgent')) not valid;
    begin
      alter table "better_supabase"."notification_events" validate constraint "notification_events_priority_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."notification_events"', 'notification_events_priority_check', '"better_supabase"."notification_events"', 'notification_events_priority_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."notification_events" enable row level security;
revoke all on "better_supabase"."notification_events" from anon, authenticated;
grant select on "better_supabase"."notification_events" to authenticated;
grant all on "better_supabase"."notification_events" to service_role;

create table if not exists "better_supabase"."notification_recipients" (
  "id" uuid primary key default gen_random_uuid(),
  "event_id" uuid not null references "better_supabase"."notification_events" ("id") on delete cascade,
  "org_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "read_at" timestamptz,
  "dismissed_at" timestamptz,
  "resolved_at" timestamptz,
  "resolution" jsonb,
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
alter table "better_supabase"."notification_events" add column if not exists "actions" jsonb;
alter table "better_supabase"."notification_recipients" add column if not exists "resolution" jsonb;
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
revoke all on "better_supabase"."notification_recipients" from anon, authenticated;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bsb_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bsb_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_events_read" on "better_supabase"."notification_events";
create policy "bsb_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "recipient_id" uuid not null references "better_supabase"."notification_recipients" ("id") on delete cascade,
  "org_id" uuid,
  "channel" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'sent', 'failed', 'skipped')),
  "provider" text,
  "provider_message_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "attempted_at" timestamptz,
  "next_attempt_at" timestamptz not null default now(),
  "delivered_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("recipient_id", "channel")
);
create index if not exists notification_deliveries_pending_idx on "better_supabase"."notification_deliveries" ("channel", "created_at") where "status" = 'pending';
create index if not exists notification_deliveries_leased_idx on "better_supabase"."notification_deliveries" ("channel", "attempted_at") where "status" = 'pending' and "attempted_at" is not null;
alter table "better_supabase"."notification_deliveries" enable row level security;
revoke all on "better_supabase"."notification_deliveries" from anon, authenticated;
grant select on "better_supabase"."notification_deliveries" to authenticated;
grant all on "better_supabase"."notification_deliveries" to service_role;
drop policy if exists "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bsb_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  )
);

create table if not exists "better_supabase"."notification_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "level" text not null default 'participating' check ("level" in ('participating', 'all', 'ignore')),
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("org_id", "user_id", "subject_type", "subject_id")
);
create index if not exists notification_subscriptions_user_idx on "better_supabase"."notification_subscriptions" ("user_id");
create index if not exists notification_subscriptions_subject_idx on "better_supabase"."notification_subscriptions" ("org_id", "subject_type", "subject_id");
alter table "better_supabase"."notification_subscriptions" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_subscriptions";
create trigger bsb_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
revoke all on "better_supabase"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bsb_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
drop policy if exists "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_read" on "better_supabase"."notification_subscriptions" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_insert" on "better_supabase"."notification_subscriptions" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_update" on "better_supabase"."notification_subscriptions" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions";
create policy "bsb_notification_subscriptions_own_delete" on "better_supabase"."notification_subscriptions" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "org_id" uuid,
  "type" text not null,
  "channel" text not null,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "org_id", "type", "channel")
);
alter table "better_supabase"."notification_preferences" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."notification_preferences";
create trigger bsb_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
revoke all on "better_supabase"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bsb_notification_preferences_own" on "better_supabase"."notification_preferences";
drop policy if exists "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_read" on "better_supabase"."notification_preferences" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_insert" on "better_supabase"."notification_preferences" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_update" on "better_supabase"."notification_preferences" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences";
create policy "bsb_notification_preferences_own_delete" on "better_supabase"."notification_preferences" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."notification_suppressions" (
  "id" uuid primary key default gen_random_uuid(),
  "channel" text not null default 'email',
  "address" text not null check ("address" = lower("address")),
  "user_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" in ('bounce', 'complaint', 'manual')),
  "provider" text,
  "provider_event_id" text,
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now(),
  unique ("channel", "address")
);
create index if not exists notification_suppressions_user_idx on "better_supabase"."notification_suppressions" ("user_id");
alter table "better_supabase"."notification_suppressions" enable row level security;
revoke all on "better_supabase"."notification_suppressions" from anon, authenticated;
grant select on "better_supabase"."notification_suppressions" to authenticated;
grant all on "better_supabase"."notification_suppressions" to service_role;
drop policy if exists "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions";
create policy "bsb_notification_suppressions_read" on "better_supabase"."notification_suppressions" for select to authenticated using ("user_id" = (select auth.uid()));

alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "better_supabase"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "better_supabase"."notification_deliveries" add column if not exists "template_key" text;
create index if not exists notification_deliveries_provider_message_idx on "better_supabase"."notification_deliveries" ("provider", "provider_message_id") where "provider_message_id" is not null;

create table if not exists "better_supabase"."notification_delivery_events" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "org_id" uuid,
  "kind" text not null check ("kind" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained')),
  "provider" text,
  "provider_event_id" text unique,
  "occurred_at" timestamptz not null default now(),
  "detail" jsonb not null default '{}',
  "created_at" timestamptz not null default now()
);
create index if not exists notification_delivery_events_delivery_idx on "better_supabase"."notification_delivery_events" ("delivery_id", "occurred_at");
alter table "better_supabase"."notification_delivery_events" enable row level security;
revoke all on "better_supabase"."notification_delivery_events" from anon, authenticated;
grant select on "better_supabase"."notification_delivery_events" to authenticated;
grant all on "better_supabase"."notification_delivery_events" to service_role;
drop policy if exists "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events";
create policy "bsb_notification_delivery_events_read" on "better_supabase"."notification_delivery_events" for select to authenticated using (
  exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  )
);

-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function "better_supabase"."notification_enabled"(member uuid, tenant uuid, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p."enabled"
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."org_id" is null or p."org_id" = notification_enabled.tenant)
    order by p."org_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
$$;
revoke execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."notification_enabled"(uuid, uuid, text, text) to service_role;

-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function "better_supabase"."send_notification"(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."org_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."org_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null then
    raise exception 'This project has no permission audience' using errcode = '0A000', hint = 'NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE';
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."org_id" is null or p."org_id" = v_tenant)
      order by x, c, p."org_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."org_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "org_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."org_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "org_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "org_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function "better_supabase"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
create or replace function "better_supabase"."send_notifications"(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '"send_notifications" takes a jsonb array of events'
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception '"send_notifications" got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'NOTIFICATION_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := "better_supabase"."send_notification"(
        notification => batch_event
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('notification', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notification"(jsonb) to service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."notify"(jsonb) to service_role;
revoke execute on function "better_supabase"."send_notifications"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."send_notifications"(jsonb) to service_role;

drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);
drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);
drop function if exists "better_supabase"."mark_notifications_unread"(uuid[], uuid);
drop function if exists "better_supabase"."mark_notifications_read"(uuid[], uuid);
drop function if exists "better_supabase"."dismiss_notifications"(uuid[]);
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read or unresolved. Page with the last item's
-- created_at and id (before, before_id).
create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."org_id" = list_notifications.tenant)
      and (list_notifications.types is null or ev."type" = any(list_notifications.types))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."org_id" = notification_page.tenant)
      and (notification_page.types is null or ev."type" = any(notification_page.types))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function "better_supabase"."notification_counts"(tenant uuid default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc."read_at" is null),
    'actionable', count(*) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    ),
    'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."org_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end) filter (
      where rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
    )
  )
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."user_id" = auth.uid()
    and rc."dismissed_at" is null
    and (notification_counts.tenant is null or rc."org_id" = notification_counts.tenant)
$$;

create or replace function "better_supabase"."get_notification"(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."org_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."org_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null, resolution jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    raise exception 'resolution must be a JSON object' using errcode = '22023', hint = 'NOTIFICATION_RESOLUTION_INVALID';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now()), "resolution" = resolve_notifications.resolution
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."org_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase".notification_page(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) to authenticated, service_role;
revoke execute on function "better_supabase".notification_counts(uuid, text[]) from public, anon;
grant execute on function "better_supabase".notification_counts(uuid, text[]) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_unread(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".mark_notifications_read(uuid[], uuid) from public, anon;
grant execute on function "better_supabase".mark_notifications_read(uuid[], uuid) to authenticated, service_role;
revoke execute on function "better_supabase".dismiss_notifications(uuid[]) from public, anon;
grant execute on function "better_supabase".dismiss_notifications(uuid[]) to authenticated, service_role;
revoke execute on function "better_supabase".get_notification(uuid) from public, anon;
grant execute on function "better_supabase".get_notification(uuid) to authenticated, service_role;
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid, jsonb) to authenticated, service_role;

-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid);
create or replace function "better_supabase"."set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."org_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("org_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."org_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("org_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) to authenticated, service_role;

-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function "better_supabase"."set_notification_preference"(type text, channel text, enabled boolean, tenant uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."org_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "org_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$$;
revoke execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."set_notification_preference"(text, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_subscriptions"(tenant uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s."subject_type",
    'subject_id', s."subject_id",
    'level', s."level",
    'tenant', s."org_id",
    'created_at', s."created_at"
  ) order by s."created_at" desc, s."id"), '[]')
  from "better_supabase"."notification_subscriptions" s
  where s."user_id" = auth.uid()
    and (list_notification_subscriptions.tenant is null or s."org_id" = list_notification_subscriptions.tenant)
    and (list_notification_subscriptions.subject_type is null or s."subject_type" = list_notification_subscriptions.subject_type)
    and (list_notification_subscriptions.subject_id is null or s."subject_id" = list_notification_subscriptions.subject_id)
$$;
revoke execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_notification_subscriptions"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_notification_preferences"(tenant uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."org_id"
  ) order by p."org_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."org_id" is null or p."org_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function "better_supabase"."claim_notification_deliveries"(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'locale', null::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."org_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead. template_key
-- names the template the channel composed, for list_subject_deliveries.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5, template_key text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_status = 'pending' and exists (
    select 1 from "better_supabase"."notification_deliveries" d
    where d."id" = complete_notification_delivery.delivery
      and d."attempts" >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;
  update "better_supabase"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) to service_role;

-- Stops a channel from sending to an address after a bounce, a complaint
-- or by hand. The first suppression wins; returns whether it is new.
create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) to service_role;

create or replace function "better_supabase"."unsuppress_notification_address"(address text, channel text default 'email')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$$;
revoke execute on function "better_supabase"."unsuppress_notification_address"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unsuppress_notification_address"(text, text) to service_role;

-- The caller's suppressions, newest first; the service sees every row.
create or replace function "better_supabase"."list_notification_suppressions"(max_items integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$$;
revoke execute on function "better_supabase"."list_notification_suppressions"(integer) from public, anon;
grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;

-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function "better_supabase"."record_delivery_event"(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := record_delivery_event.kind;
  v_at timestamptz := coalesce(record_delivery_event.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_row uuid;
  v_email text;
begin
  if v_kind is null or not (v_kind = any(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[])) then
    raise exception 'kind must be delayed, delivered, opened, clicked, bounced, complained' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_EVENT_KIND';
  end if;
  if record_delivery_event.provider_message_id is null or btrim(record_delivery_event.provider_message_id) = '' then
    raise exception 'provider_message_id is required' using errcode = '22023', hint = 'NOTIFICATION_DELIVERY_MESSAGE_ID';
  end if;
  select d."id", d."channel", rc."user_id", ev."id", ev."type", d."org_id",
    coalesce(ev."subject_type", 'notification'),
    coalesce(ev."subject_id", ev."id"::text)
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where d."provider_message_id" = record_delivery_event.provider_message_id
    and (record_delivery_event.provider is null or d."provider" = record_delivery_event.provider)
  order by d."created_at" desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into "better_supabase"."notification_delivery_events" ("delivery_id", "org_id", "kind", "provider", "provider_event_id", "occurred_at", "detail")
  values (v_delivery, v_tenant, v_kind, record_delivery_event.provider, nullif(record_delivery_event.provider_event_id, ''), v_at, coalesce(record_delivery_event.detail, '{}'))
  on conflict ("provider_event_id") do nothing
  returning "id" into v_row;
  if v_row is not null then
    update "better_supabase"."notification_deliveries" d
    set "provider_status" = v_kind, "provider_status_at" = v_at
    where d."id" = v_delivery
      and coalesce(array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], d."provider_status"), 0) <= array_position(array['delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained']::text[], v_kind);
    if v_kind in ('bounced', 'complained') and coalesce(record_delivery_event.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform "better_supabase"."suppress_notification_address"(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          record_delivery_event.provider,
          record_delivery_event.provider_event_id,
          coalesce(record_delivery_event.detail, '{}')
        );
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', (select d."provider_status" from "better_supabase"."notification_deliveries" d where d."id" = v_delivery),
    'recorded', v_row is not null
  );
end;
$$;
revoke execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery_event"(text, text, text, text, timestamptz, jsonb, boolean) to service_role;

-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function "better_supabase"."list_subject_deliveries"(subject_type text, subject_id text, tenant uuid default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Not allowed to read this record''s deliveries' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object('id', d."id", 'notification_id', ev."id", 'type', ev."type", 'channel', d."channel", 'user_id', rc."user_id", 'status', d."status", 'provider_message_id', d."provider_message_id", 'created_at', d."created_at", 'provider', d."provider", 'provider_status', d."provider_status", 'provider_status_at', d."provider_status_at", 'template_key', d."template_key", 'error', d."error", 'attempts', d."attempts", 'delivered_at', d."delivered_at", 'events', (
        select coalesce(jsonb_agg(jsonb_build_object('kind', de."kind", 'occurred_at', de."occurred_at", 'detail', de."detail") order by de."occurred_at", de."created_at"), '[]')
        from "better_supabase"."notification_delivery_events" de where de."delivery_id" = d."id"
      )) as item,
        d."created_at" as created_at, d."id" as id
      from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where ev."subject_type" = list_subject_deliveries.subject_type
        and ev."subject_id" = list_subject_deliveries.subject_id
        and (list_subject_deliveries.tenant is null or ev."org_id" = list_subject_deliveries.tenant)
      order by d."created_at" desc, d."id" desc
      limit least(greatest(coalesce(list_subject_deliveries.max_items, 50), 1), 200)
    ) x
  );
end;
$$;
revoke execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) to service_role;

-- Deletes up to batch notifications past their retention, with their recipients
-- and deliveries, and returns how many. Run it until it returns less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$$;
revoke execute on function "better_supabase"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_notifications"(interval, integer) to service_role;

-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function "better_supabase"."broadcast_notification"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."org_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_events";
create policy bsb_tenant_scope on "better_supabase"."notification_events" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."event_id" = "better_supabase"."notification_events"."id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_recipients";
create policy bsb_tenant_scope on "better_supabase"."notification_recipients" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_deliveries";
create policy bsb_tenant_scope on "better_supabase"."notification_deliveries" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_recipients" r
    where r."id" = "better_supabase"."notification_deliveries"."recipient_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_delivery_events";
create policy bsb_tenant_scope on "better_supabase"."notification_delivery_events" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (
    select 1 from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" r on r."id" = d."recipient_id"
    where d."id" = "better_supabase"."notification_delivery_events"."delivery_id"
      and r."user_id" = (select auth.uid())
  ))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_subscriptions";
create policy bsb_tenant_scope on "better_supabase"."notification_subscriptions" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."notification_preferences";
create policy bsb_tenant_scope on "better_supabase"."notification_preferences" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_024_notifications.sql
-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
