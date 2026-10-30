SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."observation_definitions" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid,
  "key"            text                     NOT NULL,
  "title"          text                     NOT NULL,
  "value_type"     text                     NOT NULL,
  "unit"           text,
  "code_system"    text,
  "code"           text,
  "components"     jsonb,
  "decimals"       integer,
  "valid_low"      numeric,
  "valid_high"     numeric,
  "reference_low"  numeric,
  "reference_high" numeric,
  "critical_low"   numeric,
  "critical_high"  numeric,
  "archived_at"    timestamp with time zone,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "observation_definitions_check1" CHECK (((reference_low IS NULL) OR (reference_high IS NULL) OR (reference_low <= reference_high))),
  CONSTRAINT "observation_definitions_check2" CHECK (((critical_low IS NULL) OR (critical_high IS NULL) OR (critical_low <= critical_high))),
  CONSTRAINT "observation_definitions_check" CHECK (((valid_low IS NULL) OR (valid_high IS NULL) OR (valid_low <= valid_high))),
  CONSTRAINT "observation_definitions_code_check" CHECK (((code IS NULL) OR (length(code) <= 100))),
  CONSTRAINT "observation_definitions_code_system_check" CHECK (((code_system IS NULL) OR (length(code_system) <= 200))),
  CONSTRAINT "observation_definitions_components_check" CHECK (((components IS NULL) OR (jsonb_typeof(components) = 'array'::text))),
  CONSTRAINT "observation_definitions_decimals_check" CHECK (((decimals IS NULL) OR ((decimals >= 0) AND (decimals <= 6)))),
  CONSTRAINT "observation_definitions_key_check" CHECK ((key ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "observation_definitions_pkey" PRIMARY KEY (id),
  CONSTRAINT "observation_definitions_tenant_id_key_key" UNIQUE NULLS NOT DISTINCT (tenant_id, key),
  CONSTRAINT "observation_definitions_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200))),
  CONSTRAINT "observation_definitions_unit_check" CHECK (((unit IS NULL) OR (length(unit) <= 50))),
  CONSTRAINT "observation_definitions_value_type_check"
    CHECK ((value_type = ANY (ARRAY['number'::text, 'integer'::text, 'boolean'::text, 'code'::text, 'text'::text, 'components'::text])))
);

ALTER TABLE "better_supabase"."observation_definitions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."observations" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "definition_id" uuid                     NOT NULL,
  "subject_type"  text                     NOT NULL,
  "subject_id"    text                     NOT NULL,
  "observed_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "value_number"  numeric,
  "value_text"    text,
  "value_code"    text,
  "components"    jsonb,
  "flag"          text                     NOT NULL DEFAULT 'normal'::text,
  "status"        text                     NOT NULL DEFAULT 'final'::text,
  "replaces_id"   uuid,
  "reason"        text,
  "method"        text,
  "device"        text,
  "source"        text                     NOT NULL DEFAULT 'manual'::text,
  "external_id"   text,
  "submission_id" uuid,
  "performer_id"  uuid,
  "note"          text,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "observations_components_check" CHECK (((components IS NULL) OR (jsonb_typeof(components) = 'object'::text))),
  CONSTRAINT "observations_device_check" CHECK (((device IS NULL) OR (length(device) <= 200))),
  CONSTRAINT "observations_external_id_check" CHECK (((external_id IS NULL) OR ((length(external_id) >= 1) AND (length(external_id) <= 200)))),
  CONSTRAINT "observations_flag_check" CHECK ((flag = ANY (ARRAY['normal'::text, 'low'::text, 'high'::text, 'critical_low'::text, 'critical_high'::text]))),
  CONSTRAINT "observations_method_check" CHECK (((method IS NULL) OR (length(method) <= 200))),
  CONSTRAINT "observations_note_check" CHECK (((note IS NULL) OR (length(note) <= 4000))),
  CONSTRAINT "observations_pkey" PRIMARY KEY (id),
  CONSTRAINT "observations_reason_check" CHECK (((reason IS NULL) OR (length(reason) <= 2000))),
  CONSTRAINT "observations_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'form'::text, 'device'::text, 'import'::text]))),
  CONSTRAINT "observations_status_check" CHECK ((status = ANY (ARRAY['final'::text, 'amended'::text, 'entered_in_error'::text]))),
  CONSTRAINT "observations_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200))),
  CONSTRAINT "observations_subject_type_check" CHECK (((length(subject_type) >= 1) AND (length(subject_type) <= 100))),
  CONSTRAINT "observations_value_code_check" CHECK (((value_code IS NULL) OR (length(value_code) <= 200))),
  CONSTRAINT "observations_value_text_check" CHECK (((value_text IS NULL) OR (length(value_text) <= 4000)))
);

