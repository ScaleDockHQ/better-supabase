-- better-supabase module: notifications
-- @bsb-block notifications@8 adopt
-- In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
    from "centrakit"."notification_preferences" p
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
    else array['in_app', 'email']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_hash text;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if not (centrakit.authz_actor_may_write()) then
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
        select s."user_id" from "centrakit"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "centrakit"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null and v_tenant is null then
    raise exception 'A permission audience needs a tenant' using errcode = '22023', hint = 'NOTIFICATION_PERMISSION_NEEDS_TENANT';
  end if;
  if nullif(notification ->> 'permission', '') is not null then
    v_recipients := v_recipients || coalesce(array(select u from centrakit.authz_organization_users_with((notification ->> 'permission'), v_tenant) as t(u)), '{}');
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
      left join "centrakit"."notification_preferences" p
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

  -- Without a key column, a keyed event gets an id derived from the key.
  if v_key is null then
    v_event := gen_random_uuid();
  else
    v_hash := md5(coalesce(v_tenant::text, '') || ':' || v_key);
    select ev."id" into v_event from "centrakit"."notification_events" ev where ev."id" = v_hash::uuid;
    v_event := coalesce(v_event, overlay(overlay(v_hash placing '8' from 13 for 1) placing to_hex(8 | (('x' || substr(v_hash, 17, 1))::bit(4)::integer & 3)) from 17 for 1)::uuid);
  end if;
  insert into "centrakit"."notification_events" ("id", "type", "metadata", "organization_id", "actor_user_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "priority", "created_by")
  values (v_event, v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', v_priority, auth.uid())
  on conflict do nothing;

  insert into "centrakit"."notification_recipients" ("event_id", "organization_id", "recipient_user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "centrakit"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "centrakit"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."recipient_user_id"
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
  perform "better_supabase".emit_event('notification.created', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'recipientIds', to_jsonb(v_recipients)), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.created:' || v_event::text, 'domain');
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
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") as item, rc."created_at" as created_at, rc."id" as id
    from "centrakit"."notification_recipients" rc
    join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
    where rc."recipient_user_id" = auth.uid()
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
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") as item, rc."created_at" as created_at, rc."id" as id
    from "centrakit"."notification_recipients" rc
    join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
    where rc."recipient_user_id" = auth.uid()
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
  from "centrakit"."notification_recipients" rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
  where rc."recipient_user_id" = auth.uid()
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
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
  from "centrakit"."notification_recipients" rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."recipient_user_id" = auth.uid()
$$;

create or replace function "better_supabase"."mark_notifications_unread"(ids uuid[], tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (centrakit.authz_actor_may_write());

  with rc as (
    update "centrakit"."notification_recipients" rc set "read_at" = null
    where rc."recipient_user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."recipient_user_id" = auth.uid()), '[]')
  )
  from rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (centrakit.authz_actor_may_write());

  with rc as (
    update "centrakit"."notification_recipients" rc set "read_at" = now()
    where rc."recipient_user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."recipient_user_id" = auth.uid()), '[]')
  )
  from rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."dismiss_notifications"(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (centrakit.authz_actor_may_write());

  with rc as (
    update "centrakit"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."recipient_user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."recipient_user_id" = auth.uid()), '[]')
  )
  from rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, 'notifications.send'), false)) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  with rc as (
    update "centrakit"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now())
    from "centrakit"."notification_events" ev
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
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."recipient_user_id" = auth.uid()), '[]')
  )
  from rc
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
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
  select coalesce(jsonb_object_agg(pr."user_id"::text, jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")), '{}')
  from "centrakit"."profiles" pr
  where pr."user_id" = any(notification_actors.ids)
    and exists (
      select 1 from "centrakit"."notification_recipients" rc
      join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
      where rc."recipient_user_id" = auth.uid() and ev."actor_user_id" = pr."user_id"
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
  if not (centrakit.authz_actor_may_write()) then
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
      select 1 from "centrakit"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "centrakit"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "centrakit"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "centrakit"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_preference.tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.member_can(auth.uid(), set_notification_preference.tenant, 'notifications.read'), false) then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "centrakit"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "centrakit"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
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
  from "centrakit"."notification_subscriptions" s
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
  from "centrakit"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$$;
revoke execute on function "better_supabase"."list_notification_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_notification_preferences"(uuid) to authenticated, service_role;

drop function if exists "better_supabase"."claim_notification_deliveries"(text, integer, interval);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);
drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text);
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
  with picked as (
    select d."id" as id from "centrakit"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "centrakit"."notification_deliveries" d set "attempted_at" = now()
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', 1,
    'user_id', rc."recipient_user_id",
    'email', u.email,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."metadata", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_user_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
  )), '[]') into claimed
  from leased l
  join "centrakit"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "centrakit"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."recipient_user_id";
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
  update "centrakit"."notification_deliveries" d
  set "status" = v_status,
    "provider" = coalesce(complete_notification_delivery.provider, d."provider"),
    "provider_message_id" = coalesce(complete_notification_delivery.provider_message_id, d."provider_message_id"),
    "error" = complete_notification_delivery.error,
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) to service_role;
revoke execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) to service_role;



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
  delete from "centrakit"."notification_events"
  where "id" in (
    select ev."id" from "centrakit"."notification_events" ev
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
    'organization:' || new."organization_id"::text || ':notifications:' || new."recipient_user_id"::text,
    true
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_notification"() from public, anon, authenticated;
drop trigger if exists "bsb_notification_broadcast" on "centrakit"."notification_recipients";
drop trigger if exists "bsb_notification_broadcast_update" on "centrakit"."notification_recipients";
create trigger "bsb_notification_broadcast" after insert on "centrakit"."notification_recipients"
  for each row execute function "better_supabase"."broadcast_notification"();
create trigger "bsb_notification_broadcast_update" after update of "read_at", "dismissed_at", "resolved_at" on "centrakit"."notification_recipients"
  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")
  execute function "better_supabase"."broadcast_notification"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_notifications_receive" on realtime.messages;
    create policy "bsb_notifications_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'organization:' || '[^:]+' || ':notifications:' || (select auth.uid())::text || '$'));
  end if;
end;
$$;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
