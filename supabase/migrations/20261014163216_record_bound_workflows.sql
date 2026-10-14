SET local check_function_bodies = off;

DROP POLICY "activity_entries_read" ON "better_supabase"."activity_entries";

DROP POLICY "workflow_definitions_read" ON "better_supabase"."workflow_definitions";

DROP FUNCTION "api"."complete_notification_delivery"(uuid, text, text, text, text, integer);

DROP FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean);

DROP FUNCTION "api"."save_workflow_definition"(uuid, text, text, text);

DROP FUNCTION "api"."save_workflow_draft"(uuid, jsonb);

DROP FUNCTION "api"."workflow_definitions_list"(uuid);

DROP FUNCTION "api"."workflow_run_principal"(uuid);

DROP FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone);

DROP FUNCTION "api"."workflow_start_target"(uuid);

DROP FUNCTION "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer);

DROP FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean);

DROP FUNCTION "better_supabase"."save_workflow_definition"(uuid, text, text, text);

DROP FUNCTION "better_supabase"."save_workflow_draft"(uuid, jsonb);

DROP FUNCTION "better_supabase"."workflow_definitions_list"(uuid);

DROP FUNCTION "better_supabase"."workflow_run_principal"(uuid);

DROP FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."workflow_start_target"(uuid);

CREATE TABLE "better_supabase"."notification_delivery_events" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "delivery_id"       uuid                     NOT NULL,
  "organization_id"   uuid,
  "kind"              text                     NOT NULL,
  "provider"          text,
  "provider_event_id" text,
  "occurred_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "detail"            jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_delivery_events_kind_check"
    CHECK ((kind = ANY (ARRAY['delayed'::text, 'delivered'::text, 'opened'::text, 'clicked'::text, 'bounced'::text, 'complained'::text]))),
  CONSTRAINT "notification_delivery_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "notification_delivery_events_provider_event_id_key" UNIQUE (provider_event_id)
);

ALTER TABLE "better_supabase"."notification_delivery_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_definition_grants" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "definition_id"  uuid                     NOT NULL,
  "principal_kind" text                     NOT NULL,
  "principal_id"   text                     NOT NULL,
  "action"         text                     NOT NULL,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_definition_grants_action_check" CHECK ((action = ANY (ARRAY['run'::text, 'edit'::text]))),
  CONSTRAINT "workflow_definition_grants_key" UNIQUE (definition_id, principal_kind, principal_id, action),
  CONSTRAINT "workflow_definition_grants_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_definition_grants_principal_id_check" CHECK (((length(principal_id) >= 1) AND (length(principal_id) <= 200))),
  CONSTRAINT "workflow_definition_grants_principal_kind_check" CHECK ((principal_kind = ANY (ARRAY['user'::text, 'team'::text, 'role'::text])))
);

ALTER TABLE "better_supabase"."workflow_definition_grants"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_opt_outs" (
  "tenant_id"     uuid                     NOT NULL,
  "definition_id" uuid                     NOT NULL,
  "created_by"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_opt_outs_pkey" PRIMARY KEY (tenant_id, definition_id)
);

ALTER TABLE "better_supabase"."workflow_opt_outs"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD COLUMN "provider_status" text;

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD COLUMN "provider_status_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD COLUMN "template_key" text;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD COLUMN "subject_types" text[] NOT NULL DEFAULT '{}'::text[];

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD COLUMN "scope" text NOT NULL DEFAULT 'tenant'::text;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD COLUMN "forked_from" uuid;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD COLUMN "forked_from_version" integer;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD COLUMN "restricted" boolean NOT NULL DEFAULT false;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "subject_type" text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "subject_id" text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "principal_kind" text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "principal_id" text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "mode" text NOT NULL DEFAULT 'live'::text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "trigger_node" text;

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD COLUMN "subject_type" text;

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD COLUMN "subject_id" text;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD COLUMN "input_schema" jsonb;

