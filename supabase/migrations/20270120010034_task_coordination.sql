SET local check_function_bodies = off;

DROP VIEW "better_supabase"."maintenance_jobs";

ALTER TABLE "better_supabase"."maintenance_requests"
  DROP CONSTRAINT "bsb_maintenance_requests_close_reason_check";

ALTER TABLE "better_supabase"."work_items"
  DROP CONSTRAINT "bsb_work_items_close_reason_check";

CREATE TABLE "better_supabase"."maintenance_request_claims" (
  "maintenance_request_id" uuid                     NOT NULL,
  "tenant_id"              uuid                     NOT NULL,
  "token"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "epoch"                  bigint                   NOT NULL DEFAULT 1,
  "holder_id"              uuid,
  "profile"                jsonb,
  "claimed_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"             timestamp with time zone NOT NULL,
  "expired_at"             timestamp with time zone
);

ALTER TABLE "better_supabase"."maintenance_request_claims"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."work_item_claims" (
  "work_item_id" uuid                     NOT NULL,
  "tenant_id"    uuid                     NOT NULL,
  "token"        uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "epoch"        bigint                   NOT NULL DEFAULT 1,
  "holder_id"    uuid,
  "profile"      jsonb,
  "claimed_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"   timestamp with time zone NOT NULL,
  "expired_at"   timestamp with time zone
);

ALTER TABLE "better_supabase"."work_item_claims"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "waiting_on" integer NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "held_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "hold_kind" text;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "hold_return_stage_id" uuid;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "delegate_profile" jsonb;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "close_note" text;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "waiting_on" integer NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "held_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "hold_kind" text;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "hold_return_stage_id" uuid;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "delegate_profile" jsonb;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "close_note" text;

