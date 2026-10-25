SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope" ON "better_supabase"."shared_views";

DROP POLICY "saved_views_read" ON "better_supabase"."shared_views";

DROP FUNCTION "api"."resolve_notifications"(text, text, text, uuid);

DROP FUNCTION "better_supabase"."team_ids_of"(uuid);

CREATE TABLE "better_supabase"."push_tickets" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "delivery_id" uuid                     NOT NULL,
  "token"       text                     NOT NULL,
  "ticket_id"   text,
  "status"      text                     NOT NULL DEFAULT 'pending'::text,
  "error"       text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "checked_at"  timestamp with time zone,
  CONSTRAINT "push_tickets_delivery_id_token_key" UNIQUE (delivery_id, token),
  CONSTRAINT "push_tickets_pkey" PRIMARY KEY (id),
  CONSTRAINT "push_tickets_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'ok'::text, 'error'::text])))
);

ALTER TABLE "better_supabase"."push_tickets"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."notification_events"
  ADD COLUMN "actions" jsonb;

ALTER TABLE "better_supabase"."notification_recipients"
  ADD COLUMN "resolution" jsonb;

ALTER TABLE "better_supabase"."profiles"
  ADD COLUMN "locale" text;

CREATE OR REPLACE FUNCTION api.complete_push_receipts (
  receipts jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_push_receipts"($1) $function$;

CREATE OR REPLACE FUNCTION api.push_tickets_for (
  delivery uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."push_tickets_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.record_push_tickets (
  delivery uuid,
  tickets  jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_push_tickets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.resolve_notifications (
  type         text,
  subject_type text,
  subject_id   text,
  tenant       uuid  DEFAULT NULL::uuid,
  resolution   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_notifications"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.unchecked_push_tickets (
  max_items  integer  DEFAULT 1000,
  older_than interval DEFAULT '00:15:00'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unchecked_push_tickets"($1, $2) $function$;

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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_push_receipts (
  receipts jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if jsonb_typeof(complete_push_receipts.receipts) <> 'array' or jsonb_array_length(complete_push_receipts.receipts) > 1000 then
    raise exception 'pass at most 1000 receipts' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  -- The delivery's provider message id is Expo's first ticket id, so every
  -- receipt of the delivery records its event on that message, once per
  -- ticket.
  perform "better_supabase"."record_delivery_event"(
    'expo',
    d."provider_message_id",
    case when r ->> 'status' = 'ok' then 'delivered' else 'bounced' end,
    'expo-receipt:' || (r ->> 'id'),
    now(),
    jsonb_strip_nulls(jsonb_build_object('token', x."token", 'error', r ->> 'error', 'message', r ->> 'message')),
    false
  )
  from "better_supabase"."push_tickets" x
  join "better_supabase"."notification_deliveries" d on d."id" = x."delivery_id"
  cross join jsonb_array_elements(complete_push_receipts.receipts) r
  where x."ticket_id" = r ->> 'id'
    and x."checked_at" is null
    and d."provider_message_id" is not null;
  update "better_supabase"."push_tickets" x set
    "status" = case when r ->> 'status' = 'ok' then 'ok' else 'error' end,
    "error" = case when r ->> 'status' = 'ok' then null else coalesce(r ->> 'error', 'Unknown') end,
    "checked_at" = now()
  from jsonb_array_elements(complete_push_receipts.receipts) r
  where x."ticket_id" = r ->> 'id'
    and x."checked_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
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
  select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution")
  from "better_supabase"."notification_recipients" rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where rc."id" = get_notification.id
    and rc."user_id" = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_member (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval,
  prefill       jsonb    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  created "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    raise exception 'Platform invitations need platform roles: blocks.permissions.model ''catalog'' with platform assignments, or blocks.invitations.options.platformRoles under ''provider''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
  end if;
  invitee_role := coalesce(invitee_role, 'member');
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, (invitee_role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
  delete from "better_supabase"."invitations" i
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role"), 'invitations/' || created."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => created."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role")
  );
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = created."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(created."id"));
end;
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mirror_profile_email()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."profiles" set "email" = lower(new.email) where "id" = new.id and "email" is distinct from lower(new.email);
  return new;
end;
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_tickets_for (
  delivery uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'token', x."token",
      'id', x."ticket_id",
      'error', x."error"
    )) order by x."created_at", x."token"), '[]'::jsonb)
    from "better_supabase"."push_tickets" x
    where x."delivery_id" = push_tickets_for.delivery
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_push_tickets (
  delivery uuid,
  tickets  jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if jsonb_typeof(record_push_tickets.tickets) <> 'array' or jsonb_array_length(record_push_tickets.tickets) > 1000 then
    raise exception 'pass at most 1000 tickets' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  insert into "better_supabase"."push_tickets" as x ("delivery_id", "token", "ticket_id", "status", "error")
  select record_push_tickets.delivery, e ->> 'token', e ->> 'id',
    case when e ->> 'id' is null then 'error' else 'pending' end,
    e ->> 'error'
  from jsonb_array_elements(record_push_tickets.tickets) e
  where e ->> 'token' is not null
  on conflict ("delivery_id", "token") do update set
    "ticket_id" = coalesce(excluded."ticket_id", x."ticket_id"),
    "status" = case when x."ticket_id" is not null then x."status" else excluded."status" end,
    "error" = case
      when x."ticket_id" is not null then x."error"
      when excluded."ticket_id" is not null then null
      else excluded."error"
    end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_ip()
  RETURNS inet
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return nullif(trim(reverse(split_part(reverse(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for'), ',', 1))), '')::inet;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_notifications (
  type         text,
  subject_type text,
  subject_id   text,
  tenant       uuid  DEFAULT NULL::uuid,
  resolution   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
      from "public"."memberships" m
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_profile (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), lower(u.email), "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.team_ids_of (
  member uuid
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.role()), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unchecked_push_tickets (
  max_items  integer  DEFAULT 1000,
  older_than interval DEFAULT '00:15:00'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."ticket_id",
      'token', x."token",
      'deliveryId', x."delivery_id"
    ) order by x."created_at"), '[]'::jsonb)
    from (
      select * from "better_supabase"."push_tickets" y
      where y."checked_at" is null
        and y."ticket_id" is not null
        and y."created_at" <= now() - unchecked_push_tickets.older_than
      order by y."created_at"
      limit least(greatest(coalesce(unchecked_push_tickets.max_items, 1000), 1), 1000)
    ) x
  );
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
    "locale" = case when update_my_profile.attrs ? 'locale' then update_my_profile.attrs ->> 'locale' else p."locale" end,
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

ALTER TABLE "better_supabase"."push_tickets"
  ADD CONSTRAINT "push_tickets_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES better_supabase.notification_deliveries(id) ON DELETE CASCADE;

CREATE INDEX push_tickets_unchecked_idx ON better_supabase.push_tickets USING btree (created_at)
  WHERE ((checked_at IS NULL) AND (ticket_id IS NOT NULL));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shared_views"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('views.read'::text)
    AS tenant_ids_with)) AND (((scope = 'user'::text) AND (owner_id = ( SELECT auth.uid() AS uid))) OR ((scope = 'team'::text) AND (team_id IN ( SELECT (t.t)::text AS t
   FROM better_supabase.team_ids_of(( SELECT auth.uid() AS uid)) t(t)))) OR (scope = 'tenant'::text)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "saved_views_read" ON "better_supabase"."shared_views"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('views.read'::text) AS tenant_ids_with)) AND (((scope = 'user'::text) AND (owner_id = ( SELECT auth.uid() AS uid))) OR
    ((scope = 'team'::text) AND (team_id IN ( SELECT (t.t)::text AS t
   FROM better_supabase.team_ids_of(( SELECT auth.uid() AS uid)) t(t)))) OR (scope = 'tenant'::text))));

REVOKE ALL ON FUNCTION "api"."complete_push_receipts"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_push_receipts"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."push_tickets_for"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."push_tickets_for"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_push_tickets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_push_tickets"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_notifications"(text, text, text, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_notifications"(text, text, text, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."unchecked_push_tickets"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unchecked_push_tickets"(integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_push_receipts"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_push_receipts"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."push_tickets_for"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."push_tickets_for"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_push_tickets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_push_tickets"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_notifications"(text, text, text, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_notifications"(text, text, text, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."team_ids_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."team_ids_of"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unchecked_push_tickets"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unchecked_push_tickets"(integer, interval) TO "service_role";

REVOKE ALL ("locale") ON TABLE "better_supabase"."profiles" FROM "authenticated";

GRANT UPDATE ("locale") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."push_tickets" TO "service_role";
