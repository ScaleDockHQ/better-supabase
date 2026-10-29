SET local check_function_bodies = off;

DROP FUNCTION "api"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer);

DROP FUNCTION "api"."resolve_share_link"(text);

DROP FUNCTION "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."resolve_share_link"(text);

ALTER TABLE "better_supabase"."share_links"
  ADD COLUMN "password_hash" text;

ALTER TABLE "better_supabase"."share_links"
  ADD COLUMN "download_allowed" boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION api.create_share_link (
  tenant           uuid,
  subject_type     text,
  subject_id       text,
  role             text,
  version_id       uuid                     DEFAULT NULL::uuid,
  expires_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_uses         integer                  DEFAULT NULL::integer,
  password         text                     DEFAULT NULL::text,
  download_allowed boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_share_link"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.resolve_share_link (
  token    text,
  password text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_share_link"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_feed (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_tenant uuid;
  v_calendar uuid;
  v_creator uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select l."id", l."subject_id", l."tenant_id", l."created_by" into v_link, v_subject, v_tenant, v_creator
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(calendar_feed.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'calendar'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null
  for update;
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  if v_creator is null or not coalesce(better_supabase.can_user(v_creator, 'tenant', v_tenant, 'calendar.read'), false) then
    return null;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link;
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color"),
      'organization', jsonb_build_object('id', v_tenant, 'name', (select g."name" from "public"."organizations" g where g."id" = v_tenant)),
      'createdBy', v_creator,
      'events', coalesce((
      select jsonb_agg(f.item order by f.starts)
      from (
        select (jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) - 'alarms') || jsonb_build_object('reminders', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = v_creator)), '[]'::jsonb) || coalesce((select jsonb_agg(jsonb_build_object('method', r."method", 'offsetMinutes', r."offset_minutes") order by r."offset_minutes") from "better_supabase"."reminders" r where r."subject_type" = 'calendar_event' and r."subject_id" = e."id"::text and r."user_id" = v_creator), '[]'::jsonb)) as item, e."starts_at" as starts
        from "better_supabase"."calendar_events" e
        join "better_supabase"."calendars" k on k."id" = e."calendar_id"
        where k."id" = v_calendar
          and (e."rrule" is not null or e."ends_at" > now() - interval '366 days')
          and true
        order by e."starts_at"
        limit 5000
      ) f
    ), '[]'::jsonb)
    )
    from "better_supabase"."calendars" k where k."id" = v_calendar and k."tenant_id" = v_tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_share_link (
  tenant           uuid,
  subject_type     text,
  subject_id       text,
  role             text,
  version_id       uuid                     DEFAULT NULL::uuid,
  expires_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_uses         integer                  DEFAULT NULL::integer,
  password         text                     DEFAULT NULL::text,
  download_allowed boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_subject_ok boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_share_link.tenant, 'share_links.create'), false)) then
    raise exception 'not allowed to share' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'SHARE_EXPIRY_INVALID';
  end if;
  if create_share_link.max_uses is not null and create_share_link.max_uses < 1 then
    raise exception 'max_uses must be at least 1' using errcode = '22023', hint = 'SHARE_MAX_USES_INVALID';
  end if;
  if create_share_link.password is not null and char_length(create_share_link.password) < 8 then
    raise exception 'a link password needs at least 8 characters' using errcode = '22023', hint = 'SHARE_LINK_PASSWORD_INVALID';
  end if;

  if coalesce(create_share_link.role, 'view') <> all (case create_share_link.subject_type
    when 'ai-chat' then array['view']::text[]
    when 'calendar' then array['view']::text[]
    when 'booking_service' then array['view']::text[]
    when 'drive_node' then array['view']::text[]
    when 'form' then array['respond']::text[]
    else array[coalesce(create_share_link.role, 'view')]
  end) then
    raise exception 'this subject type''s links can''t carry that role' using errcode = '22023', hint = 'SHARE_LINK_ROLE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    v_subject_ok := case create_share_link.subject_type
    when 'ai-chat' then exists (select 1 from "better_supabase".ai_chats s where s.id::text = create_share_link.subject_id and s.organization_id::text = create_share_link.tenant::text and s.owner_id = auth.uid())
    when 'calendar' then exists (select 1 from "better_supabase"."calendars" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'booking_service' then exists (select 1 from "better_supabase"."booking_services" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    else case create_share_link.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'customers.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    else null
  end
  end;
    if v_subject_ok is null then
      raise exception 'this subject type can''t be shared' using errcode = '22023', hint = 'SHARE_SUBJECT_UNKNOWN';
    end if;
    if not v_subject_ok then
      raise exception 'the subject does not exist in this organization' using errcode = 'P0002', hint = 'SHARE_SUBJECT_NOT_FOUND';
    end if;
  end if;
  if create_share_link.version_id is not null then
    declare
      v_version jsonb := "better_supabase"."get_version"(create_share_link.version_id);
    begin
      if v_version ->> 'subjectType' is distinct from create_share_link.subject_type
        or v_version ->> 'subjectId' is distinct from create_share_link.subject_id then
        raise exception 'the version belongs to another subject' using errcode = '22023', hint = 'SHARE_VERSION_INVALID';
      end if;
    end;
  end if;
  if create_share_link.subject_type in ('calendar') then
    update "better_supabase"."share_links" x set "revoked_at" = now()
    where x."tenant_id" = create_share_link.tenant and x."subject_type" = create_share_link.subject_type
      and x."subject_id" = create_share_link.subject_id and x."created_by" is not distinct from auth.uid() and x."revoked_at" is null;
  end if;
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "expires_at", "max_uses", "created_by", "version_id", "password_hash", "download_allowed")
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid(), create_share_link.version_id, case when create_share_link.password is not null then extensions.crypt(create_share_link.password, extensions.gen_salt('bf')) end, coalesce(create_share_link.download_allowed, true))
  returning "id" into v_id;
  perform "better_supabase".emit_event('share_link.created', jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id), 'share-links/' || v_id::text, (create_share_link.tenant)::text, null, 'better-supabase/share-links');
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_link (
  token text,
  node  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link_id uuid;
  v_role text;
  v_root text;
  v_expires timestamptz;
  v_tenant text;
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select l."id", l."role", l."subject_id", l."expires_at", l."tenant_id"::text
    into v_link_id, v_role, v_root, v_expires, v_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(drive_link.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'drive_node'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_link_id is null or v_root !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = coalesce(drive_link.node, v_root::uuid)
    and x."tenant_id"::text = v_tenant and x."deleted_at" is null;
  if not found or not (v_root::uuid = any ("better_supabase"."drive_ancestors"(v_node."id"))) then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires),
    'node', "better_supabase"."drive_node_json"(v_node),
    'children', case when v_node."kind" = 'folder' then (
      select coalesce(jsonb_agg("better_supabase"."drive_node_json"(c.r) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
      from (select y as r from "better_supabase"."drive_nodes" y where y."parent_id" = v_node."id" and y."deleted_at" is null order by (y."kind" = 'folder') desc, y."rank", lower(y."name"), y."id" limit 500) c
    ) end,
    'object', (select jsonb_build_object('bucket', f."bucket", 'path', f."object_path", 'mimeType', f."mime_type", 'status', f."status")
      from "better_supabase"."attachments" f where f."id" = v_node."attachment_id")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_public_form (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_form_id uuid;
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select x."id" into v_form_id
  from "better_supabase"."share_links" k
  join "better_supabase"."forms" x on x."id"::text = k."subject_id" and x."tenant_id" = k."tenant_id"
  where k."token_hash" = encode(extensions.digest(convert_to(get_public_form.token, 'utf8'), 'sha256'), 'hex')
    and k."subject_type" = 'form'
    and k."revoked_at" is null
    and (k."expires_at" is null or k."expires_at" > now())
    and (k."max_uses" is null or k."use_count" < k."max_uses")
    and k."password_hash" is null
    and k."role" = 'respond';
  if v_form_id is null then
    raise exception 'this form link isn''t valid' using errcode = 'P0002', hint = 'FORM_LINK_INVALID';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = v_form_id;
  if v_row."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'title', v_row."title", 'description', v_row."description", 'version', jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") - 'createdBy');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text, l."leaf_id"
    into v_subject, v_tenant, v_leaf
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(get_shared_ai_chat.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'ai-chat'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from "better_supabase".ai_chats where id = v_chat_id and organization_id::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from "better_supabase".ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', "better_supabase"."ai_message_path_of"(v_chat_id, v_leaf, false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_share_links (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'role', l."role", 'expiresAt', l."expires_at", 'revokedAt', l."revoked_at", 'downloadAllowed', l."download_allowed", 'passwordRequired', l."password_hash" is not null)), '[]'::jsonb)
  from "better_supabase"."share_links" l
  where l."subject_type" = list_share_links.subject_type
    and l."subject_id" = list_share_links.subject_id
    and (
      auth.role() = 'service_role'
      or l."created_by" = (select auth.uid())
      or l."tenant_id" in (select better_supabase.tenant_ids_with('share_links.read'))
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.public_available_slots (
  token       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone,
  tz          text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_available_slots.token is null or public_available_slots.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_available_slots.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  if public_available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = public_available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if public_available_slots.range_end - public_available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(v_service, public_available_slots.range_start, public_available_slots.range_end, public_available_slots.tz, null) t), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.public_booking_service (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_booking_service.token is null or public_booking_service.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_booking_service.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  return (
    select jsonb_build_object('id', sv."id", 'name', sv."name", 'duration', sv."duration"::text,
      'resources', coalesce((
        select jsonb_agg(jsonb_build_object('id', rs."id", 'name', rs."name", 'kind', rs."kind", 'tz', rs."tz") order by rs."name")
        from "better_supabase"."booking_resources" rs
        where rs."tenant_id" = sv."tenant_id" and rs."active"
          and (cardinality(sv."resource_kinds") = 0 or rs."kind" = any (sv."resource_kinds"))
      ), '[]'::jsonb))
    from "better_supabase"."booking_services" sv where sv."id" = v_service
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.public_hold_booking (
  token     text,
  resource  uuid,
  starts_at timestamp with time zone,
  customer  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_hold_booking.token is null or public_hold_booking.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_hold_booking.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  if nullif(trim(public_hold_booking.customer ->> 'name'), '') is null
    or coalesce(public_hold_booking.customer ->> 'email', '') !~ '^[^@\s]+@[^@\s]+$' then
    raise exception 'a guest booking needs a name and an email' using errcode = '22023', hint = 'BOOKING_CUSTOMER_INVALID';
  end if;
  return "better_supabase"."place_booking"(v_service, public_hold_booking.resource, public_hold_booking.starts_at, public_hold_booking.customer - 'userId', false, auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_share_link (
  token    text,
  password text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_link "better_supabase"."share_links"%rowtype;
  v_retry integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_link
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(resolve_share_link.token, 'utf8'), 'sha256'), 'hex')
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
  for update;
  if not found then
    return null;
  end if;
  if v_link."password_hash" is not null then
    if resolve_share_link.password is null then
      return jsonb_build_object('passwordRequired', true);
    end if;
    select greatest(1, ceil(extract(epoch from k."window_start" + k."period" - now()))::integer) into v_retry
    from "better_supabase"."rate_limits" k
    where k."scope" = 'share_link_password' and k."key" = v_link."id"::text
      and k."window_start" + k."period" > now()
      and k."hits" >= coalesce((select q."max_requests" from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password'), 10);
    if v_retry is not null then
      raise exception 'too many wrong passwords for this link' using errcode = 'BS429', hint = 'SHARE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
    end if;
    if extensions.crypt(resolve_share_link.password, v_link."password_hash") <> v_link."password_hash" then
      perform 1 from "better_supabase"."hit_rate_limit"('share_link_password', v_link."id"::text, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else 10 end, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else interval '15 minutes' end);
      return jsonb_build_object('passwordRequired', true);
    end if;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link."id";
  return jsonb_build_object('id', v_link."id", 'organizationId', v_link."tenant_id", 'subjectType', v_link."subject_type", 'subjectId', v_link."subject_id", 'role', v_link."role", 'versionId', v_link."version_id", 'expiresAt', v_link."expires_at", 'maxUses', v_link."max_uses", 'downloadAllowed', v_link."download_allowed", 'passwordRequired', v_link."password_hash" is not null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_public_form (
  token     text,
  answers   jsonb,
  bot_token text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_form_id uuid;
  v_headers jsonb;
  v_caller text;
  v_allowed boolean;
  v_retry integer;
  v_result jsonb;
begin
  select x."id" into v_form_id
  from "better_supabase"."share_links" k
  join "better_supabase"."forms" x on x."id"::text = k."subject_id" and x."tenant_id" = k."tenant_id"
  where k."token_hash" = encode(extensions.digest(convert_to(submit_public_form.token, 'utf8'), 'sha256'), 'hex')
    and k."subject_type" = 'form'
    and k."revoked_at" is null
    and (k."expires_at" is null or k."expires_at" > now())
    and (k."max_uses" is null or k."use_count" < k."max_uses")
    and k."password_hash" is null
    and k."role" = 'respond';
  if v_form_id is null then
    raise exception 'this form link isn''t valid' using errcode = 'P0002', hint = 'FORM_LINK_INVALID';
  end if;
  v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  v_caller := coalesce(auth.uid()::text, 'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown'));
  select h.allowed, h.retry_after into v_allowed, v_retry
    from "better_supabase"."hit_rate_limit"('forms:' || v_form_id::text, v_caller, 20, 'PT1H'::interval) h;
  if not v_allowed then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'BS429',
        'message', 'Rate limit for this form exceeded: 20 submissions per PT1H',
        'details', format('Retry after %s seconds.', v_retry),
        'hint', null
      )::text,
      detail = json_build_object(
        'status', 429,
        'status_text', 'Too Many Requests',
        'headers', json_build_object('Retry-After', v_retry::text)
      )::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_public_form_submission"(uuid, jsonb, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::text)', v_hook::oid::regproc)
        using v_form_id, submit_public_form.answers, submit_public_form.bot_token;
    end if;
  end;
  v_result := "better_supabase"."form_submission_save"(v_form_id, submit_public_form.answers, null, null, auth.uid(), 'public', false, null);
  return jsonb_build_object('id', v_result -> 'id', 'status', v_result -> 'status', 'submittedAt', v_result -> 'submittedAt');
end;
$function$;

REVOKE ALL ON FUNCTION "api"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_share_link"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_share_link"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamp WITH time zone, integer, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_share_link"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_share_link"(text, text) TO "anon", "authenticated", "service_role";