ALTER TABLE "better_supabase"."observations"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.amend_observation (
  observation_id uuid,
  changes        jsonb,
  reason         text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."amend_observation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.archive_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_observation_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.ingest_observations (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ingest_observations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.latest_observations (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."latest_observations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_observation_definitions (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_observation_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_observations (
  subject_type   text,
  subject_id     text,
  definition_key text    DEFAULT NULL::text,
  include_all    boolean DEFAULT false,
  max_rows       integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_observations"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.mark_observation_error (
  observation_id uuid,
  reason         text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_observation_error"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.observation_series (
  subject_type   text,
  subject_id     text,
  definition_key text,
  since          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  bucket         text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."observation_series"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.observations_from_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."observations_from_submission"($1) $function$;

CREATE OR REPLACE FUNCTION api.record_observation (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  definition_key text,
  value          jsonb,
  observed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  details        jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_observation"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.record_observations (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_observations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_observation_definition (
  tenant     uuid,
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_observation_definition"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.amend_observation (
  observation_id uuid,
  changes        jsonb,
  reason         text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."observations"%rowtype;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_changes jsonb := coalesce(amend_observation.changes, '{}'::jsonb);
  v_reason text := nullif(trim(amend_observation.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."observations" x where x."id" = amend_observation.observation_id for update;
  if not found then
    raise exception 'observation not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_old."subject_type"
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_old."subject_id")::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_old."subject_id")::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_old."subject_id")::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_old."subject_id")::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_old."subject_id")::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_old."subject_id")::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_old."subject_id")::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_old."subject_id")::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (v_old."subject_id")::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_old."subject_id")::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_old."subject_id")::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_old."subject_id")::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_old."subject_id")::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_old."subject_id")::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_old."subject_id")::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_old."subject_id")::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_old."subject_id")::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_old."subject_id")::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_old."subject_id")::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_old."subject_id")::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_old."subject_id")::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (v_old."subject_id")::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_old."subject_id")::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_old."subject_id")::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_old."subject_id")::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_old."subject_id")::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_old."subject_id")::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_old."subject_id")::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_old."subject_id")::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (v_old."subject_id")::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_old."subject_id")::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_old."subject_id")::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_old."subject_id")::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_old."subject_id")::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_old."subject_id")::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_old."subject_id")::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_old."subject_id")::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_old."subject_id")::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_old."subject_id")::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_old."subject_id")::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_old."subject_id")::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_old."subject_id")::uuid)
      else null::text
    end) = v_old."tenant_id"::text, false) else (case v_old."subject_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_old."subject_type", v_old."subject_id", 'read')) end)) then
    raise exception 'not allowed to amend this observation' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if v_old."status" <> 'final' then
    raise exception 'only a final observation can be amended' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'an amendment needs a reason of at most 2000 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if jsonb_typeof(v_changes) <> 'object' then
    raise exception 'changes is an object' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_old."definition_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_amend"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_old."id";
    end if;
  end;
  update "better_supabase"."observations" x set "status" = 'amended', "reason" = v_reason
  where x."id" = v_old."id";
  select * into v_row from "better_supabase"."observation_insert"(v_old."tenant_id", v_old."definition_id", v_old."subject_type", v_old."subject_id", coalesce(v_changes -> 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_old."value_code" = 'true')
      when 'code' then to_jsonb(v_old."value_code")
      when 'text' then to_jsonb(v_old."value_text")
      when 'components' then v_old."components"
      else to_jsonb(v_old."value_number")
    end), coalesce((v_changes ->> 'observedAt')::timestamptz, v_old."observed_at"), jsonb_strip_nulls(jsonb_build_object('method', v_old."method", 'device', v_old."device", 'note', v_old."note")) || (v_changes - 'value' - 'observedAt' - 'fields'), v_old."source", null, v_old."submission_id", (select auth.uid()), v_old."id", to_jsonb(v_old) || coalesce(v_changes -> 'fields', '{}'::jsonb));
  perform "better_supabase".emit_event('observation.amended', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'replacesId', v_old."id", 'reason', v_reason), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.amended',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation amended',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'replacesId', v_old."id", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_amend"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."observation_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."observation_definitions" x where x."id" = archive_observation_definition.definition_id;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_row."tenant_id" is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role archives system definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'observations.manage'), false)) then
    raise exception 'not allowed to manage observation definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."observation_definitions" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.updated',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'system', v_row."tenant_id" is null, 'key', v_row."key", 'title', v_row."title", 'valueType', v_row."value_type", 'unit', v_row."unit", 'codeSystem', v_row."code_system", 'code', v_row."code", 'components', coalesce(v_row."components", '[]'::jsonb), 'decimals', v_row."decimals", 'validLow', v_row."valid_low", 'validHigh', v_row."valid_high", 'referenceLow', v_row."reference_low", 'referenceHigh', v_row."reference_high", 'criticalLow', v_row."critical_low", 'criticalHigh', v_row."critical_high", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.form_resolve (
  tenant     uuid,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_errors text[];
  v_problem text;
  v_steps jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_step jsonb;
  v_field jsonb;
  v_custom jsonb;
  v_options jsonb;
  v_step_keys text[] := '{}';
  v_keys text[] := '{}';
  v_scored boolean := false;
begin
  v_errors := extensions.jsonschema_validation_errors('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["steps"],"additionalProperties":false,"properties":{"steps":{"type":"array","minItems":1,"maxItems":50,"items":{"type":"object","required":["key","fields"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"title":{"type":"string","maxLength":200},"description":{"type":"string","maxLength":2000},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"fields":{"type":"array","minItems":1,"maxItems":200,"items":{"type":"object","required":["key"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"label":{"type":"string","minLength":1,"maxLength":200},"type":{"enum":["text","textarea","email","url","number","integer","date","bool","consent","option","multi","json","nps"]},"required":{"type":"boolean"},"help":{"type":"string","maxLength":1000},"placeholder":{"type":"string","maxLength":200},"options":{"type":"array","minItems":1,"maxItems":500,"items":{"type":"object","required":["value","label"],"additionalProperties":false,"properties":{"value":{"type":"string","minLength":1,"maxLength":200},"label":{"type":"string","minLength":1,"maxLength":200}}}},"min":{"type":"number"},"max":{"type":"number"},"minLength":{"type":"integer","minimum":0},"maxLength":{"type":"integer","minimum":1},"pattern":{"type":"string","maxLength":500},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"customField":{"type":"string","pattern":"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"},"correct":{},"points":{"type":"number","minimum":0,"maximum":10000},"meta":{"type":"object","maxProperties":20}}}}}}},"scoring":{"type":"object","additionalProperties":false,"properties":{"passMark":{"type":"number","minimum":0,"maximum":100}}}}}'::json, definition::json);
  if cardinality(v_errors) > 0 then
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  <<steps>>
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    if (v_step ->> 'key') = any (v_step_keys) then
      v_problem := format('step %s is listed twice', v_step ->> 'key');
      exit;
    end if;
    v_step_keys := v_step_keys || (v_step ->> 'key');
    if v_step ? 'showIf' and not ((v_step -> 'showIf' ->> 'field') = any (v_keys)) then
      v_problem := format('step %s: showIf names %s, which isn''t an earlier field', v_step ->> 'key', v_step -> 'showIf' ->> 'field');
      exit;
    end if;
    v_fields := '[]'::jsonb;
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      if (v_field ->> 'key') = any (v_keys) then
        v_problem := format('field %s is listed twice', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'showIf' and not ((v_field -> 'showIf' ->> 'field') = any (v_keys)) then
        v_problem := format('field %s: showIf names %s, which isn''t an earlier field', v_field ->> 'key', v_field -> 'showIf' ->> 'field');
        exit steps;
      end if;
      v_keys := v_keys || (v_field ->> 'key');
      v_custom := null;
      if v_field ? 'customField' then
        select jsonb_strip_nulls(jsonb_build_object('label', d."label", 'type', case d."type" when 'multi_option' then 'multi' when 'user' then 'text' when 'rating' then 'integer' when 'currency' then 'integer' when 'bsn' then 'text' when 'iban' then 'text' when 'phone_e164' then 'text' else d."type" end, 'required', d."required"))
            || case when d."type" = 'rating' then jsonb_build_object('min', 1, 'max', 5) else '{}'::jsonb end
          into v_custom
          from "better_supabase"."field_definitions" d
          where d."id" = (v_field ->> 'customField')::uuid and d."tenant_id" = form_resolve.tenant;
        if v_custom is null then
          v_problem := format('field %s: customField %s is not a field definition in this organization', v_field ->> 'key', v_field ->> 'customField');
        exit steps;
        end if;
        if v_custom ->> 'type' in ('option', 'multi') and not v_field ? 'options' and to_regclass('"better_supabase"."field_options"') is not null then
          execute format('select jsonb_agg(jsonb_build_object(''value'', o."value", ''label'', o."label") order by o."value") from %s o where o."definition_id" = $1', to_regclass('"better_supabase"."field_options"'))
            into v_options using (v_field ->> 'customField')::uuid;
          v_custom := v_custom || jsonb_strip_nulls(jsonb_build_object('options', v_options));
        end if;
        v_field := v_custom || v_field;
      end if;
      if not (v_field ? 'label' and v_field ? 'type') then
        v_problem := format('field %s needs a label and a type, or a customField', v_field ->> 'key');
        exit steps;
      end if;
      if (v_field ->> 'type') in ('option', 'multi') and coalesce(jsonb_array_length(v_field -> 'options'), 0) = 0 then
        v_problem := format('field %s needs options', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'pattern' then
        begin
          perform '' ~ (v_field ->> 'pattern');
        exception when invalid_regular_expression then
          v_problem := format('field %s: pattern is not a valid regular expression', v_field ->> 'key');
        end;
        exit steps when v_problem is not null;
      end if;
      if v_field ? 'correct' then
        v_scored := true;
        if v_field -> 'correct' = 'null'::jsonb then
          v_problem := format('field %s: correct can''t be null', v_field ->> 'key');
          exit steps;
        end if;
        if (v_field ->> 'type') in ('consent', 'json', 'nps') then
          v_problem := format('field %s: a %s field can''t have a correct answer', v_field ->> 'key', v_field ->> 'type');
          exit steps;
        end if;
        if not "better_supabase"."form_correct_fits"(v_field) then
          v_problem := format('field %s: correct isn''t an answer the field takes', v_field ->> 'key');
          exit steps;
        end if;
      elsif v_field ? 'points' then
        v_problem := format('field %s: points need a correct answer', v_field ->> 'key');
        exit steps;
      end if;
      v_fields := v_fields || jsonb_build_array(v_field);
    end loop;
    v_steps := v_steps || jsonb_build_array(jsonb_set(v_step, '{fields}', v_fields));
  end loop;
  if v_problem is null and definition ? 'scoring' and not v_scored then
    v_problem := 'scoring needs a field with a correct answer';
  end if;
  if v_problem is not null then
    v_errors := array[v_problem];
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  return jsonb_build_object('steps', v_steps)
    || case when definition ? 'scoring' then jsonb_build_object('scoring', definition -> 'scoring') else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ingest_observations (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row "better_supabase"."observations"%rowtype;
  v_external text;
  v_source text;
  v_ids jsonb := '[]'::jsonb;
  v_skipped integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role ingests observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if jsonb_typeof(ingest_observations.items) is distinct from 'array' or jsonb_array_length(ingest_observations.items) not between 1 and 500 then
    raise exception 'items is an array of 1 to 500 observations' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  for v_item in select i from jsonb_array_elements(ingest_observations.items) i loop
    if jsonb_typeof(v_item) <> 'object' or nullif(v_item ->> 'subjectType', '') is null or nullif(v_item ->> 'subjectId', '') is null or nullif(v_item ->> 'definitionKey', '') is null then
      raise exception 'each item has a subjectType, a subjectId, a definitionKey and a value' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null or length(v_external) > 200 then
      raise exception 'each ingested item has an externalId of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    v_source := coalesce(v_item ->> 'source', 'device');
    if v_source not in ('device', 'import') then
      raise exception 'source is device or import' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_item ->> 'subjectType'
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      else null::text
    end) = ingest_observations.tenant::text, false) else (case v_item ->> 'subjectType'
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_item ->> 'subjectType', v_item ->> 'subjectId', 'read')) end) then
      raise exception 'the record isn''t in this organization' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:observations:' || ingest_observations.tenant::text || ':' || v_external, 0));
    if exists (select 1 from "better_supabase"."observations" x where x."tenant_id" = ingest_observations.tenant and x."external_id" = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    select * into v_row from "better_supabase"."observation_insert"(ingest_observations.tenant, "better_supabase"."observation_definition_id"(ingest_observations.tenant, v_item ->> 'definitionKey'), v_item ->> 'subjectType', v_item ->> 'subjectId', v_item -> 'value', (v_item ->> 'observedAt')::timestamptz, v_item -> 'details', v_source, v_external, null, null, null, v_item -> 'fields');
    v_ids := v_ids || jsonb_build_array(v_row."id");
  end loop;
  return jsonb_build_object('inserted', jsonb_array_length(v_ids), 'skipped', v_skipped, 'ids', v_ids);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.latest_observations (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(r.key, r.item), '{}'::jsonb)
  from (
    select distinct on (y."key") y."key" as key, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") as item
    from "better_supabase"."observations" x
    join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
    where x."subject_type" = latest_observations.subject_type
      and x."subject_id" = latest_observations.subject_id
      and x."status" = 'final'
    order by y."key", x."observed_at" desc, x."created_at" desc
  ) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_observation_definitions (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."title", x."key"), '[]'::jsonb)
  from "better_supabase"."observation_definitions" x
  where (
      x."tenant_id" = list_observation_definitions.tenant
      or (x."tenant_id" is null and not exists (
        select 1 from "better_supabase"."observation_definitions" y
        where y."tenant_id" = list_observation_definitions.tenant and y."key" = x."key"
      ))
    )
    and (coalesce(list_observation_definitions.include_archived, false) or x."archived_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_observations (
  subject_type   text,
  subject_id     text,
  definition_key text    DEFAULT NULL::text,
  include_all    boolean DEFAULT false,
  max_rows       integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(r.item order by r.at desc, r.created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") as item, x."observed_at" as at, x."created_at" as created
    from "better_supabase"."observations" x
    join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
    where x."subject_type" = list_observations.subject_type
      and x."subject_id" = list_observations.subject_id
      and (list_observations.definition_key is null or y."key" = list_observations.definition_key)
      and (coalesce(list_observations.include_all, false) or x."status" = 'final')
    order by x."observed_at" desc, x."created_at" desc
    limit least(greatest(coalesce(list_observations.max_rows, 100), 1), 1000)
  ) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_observation_error (
  observation_id uuid,
  reason         text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_reason text := nullif(trim(mark_observation_error.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."observations" x where x."id" = mark_observation_error.observation_id for update;
  if not found then
    raise exception 'observation not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_row."subject_type"
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (v_row."subject_id")::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (v_row."subject_id")::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (v_row."subject_id")::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_row."subject_id")::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_row."subject_id")::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid)
      else null::text
    end) = v_row."tenant_id"::text, false) else (case v_row."subject_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read')) end)) then
    raise exception 'not allowed to correct this observation' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
  if v_row."status" = 'entered_in_error' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
  end if;
  if v_row."status" <> 'final' then
    raise exception 'only a final observation can be marked entered in error' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'marking an observation entered in error needs a reason of at most 2000 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_mark_error"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."observations" x set "status" = 'entered_in_error', "reason" = v_reason
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('observation.marked_error', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'reason', v_reason), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.marked_error',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation marked entered in error',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_mark_error"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_definition_id (
  p_tenant uuid,
  p_key    text
)
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  select d."id" into v_id from "better_supabase"."observation_definitions" d
  where d."key" = p_key and (d."tenant_id" = p_tenant or d."tenant_id" is null)
  order by d."tenant_id" nulls last
  limit 1;
  if v_id is null then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_flag (
  value          numeric,
  reference_low  numeric,
  reference_high numeric,
  critical_low   numeric,
  critical_high  numeric
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case
    when value is null then 'normal'
    when critical_low is not null and value <= critical_low then 'critical_low'
    when critical_high is not null and value >= critical_high then 'critical_high'
    when reference_low is not null and value < reference_low then 'low'
    when reference_high is not null and value > reference_high then 'high'
    else 'normal'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_insert (
  p_tenant       uuid,
  p_definition   uuid,
  p_subject_type text,
  p_subject_id   text,
  p_value        jsonb,
  p_observed_at  timestamp with time zone,
  p_details      jsonb,
  p_source       text,
  p_external_id  text,
  p_submission   uuid,
  p_performer    uuid,
  p_replaces     uuid,
  p_fields       jsonb
)
  RETURNS better_supabase.observations
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_row "better_supabase"."observations"%rowtype;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_number numeric;
  v_text text;
  v_code text;
  v_components jsonb;
  v_flag text := 'normal';
  v_component jsonb;
  v_key text;
  v_part numeric;
  v_part_flag text;
  v_recipients jsonb;
  v_claims text;
begin
  select * into v_def from "better_supabase"."observation_definitions" d where d."id" = p_definition;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_def."archived_at" is not null then
    raise exception 'the observation definition is archived' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_ARCHIVED';
  end if;
  if v_at > now() + interval '5 minutes' then
    raise exception 'observed_at is in the future' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_details is not null and jsonb_typeof(p_details) <> 'object' then
    raise exception 'details is an object of method, device and note' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    raise exception 'an observation needs a value' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
  end if;
  case v_def."value_type"
    when 'number', 'integer' then
      if jsonb_typeof(p_value) <> 'number' then
        raise exception '%s takes a number', v_def."key" using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_number := (p_value #>> '{}')::numeric;
      if v_def."value_type" = 'integer' and v_number <> trunc(v_number) then
        raise exception 'the value is a whole number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if v_def."decimals" is not null then
        v_number := round(v_number, v_def."decimals");
      end if;
      if v_number < v_def."valid_low" or v_number > v_def."valid_high" then
        raise exception 'the value is outside the definition''s valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_flag := "better_supabase"."observation_flag"(v_number, v_def."reference_low", v_def."reference_high", v_def."critical_low", v_def."critical_high");
    when 'boolean' then
      if jsonb_typeof(p_value) <> 'boolean' then
        raise exception 'the value is true or false' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_code := p_value #>> '{}';
    when 'code' then
      v_code := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_code is null or length(v_code) > 200 then
        raise exception 'the value is a code of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    when 'text' then
      v_text := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_text is null or length(v_text) > 4000 then
        raise exception 'the value is a text of at most 4000 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    else
      if jsonb_typeof(p_value) <> 'object' then
        raise exception 'the value is an object of components' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if exists (
        select 1 from jsonb_object_keys(p_value) k
        where not exists (select 1 from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c where c ->> 'key' = k)
      ) then
        raise exception 'the value names a component the definition doesn''t have' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_components := '{}'::jsonb;
      for v_component in select c from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c loop
        v_key := v_component ->> 'key';
        if not (p_value ? v_key) or jsonb_typeof(p_value -> v_key) = 'null' then
          if coalesce((v_component ->> 'optional')::boolean, false) then
            continue;
          end if;
          raise exception 'the value needs the %s component', v_key using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        if jsonb_typeof(p_value -> v_key) <> 'number' then
          raise exception 'each component is a number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part := (p_value ->> v_key)::numeric;
        if v_component ? 'decimals' then
          v_part := round(v_part, (v_component ->> 'decimals')::integer);
        elsif v_def."decimals" is not null then
          v_part := round(v_part, v_def."decimals");
        end if;
        if v_part < (v_component ->> 'validLow')::numeric or v_part > (v_component ->> 'validHigh')::numeric then
          raise exception 'a component is outside its valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part_flag := "better_supabase"."observation_flag"(v_part, (v_component ->> 'referenceLow')::numeric, (v_component ->> 'referenceHigh')::numeric, (v_component ->> 'criticalLow')::numeric, (v_component ->> 'criticalHigh')::numeric);
        if (case v_part_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) > (case v_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) then
          v_flag := v_part_flag;
        end if;
        v_components := v_components || jsonb_build_object(v_key, v_part);
      end loop;
      if v_components = '{}'::jsonb then
        raise exception 'the value needs at least one component' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
  end case;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_record"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using p_tenant, p_subject_type, p_subject_id, v_def."key";
    end if;
  end;
  end if;
  insert into "better_supabase"."observations" ("tenant_id", "definition_id", "subject_type", "subject_id", "observed_at", "value_number", "value_text", "value_code", "components", "flag", "replaces_id", "method", "device", "source", "external_id", "submission_id", "performer_id", "note")
  values (p_tenant, v_def."id", p_subject_type, p_subject_id, v_at, v_number, v_text, v_code, v_components, v_flag, p_replaces, left(nullif(trim(p_details ->> 'method'), ''), 200), left(nullif(trim(p_details ->> 'device'), ''), 200), p_source, p_external_id, p_submission, p_performer, left(nullif(trim(p_details ->> 'note'), ''), 4000))
  returning * into v_row;
  if p_replaces is null then
    perform "better_supabase".emit_event('observation.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.recorded',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source")
  );
  end if;
  if v_row."flag" in ('critical_low', 'critical_high') then
    perform "better_supabase".emit_event('observation.critical', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
    select coalesce(jsonb_agg(distinct m."user_id"), '[]'::jsonb) into v_recipients
    from "better_supabase"."subject_members" m
    where m."subject_type" = v_row."subject_type"
      and m."subject_id" = v_row."subject_id"
      and m."tenant_id"::text = v_row."tenant_id"::text
      and m."role" = 'lead'
      and m."user_id" is not null
      and (m."starts_on" is null or m."starts_on" <= current_date)
      and (m."ends_on" is null or m."ends_on" >= current_date);
    if jsonb_array_length(v_recipients) > 0 then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'observation.critical',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', v_row."subject_type",
        'subject_id', v_row."subject_id",
        'summary', v_def."title" || ' is ' || replace(v_row."flag", '_', ' '),
        'recipients', v_recipients,
        'key', 'observation.critical:' || v_row."id"::text,
        'data', jsonb_build_object('observationId', v_row."id", 'definitionKey', v_def."key", 'flag', v_row."flag")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_series (
  subject_type   text,
  subject_id     text,
  definition_key text,
  since          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  bucket         text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  if observation_series.bucket is not null and observation_series.bucket not in ('hour', 'day', 'week', 'month') then
    raise exception 'bucket is one of hour, day, week, month' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if observation_series.since is not null and observation_series.until is not null and observation_series.since > observation_series.until then
    raise exception 'since is before until' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if observation_series.bucket is null then
    return (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag") order by x."observed_at"), '[]'::jsonb)
      from "better_supabase"."observations" x
      join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
      where x."subject_type" = observation_series.subject_type
        and x."subject_id" = observation_series.subject_id
        and y."key" = observation_series.definition_key
        and x."status" = 'final'
        and (observation_series.since is null or x."observed_at" >= observation_series.since)
        and (observation_series.until is null or x."observed_at" < observation_series.until)
    );
  end if;
  return (
    with points as (
      select date_trunc(observation_series.bucket, x."observed_at", 'UTC') as b, x."value_number" as n, x."components" as c
      from "better_supabase"."observations" x
      join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
      where x."subject_type" = observation_series.subject_type
        and x."subject_id" = observation_series.subject_id
        and y."key" = observation_series.definition_key
        and x."status" = 'final'
        and (observation_series.since is null or x."observed_at" >= observation_series.since)
        and (observation_series.until is null or x."observed_at" < observation_series.until)
    ),
    parts as (
      select p.b, e.key, min(e.value::numeric) as lo, max(e.value::numeric) as hi, round(avg(e.value::numeric), 4) as mean
      from points p
      cross join lateral jsonb_each_text(coalesce(p.c, '{}'::jsonb)) e
      group by p.b, e.key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'bucket', g.b,
      'count', g.total,
      'min', g.lo,
      'max', g.hi,
      'avg', g.mean,
      'components', coalesce((
        select jsonb_object_agg(q.key, jsonb_build_object('min', q.lo, 'max', q.hi, 'avg', q.mean))
        from parts q where q.b = g.b
      ), '{}'::jsonb)
    ) order by g.b), '[]'::jsonb)
    from (
      select p.b, count(*) as total, min(p.n) as lo, max(p.n) as hi, round(avg(p.n), 4) as mean
      from points p
      group by p.b
    ) g
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_submission_apply (
  p_submission uuid,
  p_quiet      boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_sub "better_supabase"."form_submissions"%rowtype;
  v_form jsonb;
  v_field jsonb;
  v_key text;
  v_part text;
  v_answer jsonb;
  v_values jsonb := '{}'::jsonb;
  v_entry record;
  v_definition uuid;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  select * into v_sub from "better_supabase"."form_submissions" x where x."id" = p_submission;
  if not found then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'form submission not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if v_sub."subject_type" is null or v_sub."subject_id" is null then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'the submission isn''t about a record' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_sub."status"::text not in ('submitted', 'accepted') then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'the submission isn''t submitted' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sub."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_sub."subject_type"::text
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_sub."subject_id"::text)::uuid)
      else null::text
    end) = v_sub."tenant_id"::text, false) else (case v_sub."subject_type"::text
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_sub."subject_type"::text, v_sub."subject_id"::text, 'read')) end)) then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'not allowed to record observations for this record' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select x."definition" into v_form from "better_supabase"."form_versions" x where x."id" = v_sub."version_id";
  for v_field in
    select f from jsonb_array_elements(coalesce(v_form -> 'steps', '[]'::jsonb)) st
    cross join lateral jsonb_array_elements(coalesce(st -> 'fields', '[]'::jsonb)) f
    where jsonb_typeof(f -> 'meta' -> 'observation') = 'string'
  loop
    v_key := v_field -> 'meta' ->> 'observation';
    v_answer := v_sub."answers" -> (v_field ->> 'key');
    if v_answer is null or v_answer in ('null'::jsonb, '""'::jsonb) then
      continue;
    end if;
    v_part := v_field -> 'meta' ->> 'component';
    if v_part is null then
      v_values := v_values || jsonb_build_object(v_key, v_answer);
    else
      v_values := v_values || jsonb_build_object(v_key, coalesce(v_values -> v_key, '{}'::jsonb) || jsonb_build_object(v_part, v_answer));
    end if;
  end loop;
  for v_entry in select e.key, e.value from jsonb_each(v_values) e loop
    select x."id" into v_definition from "better_supabase"."observation_definitions" x
    where x."key" = v_entry.key and (x."tenant_id" = v_sub."tenant_id" or x."tenant_id" is null)
    order by x."tenant_id" nulls last
    limit 1;
    if v_definition is null then
      if p_quiet then
        continue;
      end if;
      raise exception 'a field names an observation definition that doesn''t exist' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
    end if;
    if exists (select 1 from "better_supabase"."observations" x where x."submission_id" = v_sub."id" and x."definition_id" = v_definition) then
      continue;
    end if;
    select * into v_row from "better_supabase"."observation_insert"(v_sub."tenant_id", v_definition, v_sub."subject_type"::text, v_sub."subject_id"::text, v_entry.value, coalesce(v_sub."submitted_at", now()), null, 'form', null, v_sub."id", v_sub."respondent_id", null, null);
    select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_submission_trigger()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."status"::text = 'submitted' and (tg_op = 'INSERT' or old."status"::text is distinct from 'submitted') and new."subject_type" is not null then
    perform "better_supabase"."observation_submission_apply"(new."id", true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observations_from_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return "better_supabase"."observation_submission_apply"(observations_from_submission.submission_id, false);
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
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
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
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
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
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'compliance.acknowledge'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
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
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.read_sensitive'
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
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
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
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
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
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
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
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
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
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
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
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_observation (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  definition_key text,
  value          jsonb,
  observed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  details        jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_observation.tenant, 'observations.record'), false)) then
    raise exception 'not allowed to record observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case record_observation.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (record_observation.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (record_observation.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (record_observation.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_observation.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_observation.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_observation.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (record_observation.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (record_observation.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (record_observation.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_observation.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_observation.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (record_observation.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_observation.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_observation.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (record_observation.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_observation.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (record_observation.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_observation.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_observation.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (record_observation.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_observation.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_observation.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_observation.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_observation.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_observation.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_observation.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (record_observation.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (record_observation.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (record_observation.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_observation.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (record_observation.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (record_observation.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_observation.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_observation.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_observation.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_observation.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (record_observation.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_observation.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_observation.subject_id)::uuid)
      else null::text
    end) = record_observation.tenant::text, false) else (case record_observation.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_observation.subject_type, record_observation.subject_id, 'read')) end) then
    raise exception 'the record isn''t in this organization, or you can''t read it' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."observation_insert"(record_observation.tenant, "better_supabase"."observation_definition_id"(record_observation.tenant, record_observation.definition_key), record_observation.subject_type, record_observation.subject_id, record_observation.value, record_observation.observed_at, record_observation.details, 'manual', null, null, (select auth.uid()), null, null);
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_observations (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_observations.tenant, 'observations.record'), false)) then
    raise exception 'not allowed to record observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if jsonb_typeof(record_observations.items) is distinct from 'array' or jsonb_array_length(record_observations.items) not between 1 and 500 then
    raise exception 'items is an array of 1 to 500 observations' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  for v_item in select i from jsonb_array_elements(record_observations.items) i loop
    if jsonb_typeof(v_item) <> 'object' or nullif(v_item ->> 'subjectType', '') is null or nullif(v_item ->> 'subjectId', '') is null or nullif(v_item ->> 'definitionKey', '') is null then
      raise exception 'each item has a subjectType, a subjectId, a definitionKey and a value' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_item ->> 'subjectType'
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      else null::text
    end) = record_observations.tenant::text, false) else (case v_item ->> 'subjectType'
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_item ->> 'subjectType', v_item ->> 'subjectId', 'read')) end) then
      raise exception 'the record isn''t in this organization, or you can''t read it' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."observation_insert"(record_observations.tenant, "better_supabase"."observation_definition_id"(record_observations.tenant, v_item ->> 'definitionKey'), v_item ->> 'subjectType', v_item ->> 'subjectId', v_item -> 'value', (v_item ->> 'observedAt')::timestamptz, v_item -> 'details', 'manual', null, null, (select auth.uid()), null, v_item -> 'fields');
    select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_subject_export (
  subject_type text,
  subject_id   text,
  format       text DEFAULT 'ndjson'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."data_exports";
  v_tenant uuid;
  v_record jsonb;
  v_name text;
  v_reveal text;
  v_reveal_schema text;
  v_proc text;
  v_arg text;
  v_sealed text[];
  v_plain jsonb;
  v_rows jsonb;
  v_fields jsonb;
  v_parts jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_subject_export.format is null or request_subject_export.format not in ('ndjson', 'csv') then
    raise exception 'format must be ndjson or csv' using errcode = '22023', hint = 'DATA_EXPORT_FORMAT';
  end if;
  case request_subject_export.subject_type
    when 'message' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."messages" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.messages';
      v_reveal := 'messages_reveal';
      v_reveal_schema := 'better_supabase';
    when 'conversation' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."conversations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.conversations';
      v_reveal := 'conversations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'channel' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."channels" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.channels';
      v_reveal := 'channels_reveal';
      v_reveal_schema := 'better_supabase';
    when 'company' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."companies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.companies';
      v_reveal := 'companies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'person' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."people" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.people';
      v_reveal := 'people_reveal';
      v_reveal_schema := 'better_supabase';
    when 'deal' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."deals" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.deals';
      v_reveal := 'deals_reveal';
      v_reveal_schema := 'better_supabase';
    when 'course' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."courses" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.courses';
      v_reveal := 'courses_reveal';
      v_reveal_schema := 'better_supabase';
    when 'post' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."posts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.posts';
      v_reveal := 'posts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'engagement' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."engagements" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.engagements';
      v_reveal := 'engagements_reveal';
      v_reveal_schema := 'better_supabase';
    when 'quote' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."quotes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.quotes';
      v_reveal := 'quotes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_item' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_items" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_items';
      v_reveal := 'work_items_reveal';
      v_reveal_schema := 'better_supabase';
    when 'employee' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."employees" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.employees';
      v_reveal := 'employees_reveal';
      v_reveal_schema := 'better_supabase';
    when 'invoice' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."invoices" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.invoices';
      v_reveal := 'invoices_reveal';
      v_reveal_schema := 'better_supabase';
    when 'ledger_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."ledger_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.ledger_accounts';
      v_reveal := 'ledger_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."products" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.products';
      v_reveal := 'products_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product_variant' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."product_variants" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.product_variants';
      v_reveal := 'product_variants_reveal';
      v_reveal_schema := 'better_supabase';
    when 'order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.orders';
      v_reveal := 'orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'calendar_event' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."calendar_events" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.calendar_events';
      v_reveal := 'calendar_events_reveal';
      v_reveal_schema := 'better_supabase';
    when 'booking' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bookings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bookings';
      v_reveal := 'bookings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."assets" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.assets';
      v_reveal := 'assets_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset_location' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."asset_locations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.asset_locations';
      v_reveal := 'asset_locations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lease' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."lease_agreements" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.lease_agreements';
      v_reveal := 'lease_agreements_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_report' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_reports" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_reports';
      v_reveal := 'expense_reports_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_line' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_lines" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_lines';
      v_reveal := 'expense_lines_reveal';
      v_reveal_schema := 'better_supabase';
    when 'donation_fund' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."donation_funds" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.donation_funds';
      v_reveal := 'donation_funds_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_orders';
      v_reveal := 'work_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'shipment' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."shipments" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.shipments';
      v_reveal := 'shipments_reveal';
      v_reveal_schema := 'better_supabase';
    when 'contract' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."contracts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.contracts';
      v_reveal := 'contracts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'control' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."controls" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.controls';
      v_reveal := 'controls_reveal';
      v_reveal_schema := 'better_supabase';
    when 'policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.policies';
      v_reveal := 'policies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'qualification_type' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."qualification_types" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.qualification_types';
      v_reveal := 'qualification_types_reveal';
      v_reveal_schema := 'better_supabase';
    when 'risk' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."risks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.risks';
      v_reveal := 'risks_reveal';
      v_reveal_schema := 'better_supabase';
    when 'incident' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."incidents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.incidents';
      v_reveal := 'incidents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'content_entry' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."content_entries" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.content_entries';
      v_reveal := 'content_entries_reveal';
      v_reveal_schema := 'better_supabase';
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
      v_reveal_schema := 'better_supabase';
    when 'document' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."documents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.documents';
      v_reveal := 'documents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'customer' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."customers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.customers';
      v_reveal := 'customers_reveal';
      v_reveal_schema := 'public';
    when 'drive_node' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.drive_nodes';
      v_reveal := 'drive_nodes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'application' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."applications" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.applications';
      v_reveal := 'applications_reveal';
      v_reveal_schema := 'better_supabase';
    when 'change_request' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."change_requests" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.change_requests';
      v_reveal := 'change_requests_reveal';
      v_reveal_schema := 'public';
    when 'project' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."projects" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.projects';
      v_reveal := 'projects_reveal';
      v_reveal_schema := 'public';
    when 'task' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."tasks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.tasks';
      v_reveal := 'tasks_reveal';
      v_reveal_schema := 'public';
    else
      raise exception 'subject_type is not a record type in config.subjects' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end case;
  if v_record is null or not ((v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'data_lifecycle.export'), false))) then
    raise exception 'You may not export this record' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x
  where x."subject" = 'record' and x."subject_type" = request_subject_export.subject_type
    and x."subject_id" = request_subject_export.subject_id and x."requested_by" = auth.uid()
    and x."status" in ('pending', 'running');
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  -- Only the owner's reveal function, so one another role created never runs
  -- with this function's rights.
  select pg_catalog.format('%I.%I', n.nspname, p.proname), pg_catalog.format_type(p.proargtypes[0], null),
    array(select a.name from unnest(p.proargnames, p.proargmodes::text[]) with ordinality a(name, mode, n)
      where a.mode = 't' order by a.n offset 1)
  into v_proc, v_arg, v_sealed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = v_reveal_schema and p.proname = v_reveal and p.pronargs = 1
    and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
  limit 1;
  -- The stored ciphertext never leaves: a caller the reveal returns no row
  -- for gets the record without its encrypted columns.
  if v_proc is not null then
    execute format('select to_jsonb(r.*) from %s(array[$1]::%s) r', v_proc, v_arg) into v_plain
    using request_subject_export.subject_id;
    v_record := (v_record - coalesce(v_sealed, '{}'::text[])) || coalesce(v_plain, '{}'::jsonb);
  end if;
  v_parts := jsonb_build_object(v_name, jsonb_build_array(v_record));
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_subscriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_subscriptions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."guest_grants" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.guest_grants', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."attachments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.attachments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.enrollments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_runs" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_runs', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_start_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_start_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."knowledge_documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.knowledge_documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."memories" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.memories', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."taggings" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.taggings', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_stages" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_stages', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_lifecycles" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_lifecycles', v_rows);
  end if;
  if v_tenant is not null then
    v_fields := coalesce("better_supabase"."read_field_values"(v_tenant, request_subject_export.subject_type, request_subject_export.subject_id), '[]'::jsonb);
    select coalesce(jsonb_agg(((to_jsonb(t.*)) || jsonb_build_object('value_text', f.value ->> 'text')) order by t.ctid), '[]'::jsonb) into v_rows
    from "better_supabase"."field_values" t
    join jsonb_array_elements(v_fields) f on f.value ->> 'id' = t."id"::text
    where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
    if jsonb_array_length(v_rows) > 0 then
      v_parts := v_parts || jsonb_build_object('better_supabase.field_values', v_rows);
    end if;
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*) - array['token_hash', 'password_hash']::text[]) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."share_links" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.share_links', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."recurrence_rules" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.recurrence_rules', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reminders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reminders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_members" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_members', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."calendar_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.calendar_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."versions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.versions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."trash_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.trash_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reactions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reactions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reaction_scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reaction_scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."approval_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.approval_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."form_submissions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.form_submissions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."signature_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.signature_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."template_applications" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.template_applications', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."pipeline_stage_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.pipeline_stage_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."engagement_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.engagement_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."sla_clocks" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sla_clocks', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."moderation_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."rule_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.rule_evaluations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."passes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.passes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_rates" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_rates', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."work_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.work_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."shipments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.shipments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."conversations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.conversations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."message_record_mentions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.message_record_mentions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."channels" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.channels', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."activity_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.activity_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."mail_thread_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.mail_thread_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."field_changes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.field_changes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."sequence_enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sequence_enrollments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgements" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgements', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."observations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.observations', v_rows);
  end if;
  insert into "better_supabase"."data_exports" ("subject", "organization_id", "subject_type", "subject_id", "format")
  values ('record', v_tenant, request_subject_export.subject_type, request_subject_export.subject_id, request_subject_export.format)
  returning * into v_row;
  insert into "better_supabase"."data_export_contents" ("export_id", "parts") values (v_row."id", v_parts);
  perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_observation_definition (
  tenant     uuid,
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."observation_definitions"%rowtype;
  v_old "better_supabase"."observation_definitions"%rowtype;
  v_definition jsonb := coalesce(save_observation_definition.definition, '{}'::jsonb);
  v_title text;
  v_type text;
  v_components jsonb;
  v_component jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_observation_definition.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role saves system definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_observation_definition.tenant, 'observations.manage'), false)) then
    raise exception 'not allowed to manage observation definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if save_observation_definition.key is null or save_observation_definition.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'the key takes lowercase letters, digits and underscores, starting with a letter' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if jsonb_typeof(v_definition) <> 'object' then
    raise exception 'definition is an object' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_title := nullif(trim(v_definition ->> 'title'), '');
  if v_title is null or length(v_title) > 200 then
    raise exception 'a definition needs a title of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_type := v_definition ->> 'valueType';
  if v_type is null or v_type not in ('number', 'integer', 'boolean', 'code', 'text', 'components') then
    raise exception 'valueType is one of number, integer, boolean, code, text, components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'unit' and (jsonb_typeof(v_definition -> 'unit') not in ('string', 'null') or length(v_definition ->> 'unit') > 50) then
    raise exception 'unit is a UCUM unit of at most 50 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'codeSystem' and (jsonb_typeof(v_definition -> 'codeSystem') not in ('string', 'null') or length(v_definition ->> 'codeSystem') > 200) then
    raise exception 'codeSystem is a text of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'code' and (jsonb_typeof(v_definition -> 'code') not in ('string', 'null') or length(v_definition ->> 'code') > 100) then
    raise exception 'code is a text of at most 100 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'decimals' and jsonb_typeof(v_definition -> 'decimals') <> 'null' and (jsonb_typeof(v_definition -> 'decimals') <> 'number' or (v_definition ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
    raise exception 'decimals is a whole number from 0 to 6' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'validLow' and jsonb_typeof(v_definition -> 'validLow') not in ('number', 'null') then
    raise exception 'the definition''s validLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'validHigh' and jsonb_typeof(v_definition -> 'validHigh') not in ('number', 'null') then
    raise exception 'the definition''s validHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'referenceLow' and jsonb_typeof(v_definition -> 'referenceLow') not in ('number', 'null') then
    raise exception 'the definition''s referenceLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'referenceHigh' and jsonb_typeof(v_definition -> 'referenceHigh') not in ('number', 'null') then
    raise exception 'the definition''s referenceHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'criticalLow' and jsonb_typeof(v_definition -> 'criticalLow') not in ('number', 'null') then
    raise exception 'the definition''s criticalLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'criticalHigh' and jsonb_typeof(v_definition -> 'criticalHigh') not in ('number', 'null') then
    raise exception 'the definition''s criticalHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'validLow')::numeric > (v_definition ->> 'validHigh')::numeric then
    raise exception 'the definition''s validLow is at most validHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'referenceLow')::numeric > (v_definition ->> 'referenceHigh')::numeric then
    raise exception 'the definition''s referenceLow is at most referenceHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'criticalLow')::numeric > (v_definition ->> 'criticalHigh')::numeric then
    raise exception 'the definition''s criticalLow is at most criticalHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_components := case when jsonb_typeof(v_definition -> 'components') = 'null' then null else v_definition -> 'components' end;
  if v_type = 'components' then
    if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) not between 1 and 20 then
      raise exception 'a components definition has 1 to 20 components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
    end if;
    if (select count(distinct c ->> 'key') from jsonb_array_elements(v_components) c) <> jsonb_array_length(v_components) then
      raise exception 'component keys are unique' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
    end if;
    for v_component in select c from jsonb_array_elements(v_components) c loop
      if jsonb_typeof(v_component) <> 'object' or coalesce(v_component ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,62}$' then
        raise exception 'each component has a key of lowercase letters, digits and underscores' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if nullif(trim(v_component ->> 'title'), '') is null or length(v_component ->> 'title') > 200 then
        raise exception 'each component has a title of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'unit' and (jsonb_typeof(v_component -> 'unit') not in ('string', 'null') or length(v_component ->> 'unit') > 50) then
    raise exception 'a component unit is at most 50 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
      if v_component ? 'code' and (jsonb_typeof(v_component -> 'code') not in ('string', 'null') or length(v_component ->> 'code') > 100) then
    raise exception 'a component code is at most 100 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
      if v_component ? 'decimals' and (jsonb_typeof(v_component -> 'decimals') <> 'number' or (v_component ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
        raise exception 'a component''s decimals is a whole number from 0 to 6' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'optional' and jsonb_typeof(v_component -> 'optional') <> 'boolean' then
        raise exception 'a component''s optional is true or false' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'validLow' and jsonb_typeof(v_component -> 'validLow') not in ('number', 'null') then
    raise exception 'a component''s validLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'validHigh' and jsonb_typeof(v_component -> 'validHigh') not in ('number', 'null') then
    raise exception 'a component''s validHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'referenceLow' and jsonb_typeof(v_component -> 'referenceLow') not in ('number', 'null') then
    raise exception 'a component''s referenceLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'referenceHigh' and jsonb_typeof(v_component -> 'referenceHigh') not in ('number', 'null') then
    raise exception 'a component''s referenceHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'criticalLow' and jsonb_typeof(v_component -> 'criticalLow') not in ('number', 'null') then
    raise exception 'a component''s criticalLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'criticalHigh' and jsonb_typeof(v_component -> 'criticalHigh') not in ('number', 'null') then
    raise exception 'a component''s criticalHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'validLow')::numeric > (v_component ->> 'validHigh')::numeric then
    raise exception 'a component''s validLow is at most validHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'referenceLow')::numeric > (v_component ->> 'referenceHigh')::numeric then
    raise exception 'a component''s referenceLow is at most referenceHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'criticalLow')::numeric > (v_component ->> 'criticalHigh')::numeric then
    raise exception 'a component''s criticalLow is at most criticalHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
    end loop;
  elsif v_components is not null then
    raise exception 'only a components definition has components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  select * into v_old from "better_supabase"."observation_definitions" x
  where x."tenant_id" is not distinct from save_observation_definition.tenant and x."key" = save_observation_definition.key;
  if found and v_old."value_type" <> v_type and exists (select 1 from "better_supabase"."observations" x where x."definition_id" = v_old."id") then
    raise exception 'the value type can''t change once observations use the definition' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_definition_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_observation_definition.tenant, save_observation_definition.key;
    end if;
  end;
  insert into "better_supabase"."observation_definitions" ("tenant_id", "key", "title", "value_type", "unit", "code_system", "code", "components", "decimals", "valid_low", "valid_high", "reference_low", "reference_high", "critical_low", "critical_high")
  values (save_observation_definition.tenant, save_observation_definition.key, v_title, v_type, nullif(trim(v_definition ->> 'unit'), ''), nullif(trim(v_definition ->> 'codeSystem'), ''), nullif(trim(v_definition ->> 'code'), ''), v_components, (v_definition ->> 'decimals')::integer, (v_definition ->> 'validLow')::numeric, (v_definition ->> 'validHigh')::numeric, (v_definition ->> 'referenceLow')::numeric, (v_definition ->> 'referenceHigh')::numeric, (v_definition ->> 'criticalLow')::numeric, (v_definition ->> 'criticalHigh')::numeric)
  on conflict ("tenant_id", "key") do update set
      "title" = excluded."title",
      "value_type" = excluded."value_type",
      "unit" = excluded."unit",
      "code_system" = excluded."code_system",
      "code" = excluded."code",
      "components" = excluded."components",
      "decimals" = excluded."decimals",
      "valid_low" = excluded."valid_low",
      "valid_high" = excluded."valid_high",
      "reference_low" = excluded."reference_low",
      "reference_high" = excluded."reference_high",
      "critical_low" = excluded."critical_low",
      "critical_high" = excluded."critical_high",
      "archived_at" = null,
      "updated_at" = now()
  returning * into v_row;
  if v_old."id" is null then
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.created', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.created',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  else
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.updated',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_definition_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'system', v_row."tenant_id" is null, 'key', v_row."key", 'title', v_row."title", 'valueType', v_row."value_type", 'unit', v_row."unit", 'codeSystem', v_row."code_system", 'code', v_row."code", 'components', coalesce(v_row."components", '[]'::jsonb), 'decimals', v_row."decimals", 'validLow', v_row."valid_low", 'validHigh', v_row."valid_high", 'referenceLow', v_row."reference_low", 'referenceHigh', v_row."reference_high", 'criticalLow', v_row."critical_low", 'criticalHigh', v_row."critical_high", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."observations"
  ADD CONSTRAINT "observations_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.observation_definitions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."observations"
  ADD CONSTRAINT "observations_replaces_id_fkey" FOREIGN KEY (replaces_id) REFERENCES better_supabase.observations(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."observations"
  ADD CONSTRAINT "observations_submission_id_fkey" FOREIGN KEY (submission_id) REFERENCES better_supabase.form_submissions(id) ON DELETE SET NULL;

CREATE INDEX observations_definition_idx ON better_supabase.observations USING btree (definition_id);

CREATE UNIQUE INDEX observations_external_key ON better_supabase.observations USING btree (tenant_id, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX observations_replaces_idx ON better_supabase.observations USING btree (replaces_id)
  WHERE (replaces_id IS NOT NULL);

CREATE INDEX observations_series_idx ON better_supabase.observations USING btree (subject_type, subject_id, definition_id, observed_at DESC);

CREATE INDEX observations_submission_idx ON better_supabase.observations USING btree (submission_id)
  WHERE (submission_id IS NOT NULL);

CREATE INDEX observations_tenant_idx ON better_supabase.observations USING btree (tenant_id, observed_at DESC);

CREATE TRIGGER bsb_observation_submission
  AFTER INSERT OR UPDATE OF status ON better_supabase.form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.observation_submission_trigger();

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."observation_definitions"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."observation_definitions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."observation_definitions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IS NULL) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."observation_definitions"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "observation_definitions_read" ON "better_supabase"."observation_definitions"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IS NULL) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) OR (tenant_id IN ( SELECT
    better_supabase.member_organization_ids() AS member_organization_ids))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "observations_read" ON "better_supabase"."observations"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id,
    'read'::text), false)));