CREATE OR REPLACE FUNCTION api.complete_notification_delivery (
  delivery            uuid,
  status              text,
  provider            text    DEFAULT NULL::text,
  provider_message_id text    DEFAULT NULL::text,
  error               text    DEFAULT NULL::text,
  max_attempts        integer DEFAULT 5,
  template_key        text    DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_notification_delivery"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.fork_workflow_definition (
  source uuid,
  tenant uuid,
  slug   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fork_workflow_definition"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_subject_deliveries (
  subject_type text,
  subject_id   text,
  tenant       uuid    DEFAULT NULL::uuid,
  max_items    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_subject_deliveries"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.record_delivery_event (
  provider            text,
  provider_message_id text,
  kind                text,
  provider_event_id   text                     DEFAULT NULL::text,
  occurred_at         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  detail              jsonb                    DEFAULT '{}'::jsonb,
  suppress            boolean                  DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_delivery_event"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.record_workflow_run (
  engine         text,
  external_id    text,
  definition     text,
  status         text,
  tenant         uuid                     DEFAULT NULL::uuid,
  actor          uuid                     DEFAULT NULL::uuid,
  attributes     jsonb                    DEFAULT '{}'::jsonb,
  error          text                     DEFAULT NULL::text,
  started_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type   text                     DEFAULT NULL::text,
  subject_id     text                     DEFAULT NULL::text,
  principal_kind text                     DEFAULT NULL::text,
  principal_id   text                     DEFAULT NULL::text,
  mode           text                     DEFAULT NULL::text,
  trigger_node   text                     DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_workflow_run"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16) $function$;

CREATE OR REPLACE FUNCTION api.request_workflow_start (
  key          text,
  workflow     text,
  payload      jsonb    DEFAULT '{}'::jsonb,
  tenant       uuid     DEFAULT NULL::uuid,
  actor        uuid     DEFAULT NULL::uuid,
  concurrency  integer  DEFAULT NULL::integer,
  debounce     interval DEFAULT NULL::interval,
  singleton    boolean  DEFAULT false,
  subject_type text     DEFAULT NULL::text,
  subject_id   text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_workflow_start"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_definition (
  tenant        uuid,
  slug          text,
  name          text,
  description   text    DEFAULT NULL::text,
  subject_types text[]  DEFAULT NULL::text[],
  scope         text    DEFAULT NULL::text,
  restricted    boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_definition"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_draft (
  definition   uuid,
  graph        jsonb,
  input_schema jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_draft"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_workflow_definition_grant (
  definition     uuid,
  principal_kind text,
  principal_id   text,
  action         text,
  granted        boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_workflow_definition_grant"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.set_workflow_opt_out (
  tenant     uuid,
  definition uuid,
  opted_out  boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_workflow_opt_out"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.start_test_run (
  definition   uuid,
  version      uuid  DEFAULT NULL::uuid,
  trigger_node text  DEFAULT NULL::text,
  input        jsonb DEFAULT NULL::jsonb,
  stubs        jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."start_test_run"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definition_grants_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definition_grants_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definitions_list (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definitions_list"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_run_principal (
  version uuid,
  tenant  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_run_principal"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_runs_list (
  tenant       uuid                     DEFAULT NULL::uuid,
  definition   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  max          integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  mode         text                     DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_runs_list"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.workflow_start_target (
  definition uuid,
  tenant     uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_start_target"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_subject_start_target (
  definition   uuid,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_subject_start_target"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.activity_subject_readable (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return coalesce("better_supabase"."can_subject"(subject_type, subject_id, 'read'), false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_workflow_alerts (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_pair record;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_run "better_supabase"."workflow_runs"%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x."id" as alert, y."id" as run from "better_supabase"."workflow_alerts" x
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bs.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
      and y."mode" = 'live'
      and y."status" in ('queued', 'running', 'waiting')
      and y."created_at" < now() - x."threshold"
      and not exists (select 1 from "better_supabase"."workflow_alert_fires" z where z."alert_id" = x."id" and z."run_id" = y."id")
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from "better_supabase"."workflow_alerts" x where x."id" = v_pair.alert;
    select * into v_run from "better_supabase"."workflow_runs" x where x."id" = v_pair.run;
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return v_fired;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_workflow_start_requests (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."workflow_start_requests"%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_taken integer := 0;
begin
  for v_row in
    select * from "better_supabase"."workflow_start_requests"
    where "status" = 'pending'
      and "not_before" <= now()
      and ("claimed_until" is null or "claimed_until" < now())
    order by "created_at"
    for update skip locked
  loop
    exit when v_taken >= greatest(coalesce(batch, 50), 1);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(v_row."key"));
    if v_row."concurrency" is null
      or "better_supabase"."workflow_admission_active"(v_row."key") < v_row."concurrency" then
      update "better_supabase"."workflow_start_requests" set "claimed_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
      where "id" = v_row."id";
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', v_row."id",
        'key', v_row."key",
        'workflow', v_row."workflow",
        'input', v_row."input",
        'tenant', v_row."tenant_id",
        'actor', v_row."actor_id",
        'subjectType', v_row."subject_type",
        'subjectId', v_row."subject_id"
      ));
      v_taken := v_taken + 1;
    end if;
  end loop;
  return v_out;
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
    perform better_supabase.audit_event(
    event_type => 'comment.deleted',
    category => 'data',
    target_type => 'comment',
    record_id => new."id"::text,
    tenant => (new."organization_id")::uuid,
    metadata => jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id")
  );
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
      and case new."subject_type" when 'customer' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'customers.read'), false) else true end
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
  -- The author and newly mentioned members follow the subject
  -- (participating); a level a member already chose stays.
  insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
  select distinct new."organization_id", f.x, new."subject_type", new."subject_id", 'participating'
  from unnest(case when tg_op = 'INSERT' then array[new."author_id"] else '{}'::uuid[] end || v_new) f(x)
  where f.x is not null
  on conflict do nothing;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_notification_delivery (
  delivery            uuid,
  status              text,
  provider            text    DEFAULT NULL::text,
  provider_message_id text    DEFAULT NULL::text,
  error               text    DEFAULT NULL::text,
  max_attempts        integer DEFAULT 5,
  template_key        text    DEFAULT NULL::text
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
    "template_key" = coalesce(complete_notification_delivery.template_key, d."template_key"),
    "delivered_at" = case when v_status = 'sent' then now() else d."delivered_at" end,
    "attempted_at" = case when v_status = 'pending' then null else d."attempted_at" end,
    "next_attempt_at" = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, greatest(d."attempts", 1) - 1)))) else d."next_attempt_at" end
  where d."id" = complete_notification_delivery.delivery;
  return v_status;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fork_workflow_definition (
  source uuid,
  tenant uuid,
  slug   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_src "better_supabase"."workflow_definitions"%rowtype;
  v_version "better_supabase"."workflow_versions"%rowtype;
  v_row "better_supabase"."workflow_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."workflow_definitions" x where x."id" = source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" is not distinct from tenant) then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_src."scope" = 'tenant' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = source), false)
      or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = source
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      )) then
    raise exception 'You may not fork this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."workflow_versions" x where x."definition_id" = source and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."workflow_definitions" ("tenant_id", "slug", "name", "description", "subject_types", "forked_from", "forked_from_version", "created_by")
  values (tenant, slug, v_src."name", v_src."description", v_src."subject_types", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "input_schema", "created_by")
  values (v_row."id", 1, v_version."graph", v_version."input_schema", (select auth.uid()));
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'subjectTypes', to_jsonb(v_row."subject_types"),
    'scope', v_row."scope",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'restricted', v_row."restricted",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  ) || jsonb_build_object('draft', true, 'upstreamVersion', v_version."version", 'behind', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{customer}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'customer' then 'public.customers'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_subject_deliveries (
  subject_type text,
  subject_id   text,
  tenant       uuid    DEFAULT NULL::uuid,
  max_items    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
  v_permissions text[];
  v_missing text[];
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."definition_id"), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_row."definition_id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := "better_supabase"."workflow_graph_permissions"(v_row."graph");
  if not v_service then
    select array_agg(p order by p) into v_missing
    from unnest(v_permissions) p
    where not coalesce(better_supabase.can('tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', array_to_string(v_missing, ', ')
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN',
          detail = jsonb_build_object('permissions', to_jsonb(v_missing))::text;
    end if;
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set
    "status" = 'published',
    "compiled" = compiled,
    "published_at" = now(),
    "published_by" = case when v_service then null else (select auth.uid()) end,
    "owner_kind" = case when v_service then 'organization' else 'user' end,
    "permissions" = v_permissions
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
end;
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_workflow_run (
  engine         text,
  external_id    text,
  definition     text,
  status         text,
  tenant         uuid                     DEFAULT NULL::uuid,
  actor          uuid                     DEFAULT NULL::uuid,
  attributes     jsonb                    DEFAULT '{}'::jsonb,
  error          text                     DEFAULT NULL::text,
  started_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type   text                     DEFAULT NULL::text,
  subject_id     text                     DEFAULT NULL::text,
  principal_kind text                     DEFAULT NULL::text,
  principal_id   text                     DEFAULT NULL::text,
  mode           text                     DEFAULT NULL::text,
  trigger_node   text                     DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into "better_supabase"."workflow_runs" as x ("engine", "external_id", "definition", "status", "tenant_id", "actor_id", "attributes", "error", "started_at", "completed_at", "subject_type", "subject_id", "principal_kind", "principal_id", "mode", "trigger_node")
  values (engine, external_id, definition, status, tenant, actor, coalesce(attributes, '{}'::jsonb), left(error, 4000), started_at, completed_at, subject_type, subject_id, principal_kind, principal_id, coalesce(mode, 'live'), trigger_node)
  on conflict on constraint workflow_runs_engine_external_key do update set
    "definition" = excluded."definition",
    "status" = excluded."status",
    "tenant_id" = coalesce(x."tenant_id", excluded."tenant_id"),
    "actor_id" = coalesce(x."actor_id", excluded."actor_id"),
    "attributes" = x."attributes" || excluded."attributes",
    "error" = coalesce(excluded."error", x."error"),
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "completed_at" = coalesce(excluded."completed_at", x."completed_at"),
    "subject_type" = case when x."subject_type" is null then excluded."subject_type" else x."subject_type" end,
    "subject_id" = case when x."subject_type" is null then excluded."subject_id" else x."subject_id" end,
    "principal_kind" = case when x."principal_kind" is null then excluded."principal_kind" else x."principal_kind" end,
    "principal_id" = case when x."principal_kind" is null then excluded."principal_id" else x."principal_id" end,
    "trigger_node" = coalesce(x."trigger_node", excluded."trigger_node"),
    "updated_at" = now()
  returning x."id" into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_trigger (
  trigger uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_triggers" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = trigger and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.edit'), false)))
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = y."id"), false)
      or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = y."id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = y."tenant_id" and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_cancel (
  run text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."workflow_runs" x
  where (x."id"::text = request_workflow_cancel.run or x."external_id" = request_workflow_cancel.run)
  order by x."id"::text = request_workflow_cancel.run desc
  limit 1
  for update;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or v_run."actor_id" = (select auth.uid())
    or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'workflow.admin'), false))) then
    raise exception 'You may not cancel this run' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_run."status" in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node"
  );
  end if;
  update "better_supabase"."workflow_runs" set "cancel_requested_at" = coalesce("cancel_requested_at", now()), "updated_at" = now()
  where "id" = v_run."id"
  returning * into v_run;
  return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_start (
  key          text,
  workflow     text,
  payload      jsonb    DEFAULT '{}'::jsonb,
  tenant       uuid     DEFAULT NULL::uuid,
  actor        uuid     DEFAULT NULL::uuid,
  concurrency  integer  DEFAULT NULL::integer,
  debounce     interval DEFAULT NULL::interval,
  singleton    boolean  DEFAULT false,
  subject_type text     DEFAULT NULL::text,
  subject_id   text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    "better_supabase"."workflow_admission_active"(key) > 0
    or exists (select 1 from "better_supabase"."workflow_start_requests" x where x."key" = key and x."status" = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update "better_supabase"."workflow_start_requests" x set "status" = 'superseded'
    where x."key" = key and x."status" = 'pending'
      and (x."claimed_until" is null or x."claimed_until" < now());
  end if;
  insert into "better_supabase"."workflow_start_requests" ("key", "workflow", "input", "tenant_id", "actor_id", "concurrency", "not_before", "subject_type", "subject_id")
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0'), subject_type, subject_id)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_workflow_webhook_token (
  trigger uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_definition uuid;
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."tenant_id", y."id", x."kind" into v_tenant, v_definition, v_kind
  from "better_supabase"."workflow_triggers" x join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."id" = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_kind <> 'webhook' then
    raise exception 'Only webhook triggers have tokens' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_KIND';
  end if;
  delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
  insert into "better_supabase"."workflow_webhook_tokens" ("token_hash", "trigger_id")
  values (extensions.digest(v_token, 'sha256'), trigger);
  return v_token;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_definition (
  tenant        uuid,
  slug          text,
  name          text,
  description   text    DEFAULT NULL::text,
  subject_types text[]  DEFAULT NULL::text[],
  scope         text    DEFAULT NULL::text,
  restricted    boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_definitions"%rowtype;
  v_scope text := coalesce(scope, 'tenant');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('tenant', 'system') then
    raise exception 'scope is tenant or system' using errcode = '22023', hint = 'WORKFLOW_SCOPE_INVALID';
  end if;
  if v_scope = 'system' and tenant is not null then
    raise exception 'A system workflow has no tenant' using errcode = '22023', hint = 'WORKFLOW_SCOPE_INVALID';
  end if;
  if v_scope = 'system' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role saves a system workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workflow_definitions" x
  where x."tenant_id" is not distinct from tenant and x."slug" = slug
  for update;
  if found then
    if scope is not null and scope <> v_row."scope" then
      raise exception 'A workflow''s scope never changes' using errcode = '22023', hint = 'WORKFLOW_SCOPE_FIXED';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."id"), false)
      or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_row."id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      )) then
      raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    if restricted is not null and restricted <> v_row."restricted" and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
      raise exception 'Only a workflow admin restricts a workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    update "better_supabase"."workflow_definitions" x set
      "name" = name,
      "description" = description,
      "subject_types" = coalesce(subject_types, x."subject_types"),
      "restricted" = coalesce(restricted, x."restricted"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(restricted, false) and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
      raise exception 'Only a workflow admin restricts a workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    insert into "better_supabase"."workflow_definitions" ("tenant_id", "slug", "name", "description", "subject_types", "scope", "restricted", "created_by")
    values (tenant, slug, name, description, coalesce(subject_types, '{}'), v_scope, coalesce(restricted, false), (select auth.uid()))
    returning * into v_row;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'subjectTypes', to_jsonb(v_row."subject_types"),
    'scope', v_row."scope",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'restricted', v_row."restricted",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_draft (
  definition   uuid,
  graph        jsonb,
  input_schema jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  if input_schema is not null and jsonb_typeof(input_schema) <> 'object' then
    raise exception 'An input schema is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null,
    "input_schema" = coalesce(input_schema, x."input_schema")
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "input_schema", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
      coalesce(input_schema, (select y."input_schema" from "better_supabase"."workflow_versions" y
        where y."definition_id" = definition order by y."version" desc limit 1)),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "updated_at" = now() where x."id" = definition;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_trigger (
  definition uuid,
  kind       text,
  config     jsonb   DEFAULT '{}'::jsonb,
  enabled    boolean DEFAULT true,
  trigger    uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_triggers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if trigger is null then
    insert into "better_supabase"."workflow_triggers" ("definition_id", "kind", "config", "enabled")
    values (definition, kind, coalesce(config, '{}'::jsonb), coalesce(enabled, true))
    returning * into v_row;
  else
    update "better_supabase"."workflow_triggers" x set
      "kind" = kind,
      "config" = coalesce(config, '{}'::jsonb),
      "enabled" = coalesce(enabled, true),
      "updated_at" = now()
    where x."id" = trigger and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
    if kind <> 'webhook' then
      delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'kind', v_row."kind",
    'config', v_row."config",
    'enabled', v_row."enabled",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_workflow_definition_grant (
  definition     uuid,
  principal_kind text,
  principal_id   text,
  action         text,
  granted        boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage access to this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if principal_kind is null or principal_kind not in ('user', 'team', 'role') then
    raise exception 'principal_kind is user, team or role' using errcode = '22023', hint = 'WORKFLOW_GRANT_INVALID';
  end if;
  if action is null or action not in ('run', 'edit') then
    raise exception 'action is run or edit' using errcode = '22023', hint = 'WORKFLOW_GRANT_INVALID';
  end if;
  if coalesce(granted, true) then
    insert into "better_supabase"."workflow_definition_grants" ("definition_id", "principal_kind", "principal_id", "action", "created_by")
    values (definition, principal_kind, principal_id, action, (select auth.uid()))
    on conflict on constraint workflow_definition_grants_key do nothing;
  else
    delete from "better_supabase"."workflow_definition_grants" x
    where x."definition_id" = definition and x."principal_kind" = principal_kind
      and x."principal_id" = principal_id and x."action" = action;
  end if;
  return coalesce(granted, true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_workflow_opt_out (
  tenant     uuid,
  definition uuid,
  opted_out  boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if tenant is null then
    raise exception 'Pass the tenant that opts out' using errcode = '22023', hint = 'WORKFLOW_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."workflow_definitions" x
    where x."id" = definition and (x."scope" = 'system' or x."tenant_id" = tenant)
  ) then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if coalesce(opted_out, true) then
    insert into "better_supabase"."workflow_opt_outs" ("tenant_id", "definition_id", "created_by")
    values (tenant, definition, (select auth.uid()))
    on conflict do nothing;
  else
    delete from "better_supabase"."workflow_opt_outs" x where x."tenant_id" = tenant and x."definition_id" = definition;
  end if;
  return coalesce(opted_out, true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_test_run (
  definition   uuid,
  version      uuid  DEFAULT NULL::uuid,
  trigger_node text  DEFAULT NULL::text,
  input        jsonb DEFAULT NULL::jsonb,
  stubs        jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_errors jsonb;
  v_triggers text[];
  v_node text := trigger_node;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_def."tenant_id" and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not test this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if stubs is not null and jsonb_typeof(stubs) <> 'object' then
    raise exception 'stubs is an object keyed by node id' using errcode = '22023', hint = 'WORKFLOW_STUBS_INVALID';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x
  where x."definition_id" = definition
    and (case when version is null then x."status" in ('draft', 'published') else x."id" = version end)
  order by x."status" = 'draft' desc
  limit 1;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  select array_agg(n.value ->> 'id') into v_triggers
  from jsonb_array_elements(v_row."graph" -> 'nodes') n
  where n.value ->> 'kind' = 'trigger';
  if v_node is null and cardinality(v_triggers) = 1 then
    v_node := v_triggers[1];
  end if;
  if v_node is null or not (v_node = any (v_triggers)) then
    raise exception 'Pass trigger_node, the id of one of the graph''s trigger nodes' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_NODE';
  end if;
  return jsonb_build_object(
    'definition', jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'subjectTypes', to_jsonb(v_def."subject_types"),
    'scope', v_def."scope",
    'forkedFrom', v_def."forked_from",
    'forkedFromVersion', v_def."forked_from_version",
    'restricted', v_def."restricted",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  ),
    'tenant', v_def."tenant_id",
    'triggerNode', v_node,
    'input', coalesce(input, '{}'::jsonb),
    'stubs', coalesce(stubs, '{}'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.validate_workflow_graph (
  graph jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_errors text[] := '{}';
  v_nodes jsonb := coalesce(graph -> 'nodes', 'null'::jsonb);
  v_edges jsonb := coalesce(graph -> 'edges', '[]'::jsonb);
  v_node jsonb;
  v_edge jsonb;
  v_ids text[] := '{}';
  v_triggers integer := 0;
begin
  if jsonb_typeof(v_nodes) <> 'array' or jsonb_typeof(v_edges) <> 'array' then
    return jsonb_build_array('A graph has a nodes array and an edges array');
  end if;
  for v_node in select value from jsonb_array_elements(v_nodes) loop
    if coalesce(jsonb_typeof(v_node -> 'id'), '') <> 'string' or (v_node ->> 'id') !~ '^[A-Za-z0-9_-]{1,100}$' then
      v_errors := array_append(v_errors, 'Every node has an id of 1 to 100 letters, digits, underscores or hyphens');
      continue;
    end if;
    if (v_node ->> 'id') = any (v_ids) then
      v_errors := array_append(v_errors, format('Node %s appears twice', v_node ->> 'id'));
    end if;
    v_ids := array_append(v_ids, v_node ->> 'id');
    if coalesce(v_node ->> 'kind', '') not in ('trigger', 'step', 'sleep', 'approval', 'condition') then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from "better_supabase"."workflow_step_library" s where s."name" = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers < 1 then
    v_errors := array_append(v_errors, 'A graph has at least one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_definition_get (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) from "better_supabase"."workflow_definitions" x where x."id" = workflow_definition_get.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_definition_grants_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'action', x."action",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_definition_grants" x where x."definition_id" = workflow_definition_grants_list.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_definitions_list (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(
    jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', u.version,
      'behind', coalesce(u.version > x."forked_from_version", false),
      'optedOut', case when workflow_definitions_list.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = workflow_definitions_list.tenant and oo."definition_id" = x."id") end
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_definitions" x
  left join lateral (
    select y."version" as version from "better_supabase"."workflow_versions" y
    where y."definition_id" = x."forked_from" and y."status" = 'published'
  ) u on true
  where (workflow_definitions_list.tenant is null
      or x."tenant_id" = workflow_definitions_list.tenant
      or x."scope" = 'system')
    and (workflow_definitions_list.subject_type is null
      or workflow_definitions_list.subject_type = any (x."subject_types"));
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_event_targets (
  type   text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'trigger', jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ),
    'tenant', coalesce(y."tenant_id", workflow_event_targets.tenant),
    'subjectTypes', to_jsonb(y."subject_types")
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_triggers" x
  join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."kind" = 'event' and x."enabled"
    and x."config" ->> 'type' = workflow_event_targets.type
    and (
      y."tenant_id" is not distinct from workflow_event_targets.tenant
      or (y."scope" = 'system' and workflow_event_targets.tenant is not null)
    )
    and not exists (
      select 1 from "better_supabase"."workflow_opt_outs" z
      where z."tenant_id" = workflow_event_targets.tenant and z."definition_id" = y."id"
    );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_get (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node"
  )
  from "better_supabase"."workflow_runs" x
  where x."id"::text = workflow_run_get.run or x."external_id" = workflow_run_get.run
  order by x."id"::text = workflow_run_get.run desc
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_principal (
  version uuid,
  tenant  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_publisher uuid;
  v_missing text;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'This workflow version was never published' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  select case when x."scope" = 'system' then tenant else x."tenant_id" end into v_tenant
  from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if v_row."owner_kind" is null then
    raise exception 'This workflow version was published before publishers were recorded; publish it again'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
  end if;
  if v_row."owner_kind" = 'user' then
    if v_row."published_by" is null then
      raise exception 'The user who published this workflow no longer exists'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(array_append(v_row."permissions", 'workflow.publish')) p
    where not coalesce(better_supabase.can_user(v_row."published_by", 'tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'The user who published this workflow no longer holds %', v_missing
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
  end if;
  return jsonb_build_object(
    'publisher', coalesce(v_publisher, v_row."published_by"),
    'tenant', v_tenant,
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_alert()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype := new;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_fired integer := 0;
begin
  if new."mode" = 'test' or new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bs.definition'
  loop
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_list (
  tenant       uuid                     DEFAULT NULL::uuid,
  definition   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  max          integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  mode         text                     DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node"
  ) order by x."created_at" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."workflow_runs" y
    where (workflow_runs_list.tenant is null or y."tenant_id" = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y."definition" = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or y."status" = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y."created_at" < workflow_runs_list.before)
      and (workflow_runs_list.subject_type is null or y."subject_type" = workflow_runs_list.subject_type)
      and (workflow_runs_list.subject_id is null or y."subject_id" = workflow_runs_list.subject_id)
      and (workflow_runs_list.mode is null or y."mode" = workflow_runs_list.mode)
    order by y."created_at" desc
    limit least(greatest(coalesce(workflow_runs_list.max, 50), 1), 500)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_mirror_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_actor uuid;
  v_subject text;
  v_subject_type text;
  v_subject_id text;
  v_principal_kind text;
  v_mode text;
begin
  begin
    v_tenant := (new.attributes ->> 'bs.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bs.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  v_principal_kind := new.attributes ->> 'bs.principal_kind';
  if v_principal_kind is not null and v_principal_kind not in ('user', 'service_principal', 'system', 'external') then
    v_principal_kind := null;
  end if;
  if v_tenant is not null and v_actor is not null and v_principal_kind is null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false) then
    v_tenant := null;
  end if;
  v_subject := new.attributes ->> 'bs.subject';
  if v_subject is not null and position('/' in v_subject) between 2 and 101
    and length(v_subject) - position('/' in v_subject) between 1 and 200 then
    v_subject_type := left(v_subject, position('/' in v_subject) - 1);
    v_subject_id := substr(v_subject, position('/' in v_subject) + 1);
  end if;
  v_mode := case when new.attributes ->> 'bs.mode' = 'test' then 'test' else 'live' end;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bs.tenant' - 'bs.actor' - 'bs.subject' - 'bs.principal_kind' - 'bs.principal' - 'bs.mode' - 'bs.trigger_node',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC',
    v_subject_type,
    v_subject_id,
    v_principal_kind,
    case when v_principal_kind is null then null else nullif(left(new.attributes ->> 'bs.principal', 200), '') end,
    v_mode,
    nullif(left(new.attributes ->> 'bs.trigger_node', 100), '')
  );
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_start_target (
  definition uuid,
  tenant     uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  v_tenant := case when v_def."scope" = 'system' then tenant else v_def."tenant_id" end;
  if v_def."scope" = 'system' and v_tenant is null then
    raise exception 'Pass the tenant a system workflow runs in' using errcode = '22023', hint = 'WORKFLOW_TENANT_REQUIRED';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.run'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('run', 'edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not run this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_tenant is not null and exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = v_tenant and oo."definition_id" = definition) then
    raise exception 'This organization opted out of this workflow' using errcode = 'P0001', hint = 'WORKFLOW_OPTED_OUT';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."definition_id" = definition and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'subjectTypes', to_jsonb(v_def."subject_types"),
    'scope', v_def."scope",
    'forkedFrom', v_def."forked_from",
    'forkedFromVersion', v_def."forked_from_version",
    'restricted', v_def."restricted",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ), 'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  ), 'tenant', v_tenant);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_subject_start_target (
  definition   uuid,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_types text[];
begin
  if subject_type is null or subject_id is null or length(subject_type) not between 1 and 100 or length(subject_id) not between 1 and 200 then
    raise exception 'A subject has a type of 1 to 100 and an id of 1 to 200 characters' using errcode = '22023', hint = 'WORKFLOW_SUBJECT_INVALID';
  end if;
  select x."subject_types" into v_types from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (subject_type = any (v_types)) then
    raise exception 'This workflow doesn''t run on that subject type' using errcode = '22023', hint = 'WORKFLOW_SUBJECT_TYPE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce("better_supabase"."can_subject"(subject_type, subject_id, 'read'), false) then
    raise exception 'You may not run a workflow on this record' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  return "better_supabase"."workflow_start_target"(definition, tenant)
    || jsonb_build_object('subject', jsonb_build_object('type', subject_type, 'id', subject_id));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_version_get (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'publishedBy', x."published_by",
    'owner', x."owner_kind",
    'permissions', to_jsonb(x."permissions"),
    'graph', x."graph",
    'compiled', x."compiled",
    'inputSchema', x."input_schema"
  ) from "better_supabase"."workflow_versions" x where x."id" = workflow_version_get.version;
$function$;

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD CONSTRAINT "notification_deliveries_provider_status_check"
    CHECK ((provider_status = ANY (ARRAY['delayed'::text, 'delivered'::text, 'opened'::text, 'clicked'::text, 'bounced'::text, 'complained'::text])));

ALTER TABLE "better_supabase"."notification_delivery_events"
  ADD CONSTRAINT "notification_delivery_events_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES better_supabase.notification_deliveries(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_definition_grants"
  ADD CONSTRAINT "workflow_definition_grants_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_definition_grants"
  ADD CONSTRAINT "workflow_definition_grants_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.workflow_definitions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_forked_from_fkey" FOREIGN KEY (forked_from) REFERENCES better_supabase.workflow_definitions(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_forked_from_version_check" CHECK ((forked_from_version > 0));

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_scope_check" CHECK ((scope = ANY (ARRAY['tenant'::text, 'system'::text])));

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_subject_types_check" CHECK (((cardinality(subject_types) <= 50) AND (array_position(subject_types, NULL::text) IS NULL)));

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_system_check" CHECK (((scope = 'tenant'::text) OR (tenant_id IS NULL)));

ALTER TABLE "better_supabase"."workflow_opt_outs"
  ADD CONSTRAINT "workflow_opt_outs_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_opt_outs"
  ADD CONSTRAINT "workflow_opt_outs_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.workflow_definitions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_mode_check" CHECK ((mode = ANY (ARRAY['live'::text, 'test'::text])));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_principal_id_check" CHECK (((length(principal_id) >= 1) AND (length(principal_id) <= 200)));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_principal_kind_check" CHECK ((principal_kind = ANY (ARRAY['user'::text, 'service_principal'::text, 'system'::text, 'external'::text])));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_subject_check" CHECK (((subject_type IS NULL) = (subject_id IS NULL)));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200)));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_subject_type_check" CHECK (((length(subject_type) >= 1) AND (length(subject_type) <= 100)));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_trigger_node_check" CHECK (((length(trigger_node) >= 1) AND (length(trigger_node) <= 100)));

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD CONSTRAINT "workflow_start_requests_subject_check" CHECK (((subject_type IS NULL) = (subject_id IS NULL)));

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD CONSTRAINT "workflow_start_requests_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200)));

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD CONSTRAINT "workflow_start_requests_subject_type_check" CHECK (((length(subject_type) >= 1) AND (length(subject_type) <= 100)));

ALTER TABLE "better_supabase"."workflow_versions"
  ADD CONSTRAINT "workflow_versions_input_schema_check" CHECK (((input_schema IS NULL) OR (jsonb_typeof(input_schema) = 'object'::text)));

CREATE INDEX notification_deliveries_provider_message_idx ON better_supabase.notification_deliveries USING btree (PROVIDER, provider_message_id)
  WHERE (provider_message_id IS NOT NULL);

CREATE INDEX notification_delivery_events_delivery_idx ON better_supabase.notification_delivery_events USING btree (delivery_id, occurred_at);

CREATE INDEX workflow_definition_grants_created_by_idx ON better_supabase.workflow_definition_grants USING btree (created_by);

CREATE INDEX workflow_definition_grants_principal_idx ON better_supabase.workflow_definition_grants USING btree (principal_kind, principal_id);

CREATE INDEX workflow_definitions_forked_from_idx ON better_supabase.workflow_definitions USING btree (forked_from)
  WHERE (forked_from IS NOT NULL);

CREATE INDEX workflow_opt_outs_created_by_idx ON better_supabase.workflow_opt_outs USING btree (created_by);

CREATE INDEX workflow_opt_outs_definition_idx ON better_supabase.workflow_opt_outs USING btree (definition_id);

CREATE INDEX workflow_runs_subject_idx ON better_supabase.workflow_runs USING btree (tenant_id, subject_type, subject_id, created_at DESC)
  WHERE (subject_type IS NOT NULL);

CREATE POLICY "activity_entries_read" ON "better_supabase"."activity_entries"
  FOR SELECT
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('activity.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR (subject_id IS NULL) OR (NOT
    (subject_type = ANY ('{customer}'::text[]))) OR better_supabase.activity_subject_readable(subject_type, subject_id))));

CREATE POLICY "bs_notification_delivery_events_read" ON "better_supabase"."notification_delivery_events"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM (better_supabase.notification_deliveries d
     JOIN better_supabase.notification_recipients r ON ((r.id = d.recipient_id)))
  WHERE ((d.id = notification_delivery_events.delivery_id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "workflow_definition_grants_read" ON "better_supabase"."workflow_definition_grants"
  FOR SELECT
  TO "authenticated"
  USING ((definition_id IN ( SELECT x.id
   FROM better_supabase.workflow_definitions x)));

CREATE POLICY "workflow_definitions_read" ON "better_supabase"."workflow_definitions"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)) OR ((scope = 'system'::text) AND (EXISTS ( SELECT
    better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)))));

CREATE POLICY "workflow_opt_outs_read" ON "better_supabase"."workflow_opt_outs"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)));

COMMENT ON CONSTRAINT "workflow_definitions_subject_types_check" ON "better_supabase"."workflow_definitions" IS 'better-supabase check bdb3cf6a';

COMMENT ON CONSTRAINT "workflow_definitions_system_check" ON "better_supabase"."workflow_definitions" IS 'better-supabase check 02e502e1';

COMMENT ON CONSTRAINT "workflow_runs_subject_check" ON "better_supabase"."workflow_runs" IS 'better-supabase check 9166c23a';

COMMENT ON CONSTRAINT "workflow_start_requests_subject_check" ON "better_supabase"."workflow_start_requests" IS 'better-supabase check 9166c23a';

REVOKE ALL ON FUNCTION "api"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."fork_workflow_definition"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fork_workflow_definition"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_subject_deliveries"(text, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_subject_deliveries"(text, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_delivery_event"(text, text, text, text, timestamp WITH time zone, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_delivery_event"(text, text, text, text, timestamp WITH time zone, jsonb, boolean) TO "service_role";

REVOKE ALL
  ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone, text, text, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_draft"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_draft"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_workflow_definition_grant"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_workflow_definition_grant"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_workflow_opt_out"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_workflow_opt_out"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."start_test_run"(uuid, uuid, text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."start_test_run"(uuid, uuid, text, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_definition_grants_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_definition_grants_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_definitions_list"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_definitions_list"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_run_principal"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_run_principal"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_start_target"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_start_target"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_subject_start_target"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_subject_start_target"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."activity_subject_readable"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."activity_subject_readable"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fork_workflow_definition"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fork_workflow_definition"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_subject_deliveries"(text, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_delivery_event"(text, text, text, text, timestamp WITH time zone, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_delivery_event"(text, text, text, text, timestamp WITH time zone, jsonb, boolean) TO "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_draft"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_draft"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_workflow_definition_grant"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_workflow_definition_grant"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_workflow_opt_out"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_workflow_opt_out"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."start_test_run"(uuid, uuid, text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."start_test_run"(uuid, uuid, text, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_definition_grants_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_definition_grants_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_definitions_list"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_definitions_list"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_run_principal"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_run_principal"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_start_target"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_start_target"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_subject_start_target"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_subject_start_target"(uuid, text, text, uuid) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."notification_delivery_events" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_delivery_events" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_definition_grants" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_definition_grants" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_opt_outs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_opt_outs" TO "service_role";
