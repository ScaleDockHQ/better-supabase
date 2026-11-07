SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.claim_notification_deliveries (
  channel      text,
  max_items    integer  DEFAULT 50,
  lease        interval DEFAULT '00:05:00'::interval,
  max_attempts integer  DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    'email', coalesce("better_supabase"."member_address"(rc."user_id", l."channel"), u.email),
    'locale', pr."locale"::text,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."profiles" pr on pr."id" = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(coalesce("better_supabase"."member_address"(rc."user_id", l."channel"), u.email));
  return claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_notification_digests (
  max_items    integer  DEFAULT 50,
  lease        interval DEFAULT '00:05:00'::interval,
  max_attempts integer  DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  claimed jsonb;
begin
  update "better_supabase"."notification_digests" x set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where x."status" = 'pending' and x."attempts" >= greatest(1, coalesce(claim_notification_digests.max_attempts, 5))
    and x."attempted_at" < now() - claim_notification_digests.lease;
  with picked as (
    select x."id" as id from "better_supabase"."notification_digests" x
    where x."status" = 'pending'
      and (x."attempted_at" is null or x."attempted_at" < now() - claim_notification_digests.lease)
    order by x."created_at"
    limit claim_notification_digests.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_digests" x set "attempted_at" = now(), "attempts" = x."attempts" + 1
    from picked where x."id" = picked.id
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'digest_id', l."id",
    'user_id', l."user_id",
    'email', coalesce("better_supabase"."member_address"(l."user_id", l."channel"), u.email),
    'channel', l."channel",
    'cadence', l."cadence",
    'tenant', l."organization_id",
    'item_count', l."item_count",
    'items', l."items"
  )), '[]') into claimed
  from leased l left join auth.users u on u.id = l."user_id";
  return claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_address (
  p_user    uuid,
  p_channel text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case when p_channel = 'email' then 'work.' || u.email end
  from auth.users as u
  where u.id = p_user;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_delivery_event (
  provider            text,
  provider_message_id text,
  kind                text,
  provider_event_id   text                     DEFAULT NULL::text,
  occurred_at         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  detail              jsonb                    DEFAULT '{}'::jsonb,
  suppress            boolean                  DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
      select coalesce("better_supabase"."member_address"(v_user, v_channel), u.email) into v_email from auth.users u where u.id = v_user;
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
$function$;

CREATE TRIGGER bsb_realtime_delete AFTER DELETE ON better_supabase.maintenance_requests
  REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

CREATE TRIGGER bsb_realtime_insert AFTER INSERT ON better_supabase.maintenance_requests
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

CREATE TRIGGER bsb_realtime_update AFTER UPDATE ON better_supabase.maintenance_requests
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

CREATE TRIGGER bsb_realtime_delete AFTER DELETE ON better_supabase.work_items
  REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

CREATE TRIGGER bsb_realtime_insert AFTER INSERT ON better_supabase.work_items
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

CREATE TRIGGER bsb_realtime_update AFTER UPDATE ON better_supabase.work_items
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes (
  'tenant_id',
  'tenant'
);

REVOKE ALL ON FUNCTION "better_supabase"."member_address"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_address"(uuid, text) TO "service_role";