REVOKE ALL ON FUNCTION "api"."amend_observation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."amend_observation"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ingest_observations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ingest_observations"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."latest_observations"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."latest_observations"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_observation_definitions"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_observation_definitions"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_observations"(text, text, text, boolean, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_observations"(text, text, text, boolean, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_observation_error"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_observation_error"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."observation_series"(text, text, text, timestamp WITH time zone, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."observation_series"(text, text, text, timestamp WITH time zone, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."observations_from_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."observations_from_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_observation"(uuid, text, text, text, jsonb, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_observation"(uuid, text, text, text, jsonb, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_observations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_observations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_observation_definition"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_observation_definition"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."amend_observation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."amend_observation"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ingest_observations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ingest_observations"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."latest_observations"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."latest_observations"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_observation_definitions"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_observation_definitions"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_observations"(text, text, text, boolean, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_observations"(text, text, text, boolean, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_observation_error"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_observation_error"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."observation_definition_id"(uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."observation_flag"(numeric, numeric, numeric, numeric, numeric) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."observation_insert"(uuid, uuid, text, text, jsonb, timestamp WITH time zone, jsonb, text, text, uuid, uuid, uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."observation_series"(text, text, text, timestamp WITH time zone, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."observation_series"(text, text, text, timestamp WITH time zone, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."observation_submission_apply"(uuid, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."observation_submission_trigger"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."observations_from_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."observations_from_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_observation"(uuid, text, text, text, jsonb, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_observation"(uuid, text, text, text, jsonb, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_observations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_observations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_observation_definition"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_observation_definition"(uuid, text, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."observation_definitions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."observation_definitions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."observations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."observations" TO "service_role";
