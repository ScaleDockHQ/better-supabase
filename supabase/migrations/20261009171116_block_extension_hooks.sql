SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.send_notification (
  notification jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.updated',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', auth.uid())
  );
  return true;
end;
$function$;
