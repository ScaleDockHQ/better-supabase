SET local check_function_bodies = off;

ALTER TABLE "public"."notifications"
  DROP CONSTRAINT "notifications_organization_id_fkey";

ALTER TABLE "public"."notifications"
  DROP CONSTRAINT "notifications_user_id_fkey";

DROP TABLE "public"."notifications";

CREATE TABLE "better_supabase"."notification_deliveries" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "recipient_id"        uuid                     NOT NULL,
  "organization_id"     uuid,
  "channel"             text                     NOT NULL,
  "status"              text                     NOT NULL DEFAULT 'pending'::text,
  "provider"            text,
  "provider_message_id" text,
  "error"               text,
  "attempts"            integer                  NOT NULL DEFAULT 0,
  "attempted_at"        timestamp with time zone,
  "next_attempt_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "delivered_at"        timestamp with time zone,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY (id),
  CONSTRAINT "notification_deliveries_recipient_id_channel_key" UNIQUE (recipient_id, channel),
  CONSTRAINT "notification_deliveries_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'skipped'::text])))
);

ALTER TABLE "better_supabase"."notification_deliveries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."notification_events" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid,
  "type"            text                     NOT NULL,
  "actor_id"        uuid,
  "subject_type"    text,
  "subject_id"      text,
  "subject_label"   text,
  "summary"         text,
  "action_path"     text,
  "priority"        text                     NOT NULL DEFAULT 'normal'::text,
  "data"            jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "idempotency_key" text,
  "created_by"      uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_events_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."notification_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."notification_preferences" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"         uuid                     NOT NULL,
  "organization_id" uuid,
  "type"            text                     NOT NULL,
  "channel"         text                     NOT NULL,
  "enabled"         boolean                  NOT NULL DEFAULT true,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_preferences_pkey" PRIMARY KEY (id),
  CONSTRAINT "notification_preferences_user_id_organization_id_type_chann_key" UNIQUE NULLS NOT DISTINCT (user_id, organization_id, TYPE, channel)
);

