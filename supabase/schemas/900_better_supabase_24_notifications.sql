-- better-supabase module: notifications (0.5.1)
-- @bs-module notifications@4 managed
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
  "delivered_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("event_id", "user_id")
);
create index if not exists notification_recipients_inbox_idx on "better_supabase"."notification_recipients" ("user_id", "created_at" desc) where "dismissed_at" is null;
create index if not exists notification_recipients_unread_idx on "better_supabase"."notification_recipients" ("user_id") where "read_at" is null and "dismissed_at" is null;
create index if not exists notification_recipients_user_idx on "better_supabase"."notification_recipients" ("user_id");
alter table "better_supabase"."notification_recipients" enable row level security;
revoke all on "better_supabase"."notification_recipients" from anon, authenticated;
grant select on "better_supabase"."notification_recipients" to authenticated;
grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;
grant all on "better_supabase"."notification_recipients" to service_role;
drop policy if exists "bs_notification_recipients_read" on "better_supabase"."notification_recipients";
create policy "bs_notification_recipients_read" on "better_supabase"."notification_recipients" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "bs_notification_recipients_update" on "better_supabase"."notification_recipients";
create policy "bs_notification_recipients_update" on "better_supabase"."notification_recipients" for update to authenticated using ("user_id" = (select auth.uid())) with check ("user_id" = (select auth.uid()));
drop policy if exists "bs_notification_events_read" on "better_supabase"."notification_events";
create policy "bs_notification_events_read" on "better_supabase"."notification_events" for select to authenticated using (
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
drop policy if exists "bs_notification_deliveries_read" on "better_supabase"."notification_deliveries";
create policy "bs_notification_deliveries_read" on "better_supabase"."notification_deliveries" for select to authenticated using (
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
drop trigger if exists bs_updated_at on "better_supabase"."notification_subscriptions";
create trigger bs_updated_at before update on "better_supabase"."notification_subscriptions"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_subscriptions" enable row level security;
revoke all on "better_supabase"."notification_subscriptions" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_subscriptions" to authenticated;
grant all on "better_supabase"."notification_subscriptions" to service_role;
drop policy if exists "bs_notification_subscriptions_own" on "better_supabase"."notification_subscriptions";
create policy "bs_notification_subscriptions_own" on "better_supabase"."notification_subscriptions" for all to authenticated using ("user_id" = (select auth.uid())) with check ("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read'))));

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
drop trigger if exists bs_updated_at on "better_supabase"."notification_preferences";
create trigger bs_updated_at before update on "better_supabase"."notification_preferences"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."notification_preferences" enable row level security;
revoke all on "better_supabase"."notification_preferences" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."notification_preferences" to authenticated;
grant all on "better_supabase"."notification_preferences" to service_role;
drop policy if exists "bs_notification_preferences_own" on "better_supabase"."notification_preferences";
create policy "bs_notification_preferences_own" on "better_supabase"."notification_preferences" for all to authenticated using ("user_id" = (select auth.uid())) with check ("user_id" = (select auth.uid()) and ("organization_id" is null or "organization_id" in (select better_supabase.tenant_ids_with('notifications.read'))));

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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, 'notifications.send'), false) then
      raise exception 'Not allowed to send notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
    end if;
    v_actor := auth.uid();
  end if;
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
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', v_priority, v_key, auth.uid())
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
revoke execute on function "better_supabase"."send_notification"(jsonb) from public, anon;
grant execute on function "better_supabase"."send_notification"(jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."notify"(jsonb) from public, anon;
grant execute on function "better_supabase"."notify"(jsonb) to authenticated, service_role;

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
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") as item, rc."created_at" as created_at, rc."id" as id
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
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") as item, rc."created_at" as created_at, rc."id" as id
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
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
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
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
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
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
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
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
create or replace function "better_supabase"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, 'notifications.send'), false)) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now())
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
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
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
revoke execute on function "better_supabase".resolve_notifications(text, text, text, uuid) from public, anon;
grant execute on function "better_supabase".resolve_notifications(text, text, text, uuid) to authenticated, service_role;
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
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id";
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead.
create or replace function "better_supabase"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5)
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
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) to service_role;

-- Deletes up to batch notifications older than older_than, with their
-- recipients and deliveries, and returns how many. Run it until it returns
-- less than batch.
create or replace function "better_supabase"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from "better_supabase"."notification_events"
    where "id" in (
      select ev."id" from "better_supabase"."notification_events" ev
      where ev."created_at" < now() - coalesce(older_than, '90 days')
      order by ev."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
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
drop trigger if exists "bs_notification_broadcast" on "better_supabase"."notification_recipients";
drop trigger if exists "bs_notification_broadcast_update" on "better_supabase"."notification_recipients";
create trigger "bs_notification_broadcast" after insert on "better_supabase"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bs_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_notifications_receive" on realtime.messages;
    create policy "bs_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

-- sql.modules.notifications.api: entry points for the Data API.
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
revoke execute on function "api"."send_notification"(jsonb) from public, anon;
grant execute on function "api"."send_notification"(jsonb) to authenticated, service_role;

create or replace function "api"."notify"(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify"($1) $$;
revoke execute on function "api"."notify"(jsonb) from public, anon;
grant execute on function "api"."notify"(jsonb) to authenticated, service_role;

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

create or replace function "api"."resolve_notifications"(type text, subject_type text, subject_id text, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_notifications"($1, $2, $3, $4) $$;
revoke execute on function "api"."resolve_notifications"(text, text, text, uuid) from public, anon;
grant execute on function "api"."resolve_notifications"(text, text, text, uuid) to authenticated, service_role;

create or replace function "api"."notification_actors"(ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notification_actors"($1) $$;
revoke execute on function "api"."notification_actors"(uuid[]) from public, anon;
grant execute on function "api"."notification_actors"(uuid[]) to authenticated, service_role;

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

create or replace function "api"."complete_notification_delivery"(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_notification_delivery"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."complete_notification_delivery"(uuid, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function "api"."complete_notification_delivery"(uuid, text, text, text, text, integer) to service_role;

create or replace function "api"."purge_notifications"(older_than interval default '90 days', batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_notifications"($1, $2) $$;
revoke execute on function "api"."purge_notifications"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_notifications"(interval, integer) to service_role;

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