CREATE OR REPLACE FUNCTION api.claim_maintenance_request (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_maintenance_request"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.claim_next_maintenance_request (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_next_maintenance_request"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.claim_next_work_item (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_next_work_item"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.claim_work_item (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_work_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.close_maintenance_request (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_maintenance_request"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.close_work_item (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_work_item"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.create_maintenance_requests (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_maintenance_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_work_items (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_work_items"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delegate_maintenance_request (
  task    uuid,
  to_user uuid,
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delegate_maintenance_request"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.delegate_work_item (
  task    uuid,
  to_user uuid,
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delegate_work_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.expire_maintenance_request_claims()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."expire_maintenance_request_claims"() $function$;

CREATE OR REPLACE FUNCTION api.expire_work_item_claims()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."expire_work_item_claims"() $function$;

CREATE OR REPLACE FUNCTION api.explain_permission (
  tenant     uuid,
  member     uuid,
  permission text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."explain_permission"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.hold_maintenance_request (
  task         uuid,
  kind         text,
  note         text   DEFAULT NULL::text,
  ask_user_ids uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."hold_maintenance_request"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.hold_work_item (
  task         uuid,
  kind         text,
  note         text   DEFAULT NULL::text,
  ask_user_ids uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."hold_work_item"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_request_actor (
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_request_actor"($1) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_request_claim (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_request_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_request_stage_times (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_request_stage_times"($1) $function$;

CREATE OR REPLACE FUNCTION api.move_maintenance_request (
  task   uuid,
  stage  uuid DEFAULT NULL::uuid,
  before uuid DEFAULT NULL::uuid,
  after  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."move_maintenance_request"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.move_maintenance_requests (
  moves jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."move_maintenance_requests"($1) $function$;

CREATE OR REPLACE FUNCTION api.move_work_item (
  task   uuid,
  stage  uuid DEFAULT NULL::uuid,
  before uuid DEFAULT NULL::uuid,
  after  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."move_work_item"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.move_work_items (
  moves jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."move_work_items"($1) $function$;

CREATE OR REPLACE FUNCTION api.release_maintenance_request_claim (
  task  uuid,
  token uuid,
  note  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_maintenance_request_claim"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.release_maintenance_request_hold (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_maintenance_request_hold"($1) $function$;

CREATE OR REPLACE FUNCTION api.release_work_item_claim (
  task  uuid,
  token uuid,
  note  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_work_item_claim"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.release_work_item_hold (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_work_item_hold"($1) $function$;

CREATE OR REPLACE FUNCTION api.renew_maintenance_request_claim (
  task  uuid,
  token uuid,
  lease integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."renew_maintenance_request_claim"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.renew_work_item_claim (
  task  uuid,
  token uuid,
  lease integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."renew_work_item_claim"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_maintenance_request_needs (
  task uuid,
  ids  uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_maintenance_request_needs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_work_item_needs (
  task uuid,
  ids  uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_work_item_needs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.work_item_actor (
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."work_item_actor"($1) $function$;

CREATE OR REPLACE FUNCTION api.work_item_claim (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."work_item_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.work_item_stage_times (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."work_item_stage_times"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_request (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."maintenance_requests" x where x."id" = archive_maintenance_request.task;
  update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_request.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_maintenance_request.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_maintenance_request.archived then
    perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  elsif v_was is not null then
    perform "better_supabase".emit_event('maintenance_request.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_requests (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select coalesce(array_agg(x."id"), '{}') into v_was from "better_supabase"."maintenance_requests" x
  where x."id" = any (coalesce(archive_maintenance_requests.ids, '{}')) and x."archived_at" is not null;
  for v_row in
    with changed as (
      update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_requests.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_maintenance_requests.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_maintenance_requests.archived then
      perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    elsif v_row."id" = any (v_was) then
      perform "better_supabase".emit_event('maintenance_request.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_item (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."work_items" x where x."id" = archive_work_item.task;
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  elsif v_was is not null then
    perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_items (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select coalesce(array_agg(x."id"), '{}') into v_was from "better_supabase"."work_items" x
  where x."id" = any (coalesce(archive_work_items.ids, '{}')) and x."archived_at" is not null;
  for v_row in
    with changed as (
      update "better_supabase"."work_items" x set "archived_at" = case when archive_work_items.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_work_items.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_work_items.archived then
      perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif v_row."id" = any (v_was) then
      perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."tenant_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(summary_key, event_type),
    summary_params,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event.target_type is not null and audit_event.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event.target_type || ':' || audit_event.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."tenant_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event_trusted.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event_trusted.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event_trusted.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(summary_key, event_type),
    summary_params,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event_trusted.target_type is not null and audit_event_trusted.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event_trusted.target_type || ':' || audit_event_trusted.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
  v_label text;
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0 then
    return null;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is not null then
    v_label := better_supabase.memo_slot_get('audit.tenant_label.t' || replace(row_tenant::text, '-', ''));
    if v_label is null then
      v_label := (select o."name"::text from "public"."organizations" o where o."id" = row_tenant);
      perform better_supabase.memo_slot_set('audit.tenant_label.t' || replace(row_tenant::text, '-', ''), coalesce(v_label, ''));
    end if;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' ->> 'kind' = 'agent' then 'agent'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    v_label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_statement_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
begin
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if tg_op = 'INSERT' then
    with src as (
      select null::jsonb as old_row, to_jsonb(n) as new_row from new_rows n
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' ->> 'kind' = 'agent' then 'agent'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  elsif tg_op = 'DELETE' then
    with src as (
      select to_jsonb(o) as old_row, null::jsonb as new_row from old_rows o
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' ->> 'kind' = 'agent' then 'agent'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  else
    with src as (
      select o.j as old_row, n.j as new_row
      from (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from old_rows r) o
      full join (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from new_rows r) n on o.k = n.k
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' ->> 'kind' = 'agent' then 'agent'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_maintenance_request_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."maintenance_requests" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      new."close_note" := coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
      new."held_at" := null;
      new."hold_kind" := null;
      new."hold_return_stage_id" := null;
      delete from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = new."id";
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('maintenance_request.closed', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason", 'note', coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      new."close_note" := null;
      perform "better_supabase".emit_event('maintenance_request.reopened', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      new."close_note" := coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
      new."held_at" := null;
      new."hold_kind" := null;
      new."hold_return_stage_id" := null;
      delete from "better_supabase"."work_item_claims" c where c."work_item_id" = new."id";
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason", 'note', coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      new."close_note" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_maintenance_request (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_claim "better_supabase"."maintenance_request_claims";
  v_actor jsonb := "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = claim_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be claimed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  insert into "better_supabase"."maintenance_request_claims" as c ("maintenance_request_id", "tenant_id", "holder_id", "profile", "expires_at")
  values (v_row."id", v_row."tenant_id", auth.uid(), v_actor, now() + make_interval(secs => least(900, greatest(1, coalesce(claim_maintenance_request.lease, 900)))))
  on conflict ("maintenance_request_id") do update set
    "token" = case when c."expires_at" > now() then c."token" else gen_random_uuid() end,
    "epoch" = case when c."expires_at" > now() then c."epoch" else c."epoch" + 1 end,
    "holder_id" = excluded."holder_id",
    "profile" = excluded."profile",
    "claimed_at" = case when c."expires_at" > now() then c."claimed_at" else now() end,
    "expires_at" = excluded."expires_at",
    "expired_at" = null
  where not c."expires_at" > now()
    or (c."holder_id" is not distinct from excluded."holder_id" and c."profile" ->> 'name' is not distinct from excluded."profile" ->> 'name')
  returning * into v_claim;
  if not found then
    raise exception 'another holder has a live claim on the task' using errcode = '55P03', hint = 'TASK_CLAIMED';
  end if;
  perform "better_supabase".emit_event('maintenance_request.claimed', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return jsonb_build_object('task', (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id"), 'claim', jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_next_maintenance_request (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_maintenance_request.tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to claim work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."maintenance_requests" x
  where x."tenant_id" = claim_next_maintenance_request.tenant and x."archived_at" is null and x."closed_at" is null
    and x."held_at" is null
    and not exists (select 1 from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = x."id" and c."expires_at" > now())
      and (claim_next_maintenance_request.filter ->> 'teamId' is null or x."team_id" = (claim_next_maintenance_request.filter ->> 'teamId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'projectId' is null or x."project_id" = (claim_next_maintenance_request.filter ->> 'projectId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'parentId' is null or x."parent_id" = (claim_next_maintenance_request.filter ->> 'parentId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'stageId' is null or x."stage_id" = (claim_next_maintenance_request.filter ->> 'stageId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = (claim_next_maintenance_request.filter ->> 'assigneeId')::uuid))
  order by (case when exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = auth.uid()) then 0 else 1 end), x."number"
  limit 1
  for update of x skip locked;
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_maintenance_request"(v_id, claim_next_maintenance_request.lease, claim_next_maintenance_request.profile);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_next_work_item (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to claim work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."work_items" x
  where x."tenant_id" = claim_next_work_item.tenant and x."archived_at" is null and x."closed_at" is null
    and x."held_at" is null
    and not exists (select 1 from "better_supabase"."work_item_claims" c where c."work_item_id" = x."id" and c."expires_at" > now())
      and (claim_next_work_item.filter ->> 'teamId' is null or x."team_id" = (claim_next_work_item.filter ->> 'teamId')::uuid)
      and (claim_next_work_item.filter ->> 'projectId' is null or x."project_id" = (claim_next_work_item.filter ->> 'projectId')::uuid)
      and (claim_next_work_item.filter ->> 'parentId' is null or x."parent_id" = (claim_next_work_item.filter ->> 'parentId')::uuid)
      and (claim_next_work_item.filter ->> 'stageId' is null or x."stage_id" = (claim_next_work_item.filter ->> 'stageId')::uuid)
      and (claim_next_work_item.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (claim_next_work_item.filter ->> 'assigneeId')::uuid))
  order by (case when exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = auth.uid()) then 0 else 1 end), x."number"
  limit 1
  for update of x skip locked;
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_work_item"(v_id, claim_next_work_item.lease, claim_next_work_item.profile);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_work_item (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_claim "better_supabase"."work_item_claims";
  v_actor jsonb := "better_supabase"."work_item_actor"(claim_work_item.profile);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = claim_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be claimed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  insert into "better_supabase"."work_item_claims" as c ("work_item_id", "tenant_id", "holder_id", "profile", "expires_at")
  values (v_row."id", v_row."tenant_id", auth.uid(), v_actor, now() + make_interval(secs => least(900, greatest(1, coalesce(claim_work_item.lease, 900)))))
  on conflict ("work_item_id") do update set
    "token" = case when c."expires_at" > now() then c."token" else gen_random_uuid() end,
    "epoch" = case when c."expires_at" > now() then c."epoch" else c."epoch" + 1 end,
    "holder_id" = excluded."holder_id",
    "profile" = excluded."profile",
    "claimed_at" = case when c."expires_at" > now() then c."claimed_at" else now() end,
    "expires_at" = excluded."expires_at",
    "expired_at" = null
  where not c."expires_at" > now()
    or (c."holder_id" is not distinct from excluded."holder_id" and c."profile" ->> 'name' is not distinct from excluded."profile" ->> 'name')
  returning * into v_claim;
  if not found then
    raise exception 'another holder has a live claim on the task' using errcode = '55P03', hint = 'TASK_CLAIMED';
  end if;
  perform "better_supabase".emit_event('work_item.claimed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return jsonb_build_object('task', (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id"), 'claim', jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_maintenance_request (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."maintenance_requests"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = clone_maintenance_request.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_maintenance_request.source, clone_maintenance_request.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = v_src."id";
  v_created := "better_supabase"."create_maintenance_request"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "done", "rank")
  select c."tenant_id", v_id, c."title", false, c."rank"
  from "better_supabase"."maintenance_request_checklist_items" c where c."maintenance_request_id" = clone_maintenance_request.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select g."tenant_id", g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'maintenance_request' and g."subject_id" = clone_maintenance_request.source::text;
  for v_child in select c."id" from "better_supabase"."maintenance_requests" c where c."parent_id" = clone_maintenance_request.source loop
    v_copy := "better_supabase"."clone_maintenance_request"(v_child, coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."maintenance_requests" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_work_item (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."work_items"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."work_items" x where x."id" = clone_work_item.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_work_item.source, clone_work_item.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = v_src."id";
  v_created := "better_supabase"."create_work_item"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "rank")
  select c."tenant_id", v_id, c."title", false, c."rank"
  from "better_supabase"."work_item_checklist_items" c where c."work_item_id" = clone_work_item.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select g."tenant_id", g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'work_item' and g."subject_id" = clone_work_item.source::text;
  for v_child in select c."id" from "better_supabase"."work_items" c where c."parent_id" = clone_work_item.source loop
    v_copy := "better_supabase"."clone_work_item"(v_child, coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."work_items" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_maintenance_request (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_stage uuid;
  v_note text := nullif(trim(close_maintenance_request.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if close_maintenance_request.outcome is null or close_maintenance_request.outcome not in ('completed', 'canceled', 'failed', 'open') then
    raise exception 'outcome is completed, canceled, failed or open' using errcode = '22023', hint = 'TASK_OUTCOME_INVALID';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = close_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if close_maintenance_request.outcome = 'open' and v_row."closed_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
  end if;
  if close_maintenance_request.outcome <> 'open' and v_row."closed_at" is not null then
    raise exception 'the task is already closed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_close"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", close_maintenance_request.outcome, v_note;
    end if;
  end;
  v_stage := coalesce(close_maintenance_request.stage, case close_maintenance_request.outcome
    when 'completed' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'completed' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    when 'open' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'unstarted' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    else (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'canceled' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1) end);
  if v_stage is null then
    raise exception 'the task''s pipeline has no stage for this outcome; pass a stage' using errcode = '22023', hint = 'TASK_STAGE_REQUIRED';
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_maintenance_request.outcome = 'failed' then
      begin
        update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage, "close_reason" = 'failed' where x."id" = v_row."id";
      exception when check_violation or invalid_text_representation then
        update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage where x."id" = v_row."id";
      end;
    else
      update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage where x."id" = v_row."id";
    end if;
  exception when check_violation or foreign_key_violation then
    raise exception 'the stage can''t be used for this task' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_row."id";
  if close_maintenance_request.outcome = 'failed' then
    perform "better_supabase".emit_event('maintenance_request.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'note', v_note, 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_work_item (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_note text := nullif(trim(close_work_item.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if close_work_item.outcome is null or close_work_item.outcome not in ('completed', 'canceled', 'failed', 'open') then
    raise exception 'outcome is completed, canceled, failed or open' using errcode = '22023', hint = 'TASK_OUTCOME_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = close_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if close_work_item.outcome = 'open' and v_row."closed_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
  end if;
  if close_work_item.outcome <> 'open' and v_row."closed_at" is not null then
    raise exception 'the task is already closed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_close"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", close_work_item.outcome, v_note;
    end if;
  end;
  v_stage := coalesce(close_work_item.stage, case close_work_item.outcome
    when 'completed' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'completed' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    when 'open' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'unstarted' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    else (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'canceled' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1) end);
  if v_stage is null then
    raise exception 'the task''s pipeline has no stage for this outcome; pass a stage' using errcode = '22023', hint = 'TASK_STAGE_REQUIRED';
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_work_item.outcome = 'failed' then
      begin
        update "better_supabase"."work_items" x set "stage_id" = v_stage, "close_reason" = 'failed' where x."id" = v_row."id";
      exception when check_violation or invalid_text_representation then
        update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
      end;
    else
      update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
    end if;
  exception when check_violation or foreign_key_violation then
    raise exception 'the stage can''t be used for this task' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  if close_work_item.outcome = 'failed' then
    perform "better_supabase".emit_event('work_item.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'note', v_note, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_request (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."maintenance_requests";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_maintenance_request.tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_maintenance_request.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_maintenance_request.tenant, create_maintenance_request.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_maintenance_request.tenant::text || ':maintenance_request', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."maintenance_requests" x where x."tenant_id" = create_maintenance_request.tenant;
  v_identifier := 'MR' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."maintenance_requests" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by", "unit_id", "lease_id")
    values (create_maintenance_request.tenant, v_seq, v_identifier, trim(create_maintenance_request.attrs ->> 'title'), create_maintenance_request.attrs ->> 'body',
      (create_maintenance_request.attrs ->> 'parentId')::uuid, (create_maintenance_request.attrs ->> 'teamId')::uuid, (create_maintenance_request.attrs ->> 'projectId')::uuid,
      (create_maintenance_request.attrs ->> 'iterationId')::uuid, coalesce((create_maintenance_request.attrs ->> 'priority')::smallint, 0),
      (create_maintenance_request.attrs ->> 'estimate')::numeric, (create_maintenance_request.attrs ->> 'progress')::smallint,
      (create_maintenance_request.attrs ->> 'startAt')::timestamptz, (create_maintenance_request.attrs ->> 'endAt')::timestamptz, (create_maintenance_request.attrs ->> 'dueAt')::timestamptz,
      (create_maintenance_request.attrs ->> 'pipelineId')::uuid, (create_maintenance_request.attrs ->> 'stageId')::uuid, auth.uid(), case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', (create_maintenance_request.attrs -> 'fields') -> 'unit_id')))."unit_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'unit_id', (null::"better_supabase"."maintenance_requests")."unit_id") end, case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', (create_maintenance_request.attrs -> 'fields') -> 'lease_id')))."lease_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'lease_id', (null::"better_supabase"."maintenance_requests")."lease_id") end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  update "better_supabase"."maintenance_requests" x set "unit_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then r."unit_id" else x."unit_id" end, "lease_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then r."lease_id" else x."lease_id" end
  from jsonb_populate_record(null::"better_supabase"."maintenance_requests", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_maintenance_request.attrs -> 'fields')) e where e.key in ('unit_id', 'lease_id'))) r
  where x."id" = v_id;
  if cardinality(coalesce(create_maintenance_request.assignees, '{}')) > 0 then
    perform "better_supabase"."set_maintenance_request_assignees"(v_id, create_maintenance_request.assignees);
  end if;
  update "better_supabase"."maintenance_requests" x set "rank" = "better_supabase"."rank_between"((select max(y."rank" collate "C") from "better_supabase"."maintenance_requests" y where y."tenant_id" = x."tenant_id" and y."stage_id" is not distinct from x."stage_id" and y."archived_at" is null and y."id" <> x."id"), null)
  where x."id" = v_id and x."stage_id" is not null;
  if jsonb_typeof(create_maintenance_request.attrs -> 'needs') = 'array' and jsonb_array_length(create_maintenance_request.attrs -> 'needs') > 0 then
    perform "better_supabase"."set_maintenance_request_needs"(v_id, array(select x::uuid from jsonb_array_elements_text(create_maintenance_request.attrs -> 'needs') x));
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('maintenance_request.created', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_requests (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item jsonb;
  v_pos integer := 0;
  v_keys jsonb := '{}';
  v_ids uuid[] := '{}';
  v_key text;
  v_task jsonb;
  v_id uuid;
  v_ref jsonb;
  v_prereqs uuid[];
  v_known text[] := array['key', 'title', 'body', 'parentId', 'teamId', 'projectId', 'iterationId', 'priority', 'estimate', 'progress', 'startAt', 'endAt', 'dueAt', 'pipelineId', 'stageId', 'fields', 'assignees', 'needs'];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(create_maintenance_requests.items) is distinct from 'array' then
    raise exception 'items must be a list of tasks' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
  end if;
  if jsonb_array_length(create_maintenance_requests.items) > 100 then
    raise exception 'a plan holds at most 100 tasks' using errcode = '54000', hint = 'TASK_PLAN_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(create_maintenance_requests.items) loop
    v_pos := v_pos + 1;
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'each item must be an object' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    if exists (select 1 from jsonb_object_keys(v_item) k where not (k = any (v_known))) then
      raise exception 'an item has a property create can''t write' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    v_key := v_item ->> 'key';
    if v_key is not null then
      if v_keys ? v_key then
        raise exception 'two items share a key' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
      v_keys := v_keys || jsonb_build_object(v_key, v_pos);
    end if;
  end loop;
  for v_item in select value from jsonb_array_elements(create_maintenance_requests.items) loop
    for v_ref in select value from jsonb_array_elements(coalesce(v_item -> 'needs', '[]'::jsonb)) union all select v_item -> 'parentId' where v_item ? 'parentId' loop
      if jsonb_typeof(v_ref) = 'object' and not (v_keys ? (v_ref ->> 'key')) then
        raise exception 'an item refers to a key the plan doesn''t have' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
    end loop;
  end loop;
  for v_item in select value from jsonb_array_elements(create_maintenance_requests.items) loop
    v_task := "better_supabase"."create_maintenance_request"(
      create_maintenance_requests.tenant,
      (v_item - 'key' - 'needs' - 'assignees' - 'parentId'),
      coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(v_item -> 'assignees', '[]'::jsonb)) x), '{}'));
    v_ids := array_append(v_ids, (v_task ->> 'id')::uuid);
  end loop;
  v_pos := 0;
  for v_item in select value from jsonb_array_elements(create_maintenance_requests.items) loop
    v_pos := v_pos + 1;
    v_id := v_ids[v_pos];
    if v_item ? 'parentId' then
      v_ref := v_item -> 'parentId';
      update "better_supabase"."maintenance_requests" x set "parent_id" = case when jsonb_typeof(v_ref) = 'object' then v_ids[(v_keys ->> (v_ref ->> 'key'))::integer] else (v_ref #>> '{}')::uuid end
      where x."id" = v_id;
    end if;
    if jsonb_array_length(coalesce(v_item -> 'needs', '[]'::jsonb)) > 0 then
      v_prereqs := array(select case when jsonb_typeof(x) = 'object' then v_ids[(v_keys ->> (x ->> 'key'))::integer] else (x #>> '{}')::uuid end
        from jsonb_array_elements(v_item -> 'needs') x);
      perform "better_supabase"."set_maintenance_request_needs"(v_id, v_prereqs);
    end if;
  end loop;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) order by array_position(v_ids, x."id")) from "better_supabase"."maintenance_requests" x where x."id" = any (v_ids)), '[]'::jsonb),
    'keys', coalesce((select jsonb_object_agg(k.key, v_ids[(k.value #>> '{}')::integer]) from jsonb_each(v_keys) k), '{}'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_item (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."work_items";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."work_items" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  update "better_supabase"."work_items" x set "rank" = "better_supabase"."rank_between"((select max(y."rank" collate "C") from "better_supabase"."work_items" y where y."tenant_id" = x."tenant_id" and y."stage_id" is not distinct from x."stage_id" and y."archived_at" is null and y."id" <> x."id"), null)
  where x."id" = v_id and x."stage_id" is not null;
  if jsonb_typeof(create_work_item.attrs -> 'needs') = 'array' and jsonb_array_length(create_work_item.attrs -> 'needs') > 0 then
    perform "better_supabase"."set_work_item_needs"(v_id, array(select x::uuid from jsonb_array_elements_text(create_work_item.attrs -> 'needs') x));
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('work_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_items (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item jsonb;
  v_pos integer := 0;
  v_keys jsonb := '{}';
  v_ids uuid[] := '{}';
  v_key text;
  v_task jsonb;
  v_id uuid;
  v_ref jsonb;
  v_prereqs uuid[];
  v_known text[] := array['key', 'title', 'body', 'parentId', 'teamId', 'projectId', 'iterationId', 'priority', 'estimate', 'progress', 'startAt', 'endAt', 'dueAt', 'pipelineId', 'stageId', 'fields', 'assignees', 'needs'];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(create_work_items.items) is distinct from 'array' then
    raise exception 'items must be a list of tasks' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
  end if;
  if jsonb_array_length(create_work_items.items) > 100 then
    raise exception 'a plan holds at most 100 tasks' using errcode = '54000', hint = 'TASK_PLAN_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_pos := v_pos + 1;
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'each item must be an object' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    if exists (select 1 from jsonb_object_keys(v_item) k where not (k = any (v_known))) then
      raise exception 'an item has a property create can''t write' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    v_key := v_item ->> 'key';
    if v_key is not null then
      if v_keys ? v_key then
        raise exception 'two items share a key' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
      v_keys := v_keys || jsonb_build_object(v_key, v_pos);
    end if;
  end loop;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    for v_ref in select value from jsonb_array_elements(coalesce(v_item -> 'needs', '[]'::jsonb)) union all select v_item -> 'parentId' where v_item ? 'parentId' loop
      if jsonb_typeof(v_ref) = 'object' and not (v_keys ? (v_ref ->> 'key')) then
        raise exception 'an item refers to a key the plan doesn''t have' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
    end loop;
  end loop;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_task := "better_supabase"."create_work_item"(
      create_work_items.tenant,
      (v_item - 'key' - 'needs' - 'assignees' - 'parentId'),
      coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(v_item -> 'assignees', '[]'::jsonb)) x), '{}'));
    v_ids := array_append(v_ids, (v_task ->> 'id')::uuid);
  end loop;
  v_pos := 0;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_pos := v_pos + 1;
    v_id := v_ids[v_pos];
    if v_item ? 'parentId' then
      v_ref := v_item -> 'parentId';
      update "better_supabase"."work_items" x set "parent_id" = case when jsonb_typeof(v_ref) = 'object' then v_ids[(v_keys ->> (v_ref ->> 'key'))::integer] else (v_ref #>> '{}')::uuid end
      where x."id" = v_id;
    end if;
    if jsonb_array_length(coalesce(v_item -> 'needs', '[]'::jsonb)) > 0 then
      v_prereqs := array(select case when jsonb_typeof(x) = 'object' then v_ids[(v_keys ->> (x ->> 'key'))::integer] else (x #>> '{}')::uuid end
        from jsonb_array_elements(v_item -> 'needs') x);
      perform "better_supabase"."set_work_item_needs"(v_id, v_prereqs);
    end if;
  end loop;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) order by array_position(v_ids, x."id")) from "better_supabase"."work_items" x where x."id" = any (v_ids)), '[]'::jsonb),
    'keys', coalesce((select jsonb_object_agg(k.key, v_ids[(k.value #>> '{}')::integer]) from jsonb_each(v_keys) k), '{}'::jsonb));
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
    ('user', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_links', '"better_supabase"."ai_chat_links"', 'created_by', true, array['salt']::text[], true),
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
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'decided_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.identity_links', '"better_supabase"."identity_links"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.identity_link_codes', '"better_supabase"."identity_link_codes"', 'user_id', true, '{}'::text[], false),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_claims', '"better_supabase"."work_item_claims"', 'holder_id', true, '{}'::text[], false),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.collection_favorites', '"better_supabase"."collection_favorites"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_items', '"better_supabase"."saved_items"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.reviews', '"better_supabase"."reviews"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'submitted_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.warranty_claims', '"better_supabase"."warranty_claims"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'appraisee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'satisfied_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
    ('user', 'better_supabase.checkout_sessions', '"better_supabase"."checkout_sessions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_mandates', '"better_supabase"."agent_mandates"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.advisory_products', '"better_supabase"."advisory_products"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.vex_statements', '"better_supabase"."vex_statements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.advisories', '"better_supabase"."advisories"', 'created_by', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'tenant_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'tenant_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_sessions', '"better_supabase"."support_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_requests', '"better_supabase"."support_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incoming_webhooks', '"better_supabase"."incoming_webhooks"', 'tenant', true, array['token_hash', 'secret', 'secret_id', 'previous_secret', 'previous_secret_id']::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_native_subscriptions', '"better_supabase"."billing_native_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_customers', '"better_supabase"."billing_customers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_subscriptions', '"better_supabase"."billing_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'tenant_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_chunks', '"better_supabase"."import_chunks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.purchase_order_tax_lines', '"better_supabase"."purchase_order_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_claims', '"better_supabase"."work_item_claims"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.work_item_specification_lines', '"better_supabase"."work_item_specification_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_material_lines', '"better_supabase"."work_item_material_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_locations', '"better_supabase"."party_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_bank_accounts', '"better_supabase"."party_bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_channels', '"better_supabase"."party_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_subjects', '"better_supabase"."activity_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_open_items', '"better_supabase"."invoice_open_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_endpoints', '"better_supabase"."e_invoice_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_deliveries', '"better_supabase"."e_invoice_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collection_entries', '"better_supabase"."subject_collection_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_favorites', '"better_supabase"."collection_favorites"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_items', '"better_supabase"."saved_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.hostnames', '"better_supabase"."hostnames"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reviews', '"better_supabase"."reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.review_stats', '"better_supabase"."review_stats"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_types', '"better_supabase"."leave_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_profiles', '"better_supabase"."incident_regulatory_profiles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_schedules', '"better_supabase"."accounting_recognition_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_rows', '"better_supabase"."accounting_recognition_rows"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_receipts', '"better_supabase"."consent_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.warranty_claims', '"better_supabase"."warranty_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.putaway_rules', '"better_supabase"."putaway_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bin_slots', '"better_supabase"."bin_slots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.variant_sizes', '"better_supabase"."variant_sizes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.periods', '"better_supabase"."periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.checkout_sessions', '"better_supabase"."checkout_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_mandates', '"better_supabase"."agent_mandates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_products', '"better_supabase"."advisory_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_product_versions', '"better_supabase"."advisory_product_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sbom_components', '"better_supabase"."sbom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.vulnerabilities', '"better_supabase"."vulnerabilities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.vex_statements', '"better_supabase"."vex_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisories', '"better_supabase"."advisories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_vulnerabilities', '"better_supabase"."advisory_vulnerabilities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_versions', '"better_supabase"."prompt_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_labels', '"better_supabase"."prompt_labels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_datasets', '"better_supabase"."eval_datasets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_runs', '"better_supabase"."eval_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_policies', '"better_supabase"."guardrail_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_decisions', '"better_supabase"."guardrail_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.option_sets', '"better_supabase"."option_sets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.option_set_items', '"better_supabase"."option_set_items"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delegate_maintenance_request (
  task    uuid,
  to_user uuid,
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_actor jsonb := "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile);
  v_added boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = delegate_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can_user(delegate_maintenance_request.to_user, 'tenant', v_row."tenant_id", 'facilities.read'), false) then
    raise exception 'the user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id") values (v_row."tenant_id", v_row."id", delegate_maintenance_request.to_user)
  on conflict do nothing;
  v_added := found;
  delete from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = v_row."id" and c."holder_id" is distinct from delegate_maintenance_request.to_user;
  update "better_supabase"."maintenance_requests" x set "delegate_profile" = v_actor where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_request.delegated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'delegateId', delegate_maintenance_request.to_user, 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  if v_added then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(array(select y."user_id" from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id")), 'addedIds', jsonb_build_array(delegate_maintenance_request.to_user), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delegate_work_item (
  task    uuid,
  to_user uuid,
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_actor jsonb := "better_supabase"."work_item_actor"(delegate_work_item.profile);
  v_added boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = delegate_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can_user(delegate_work_item.to_user, 'tenant', v_row."tenant_id", 'tasks.read'), false) then
    raise exception 'the user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id") values (v_row."tenant_id", v_row."id", delegate_work_item.to_user)
  on conflict do nothing;
  v_added := found;
  delete from "better_supabase"."work_item_claims" c where c."work_item_id" = v_row."id" and c."holder_id" is distinct from delegate_work_item.to_user;
  update "better_supabase"."work_items" x set "delegate_profile" = v_actor where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.delegated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'delegateId', delegate_work_item.to_user, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  if v_added then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(array(select y."user_id" from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id")), 'addedIds', jsonb_build_array(delegate_work_item.to_user), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_request (
  task uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."maintenance_requests" x
  where x."id" = delete_maintenance_request.task
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_request_checklist_item (
  checklist_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."maintenance_requests" x join "better_supabase"."maintenance_request_checklist_items" y on y."maintenance_request_id" = x."id"
  where y."id" = delete_maintenance_request_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."maintenance_request_checklist_items" y where y."id" = delete_maintenance_request_checklist_item.checklist_item;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_requests (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."maintenance_requests" x
      where x."id" = any (coalesce(delete_maintenance_requests.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item (
  task uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."work_items" x
  where x."id" = delete_work_item.task
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item_checklist_item (
  checklist_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."work_items" x join "better_supabase"."work_item_checklist_items" y on y."work_item_id" = x."id"
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_items (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."work_items" x
      where x."id" = any (coalesce(delete_work_items.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_maintenance_request_claims()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."maintenance_request_claims";
  v_row "better_supabase"."maintenance_requests";
  v_count integer := 0;
begin
  for v_claim in update "better_supabase"."maintenance_request_claims" c set "expired_at" = now() where c."expires_at" <= now() and c."expired_at" is null returning c.* loop
    v_count := v_count + 1;
    select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_claim."maintenance_request_id";
    if found and v_row."closed_at" is null then
      perform "better_supabase".emit_event('maintenance_request.claim_expired', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(v_claim."profile") ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_work_item_claims()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."work_item_claims";
  v_row "better_supabase"."work_items";
  v_count integer := 0;
begin
  for v_claim in update "better_supabase"."work_item_claims" c set "expired_at" = now() where c."expires_at" <= now() and c."expired_at" is null returning c.* loop
    v_count := v_count + 1;
    select * into v_row from "better_supabase"."work_items" x where x."id" = v_claim."work_item_id";
    if found and v_row."closed_at" is null then
      perform "better_supabase".emit_event('work_item.claim_expired', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.explain_permission (
  tenant     uuid,
  member     uuid,
  permission text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_allowed boolean;
  v_member boolean;
  v_roles jsonb;
  v_matched text[];
  v_override boolean;
  v_reason text;
begin
  if not (coalesce(auth.jwt() ->> 'role', '') = 'service_role' or explain_permission.member is not distinct from auth.uid()
    or coalesce(better_supabase.member_can(auth.uid(), explain_permission.tenant, 'members.read'), false)) then
    raise exception 'Not allowed to explain this member''s permissions' using errcode = '42501', hint = 'PERMISSIONS_FORBIDDEN';
  end if;
  v_allowed := coalesce(better_supabase.member_can(explain_permission.member, explain_permission.tenant, explain_permission.permission), false);
  select count(*) > 0, coalesce(jsonb_agg(m."role"::text), '[]'::jsonb) into v_member, v_roles
  from "public"."memberships" m
  where m."organization_id" = explain_permission.tenant and m."user_id" = explain_permission.member;
  v_matched := coalesce((
    select array_agg(k.key order by k.key)
    from unnest(better_supabase.member_permissions(explain_permission.member, explain_permission.tenant)) k(key)
    where better_supabase.permission_matches(k.key, explain_permission.permission)
  ), '{}'::text[]);
  v_override := (select bool_and(ov."granted") from "better_supabase"."permission_overrides" ov
        join "better_supabase"."permissions" p on p."id" = ov."permission_id"
        join "public"."memberships" m on m."organization_id" = explain_permission.tenant and m."user_id" = explain_permission.member and m."role" = ov."role_id"
        where ov."tenant_id" = explain_permission.tenant
          and p."key" = explain_permission.permission);
  v_reason := case
    when v_allowed then case when v_override is true then 'granted_by_override' else 'granted_by_role' end
    when better_supabase.user_disabled(explain_permission.member) then 'member_disabled'
    when better_supabase.tenant_disabled(explain_permission.tenant) then 'organization_disabled'
    when not v_member then 'not_a_member'
    when v_override is false then 'denied_by_override'
    when (explain_permission.member is distinct from auth.uid() or better_supabase.cap_allows(explain_permission.permission)) is not true then 'not_in_scope'
    else 'role_lacks_key'
  end;
  return jsonb_build_object(
    'permission', explain_permission.permission,
    'userId', explain_permission.member,
    'organizationId', explain_permission.tenant,
    'allowed', v_allowed,
    'reason', v_reason,
    'roles', v_roles,
    'matchedBy', to_jsonb(v_matched),
    'override', v_override
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_maintenance_request (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = get_maintenance_request.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_work_item (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = get_work_item.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hold_maintenance_request (
  task         uuid,
  kind         text,
  note         text   DEFAULT NULL::text,
  ask_user_ids uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_stage uuid;
  v_note text := nullif(trim(hold_maintenance_request.note), '');
  v_ask uuid[] := array(select distinct x from unnest(coalesce(hold_maintenance_request.ask_user_ids, '{}')) x where x is not null);
  v_conversation text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if hold_maintenance_request.kind is null or hold_maintenance_request.kind !~ '^[a-z][a-z_]{0,31}$' then
    raise exception 'kind must be a short lowercase word such as review or input' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = hold_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be held' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is already on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  if exists (select 1 from unnest(v_ask) x where not coalesce(better_supabase.can_user(x, 'tenant', v_row."tenant_id", 'facilities.read'), false)) then
    raise exception 'an asked user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  delete from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = v_row."id";
  update "better_supabase"."maintenance_requests" x set "held_at" = now(), "hold_kind" = hold_maintenance_request.kind where x."id" = v_row."id";
  if v_note is not null or cardinality(v_ask) > 0 then
    v_conversation := ("better_supabase"."open_conversation"(v_row."tenant_id", 'subject', jsonb_build_object('subjectType', 'maintenance_request', 'subjectId', v_row."id"::text), '{}'))
      ->> 'id';
    perform "better_supabase"."send_message"(v_conversation::uuid, coalesce(v_note, 'On hold: ' || hold_maintenance_request.kind),
      jsonb_build_object('mentions', to_jsonb(v_ask)), '{}');
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_request.held', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', hold_maintenance_request.kind, 'note', v_note, 'askUserIds', to_jsonb(v_ask), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hold_work_item (
  task         uuid,
  kind         text,
  note         text   DEFAULT NULL::text,
  ask_user_ids uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_note text := nullif(trim(hold_work_item.note), '');
  v_ask uuid[] := array(select distinct x from unnest(coalesce(hold_work_item.ask_user_ids, '{}')) x where x is not null);
  v_conversation text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if hold_work_item.kind is null or hold_work_item.kind !~ '^[a-z][a-z_]{0,31}$' then
    raise exception 'kind must be a short lowercase word such as review or input' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = hold_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be held' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is already on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  if exists (select 1 from unnest(v_ask) x where not coalesce(better_supabase.can_user(x, 'tenant', v_row."tenant_id", 'tasks.read'), false)) then
    raise exception 'an asked user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  delete from "better_supabase"."work_item_claims" c where c."work_item_id" = v_row."id";
  update "better_supabase"."work_items" x set "held_at" = now(), "hold_kind" = hold_work_item.kind where x."id" = v_row."id";
  if v_note is not null or cardinality(v_ask) > 0 then
    v_conversation := ("better_supabase"."open_conversation"(v_row."tenant_id", 'subject', jsonb_build_object('subjectType', 'work_item', 'subjectId', v_row."id"::text), '{}'))
      ->> 'id';
    perform "better_supabase"."send_message"(v_conversation::uuid, coalesce(v_note, 'On hold: ' || hold_work_item.kind),
      jsonb_build_object('mentions', to_jsonb(v_ask)), '{}');
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.held', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', hold_work_item.kind, 'note', v_note, 'askUserIds', to_jsonb(v_ask), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_requests (
  tenant    uuid,
  filter    jsonb,
  search    text,
  after     uuid,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as value, x."number" as number
    from "better_supabase"."maintenance_requests" x
    where x."tenant_id" = list_maintenance_requests.tenant and x."archived_at" is null
      and (list_maintenance_requests.filter ->> 'teamId' is null or x."team_id" = (list_maintenance_requests.filter ->> 'teamId')::uuid)
      and (list_maintenance_requests.filter ->> 'projectId' is null or x."project_id" = (list_maintenance_requests.filter ->> 'projectId')::uuid)
      and (list_maintenance_requests.filter ->> 'iterationId' is null or x."iteration_id" = (list_maintenance_requests.filter ->> 'iterationId')::uuid)
      and (list_maintenance_requests.filter ->> 'parentId' is null or x."parent_id" = (list_maintenance_requests.filter ->> 'parentId')::uuid)
      and (list_maintenance_requests.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = (list_maintenance_requests.filter ->> 'assigneeId')::uuid))
      and (list_maintenance_requests.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_maintenance_requests.filter -> 'states'))))
      and (coalesce((list_maintenance_requests.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (coalesce((list_maintenance_requests.filter ->> 'ready')::boolean, false) = false or (x."waiting_on" = 0 and x."closed_at" is null))
      and (list_maintenance_requests.search is null or x."title" ilike '%' || list_maintenance_requests.search || '%' or x."identifier" ilike list_maintenance_requests.search || '%')
      and (list_maintenance_requests.after is null or x."number" < (select z."number" from "better_supabase"."maintenance_requests" z where z."id" = list_maintenance_requests.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_maintenance_requests.page_size, 50), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_work_items (
  tenant    uuid,
  filter    jsonb,
  search    text,
  after     uuid,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as value, x."number" as number
    from "better_supabase"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (coalesce((list_work_items.filter ->> 'ready')::boolean, false) = false or (x."waiting_on" = 0 and x."closed_at" is null))
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "better_supabase"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_request_actor (
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'kind', case
      when maintenance_request_actor.profile ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then maintenance_request_actor.profile ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end,
    'name', left(coalesce(nullif(maintenance_request_actor.profile ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_request_claim (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('epoch', c."epoch", 'holderId', c."holder_id", 'profile', c."profile", 'claimedAt', c."claimed_at", 'expiresAt', c."expires_at")
  from "better_supabase"."maintenance_request_claims" c
  where c."maintenance_request_id" = maintenance_request_claim.task and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'facilities.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_request_claims_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."maintenance_request_id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."maintenance_request_id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_request_needs_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and tg_table_name = 'maintenance_requests' then
    perform "better_supabase"."recount_maintenance_request_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = old."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'maintenance_request' and r."source_id" = old."id"::text and r."target_type" = 'maintenance_request'));
  elsif tg_table_name = 'maintenance_requests' then
    perform "better_supabase"."recount_maintenance_request_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = new."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'maintenance_request' and r."source_id" = new."id"::text and r."target_type" = 'maintenance_request'));
  elsif tg_op = 'DELETE' then
    if old."kind" = 'blocks' and old."target_type" = 'maintenance_request' and old."source_type" = 'maintenance_request' then
      perform "better_supabase"."recount_maintenance_request_needs"(array[old."target_id"::uuid]);
    end if;
  elsif new."kind" = 'blocks' and new."target_type" = 'maintenance_request' and new."source_type" = 'maintenance_request' then
    perform "better_supabase"."recount_maintenance_request_needs"(array[new."target_id"::uuid]);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_request_stage_times (
  task uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'stageId', h."to_stage_id", 'stageName', h."stage_name", 'category', h."category"::text,
    'enteredAt', h."entered_at", 'exitedAt', h."exited_at",
    'seconds', round(extract(epoch from (coalesce(h."exited_at", now()) - h."entered_at")))::bigint
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."maintenance_requests" x on x."id"::text = h."subject_id" and x."tenant_id" = h."tenant_id"
  where x."id" = maintenance_request_stage_times.task and h."subject_type" = 'maintenance_request'
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.read'), false)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_requests_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_maintenance_request (
  task   uuid,
  stage  uuid DEFAULT NULL::uuid,
  before uuid DEFAULT NULL::uuid,
  after  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_stage uuid;
  v_prev text;
  v_next text;
  v_rank text;
  v_tries integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = move_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null and move_maintenance_request.stage is null then
    raise exception 'a closed task keeps its place' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(move_maintenance_request.stage, v_row."stage_id");
  loop
    v_prev := null;
    v_next := null;
    if move_maintenance_request.after is not null then
      select x."rank" into v_prev from "better_supabase"."maintenance_requests" x where x."id" = move_maintenance_request.after and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place after isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_maintenance_request.before is not null then
      select x."rank" into v_next from "better_supabase"."maintenance_requests" x where x."id" = move_maintenance_request.before and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place before isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_maintenance_request.after is not null and move_maintenance_request.before is null then
      select min(x."rank" collate "C") into v_next from "better_supabase"."maintenance_requests" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" > v_prev collate "C";
    elsif move_maintenance_request.before is not null and move_maintenance_request.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."maintenance_requests" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" < v_next collate "C";
    elsif move_maintenance_request.before is null and move_maintenance_request.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."maintenance_requests" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
    end if;
    exit when v_prev is null or v_next is null or v_prev collate "C" < v_next collate "C";
    if v_tries > 0 then
      raise exception 'the neighbours share a rank key' using errcode = '22023', hint = 'TASK_RANK_CONFLICT';
    end if;
    v_tries := v_tries + 1;
    with ordered as (
      select x."id" as id, row_number() over (order by x."rank" collate "C", x."number", x."id") as nth, count(*) over () as total
      from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null)
    update "better_supabase"."maintenance_requests" y set "rank" = "better_supabase"."rank_key"(o.nth, o.total) from ordered o where y."id" = o.id;
  end loop;
  v_rank := "better_supabase"."rank_between"(v_prev, v_next);
  update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage, "rank" = v_rank where x."id" = v_row."id";
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('stageId', 'rank'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_maintenance_requests (
  moves jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_move jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(move_maintenance_requests.moves, '[]')) <> 'array' then
    raise exception 'moves must be a list' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_move in select value from jsonb_array_elements(move_maintenance_requests.moves) loop
    begin
      perform "better_supabase"."move_maintenance_request"((v_move ->> 'maintenanceRequestId')::uuid, (v_move ->> 'stageId')::uuid, (v_move ->> 'beforeId')::uuid, (v_move ->> 'afterId')::uuid);
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_move ->> 'maintenanceRequestId'));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_move ->> 'maintenanceRequestId', 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_work_item (
  task   uuid,
  stage  uuid DEFAULT NULL::uuid,
  before uuid DEFAULT NULL::uuid,
  after  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_prev text;
  v_next text;
  v_rank text;
  v_tries integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = move_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null and move_work_item.stage is null then
    raise exception 'a closed task keeps its place' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(move_work_item.stage, v_row."stage_id");
  loop
    v_prev := null;
    v_next := null;
    if move_work_item.after is not null then
      select x."rank" into v_prev from "better_supabase"."work_items" x where x."id" = move_work_item.after and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place after isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_work_item.before is not null then
      select x."rank" into v_next from "better_supabase"."work_items" x where x."id" = move_work_item.before and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place before isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_work_item.after is not null and move_work_item.before is null then
      select min(x."rank" collate "C") into v_next from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" > v_prev collate "C";
    elsif move_work_item.before is not null and move_work_item.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" < v_next collate "C";
    elsif move_work_item.before is null and move_work_item.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
    end if;
    exit when v_prev is null or v_next is null or v_prev collate "C" < v_next collate "C";
    if v_tries > 0 then
      raise exception 'the neighbours share a rank key' using errcode = '22023', hint = 'TASK_RANK_CONFLICT';
    end if;
    v_tries := v_tries + 1;
    with ordered as (
      select x."id" as id, row_number() over (order by x."rank" collate "C", x."number", x."id") as nth, count(*) over () as total
      from "better_supabase"."work_items" x
      where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null)
    update "better_supabase"."work_items" y set "rank" = "better_supabase"."rank_key"(o.nth, o.total) from ordered o where y."id" = o.id;
  end loop;
  v_rank := "better_supabase"."rank_between"(v_prev, v_next);
  update "better_supabase"."work_items" x set "stage_id" = v_stage, "rank" = v_rank where x."id" = v_row."id";
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('stageId', 'rank'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_work_items (
  moves jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_move jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(move_work_items.moves, '[]')) <> 'array' then
    raise exception 'moves must be a list' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_move in select value from jsonb_array_elements(move_work_items.moves) loop
    begin
      perform "better_supabase"."move_work_item"((v_move ->> 'workItemId')::uuid, (v_move ->> 'stageId')::uuid, (v_move ->> 'beforeId')::uuid, (v_move ->> 'afterId')::uuid);
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_move ->> 'workItemId'));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_move ->> 'workItemId', 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'advisories.publish' then 'advisories.publish'
    when 'advisories.read' then 'advisories.read'
    when 'advisories.write' then 'advisories.write'
    when 'agent-checkout.manage' then 'agent_checkout.manage'
    when 'agent-checkout.read' then 'agent_checkout.read'
    when 'agent-checkout.write' then 'agent_checkout.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.manage' then 'ai_chat.manage'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'appraisals.manage' then 'appraisals.manage'
    when 'appraisals.read' then 'appraisals.read'
    when 'appraisals.review' then 'appraisals.review'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.read' then 'audit.read'
    when 'audit.readAll' then 'audit.read'
    when 'audit.revert' then 'audit.revert'
    when 'automations.manage' then 'automations.manage'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'automations.write' then 'automations.write'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'billing.manage' then 'billing.manage'
    when 'billing.read' then 'billing.read'
    when 'billing.readAll' then 'billing.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk-actions.run' then 'bulk_actions.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'clinical-decision-support.manage' then 'clinical_decision_support.manage'
    when 'clinical-decision-support.read' then 'clinical_decision_support.read'
    when 'clinical-decision-support.write' then 'clinical_decision_support.write'
    when 'collections.read' then 'collections.read'
    when 'collections.share' then 'collections.share'
    when 'collections.write' then 'collections.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'commissions.manage' then 'commissions.manage'
    when 'commissions.read' then 'commissions.read'
    when 'commissions.write' then 'commissions.write'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deadlines.manage' then 'deadlines.manage'
    when 'deadlines.read' then 'deadlines.read'
    when 'deadlines.write' then 'deadlines.write'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'e-prescribing.manage' then 'e_prescribing.manage'
    when 'e-prescribing.read' then 'e_prescribing.read'
    when 'e-prescribing.sign' then 'e_prescribing.sign'
    when 'e-prescribing.write' then 'e_prescribing.write'
    when 'employees.read' then 'employees.read'
    when 'employees.readSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-encryption.manage' then 'field_encryption.manage'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'impersonation.read' then 'impersonation.read'
    when 'impersonation.revoke' then 'impersonation.revoke'
    when 'impersonation.start' then 'impersonation.start'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'incoming-webhooks.create' then 'webhooks.manage'
    when 'incoming-webhooks.delete' then 'webhooks.manage'
    when 'incoming-webhooks.read' then 'webhooks.read'
    when 'incoming-webhooks.update' then 'webhooks.manage'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.send' then 'invoices.send'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'leave.approve' then 'leave.approve'
    when 'leave.manage' then 'leave.manage'
    when 'leave.read' then 'leave.read'
    when 'leave.request' then 'leave.request'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'lims.manage' then 'lims.manage'
    when 'lims.read' then 'lims.read'
    when 'lims.write' then 'lims.write'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'numbering.read' then 'numbering.read'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'option-sets.manage' then 'option_sets.manage'
    when 'option-sets.read' then 'option_sets.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'periods.manage' then 'periods.manage'
    when 'periods.read' then 'periods.read'
    when 'periods.write' then 'periods.write'
    when 'permissions.explain' then 'members.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'referrals.manage' then 'referrals.manage'
    when 'referrals.read' then 'referrals.read'
    when 'referrals.write' then 'referrals.write'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'reviews.manage' then 'reviews.manage'
    when 'rfqs.manage' then 'rfqs.manage'
    when 'rfqs.read' then 'rfqs.read'
    when 'rfqs.write' then 'rfqs.write'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.read' then 'segments.read'
    when 'segments.write' then 'segments.write'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'tills.manage' then 'tills.manage'
    when 'tills.read' then 'tills.read'
    when 'tills.write' then 'tills.write'
    when 'time-entries.approve' then 'time_entries.approve'
    when 'time-entries.manage' then 'time_entries.manage'
    when 'time-entries.read' then 'time_entries.read'
    when 'time-entries.track' then 'time_entries.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
    when 'warranty.decide' then 'warranty.decide'
    when 'warranty.read' then 'warranty.read'
    when 'warranty.write' then 'warranty.write'
    when 'webhooks.manage' then 'webhooks.manage'
    when 'webhooks.read' then 'webhooks.read'
    when 'workflow-editor.manage' then 'workflow_editor.manage'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflow-editor.write' then 'workflow_editor.write'
    when 'workflows.manage' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_maintenance_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_maintenance_requests.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'priority') then
      raise exception 'facet is one of state, priority' using errcode = '22023', hint = 'TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (x."state")::text when 'priority' then (x."priority"::text)::text end) as v
      from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'title', 'dueAt', 'createdAt') then
    raise exception 'sort is one of number, title, dueAt, createdAt' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_work_items (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_work_items.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'priority') then
      raise exception 'facet is one of state, priority' using errcode = '22023', hint = 'TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (x."state")::text when 'priority' then (x."priority"::text)::text end) as v
      from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'title', 'dueAt', 'createdAt') then
    raise exception 'sort is one of number, title, dueAt, createdAt' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recount_maintenance_request_needs (
  ids uuid[]
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_next integer;
  v_was integer;
begin
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (coalesce(recount_maintenance_request_needs.ids, '{}')) order by x."id" for update loop
    select count(*)::integer into v_next
    from "better_supabase"."relations" r
    join "better_supabase"."maintenance_requests" p on p."id"::text = r."source_id" and p."tenant_id" = v_row."tenant_id"
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks'
      and r."source_type" = 'maintenance_request' and r."target_type" = 'maintenance_request'
      and r."target_id" = v_row."id"::text
      and not (p."state" = 'completed');
    v_was := v_row."waiting_on";
    if v_next is distinct from v_was then
      update "better_supabase"."maintenance_requests" x set "waiting_on" = v_next where x."id" = v_row."id" returning * into v_row;
      if v_next = 0 and v_row."closed_at" is null then
        perform "better_supabase".emit_event('maintenance_request.unblocked', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'waitingOn', 0, 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
      end if;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recount_work_item_needs (
  ids uuid[]
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_next integer;
  v_was integer;
begin
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (coalesce(recount_work_item_needs.ids, '{}')) order by x."id" for update loop
    select count(*)::integer into v_next
    from "better_supabase"."relations" r
    join "better_supabase"."work_items" p on p."id"::text = r."source_id" and p."tenant_id" = v_row."tenant_id"
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks'
      and r."source_type" = 'work_item' and r."target_type" = 'work_item'
      and r."target_id" = v_row."id"::text
      and not (p."state" = 'completed');
    v_was := v_row."waiting_on";
    if v_next is distinct from v_was then
      update "better_supabase"."work_items" x set "waiting_on" = v_next where x."id" = v_row."id" returning * into v_row;
      if v_next = 0 and v_row."closed_at" is null then
        perform "better_supabase".emit_event('work_item.unblocked', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'waitingOn', 0, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
      end if;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_maintenance_request_claim (
  task  uuid,
  token uuid,
  note  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."maintenance_request_claims";
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = release_maintenance_request_claim.task for update;
  if not found then
    raise exception 'nobody holds this task' using errcode = 'P0002', hint = 'TASK_CLAIM_NOT_HELD';
  end if;
  if v_claim."token" is distinct from release_maintenance_request_claim.token or not (v_claim."expires_at" > now()) then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  update "better_supabase"."maintenance_request_claims" c set "expires_at" = now(), "expired_at" = now() where c."maintenance_request_id" = release_maintenance_request_claim.task;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = release_maintenance_request_claim.task;
  perform "better_supabase".emit_event('maintenance_request.released', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'note', nullif(trim(release_maintenance_request_claim.note), ''), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(v_claim."profile") ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_maintenance_request_hold (
  task uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = release_maintenance_request_hold.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."held_at" is null then
    raise exception 'the task isn''t on hold' using errcode = '55000', hint = 'TASK_NOT_HELD';
  end if;
  v_kind := v_row."hold_kind";
  update "better_supabase"."maintenance_requests" x set "held_at" = null, "hold_kind" = null, "hold_return_stage_id" = null where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('maintenance_request.hold_released', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', v_kind, 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_work_item_claim (
  task  uuid,
  token uuid,
  note  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."work_item_claims";
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."work_item_claims" c where c."work_item_id" = release_work_item_claim.task for update;
  if not found then
    raise exception 'nobody holds this task' using errcode = 'P0002', hint = 'TASK_CLAIM_NOT_HELD';
  end if;
  if v_claim."token" is distinct from release_work_item_claim.token or not (v_claim."expires_at" > now()) then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  update "better_supabase"."work_item_claims" c set "expires_at" = now(), "expired_at" = now() where c."work_item_id" = release_work_item_claim.task;
  select * into v_row from "better_supabase"."work_items" x where x."id" = release_work_item_claim.task;
  perform "better_supabase".emit_event('work_item.released', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'note', nullif(trim(release_work_item_claim.note), ''), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_work_item_hold (
  task uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = release_work_item_hold.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."held_at" is null then
    raise exception 'the task isn''t on hold' using errcode = '55000', hint = 'TASK_NOT_HELD';
  end if;
  v_kind := v_row."hold_kind";
  update "better_supabase"."work_items" x set "held_at" = null, "hold_kind" = null, "hold_return_stage_id" = null where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('work_item.hold_released', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', v_kind, 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.renew_maintenance_request_claim (
  task  uuid,
  token uuid,
  lease integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."maintenance_request_claims";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."maintenance_request_claims" c set "expires_at" = now() + make_interval(secs => least(900, greatest(1, coalesce(renew_maintenance_request_claim.lease, 900))))
  where c."maintenance_request_id" = renew_maintenance_request_claim.task and c."token" = renew_maintenance_request_claim.token and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'facilities.write'), false))
  returning * into v_claim;
  if not found then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  return jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.renew_work_item_claim (
  task  uuid,
  token uuid,
  lease integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claim "better_supabase"."work_item_claims";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."work_item_claims" c set "expires_at" = now() + make_interval(secs => least(900, greatest(1, coalesce(renew_work_item_claim.lease, 900))))
  where c."work_item_id" = renew_work_item_claim.task and c."token" = renew_work_item_claim.token and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'tasks.write'), false))
  returning * into v_claim;
  if not found then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  return jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.repeat_maintenance_request (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."maintenance_requests";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = repeat_maintenance_request.task for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."maintenance_requests" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
  end if;
  v_shift := coalesce(repeat_maintenance_request.due_at - coalesce(v_src."due_at", v_src."end_at", v_src."start_at"), interval '0');
  v_next := "better_supabase"."create_maintenance_request"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'body', v_src."body", 'parentId', v_src."parent_id", 'teamId', v_src."team_id",
    'projectId', v_src."project_id", 'priority', v_src."priority", 'estimate', v_src."estimate",
    'startAt', v_src."start_at" + v_shift, 'endAt', v_src."end_at" + v_shift, 'dueAt', repeat_maintenance_request.due_at,
    'pipelineId', v_src."pipeline_id")) || jsonb_build_object('fields', jsonb_build_object('unit_id', v_src."unit_id", 'lease_id', v_src."lease_id")),
    array(select y."user_id" from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_src."id"));
  v_id := (v_next ->> 'id')::uuid;
  update "better_supabase"."maintenance_requests" x set "recurs_from" = v_src."id" where x."id" = v_id;
  insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "rank", "created_by")
  select y."tenant_id", v_id, y."title", y."rank", y."created_by" from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = v_src."id";
  update "better_supabase"."recurrence_rules" rr set "subject_id" = v_id::text
  where rr."tenant_id" = v_src."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = v_src."id"::text;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.repeat_work_item (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."work_items";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."work_items" x where x."id" = repeat_work_item.task for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."work_items" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
  end if;
  v_shift := coalesce(repeat_work_item.due_at - coalesce(v_src."due_at", v_src."end_at", v_src."start_at"), interval '0');
  v_next := "better_supabase"."create_work_item"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'body', v_src."body", 'parentId', v_src."parent_id", 'teamId', v_src."team_id",
    'projectId', v_src."project_id", 'priority', v_src."priority", 'estimate', v_src."estimate",
    'startAt', v_src."start_at" + v_shift, 'endAt', v_src."end_at" + v_shift, 'dueAt', repeat_work_item.due_at,
    'pipelineId', v_src."pipeline_id")),
    array(select y."user_id" from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_src."id"));
  v_id := (v_next ->> 'id')::uuid;
  update "better_supabase"."work_items" x set "recurs_from" = v_src."id" where x."id" = v_id;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "rank", "created_by")
  select y."tenant_id", v_id, y."title", y."rank", y."created_by" from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = v_src."id";
  update "better_supabase"."recurrence_rules" rr set "subject_id" = v_id::text
  where rr."tenant_id" = v_src."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_src."id"::text;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_maintenance_request_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_id uuid := save_maintenance_request_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_maintenance_request_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = save_maintenance_request_checklist_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = v_row."id";
      insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_maintenance_request_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_maintenance_request_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."maintenance_request_checklist_items" y set
        "title" = coalesce(trim(save_maintenance_request_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_maintenance_request_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."maintenance_request_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select jsonb_build_object('id', y."id", 'maintenanceRequestId', y."maintenance_request_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."maintenance_request_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_item_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_work_item_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = v_row."id";
      insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_work_item_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_work_item_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."work_item_checklist_items" y set
        "title" = coalesce(trim(save_work_item_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_work_item_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."work_item_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."work_item_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'maintenance_request.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_needs (
  task uuid,
  ids  uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_needs.ids, '{}')) x where x is not null);
  v_old uuid[];
  v_id uuid;
begin
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_needs.task and x."archived_at" is null;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if set_maintenance_request_needs.task = any (v_ids) then
    raise exception 'a task can''t wait on itself' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  if exists (select 1 from unnest(v_ids) x where not exists (
    select 1 from "better_supabase"."maintenance_requests" p where p."id" = x and p."tenant_id" = v_row."tenant_id")) then
    raise exception 'a prerequisite doesn''t exist in this organization' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  v_old := array(select r."source_id"::uuid from "better_supabase"."relations" r
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks' and r."source_type" = 'maintenance_request'
      and r."target_type" = 'maintenance_request' and r."target_id" = v_row."id"::text);
  foreach v_id in array array(select x from unnest(v_old) x where not (x = any (v_ids))) loop
    perform "better_supabase"."unlink"(v_row."tenant_id", 'blocks', 'maintenance_request', v_id::text, 'maintenance_request', v_row."id"::text);
  end loop;
  foreach v_id in array array(select x from unnest(v_ids) x where not (x = any (v_old))) loop
    perform "better_supabase"."link"(v_row."tenant_id", 'blocks', 'maintenance_request', v_id::text, 'maintenance_request', v_row."id"::text, '{}'::jsonb);
  end loop;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_recurrence.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_maintenance_request_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = v_row."id"::text;
  else
    if set_maintenance_request_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_maintenance_request_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'maintenance_request', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_maintenance_request_recurrence.tzid, 'UTC'), regexp_replace(set_maintenance_request_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) -> 'recurrence' from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_needs (
  task uuid,
  ids  uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := array(select distinct x from unnest(coalesce(set_work_item_needs.ids, '{}')) x where x is not null);
  v_old uuid[];
  v_id uuid;
begin
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_needs.task and x."archived_at" is null;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if set_work_item_needs.task = any (v_ids) then
    raise exception 'a task can''t wait on itself' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  if exists (select 1 from unnest(v_ids) x where not exists (
    select 1 from "better_supabase"."work_items" p where p."id" = x and p."tenant_id" = v_row."tenant_id")) then
    raise exception 'a prerequisite doesn''t exist in this organization' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  v_old := array(select r."source_id"::uuid from "better_supabase"."relations" r
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks' and r."source_type" = 'work_item'
      and r."target_type" = 'work_item' and r."target_id" = v_row."id"::text);
  foreach v_id in array array(select x from unnest(v_old) x where not (x = any (v_ids))) loop
    perform "better_supabase"."unlink"(v_row."tenant_id", 'blocks', 'work_item', v_id::text, 'work_item', v_row."id"::text);
  end loop;
  foreach v_id in array array(select x from unnest(v_ids) x where not (x = any (v_old))) loop
    perform "better_supabase"."link"(v_row."tenant_id", 'blocks', 'work_item', v_id::text, 'work_item', v_row."id"::text, '{}'::jsonb);
  end loop;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_recurrence.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_row."id"::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'work_item', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_maintenance_requests (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."maintenance_requests";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_maintenance_requests.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { maintenanceRequestId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_maintenance_requests.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'maintenanceRequestId')::uuid;
      if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."maintenance_requests" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."maintenance_requests" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."maintenance_requests" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."maintenance_requests" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."maintenance_requests" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."maintenance_requests" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."maintenance_requests" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."maintenance_requests" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."maintenance_requests" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."maintenance_requests" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."maintenance_requests" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."maintenance_requests" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."maintenance_requests" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."maintenance_requests" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."maintenance_requests" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."maintenance_requests" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      when 'unit_id' then
        update "better_supabase"."maintenance_requests" x set "unit_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', v_change -> 'value')))."unit_id" where x."id" = v_item;
      when 'lease_id' then
        update "better_supabase"."maintenance_requests" x set "lease_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', v_change -> 'value')))."lease_id" where x."id" = v_item;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_maintenance_requests.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_change ->> 'maintenanceRequestId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'maintenanceRequestId')::uuid = v_row."id"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_work_items (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."work_items";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."work_items" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."work_items" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."work_items" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."work_items" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."work_items" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."work_items" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."work_items" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."work_items" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."work_items" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."work_items" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."work_items" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."work_items" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."work_items" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."work_items" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."work_items" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."work_items" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_work_items.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_item_actor (
  profile jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'kind', case
      when work_item_actor.profile ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then work_item_actor.profile ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end,
    'name', left(coalesce(nullif(work_item_actor.profile ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_item_claim (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('epoch', c."epoch", 'holderId', c."holder_id", 'profile', c."profile", 'claimedAt', c."claimed_at", 'expiresAt', c."expires_at")
  from "better_supabase"."work_item_claims" c
  where c."work_item_id" = work_item_claim.task and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'tasks.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_item_claims_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."work_item_id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."work_item_id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_item_needs_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and tg_table_name = 'work_items' then
    perform "better_supabase"."recount_work_item_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = old."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'work_item' and r."source_id" = old."id"::text and r."target_type" = 'work_item'));
  elsif tg_table_name = 'work_items' then
    perform "better_supabase"."recount_work_item_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = new."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'work_item' and r."source_id" = new."id"::text and r."target_type" = 'work_item'));
  elsif tg_op = 'DELETE' then
    if old."kind" = 'blocks' and old."target_type" = 'work_item' and old."source_type" = 'work_item' then
      perform "better_supabase"."recount_work_item_needs"(array[old."target_id"::uuid]);
    end if;
  elsif new."kind" = 'blocks' and new."target_type" = 'work_item' and new."source_type" = 'work_item' then
    perform "better_supabase"."recount_work_item_needs"(array[new."target_id"::uuid]);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_item_stage_times (
  task uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'stageId', h."to_stage_id", 'stageName', h."stage_name", 'category', h."category"::text,
    'enteredAt', h."entered_at", 'exitedAt', h."exited_at",
    'seconds', round(extract(epoch from (coalesce(h."exited_at", now()) - h."entered_at")))::bigint
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."work_items" x on x."id"::text = h."subject_id" and x."tenant_id" = h."tenant_id"
  where x."id" = work_item_stage_times.task and h."subject_type" = 'work_item'
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.work_items_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$function$;

ALTER TABLE "better_supabase"."maintenance_request_claims"
  ADD CONSTRAINT "maintenance_request_claims_maintenance_request_id_fkey" FOREIGN KEY (maintenance_request_id) REFERENCES better_supabase.maintenance_requests(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD CONSTRAINT "bsb_maintenance_requests_close_reason_check" CHECK ((close_reason = ANY (ARRAY['completed'::text, 'not_planned'::text, 'duplicate'::text, 'failed'::text])));

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD CONSTRAINT "bsb_maintenance_requests_waiting_on_check" CHECK ((waiting_on >= 0));

ALTER TABLE "better_supabase"."work_item_claims"
  ADD CONSTRAINT "work_item_claims_work_item_id_fkey" FOREIGN KEY (work_item_id) REFERENCES better_supabase.work_items(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."work_items"
  ADD CONSTRAINT "bsb_work_items_close_reason_check" CHECK ((close_reason = ANY (ARRAY['completed'::text, 'not_planned'::text, 'duplicate'::text, 'failed'::text])));

ALTER TABLE "better_supabase"."work_items"
  ADD CONSTRAINT "bsb_work_items_waiting_on_check" CHECK ((waiting_on >= 0));

CREATE VIEW "better_supabase"."maintenance_jobs" WITH (security_invoker=true) AS  SELECT j.job,
    j.fn AS function,
    j.every_interval AS every,
    s.last_run_at,
    s.last_status,
    s.last_error,
    COALESCE(s.runs, (0)::bigint) AS runs,
    ((s.last_run_at IS NULL) OR ((s.last_run_at + j.every_interval) <= now())) AS due
   FROM (( VALUES ('digest_run'::text,'"better_supabase"."run_notification_digests"'::text,'01:00:00'::interval), ('expire_approvals'::text,'"better_supabase"."expire_approvals"'::text,'00:15:00'::interval), ('expire_support_sessions'::text,'"better_supabase"."expire_support_sessions"'::text,'00:05:00'::interval), ('expire_work_item_claims'::text,'"better_supabase"."expire_work_item_claims"'::text,'00:01:00'::interval), ('purge_chat_state'::text,'"better_supabase"."purge_chat_state"'::text,'00:15:00'::interval), ('purge_expired_trash'::text,'"better_supabase"."purge_expired_trash"'::text,'1 day'::interval), ('purge_idempotency_keys'::text,'better_supabase.purge_idempotency_keys'::text,'01:00:00'::interval), ('purge_rate_limits'::text,'better_supabase.purge_rate_limits'::text,'00:15:00'::interval), ('purge_usage_events'::text,'"better_supabase"."purge_usage_events"'::text,'1 day'::interval), ('purge_webhook_deliveries'::text,'"better_supabase"."purge_webhook_deliveries"'::text,'1 day'::interval), ('purge_webhooks'::text,'better_supabase.purge_webhooks'::text,'1 day'::interval)) j(job, fn, every_interval)
     LEFT JOIN better_supabase.maintenance_state s ON ((s.job = j.job)));

CREATE INDEX maintenance_request_claims_expires_idx ON better_supabase.maintenance_request_claims USING btree (expires_at);

CREATE INDEX maintenance_request_claims_tenant_idx ON better_supabase.maintenance_request_claims USING btree (tenant_id, holder_id);

CREATE UNIQUE INDEX maintenance_request_claims_unique_idx ON better_supabase.maintenance_request_claims USING btree (maintenance_request_id);

CREATE INDEX maintenance_requests_ready_idx ON better_supabase.maintenance_requests USING btree (tenant_id, number)
  WHERE ((waiting_on = 0) AND (closed_at IS NULL));

CREATE INDEX work_item_claims_expires_idx ON better_supabase.work_item_claims USING btree (expires_at);

CREATE INDEX work_item_claims_tenant_idx ON better_supabase.work_item_claims USING btree (tenant_id, holder_id);

CREATE UNIQUE INDEX work_item_claims_unique_idx ON better_supabase.work_item_claims USING btree (work_item_id);

CREATE INDEX work_items_ready_idx ON better_supabase.work_items USING btree (tenant_id, number)
  WHERE ((waiting_on = 0) AND (closed_at IS NULL));

CREATE TRIGGER bsb_maintenance_request_claims_changed
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_request_claims
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.maintenance_request_claims_changed();

CREATE TRIGGER bsb_maintenance_request_needs_state
  AFTER DELETE OR UPDATE OF state ON better_supabase.maintenance_requests
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.maintenance_request_needs_changed();

CREATE TRIGGER bsb_maintenance_requests_changed
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_requests
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.maintenance_requests_changed();

CREATE TRIGGER bsb_maintenance_request_needs_relation
  AFTER INSERT OR DELETE ON better_supabase.relations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.maintenance_request_needs_changed();

CREATE TRIGGER bsb_work_item_needs_relation
  AFTER INSERT OR DELETE ON better_supabase.relations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.work_item_needs_changed();

CREATE TRIGGER bsb_work_item_claims_changed
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_item_claims
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.work_item_claims_changed();

CREATE TRIGGER bsb_work_item_needs_state
  AFTER DELETE OR UPDATE OF state ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.work_item_needs_changed();

CREATE TRIGGER bsb_work_items_changed
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.work_items_changed();

CREATE POLICY "bsb_maintenance_requests_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'tasks:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 7) IN ( SELECT (x.x)::text AS x
   FROM better_supabase.tenant_ids_with('facilities.read'::text) x(x)))));

CREATE POLICY "bsb_work_items_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'tasks:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 7) IN ( SELECT (x.x)::text AS x
   FROM better_supabase.tenant_ids_with('tasks.read'::text) x(x)))));

REVOKE ALL ON FUNCTION "api"."claim_maintenance_request"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_maintenance_request"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_next_maintenance_request"(uuid, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_next_maintenance_request"(uuid, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_next_work_item"(uuid, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_next_work_item"(uuid, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_work_item"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_work_item"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."close_maintenance_request"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_maintenance_request"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."close_work_item"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_work_item"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_maintenance_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_maintenance_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_work_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_work_items"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delegate_maintenance_request"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delegate_maintenance_request"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delegate_work_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delegate_work_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."expire_maintenance_request_claims"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."expire_maintenance_request_claims"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."expire_work_item_claims"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."expire_work_item_claims"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."explain_permission"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."explain_permission"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."hold_maintenance_request"(uuid, text, text, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."hold_maintenance_request"(uuid, text, text, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."hold_work_item"(uuid, text, text, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."hold_work_item"(uuid, text, text, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_request_actor"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_request_actor"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_request_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_request_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_request_stage_times"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_request_stage_times"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."move_maintenance_request"(uuid, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."move_maintenance_request"(uuid, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."move_maintenance_requests"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."move_maintenance_requests"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."move_work_item"(uuid, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."move_work_item"(uuid, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."move_work_items"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."move_work_items"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."release_maintenance_request_claim"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_maintenance_request_claim"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."release_maintenance_request_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_maintenance_request_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."release_work_item_claim"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_work_item_claim"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."release_work_item_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_work_item_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."renew_maintenance_request_claim"(uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."renew_maintenance_request_claim"(uuid, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."renew_work_item_claim"(uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."renew_work_item_claim"(uuid, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_maintenance_request_needs"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_maintenance_request_needs"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_work_item_needs"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_work_item_needs"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."work_item_actor"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."work_item_actor"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."work_item_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."work_item_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."work_item_stage_times"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."work_item_stage_times"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_maintenance_request"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_maintenance_request"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_next_maintenance_request"(uuid, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_next_maintenance_request"(uuid, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_next_work_item"(uuid, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_next_work_item"(uuid, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_work_item"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_work_item"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_maintenance_request"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_maintenance_request"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_work_item"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_work_item"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_maintenance_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_maintenance_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_work_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_work_items"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delegate_maintenance_request"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delegate_maintenance_request"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delegate_work_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delegate_work_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."expire_maintenance_request_claims"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expire_maintenance_request_claims"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."expire_work_item_claims"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expire_work_item_claims"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."explain_permission"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."explain_permission"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."hold_maintenance_request"(uuid, text, text, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."hold_maintenance_request"(uuid, text, text, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."hold_work_item"(uuid, text, text, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."hold_work_item"(uuid, text, text, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_request_actor"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_request_actor"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_request_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_request_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_request_claims_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_request_needs_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_request_stage_times"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_request_stage_times"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_requests_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."move_maintenance_request"(uuid, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."move_maintenance_request"(uuid, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."move_maintenance_requests"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."move_maintenance_requests"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."move_work_item"(uuid, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."move_work_item"(uuid, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."move_work_items"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."move_work_items"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."recount_maintenance_request_needs"(uuid[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."recount_work_item_needs"(uuid[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."release_maintenance_request_claim"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_maintenance_request_claim"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_maintenance_request_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_maintenance_request_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_work_item_claim"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_work_item_claim"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_work_item_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_work_item_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."renew_maintenance_request_claim"(uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."renew_maintenance_request_claim"(uuid, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."renew_work_item_claim"(uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."renew_work_item_claim"(uuid, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_maintenance_request_needs"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_maintenance_request_needs"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_work_item_needs"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_work_item_needs"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."work_item_actor"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."work_item_actor"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."work_item_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."work_item_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."work_item_claims_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."work_item_needs_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."work_item_stage_times"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."work_item_stage_times"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."work_items_changed"() FROM PUBLIC;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."maintenance_request_claims" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."work_item_claims" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_jobs" TO "service_role";