ALTER TABLE "better_supabase"."notification_preferences"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."notification_recipients" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "event_id"        uuid                     NOT NULL,
  "organization_id" uuid,
  "user_id"         uuid                     NOT NULL,
  "read_at"         timestamp with time zone,
  "dismissed_at"    timestamp with time zone,
  "resolved_at"     timestamp with time zone,
  "delivered_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_recipients_event_id_user_id_key" UNIQUE (event_id, user_id),
  CONSTRAINT "notification_recipients_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."notification_recipients"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."notification_subscriptions" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid,
  "user_id"         uuid                     NOT NULL,
  "subject_type"    text                     NOT NULL,
  "subject_id"      text                     NOT NULL,
  "level"           text                     NOT NULL DEFAULT 'participating'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_subscriptions_level_check" CHECK ((level = ANY (ARRAY['participating'::text, 'all'::text, 'ignore'::text]))),
  CONSTRAINT "notification_subscriptions_organization_id_user_id_subject__key" UNIQUE NULLS NOT DISTINCT (organization_id, user_id, subject_type, subject_id),
  CONSTRAINT "notification_subscriptions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."notification_subscriptions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.claim_notification_deliveries (
  channel      text,
  max_items    integer  DEFAULT 50,
  lease        interval DEFAULT '00:05:00'::interval,
  max_attempts integer  DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_notification_deliveries"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.complete_notification_delivery (
  delivery            uuid,
  status              text,
  provider            text    DEFAULT NULL::text,
  provider_message_id text    DEFAULT NULL::text,
  error               text    DEFAULT NULL::text,
  max_attempts        integer DEFAULT 5
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_notification_delivery"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.dismiss_notifications (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."dismiss_notifications"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_notification (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_notification"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_notification_preferences (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_preferences"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_notification_subscriptions (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_subscriptions"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_notifications (
  tenant        uuid                     DEFAULT NULL::uuid,
  status        text                     DEFAULT 'all'::text,
  types         text[]                   DEFAULT NULL::text[],
  before        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_items     integer                  DEFAULT 50,
  before_id     uuid                     DEFAULT NULL::uuid,
  subject_types text[]                   DEFAULT NULL::text[],
  search        text                     DEFAULT NULL::text,
  read          boolean                  DEFAULT NULL::boolean,
  resolved      boolean                  DEFAULT NULL::boolean,
  dismissed     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notifications"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $function$;

CREATE OR REPLACE FUNCTION api.mark_notifications_read (
  ids    uuid[] DEFAULT NULL::uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_notifications_read"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.mark_notifications_unread (
  ids    uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_notifications_unread"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.notification_actors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_actors"($1) $function$;

CREATE OR REPLACE FUNCTION api.notification_counts (
  tenant     uuid   DEFAULT NULL::uuid,
  actionable text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_counts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.notification_enabled (
  member  uuid,
  tenant  uuid,
  type    text,
  channel text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_enabled"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.notification_page (
  tenant        uuid    DEFAULT NULL::uuid,
  status        text    DEFAULT 'all'::text,
  types         text[]  DEFAULT NULL::text[],
  subject_types text[]  DEFAULT NULL::text[],
  search        text    DEFAULT NULL::text,
  max_items     integer DEFAULT 50,
  skip          integer DEFAULT 0,
  read          boolean DEFAULT NULL::boolean,
  resolved      boolean DEFAULT NULL::boolean,
  dismissed     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_page"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.notify (
  notification jsonb
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notify"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_notifications (
  older_than interval DEFAULT '90 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_notifications"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.resolve_notifications (
  type         text,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_notifications"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.send_notification (
  notification jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."send_notification"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_notification_preference (
  type    text,
  channel text,
  enabled boolean,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_notification_preference"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_notification_subscription (
  subject_type text,
  subject_id   text,
  level        text,
  tenant       uuid    DEFAULT NULL::uuid,
  member       uuid    DEFAULT NULL::uuid,
  if_absent    boolean DEFAULT false
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_notification_subscription"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_notification()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform realtime.send(
    jsonb_build_object('id', new."id", 'event_id', new."event_id", 'operation', lower(tg_op), 'tenant', new."organization_id"),
    case when tg_op = 'INSERT' then 'notification_created' else 'notification_updated' end,
    'notifications:' || new."user_id"::text,
    true
  );
  return null;
end;
$function$;

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
    'email', u.email,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id";
  return claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    null;
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
  );
  if tg_op = 'INSERT' then
    null;
  end if;
  if cardinality(v_new) > 0 then
    null;
  end if;
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new."organization_id",
      'actor', new."author_id",
      'subject_type', new."subject_type",
      'subject_id', new."subject_id",
      'summary', left(new."body", 140),
      'subject_label', null::text,
      'action_path', null::text,
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_notification_delivery (
  delivery            uuid,
  status              text,
  provider            text    DEFAULT NULL::text,
  provider_message_id text    DEFAULT NULL::text,
  error               text    DEFAULT NULL::text,
  max_attempts        integer DEFAULT 5
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dismiss_notifications (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_notification (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notification_preferences (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p."type",
    'channel', p."channel",
    'enabled', p."enabled",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notification_subscriptions (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notifications (
  tenant        uuid                     DEFAULT NULL::uuid,
  status        text                     DEFAULT 'all'::text,
  types         text[]                   DEFAULT NULL::text[],
  before        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_items     integer                  DEFAULT 50,
  before_id     uuid                     DEFAULT NULL::uuid,
  subject_types text[]                   DEFAULT NULL::text[],
  search        text                     DEFAULT NULL::text,
  read          boolean                  DEFAULT NULL::boolean,
  resolved      boolean                  DEFAULT NULL::boolean,
  dismissed     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_notifications_read (
  ids    uuid[] DEFAULT NULL::uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_notifications_unread (
  ids    uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_actors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(pr."id"::text, jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url", 'avatarPath', pr."avatar_path")), '{}')
  from "better_supabase"."profiles" pr
  where pr."id" = any(notification_actors.ids)
    and exists (
      select 1 from "better_supabase"."notification_recipients" rc
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where rc."user_id" = auth.uid() and ev."actor_id" = pr."id"
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_counts (
  tenant     uuid   DEFAULT NULL::uuid,
  actionable text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_enabled (
  member  uuid,
  tenant  uuid,
  type    text,
  channel text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_page (
  tenant        uuid    DEFAULT NULL::uuid,
  status        text    DEFAULT 'all'::text,
  types         text[]  DEFAULT NULL::text[],
  subject_types text[]  DEFAULT NULL::text[],
  search        text    DEFAULT NULL::text,
  max_items     integer DEFAULT 50,
  skip          integer DEFAULT 0,
  read          boolean DEFAULT NULL::boolean,
  resolved      boolean DEFAULT NULL::boolean,
  dismissed     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify (
  notification jsonb
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_notifications (
  older_than interval DEFAULT '90 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_notifications (
  type         text,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read'
    ]
    else array[]::text[]
  end
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_notification_preference (
  type    text,
  channel text,
  enabled boolean,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_notification_subscription (
  subject_type text,
  subject_id   text,
  level        text,
  tenant       uuid    DEFAULT NULL::uuid,
  member       uuid    DEFAULT NULL::uuid,
  if_absent    boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "better_supabase"."notification_events"
  ADD CONSTRAINT "notification_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."notification_events"
  ADD CONSTRAINT "notification_events_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."notification_preferences"
  ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."notification_recipients"
  ADD CONSTRAINT "notification_recipients_event_id_fkey" FOREIGN KEY (event_id) REFERENCES better_supabase.notification_events(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD CONSTRAINT "notification_deliveries_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES better_supabase.notification_recipients(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."notification_recipients"
  ADD CONSTRAINT "notification_recipients_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."notification_subscriptions"
  ADD CONSTRAINT "notification_subscriptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX notification_deliveries_leased_idx ON better_supabase.notification_deliveries USING btree (channel, attempted_at)
  WHERE ((status = 'pending'::text) AND (attempted_at IS NOT NULL));

CREATE INDEX notification_deliveries_pending_idx ON better_supabase.notification_deliveries USING btree (channel, created_at)
  WHERE (status = 'pending'::text);

CREATE INDEX notification_events_actor_idx ON better_supabase.notification_events USING btree (actor_id);

CREATE INDEX notification_events_created_at_idx ON better_supabase.notification_events USING btree (created_at);

CREATE INDEX notification_events_created_by_idx ON better_supabase.notification_events USING btree (created_by);

CREATE UNIQUE INDEX notification_events_key_idx ON better_supabase.notification_events USING btree (idempotency_key, organization_id) NULLS NOT DISTINCT
  WHERE (idempotency_key IS NOT NULL);

CREATE INDEX notification_events_subject_idx ON better_supabase.notification_events USING btree (subject_type, subject_id);

CREATE INDEX notification_recipients_inbox_idx ON better_supabase.notification_recipients USING btree (user_id, created_at DESC)
  WHERE (dismissed_at IS NULL);

CREATE INDEX notification_recipients_unread_idx ON better_supabase.notification_recipients USING btree (user_id)
  WHERE ((read_at IS NULL) AND (dismissed_at IS NULL));

CREATE INDEX notification_recipients_user_idx ON better_supabase.notification_recipients USING btree (user_id);

CREATE INDEX notification_subscriptions_subject_idx ON better_supabase.notification_subscriptions USING btree (organization_id, subject_type, subject_id);

CREATE INDEX notification_subscriptions_user_idx ON better_supabase.notification_subscriptions USING btree (user_id);

CREATE TRIGGER bs_comments_after_write
  AFTER INSERT OR UPDATE OF mentions, deleted_at ON better_supabase.comments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_after_write();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bs_notification_broadcast_update
  AFTER UPDATE OF read_at, dismissed_at, resolved_at ON better_supabase.notification_recipients
  FOR EACH ROW
  WHEN (((old.read_at IS DISTINCT FROM new.read_at) OR (old.dismissed_at IS DISTINCT FROM new.dismissed_at) OR (old.resolved_at IS DISTINCT FROM new.resolved_at)))
  EXECUTE FUNCTION better_supabase.broadcast_notification();

CREATE TRIGGER bs_notification_broadcast
  AFTER INSERT ON better_supabase.notification_recipients
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.broadcast_notification();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.notification_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE POLICY "bs_notification_deliveries_read" ON "better_supabase"."notification_deliveries"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.id = notification_deliveries.recipient_id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "bs_notification_events_read" ON "better_supabase"."notification_events"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.event_id = notification_events.id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "bs_notification_preferences_own" ON "better_supabase"."notification_preferences"
  FOR ALL
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with)))));

CREATE POLICY "bs_notification_recipients_read" ON "better_supabase"."notification_recipients"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_notification_recipients_update" ON "better_supabase"."notification_recipients"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_notification_subscriptions_own" ON "better_supabase"."notification_subscriptions"
  FOR ALL
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with)))));

CREATE POLICY "bs_notifications_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~ ((('^'::text || 'notifications:'::text) || (( SELECT auth.uid() AS uid))::text) || '$'::text))));

REVOKE ALL ON FUNCTION "api"."claim_notification_deliveries"(text, integer, interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_notification_deliveries"(text, integer, interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."complete_notification_delivery"(uuid, text, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_notification_delivery"(uuid, text, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."dismiss_notifications"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."dismiss_notifications"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_notification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_notification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_notification_preferences"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_notification_preferences"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_notification_subscriptions"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_notification_subscriptions"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_notifications_read"(uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_notifications_read"(uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_notifications_unread"(uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_notifications_unread"(uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_actors"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_actors"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_counts"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_counts"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_enabled"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_enabled"(uuid, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notify"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notify"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_notifications"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_notifications"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_notifications"(text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_notifications"(text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."send_notification"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."send_notification"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_notification_preference"(text, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_notification_preference"(text, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."broadcast_notification"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_notification_deliveries"(text, integer, interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comments_after_write"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."dismiss_notifications"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."dismiss_notifications"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_notification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_notification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notification_preferences"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_notification_preferences"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notification_subscriptions"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_notification_subscriptions"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_notifications_read"(uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_notifications_read"(uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_notifications_unread"(uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_notifications_unread"(uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_actors"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_actors"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_counts"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_counts"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_enabled"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_enabled"(uuid, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notify"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notify"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_notifications"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_notifications"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_notifications"(text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_notifications"(text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."send_notification"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."send_notification"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_notification_preference"(text, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_notification_preference"(text, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_notification_subscription"(text, text, text, uuid, uuid, boolean) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."notification_deliveries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_deliveries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."notification_events" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_events" TO "service_role";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "better_supabase"."notification_preferences" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_preferences" TO "service_role";

GRANT UPDATE ("dismissed_at") ON TABLE "better_supabase"."notification_recipients" TO "authenticated";

GRANT UPDATE ("read_at") ON TABLE "better_supabase"."notification_recipients" TO "authenticated";

GRANT SELECT ON TABLE "better_supabase"."notification_recipients" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_recipients" TO "service_role";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "better_supabase"."notification_subscriptions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_subscriptions" TO "service_role";
