SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."consent_receipts" (
  "id"           uuid                     NOT NULL,
  "tenant_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "consent_id"   uuid                     NOT NULL,
  "status"       text                     NOT NULL,
  "receipt"      jsonb                    NOT NULL,
  "digest"       text                     NOT NULL,
  "issued_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "consent_receipts_consent_id_status_key" UNIQUE (consent_id, status),
  CONSTRAINT "consent_receipts_digest_check" CHECK ((digest ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "consent_receipts_pkey" PRIMARY KEY (id),
  CONSTRAINT "consent_receipts_receipt_check" CHECK ((jsonb_typeof(receipt) = 'object'::text))
);

ALTER TABLE "better_supabase"."consent_receipts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."consent_signals" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "kind"         text                     NOT NULL,
  "raw"          text                     NOT NULL,
  "parsed"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "consent_ids"  uuid[]                   NOT NULL DEFAULT '{}'::uuid[],
  "created_by"   uuid,
  "received_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "consent_signals_kind_check" CHECK ((kind = ANY (ARRAY['gpc'::text, 'tcf'::text, 'gpp'::text]))),
  CONSTRAINT "consent_signals_parsed_check" CHECK ((jsonb_typeof(parsed) = 'object'::text)),
  CONSTRAINT "consent_signals_pkey" PRIMARY KEY (id),
  CONSTRAINT "consent_signals_raw_check" CHECK (((length(raw) >= 1) AND (length(raw) <= 8192)))
);

ALTER TABLE "better_supabase"."consent_signals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."data_subject_requests" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id"     uuid                     NOT NULL,
  "kind"                text                     NOT NULL,
  "requester"           text                     NOT NULL,
  "subject_type"        text,
  "subject_id"          text,
  "details"             text,
  "status"              text                     NOT NULL DEFAULT 'received'::text,
  "received_at"         timestamp with time zone NOT NULL DEFAULT now(),
  "received_by"         uuid,
  "due_at"              timestamp with time zone NOT NULL,
  "extended_at"         timestamp with time zone,
  "extension_reason"    text,
  "verified_at"         timestamp with time zone,
  "verified_by"         uuid,
  "verification_method" text,
  "export_id"           uuid,
  "resolution"          text,
  "closed_at"           timestamp with time zone,
  "closed_by"           uuid,
  CONSTRAINT "data_subject_requests_check" CHECK (((subject_type IS NULL) = (subject_id IS NULL))),
  CONSTRAINT "data_subject_requests_details_check" CHECK (((details IS NULL) OR (length(details) <= 5000))),
  CONSTRAINT "data_subject_requests_kind_check" CHECK ((kind = ANY (ARRAY['access'::text, 'erasure'::text, 'rectification'::text, 'portability'::text]))),
  CONSTRAINT "data_subject_requests_pkey" PRIMARY KEY (id),
  CONSTRAINT "data_subject_requests_requester_check" CHECK (((length(requester) >= 1) AND (length(requester) <= 320))),
  CONSTRAINT "data_subject_requests_status_check" CHECK ((status = ANY (ARRAY['received'::text, 'verified'::text, 'fulfilled'::text, 'refused'::text])))
);

ALTER TABLE "better_supabase"."data_subject_requests"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incident_regulatory_filings" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "incident_id"  uuid                     NOT NULL,
  "regime"       text                     NOT NULL,
  "stage"        text                     NOT NULL,
  "due_at"       timestamp with time zone,
  "reminder_id"  uuid,
  "submitted_at" timestamp with time zone,
  "submitted_by" uuid,
  "reference"    text,
  "notes"        text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "incident_regulatory_filings_incident_id_regime_stage_key" UNIQUE (incident_id, regime, stage),
  CONSTRAINT "incident_regulatory_filings_notes_check" CHECK (((notes IS NULL) OR (length(notes) <= 5000))),
  CONSTRAINT "incident_regulatory_filings_pkey" PRIMARY KEY (id),
  CONSTRAINT "incident_regulatory_filings_reference_check" CHECK (((reference IS NULL) OR (length(reference) <= 200))),
  CONSTRAINT "incident_regulatory_filings_regime_check" CHECK ((regime = ANY (ARRAY['nis2'::text, 'dora'::text, 'cra'::text]))),
  CONSTRAINT "incident_regulatory_filings_stage_check"
    CHECK ((stage = ANY (ARRAY['early_warning'::text, 'notification'::text, 'initial'::text, 'intermediate'::text, 'final'::text])))
);

ALTER TABLE "better_supabase"."incident_regulatory_filings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incident_regulatory_profiles" (
  "incident_id"          uuid                     NOT NULL,
  "tenant_id"            uuid                     NOT NULL,
  "regimes"              text[]                   NOT NULL DEFAULT '{}'::text[],
  "aware_at"             timestamp with time zone NOT NULL,
  "classification"       text,
  "classified_at"        timestamp with time zone,
  "significant"          boolean                  NOT NULL DEFAULT false,
  "actively_exploited"   boolean                  NOT NULL DEFAULT false,
  "measure_available_at" timestamp with time zone,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "incident_regulatory_profiles_classification_check" CHECK (((classification IS NULL) OR (classification = ANY (ARRAY['major'::text, 'non_major'::text])))),
  CONSTRAINT "incident_regulatory_profiles_pkey" PRIMARY KEY (incident_id),
  CONSTRAINT "incident_regulatory_profiles_regimes_check" CHECK ((regimes <@ ARRAY['nis2'::text, 'dora'::text, 'cra'::text]))
);

ALTER TABLE "better_supabase"."incident_regulatory_profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."moderation_appeals" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "statement_id" uuid,
  "notice_id"    uuid,
  "appellant_id" uuid,
  "reasons"      text                     NOT NULL,
  "status"       text                     NOT NULL DEFAULT 'open'::text,
  "outcome"      text,
  "decided_by"   uuid,
  "decided_at"   timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "moderation_appeals_check" CHECK (((statement_id IS NOT NULL) <> (notice_id IS NOT NULL))),
  CONSTRAINT "moderation_appeals_outcome_check" CHECK (((outcome IS NULL) OR (length(outcome) <= 2000))),
  CONSTRAINT "moderation_appeals_pkey" PRIMARY KEY (id),
  CONSTRAINT "moderation_appeals_reasons_check" CHECK (((length(reasons) >= 1) AND (length(reasons) <= 5000))),
  CONSTRAINT "moderation_appeals_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'upheld'::text, 'reversed'::text])))
);

ALTER TABLE "better_supabase"."moderation_appeals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."moderation_flaggers" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "name"       text                     NOT NULL,
  "awarded_by" text,
  "revoked_at" timestamp with time zone,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "moderation_flaggers_awarded_by_check" CHECK (((awarded_by IS NULL) OR (length(awarded_by) <= 200))),
  CONSTRAINT "moderation_flaggers_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "moderation_flaggers_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."moderation_flaggers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."moderation_notices" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "item_id"        uuid,
  "subject_type"   text                     NOT NULL,
  "subject_id"     text                     NOT NULL,
  "explanation"    text                     NOT NULL,
  "url"            text,
  "notifier_name"  text,
  "notifier_email" text,
  "notifier_id"    uuid,
  "trusted"        boolean                  NOT NULL DEFAULT false,
  "status"         text                     NOT NULL DEFAULT 'received'::text,
  "outcome"        text,
  "decided_by"     uuid,
  "decided_at"     timestamp with time zone,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "moderation_notices_explanation_check" CHECK (((length(explanation) >= 1) AND (length(explanation) <= 5000))),
  CONSTRAINT "moderation_notices_notifier_email_check" CHECK (((notifier_email IS NULL) OR (length(notifier_email) <= 320))),
  CONSTRAINT "moderation_notices_notifier_name_check" CHECK (((notifier_name IS NULL) OR (length(notifier_name) <= 200))),
  CONSTRAINT "moderation_notices_outcome_check" CHECK (((outcome IS NULL) OR (length(outcome) <= 2000))),
  CONSTRAINT "moderation_notices_pkey" PRIMARY KEY (id),
  CONSTRAINT "moderation_notices_status_check" CHECK ((status = ANY (ARRAY['received'::text, 'actioned'::text, 'rejected'::text]))),
  CONSTRAINT "moderation_notices_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200))),
  CONSTRAINT "moderation_notices_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "moderation_notices_url_check" CHECK (((url IS NULL) OR (length(url) <= 2000)))
);

ALTER TABLE "better_supabase"."moderation_notices"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."moderation_statements" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"           uuid                     NOT NULL,
  "item_id"             uuid                     NOT NULL,
  "restriction"         text                     NOT NULL,
  "facts"               text                     NOT NULL,
  "legal_ground"        text,
  "terms_ground"        text,
  "automated_detection" boolean                  NOT NULL DEFAULT false,
  "automated_decision"  boolean                  NOT NULL DEFAULT false,
  "redress"             text[]                   NOT NULL DEFAULT ARRAY['internal_complaint'::text,
  'out_of_court'::text,
  'judicial'::text],
  "issued_by"           uuid,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "moderation_statements_check" CHECK (((legal_ground IS NOT NULL) OR (terms_ground IS NOT NULL))),
  CONSTRAINT "moderation_statements_facts_check" CHECK (((length(facts) >= 1) AND (length(facts) <= 5000))),
  CONSTRAINT "moderation_statements_legal_ground_check" CHECK (((legal_ground IS NULL) OR (length(legal_ground) <= 2000))),
  CONSTRAINT "moderation_statements_pkey" PRIMARY KEY (id),
  CONSTRAINT "moderation_statements_restriction_check"
    CHECK
    ((restriction = ANY (ARRAY['removal'::text, 'disabled_access'::text, 'demotion'::text, 'visibility_suspension'::text, 'monetary_suspension'::text, 'service_suspension'::text,
    'service_termination'::text, 'account_suspension'::text, 'account_termination'::text]))),
  CONSTRAINT "moderation_statements_terms_ground_check" CHECK (((terms_ground IS NULL) OR (length(terms_ground) <= 2000)))
);

ALTER TABLE "better_supabase"."moderation_statements"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.apply_oscal_profile (
  framework_id uuid,
  document     jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."apply_oscal_profile"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.decide_appeal (
  appeal_id uuid,
  outcome   text,
  reason    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_appeal"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.decide_notice (
  notice_id uuid,
  decision  text,
  outcome   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_notice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.export_oscal_assessment_results (
  framework_id uuid,
  title        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."export_oscal_assessment_results"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.extend_data_subject_request (
  id     uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."extend_data_subject_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.file_appeal (
  statement_id uuid DEFAULT NULL::uuid,
  notice_id    uuid DEFAULT NULL::uuid,
  reasons      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."file_appeal"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.fulfil_data_subject_request (
  id         uuid,
  resolution text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fulfil_data_subject_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_incident_regulatory_profile (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_incident_regulatory_profile"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_oscal_catalog (
  tenant   uuid,
  document jsonb,
  key      text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_oscal_catalog"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.issue_consent_receipt (
  consent_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."issue_consent_receipt"($1) $function$;

CREATE OR REPLACE FUNCTION api.issue_statement (
  item_id             uuid,
  restriction         text,
  facts               text,
  legal_ground        text    DEFAULT NULL::text,
  terms_ground        text    DEFAULT NULL::text,
  automated_detection boolean DEFAULT false,
  automated_decision  boolean DEFAULT false,
  redress             text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."issue_statement"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.list_consent_receipts (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consent_receipts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_consent_signals (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consent_signals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_data_subject_requests (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  open_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_data_subject_requests"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_incident_filings (
  tenant  uuid,
  pending boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_incident_filings"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_notices (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notices"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_statements (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_statements"($1) $function$;

CREATE OR REPLACE FUNCTION api.open_data_subject_request (
  tenant       uuid,
  kind         text,
  requester    text,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  details      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_data_subject_request"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.record_consent_signal (
  subject_type text,
  subject_id   text,
  kind         text,
  value        text,
  purpose_keys text[] DEFAULT '{}'::text[],
  consent_id   uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_consent_signal"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.refuse_data_subject_request (
  id     uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."refuse_data_subject_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_incident_regulatory_profile (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_incident_regulatory_profile"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_trusted_flagger (
  tenant     uuid,
  user_id    uuid,
  name       text    DEFAULT NULL::text,
  awarded_by text    DEFAULT NULL::text,
  active     boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_trusted_flagger"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.submit_incident_filing (
  incident_id  uuid,
  regime       text,
  stage        text,
  reference    text                     DEFAULT NULL::text,
  notes        text                     DEFAULT NULL::text,
  submitted_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."submit_incident_filing"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.submit_notice (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  explanation    text,
  url            text DEFAULT NULL::text,
  notifier_name  text DEFAULT NULL::text,
  notifier_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."submit_notice"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.transparency_report (
  tenant       uuid,
  period_start timestamp with time zone,
  period_end   timestamp with time zone
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."transparency_report"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.verify_data_subject_request (
  id     uuid,
  method text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."verify_data_subject_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_oscal_profile (
  framework_id uuid,
  document     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_import jsonb;
  v_all boolean := false;
  v_included text[] := '{}';
  v_excluded text[] := '{}';
  v_codes text[];
  v_applicable integer;
  v_other integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = apply_oscal_profile.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if apply_oscal_profile.document is null or jsonb_typeof(apply_oscal_profile.document -> 'profile') is distinct from 'object' then
    raise exception 'the document needs a profile object' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  if jsonb_typeof(apply_oscal_profile.document #> '{profile,imports}') is distinct from 'array' then
    raise exception 'the profile needs imports' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  for v_import in select i from jsonb_array_elements(apply_oscal_profile.document #> '{profile,imports}') i loop
    if v_import ? 'include-all' then
      v_all := true;
    end if;
    v_included := v_included || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."include-controls"[*]."with-ids"[*]'))), '{}');
    v_excluded := v_excluded || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."exclude-controls"[*]."with-ids"[*]'))), '{}');
  end loop;
  if not v_all and cardinality(v_included) = 0 then
    raise exception 'the profile includes no controls' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  select coalesce(array_agg(c."code"), '{}') into v_codes from "better_supabase"."controls" c where c."framework_id" = v_framework."id";
  update "better_supabase"."controls" c set "applicable" = (v_all or c."code" = any(v_included)) and not (c."code" = any(v_excluded)), "updated_at" = now()
  where c."framework_id" = v_framework."id"
    and c."applicable" is distinct from ((v_all or c."code" = any(v_included)) and not (c."code" = any(v_excluded)));
  select count(*) filter (where c."applicable"), count(*) filter (where not c."applicable") into v_applicable, v_other
  from "better_supabase"."controls" c where c."framework_id" = v_framework."id";
  return jsonb_build_object(
    'frameworkId', v_framework."id",
    'applicable', v_applicable,
    'notApplicable', v_other,
    'unknownIds', to_jsonb(array(select distinct i from unnest(v_included || v_excluded) i where not (i = any(v_codes)) order by i))
  );
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
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'subject_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_e_endpoints', '"better_supabase"."invoice_e_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_e_deliveries', '"better_supabase"."invoice_e_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_appeal (
  appeal_id uuid,
  outcome   text,
  reason    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_appeals";
  v_item "better_supabase"."moderation_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."moderation_appeals" x where x."id" = decide_appeal.appeal_id for update;
  if v_row."id" is null then
    raise exception 'appeal not found' using errcode = 'P0002', hint = 'MODERATION_APPEAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to decide on appeals' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if decide_appeal.outcome is null or decide_appeal.outcome not in ('upheld', 'reversed') then
    raise exception 'outcome must be upheld or reversed' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(decide_appeal.reason) > 2000 then
    raise exception 'reason must be at most 2000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'this appeal was decided already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if decide_appeal.outcome = 'reversed' then
    if v_row."statement_id" is not null then
      select x.* into v_item from "better_supabase"."moderation_items" x join "better_supabase"."moderation_statements" s on s."item_id" = x."id" where s."id" = v_row."statement_id";
      if v_item."status" in ('hidden', 'removed') then
        perform "better_supabase"."moderation_apply"(v_item."id", 'restore', decide_appeal.reason, false);
      end if;
    else
      update "better_supabase"."moderation_notices" x set "status" = 'received', "decided_at" = null, "decided_by" = null
      where x."id" = v_row."notice_id";
    end if;
  end if;
  update "better_supabase"."moderation_appeals" x
  set "status" = decide_appeal.outcome, "outcome" = nullif(trim(decide_appeal.reason), ''), "decided_by" = auth.uid(), "decided_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('moderation_appeal.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'status', v_row."status", 'appellantId', v_row."appellant_id"), 'moderation-appeals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_appeal.decided',
    category => 'data',
    target_type => 'moderation_appeal',
    record_id => v_row."id"::text,
    summary => 'appeal ' || v_row."status",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'status', v_row."status", 'appellantId', v_row."appellant_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'appellantId', v_row."appellant_id", 'reasons', v_row."reasons", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_notice (
  notice_id uuid,
  decision  text,
  outcome   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_notices";
  v_item "better_supabase"."moderation_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."moderation_notices" x where x."id" = decide_notice.notice_id for update;
  if v_row."id" is null then
    raise exception 'notice not found' using errcode = 'P0002', hint = 'MODERATION_NOTICE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to decide on notices' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if decide_notice.decision is null or decide_notice.decision not in ('hide', 'remove', 'reject') then
    raise exception 'decision must be hide, remove or reject' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(decide_notice.outcome) > 2000 then
    raise exception 'outcome must be at most 2000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if v_row."status" <> 'received' then
    raise exception 'this notice was decided already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if decide_notice.decision <> 'reject' then
    if v_row."item_id" is null then
      raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
    end if;
    perform "better_supabase"."moderation_apply"(v_row."item_id", decide_notice.decision, decide_notice.outcome, false);
  end if;
  update "better_supabase"."moderation_notices" x
  set "status" = case when decide_notice.decision = 'reject' then 'rejected' else 'actioned' end,
    "outcome" = nullif(trim(decide_notice.outcome), ''), "decided_by" = auth.uid(), "decided_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('moderation_notice.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'itemId', v_row."item_id", 'status', v_row."status", 'decision', decide_notice.decision, 'notifierId', v_row."notifier_id"), 'moderation-notices/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_notice.decided',
    category => 'data',
    target_type => 'moderation_notice',
    record_id => v_row."id"::text,
    summary => 'notice ' || v_row."status",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'itemId', v_row."item_id", 'status', v_row."status", 'decision', decide_notice.decision, 'notifierId', v_row."notifier_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'explanation', v_row."explanation", 'url', v_row."url", 'notifierName', v_row."notifier_name", 'notifierEmail', v_row."notifier_email", 'notifierId', v_row."notifier_id", 'trusted', v_row."trusted", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.export_oscal_assessment_results (
  framework_id uuid,
  title        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_now text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_title text;
begin
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = export_oscal_assessment_results.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  v_title := coalesce(nullif(trim(export_oscal_assessment_results.title), ''), v_framework."name" || ' assessment results');
  return jsonb_build_object('assessment-results', jsonb_build_object(
    'uuid', gen_random_uuid(),
    'metadata', jsonb_build_object(
      'title', v_title,
      'last-modified', v_now,
      'version', coalesce(v_framework."version", '1'),
      'oscal-version', '1.2.3'
    ),
    'import-ap', jsonb_build_object('href', 'urn:uuid:' || v_framework."id"::text),
    'results', jsonb_build_array(jsonb_build_object(
      'uuid', gen_random_uuid(),
      'title', v_title,
      'description', 'Evidence collected for the applicable controls of ' || v_framework."name" || '.',
      'start', v_now,
      'reviewed-controls', jsonb_build_object('control-selections', jsonb_build_array(jsonb_build_object(
        'include-controls', coalesce((
          select jsonb_agg(jsonb_build_object('control-id', c."code") order by c."code")
          from "better_supabase"."controls" c where c."framework_id" = v_framework."id" and c."applicable"
        ), '[]'::jsonb)
      ))),
      'observations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', ev."id",
          'description', coalesce(ev."note", 'Evidence for control ' || c."code"),
          'methods', jsonb_build_array('EXAMINE'),
          'collected', to_char(ev."collected_at" at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'relevant-evidence', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
            'description', coalesce(ev."note", 'Attachment'),
            'href', case when ev."attachment_id" is null then null else 'urn:uuid:' || ev."attachment_id"::text end
          )))
        ) order by c."code", ev."collected_at", ev."id")
        from "better_supabase"."control_evidence" ev
        join "better_supabase"."controls" c on c."id" = ev."control_id"
        where c."framework_id" = v_framework."id" and c."applicable"
      ), '[]'::jsonb),
      'findings', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', gen_random_uuid(),
          'title', c."code" || ' ' || c."title",
          'description', c."title",
          'target', jsonb_build_object(
            'type', 'objective-id',
            'target-id', c."code",
            'status', jsonb_build_object('state', case when exists (
              select 1 from "better_supabase"."control_evidence" ev where ev."control_id" = c."id" and (ev."valid_until" is null or ev."valid_until" >= current_date)
            ) then 'satisfied' else 'not-satisfied' end)
          ),
          'related-observations', coalesce((
            select jsonb_agg(jsonb_build_object('observation-uuid', ev."id") order by ev."collected_at", ev."id")
            from "better_supabase"."control_evidence" ev where ev."control_id" = c."id"
          ), '[]'::jsonb)
        ) order by c."code")
        from "better_supabase"."controls" c where c."framework_id" = v_framework."id" and c."applicable"
      ), '[]'::jsonb)
    ))
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_data_subject_request (
  id     uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = extend_data_subject_request.id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if v_row."extended_at" is not null then
    raise exception 'the due date was already extended once' using errcode = '55000', hint = 'DSAR_EXTENDED';
  end if;
  if extend_data_subject_request.reason is null or length(trim(extend_data_subject_request.reason)) = 0 then
    raise exception 'reason is required' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  update "better_supabase"."data_subject_requests" x set "due_at" = x."received_at" + interval '3 months', "extended_at" = now(), "extension_reason" = trim(extend_data_subject_request.reason)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.extended', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.extended',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.file_appeal (
  statement_id uuid DEFAULT NULL::uuid,
  notice_id    uuid DEFAULT NULL::uuid,
  reasons      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_row "better_supabase"."moderation_appeals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to file an appeal' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if (file_appeal.statement_id is null) = (file_appeal.notice_id is null) then
    raise exception 'an appeal names a statement or a notice' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if file_appeal.reasons is null or length(trim(file_appeal.reasons)) = 0 or length(file_appeal.reasons) > 5000 then
    raise exception 'an appeal needs reasons of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if file_appeal.statement_id is not null then
    select s."tenant_id" into v_tenant
    from "better_supabase"."moderation_statements" s join "better_supabase"."moderation_items" x on x."id" = s."item_id"
    where s."id" = file_appeal.statement_id and x."author_id" = v_me;
  else
    select x."tenant_id" into v_tenant from "better_supabase"."moderation_notices" x
    where x."id" = file_appeal.notice_id and x."notifier_id" = v_me and x."status" = 'rejected';
  end if;
  if v_tenant is null then
    raise exception 'you can only appeal a decision that affects you' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."moderation_appeals" ("tenant_id", "statement_id", "notice_id", "appellant_id", "reasons")
    values (v_tenant, file_appeal.statement_id, file_appeal.notice_id, v_me, trim(file_appeal.reasons))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'an appeal is open for this decision already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end;
  perform "better_supabase".emit_event('moderation_appeal.filed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'appellantId', v_row."appellant_id"), 'moderation-appeals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'appellantId', v_row."appellant_id", 'reasons', v_row."reasons", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fulfil_data_subject_request (
  id         uuid,
  resolution text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
  v_export jsonb;
  v_export_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = fulfil_data_subject_request.id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if v_row."verified_at" is null then
    raise exception 'verify the requester''s identity first' using errcode = '55000', hint = 'DSAR_UNVERIFIED';
  end if;
  if v_row."kind" in ('access', 'portability') then
    if v_row."subject_type" is null then
      raise exception 'an access or portability request names the record to export' using errcode = '22023', hint = 'DSAR_INVALID';
    end if;
    v_export := "better_supabase"."request_subject_export"(v_row."subject_type", v_row."subject_id", 'ndjson');
    v_export_id := (v_export ->> 'id')::uuid;
  else
    if fulfil_data_subject_request.resolution is null or length(trim(fulfil_data_subject_request.resolution)) = 0 then
      raise exception 'resolution is required' using errcode = '22023', hint = 'DSAR_INVALID';
    end if;
    if v_row."kind" = 'erasure' and "better_supabase"."is_held"('data_subject_request', v_row."organization_id"::text) then
      raise exception 'a legal hold stops the erasure; refuse the request with its reason' using errcode = '55000', hint = 'DSAR_HELD';
    end if;
  end if;
  update "better_supabase"."data_subject_requests" x set "status" = 'fulfilled', "closed_at" = now(), "closed_by" = auth.uid(), "export_id" = v_export_id, "resolution" = nullif(trim(fulfil_data_subject_request.resolution), '')
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.fulfilled', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.fulfilled',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_incident_regulatory_profile (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('incidentId', x."incident_id", 'organizationId', x."tenant_id", 'regimes', to_jsonb(x."regimes"), 'awareAt', x."aware_at", 'classification', x."classification", 'classifiedAt', x."classified_at", 'significant', x."significant", 'activelyExploited', x."actively_exploited", 'measureAvailableAt', x."measure_available_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('filings', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'incidentId', y."incident_id", 'regime', y."regime", 'stage', y."stage", 'dueAt', y."due_at", 'submittedAt', y."submitted_at", 'submittedBy', y."submitted_by", 'reference', y."reference", 'notes', y."notes", 'createdAt', y."created_at") order by y."due_at" nulls last, y."regime", y."stage") from "better_supabase"."incident_regulatory_filings" y where y."incident_id" = x."incident_id"), '[]'::jsonb))
  from "better_supabase"."incident_regulatory_profiles" x
  where x."incident_id" = get_incident_regulatory_profile.incident_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_oscal_catalog (
  tenant   uuid,
  document jsonb,
  key      text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := import_oscal_catalog.tenant;
  v_catalog jsonb;
  v_key text;
  v_title text;
  v_version text;
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_ctl jsonb;
  v_code text;
  v_ctl_title text;
  v_prose text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if import_oscal_catalog.document is null or jsonb_typeof(import_oscal_catalog.document -> 'catalog') is distinct from 'object' then
    raise exception 'the document needs a catalog object' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  v_catalog := import_oscal_catalog.document -> 'catalog';
  v_title := nullif(trim(v_catalog #>> '{metadata,title}'), '');
  if v_title is null then
    raise exception 'the catalog needs a metadata title' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  v_version := nullif(trim(v_catalog #>> '{metadata,version}'), '');
  v_key := coalesce(nullif(trim(import_oscal_catalog.key), ''), 'oscal-' || lower(left(replace(coalesce(v_catalog ->> 'uuid', ''), '-', ''), 12)));
  if v_key !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'key must be lowercase letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version")
  values (v_tenant, v_key, v_title, 'standard', v_version)
  on conflict ("tenant_id", "key") do update set "name" = excluded."name", "version" = excluded."version", "updated_at" = now()
  returning * into v_framework;
  for v_ctl in
    select c from jsonb_path_query(v_catalog, 'strict $.**.controls[*]') c
  loop
    v_code := left(trim(v_ctl ->> 'id'), 50);
    v_ctl_title := left(trim(v_ctl ->> 'title'), 200);
    if v_code is null or v_code = '' or v_ctl_title is null or v_ctl_title = '' then
      raise exception 'every control needs an id and a title' using errcode = '22023', hint = 'OSCAL_INVALID';
    end if;
    v_prose := left(nullif(trim(jsonb_path_query_first(v_ctl, 'lax $.parts[*] ? (@.name == "statement").prose') #>> '{}'), ''), 10000);
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "source")
    values (v_tenant, v_framework."id", v_code, v_ctl_title, v_prose, 'oscal')
    on conflict ("framework_id", "code") do update set "title" = excluded."title", "description" = excluded."description", "updated_at" = now();
    v_count := v_count + 1;
  end loop;
  perform "better_supabase".emit_event('control_framework.imported', jsonb_build_object('organizationId', v_framework."tenant_id"::text, 'frameworkId', v_framework."id", 'format', 'oscal-catalog', 'controls', v_count), 'controls/' || v_framework."id"::text, (v_framework."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control_framework.imported',
    category => 'data',
    target_type => 'control_framework',
    record_id => v_framework."id"::text,
    tenant => (v_framework."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_framework."tenant_id"::text, 'frameworkId', v_framework."id", 'format', 'oscal-catalog', 'controls', v_count)
  );
  return jsonb_build_object('frameworkId', v_framework."id", 'key', v_framework."key", 'controls', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_consent_receipt (
  consent_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_receipt "better_supabase"."consent_receipts";
  v_id uuid := gen_random_uuid();
  v_issued timestamptz := now();
  v_doc jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consents" x where x."id" = issue_consent_receipt.consent_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.read'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  select * into v_receipt from "better_supabase"."consent_receipts" x where x."consent_id" = v_row."id" and x."status" = v_row."status";
  if found then
    return (v_receipt."receipt" || jsonb_build_object('digest', v_receipt."digest"));
  end if;
  select * into v_purpose from "better_supabase"."consent_purposes" x where x."id" = v_row."purpose_id";
  v_doc := jsonb_build_object(
    'format', 'better-supabase/consent-receipt@1',
    'receiptId', v_id,
    'issuedAt', v_issued,
    'organizationId', v_row."tenant_id",
    'subject', jsonb_build_object('type', v_row."subject_type", 'id', v_row."subject_id"),
    'purpose', jsonb_build_object('key', v_purpose."key", 'title', v_purpose."title", 'version', v_purpose."version", 'legalBasis', v_purpose."legal_basis"),
    'consent', jsonb_build_object('id', v_row."id", 'status', v_row."status", 'givenBy', v_row."given_by", 'grantedAt', v_row."granted_at", 'validUntil', v_row."valid_until", 'withdrawnAt', v_row."withdrawn_at", 'scope', coalesce(v_row."scope", '{}'::jsonb)),
    'evidence', jsonb_build_object(
      'signatureId', v_row."signature_id",
      'submissionId', v_row."submission_id",
      'attachmentId', v_row."attachment_id",
      'signals', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'kind', y."kind", 'receivedAt', y."received_at") order by y."received_at", y."id"), '[]'::jsonb) from "better_supabase"."consent_signals" y where v_row."id" = any(y."consent_ids"))
    )
  );
  insert into "better_supabase"."consent_receipts" ("id", "tenant_id", "subject_type", "subject_id", "consent_id", "status", "receipt", "digest", "issued_at")
  values (v_id, v_row."tenant_id", v_row."subject_type", v_row."subject_id", v_row."id", v_row."status", v_doc, encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex'), v_issued)
  returning * into v_receipt;
  perform "better_supabase".emit_event('consent_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'receiptId', v_receipt."id", 'consentId', v_receipt."consent_id", 'status', v_receipt."status", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'consent-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/consents');
  return (v_receipt."receipt" || jsonb_build_object('digest', v_receipt."digest"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_statement (
  item_id             uuid,
  restriction         text,
  facts               text,
  legal_ground        text    DEFAULT NULL::text,
  terms_ground        text    DEFAULT NULL::text,
  automated_detection boolean DEFAULT false,
  automated_decision  boolean DEFAULT false,
  redress             text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item "better_supabase"."moderation_items";
  v_row "better_supabase"."moderation_statements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_item from "better_supabase"."moderation_items" x where x."id" = issue_statement.item_id;
  if v_item."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_item."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to issue statements of reasons' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if issue_statement.restriction is null or issue_statement.restriction not in ('removal', 'disabled_access', 'demotion', 'visibility_suspension', 'monetary_suspension', 'service_suspension', 'service_termination', 'account_suspension', 'account_termination') then
    raise exception 'restriction must be one of the Article 17 restrictions' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if issue_statement.facts is null or length(trim(issue_statement.facts)) = 0 or length(issue_statement.facts) > 5000 then
    raise exception 'a statement needs facts and circumstances of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if nullif(trim(issue_statement.legal_ground), '') is null and nullif(trim(issue_statement.terms_ground), '') is null then
    raise exception 'a statement needs a legal ground or a terms ground' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_statements" ("tenant_id", "item_id", "restriction", "facts", "legal_ground", "terms_ground", "automated_detection", "automated_decision", "redress", "issued_by")
  values (v_item."tenant_id", v_item."id", issue_statement.restriction, trim(issue_statement.facts), nullif(trim(issue_statement.legal_ground), ''), nullif(trim(issue_statement.terms_ground), ''),
    coalesce(issue_statement.automated_detection, false), coalesce(issue_statement.automated_decision, false),
    coalesce(issue_statement.redress, array['internal_complaint', 'out_of_court', 'judicial']), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('moderation_statement.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'itemId', v_row."item_id", 'restriction', v_row."restriction", 'authorId', v_item."author_id"), 'moderation-statements/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_statement.issued',
    category => 'data',
    target_type => 'moderation_statement',
    record_id => v_row."id"::text,
    summary => 'statement of reasons: ' || v_row."restriction",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'itemId', v_row."item_id", 'restriction', v_row."restriction", 'authorId', v_item."author_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'restriction', v_row."restriction", 'facts', v_row."facts", 'legalGround', v_row."legal_ground", 'termsGround', v_row."terms_ground", 'automatedDetection', v_row."automated_detection", 'automatedDecision', v_row."automated_decision", 'redress', to_jsonb(v_row."redress"), 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_consent_receipts (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case list_consent_receipts.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (list_consent_receipts.subject_id)::uuid)
      else null::text
    end))::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(list_consent_receipts.subject_type, list_consent_receipts.subject_id, 'read'), false))
      or ((v_tenant)::text, (list_consent_receipts.subject_type)::text, (list_consent_receipts.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (list_consent_receipts.subject_type)::text, (list_consent_receipts.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = list_consent_receipts.subject_type and r."target_id" = (list_consent_receipts.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to read the consent receipts of this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((x."receipt" || jsonb_build_object('digest', x."digest")) order by x."issued_at" desc, x."id"), '[]'::jsonb)
    from "better_supabase"."consent_receipts" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_consent_receipts.subject_type and x."subject_id" = list_consent_receipts.subject_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_consent_signals (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case list_consent_signals.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (list_consent_signals.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (list_consent_signals.subject_id)::uuid)
      else null::text
    end))::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(list_consent_signals.subject_type, list_consent_signals.subject_id, 'read'), false))
      or ((v_tenant)::text, (list_consent_signals.subject_type)::text, (list_consent_signals.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (list_consent_signals.subject_type)::text, (list_consent_signals.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = list_consent_signals.subject_type and r."target_id" = (list_consent_signals.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to read the consent signals of this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'kind', x."kind", 'raw', x."raw", 'parsed', x."parsed", 'consentIds', to_jsonb(x."consent_ids"), 'receivedAt', x."received_at") order by x."received_at" desc, x."id"), '[]'::jsonb)
    from "better_supabase"."consent_signals" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_consent_signals.subject_type and x."subject_id" = list_consent_signals.subject_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_data_subject_requests (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  open_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_data_subject_requests.tenant, 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) order by x."due_at", x."id")
    from "better_supabase"."data_subject_requests" x
    where x."organization_id" = list_data_subject_requests.tenant
      and (list_data_subject_requests.status is null or x."status" = list_data_subject_requests.status)
      and (not list_data_subject_requests.open_only or x."closed_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_incident_filings (
  tenant  uuid,
  pending boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_incident_filings.tenant, 'incidents.read'), false)) then
    raise exception 'not allowed to read incident filings' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'incidentId', x."incident_id", 'regime', x."regime", 'stage', x."stage", 'dueAt', x."due_at", 'submittedAt', x."submitted_at", 'submittedBy', x."submitted_by", 'reference', x."reference", 'notes', x."notes", 'createdAt', x."created_at") order by x."due_at" nulls last, x."id")
    from "better_supabase"."incident_regulatory_filings" x
    where x."tenant_id" = list_incident_filings.tenant
      and (coalesce(list_incident_filings.pending, true) is false or x."submitted_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notices (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_notices.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read notices' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.notice order by q.trusted desc, q.created asc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'itemId', x."item_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'explanation', x."explanation", 'url', x."url", 'notifierName', x."notifier_name", 'notifierEmail', x."notifier_email", 'notifierId', x."notifier_id", 'trusted', x."trusted", 'status', x."status", 'outcome', x."outcome", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as notice, x."trusted" as trusted, x."created_at" as created
    from "better_supabase"."moderation_notices" x
    where x."tenant_id" = list_notices.tenant
      and x."status" = coalesce(list_notices.status, 'received')
    order by x."trusted" desc, x."created_at" asc
    limit least(greatest(coalesce(list_notices.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_statements (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item "better_supabase"."moderation_items";
begin
  select * into v_item from "better_supabase"."moderation_items" x where x."id" = list_statements.item_id;
  if v_item."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  if not ((auth.uid() is not null and v_item."author_id" is not distinct from auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_item."tenant_id", 'moderation.read'), false))) then
    raise exception 'not allowed to read statements of reasons' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'itemId', y."item_id", 'restriction', y."restriction", 'facts', y."facts", 'legalGround', y."legal_ground", 'termsGround', y."terms_ground", 'automatedDetection', y."automated_detection", 'automatedDecision', y."automated_decision", 'redress', to_jsonb(y."redress"), 'issuedBy', y."issued_by", 'createdAt', y."created_at") order by y."created_at" desc) from "better_supabase"."moderation_statements" y where y."item_id" = v_item."id"), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_data_subject_request (
  tenant       uuid,
  kind         text,
  requester    text,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  details      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_data_subject_request.tenant, 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if open_data_subject_request.kind is null or open_data_subject_request.kind not in ('access', 'erasure', 'rectification', 'portability') then
    raise exception 'kind must be access, erasure, rectification or portability' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if open_data_subject_request.requester is null or length(trim(open_data_subject_request.requester)) = 0 then
    raise exception 'requester is required' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if (open_data_subject_request.subject_type is null) <> (open_data_subject_request.subject_id is null) then
    raise exception 'subject_type and subject_id go together' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  insert into "better_supabase"."data_subject_requests" ("organization_id", "kind", "requester", "subject_type", "subject_id", "details", "received_by", "due_at")
  values (open_data_subject_request.tenant, open_data_subject_request.kind, trim(open_data_subject_request.requester), open_data_subject_request.subject_type, open_data_subject_request.subject_id, open_data_subject_request.details, auth.uid(), now() + interval '30 days')
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.received', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.received',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.parse_gpp_string (
  gpp_string text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_header text := split_part(coalesce(gpp_string, ''), '~', 1);
  v_bits text := '';
  i integer;
  v_sections jsonb;
begin
  if v_header !~ '^[A-Za-z0-9_-]{4,}$' then
    raise exception 'a GPP string starts with a base64url header' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  for i in 1 .. length(v_header) loop
    v_bits := v_bits || (strpos('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_', substr(v_header, i, 1)) - 1)::bit(6)::text;
  end loop;
  if length(v_bits) < 12 or substring(v_bits from 1 for 6)::bit(6)::int <> 3 then
    raise exception 'the GPP header has type 3' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  select coalesce(jsonb_agg(s order by n), '[]'::jsonb) into v_sections
  from unnest(string_to_array(gpp_string, '~')) with ordinality as t(s, n)
  where n > 1;
  return jsonb_build_object(
    'type', substring(v_bits from 1 for 6)::bit(6)::int,
    'version', substring(v_bits from 7 for 6)::bit(6)::int,
    'sections', v_sections
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.parse_tc_string (
  tc_string text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_core text := split_part(coalesce(tc_string, ''), '.', 1);
  v_bits text := '';
  i integer;
begin
  if v_core !~ '^[A-Za-z0-9_-]{36,}$' then
    raise exception 'a TC string is base64url text of at least 36 characters' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  for i in 1 .. length(v_core) loop
    v_bits := v_bits || (strpos('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_', substr(v_core, i, 1)) - 1)::bit(6)::text;
  end loop;
  if length(v_bits) < 213 then
    raise exception 'the TC string is shorter than a core segment' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  if substring(v_bits from 1 for 6)::bit(6)::bigint <> 2 then
    raise exception 'only TCF v2 TC strings are supported' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  return jsonb_build_object(
    'version', substring(v_bits from 1 for 6)::bit(6)::bigint,
    'created', to_jsonb(to_timestamp(substring(v_bits from 7 for 36)::bit(36)::bigint / 10.0)),
    'lastUpdated', to_jsonb(to_timestamp(substring(v_bits from 43 for 36)::bit(36)::bigint / 10.0)),
    'cmpId', substring(v_bits from 79 for 12)::bit(12)::bigint,
    'cmpVersion', substring(v_bits from 91 for 12)::bit(12)::bigint,
    'consentScreen', substring(v_bits from 103 for 6)::bit(6)::bigint,
    'consentLanguage', chr(65 + (substring(v_bits from 109 for 6)::bit(6)::int)) || chr(65 + (substring(v_bits from 115 for 6)::bit(6)::int)),
    'vendorListVersion', substring(v_bits from 121 for 12)::bit(12)::bigint,
    'tcfPolicyVersion', substring(v_bits from 133 for 6)::bit(6)::bigint,
    'tcfV22', substring(v_bits from 133 for 6)::bit(6)::bigint >= 4,
    'isServiceSpecific', substring(v_bits from 139 for 1) = '1',
    'useNonStandardTexts', substring(v_bits from 140 for 1) = '1',
    'specialFeatureOptIns', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, 12) k where substring(v_bits from 140 + k for 1) = '1'),
    'purposesConsent', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, 24) k where substring(v_bits from 152 + k for 1) = '1'),
    'purposesLiTransparency', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, 24) k where substring(v_bits from 176 + k for 1) = '1'),
    'purposeOneTreatment', substring(v_bits from 201 for 1) = '1',
    'publisherCc', chr(65 + (substring(v_bits from 202 for 6)::bit(6)::int)) || chr(65 + (substring(v_bits from 208 for 6)::bit(6)::int))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.plan_incident_filings (
  incident_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_inc "better_supabase"."incidents";
  v_p "better_supabase"."incident_regulatory_profiles";
  v_filing "better_supabase"."incident_regulatory_filings";
  v_plan jsonb := '[]'::jsonb;
  v_keys text[];
  v_due timestamptz;
  v_initial_due timestamptz;
  v_initial_sub timestamptz;
  v_inter_due timestamptz;
  v_inter_sub timestamptz;
  v_notice_sub timestamptz;
  v_el jsonb;
  v_user uuid;
  v_at timestamptz;
  v_reminder uuid;
begin
  select * into v_inc from "better_supabase"."incidents" x where x."id" = plan_incident_filings.incident_id;
  select * into v_p from "better_supabase"."incident_regulatory_profiles" x where x."incident_id" = plan_incident_filings.incident_id;
  if v_p."incident_id" is null then
    return;
  end if;
  v_user := coalesce(v_inc."commander_id", v_inc."created_by", auth.uid());
  if 'nis2' = any(v_p."regimes") then
    select x."submitted_at" into v_notice_sub from "better_supabase"."incident_regulatory_filings" x
    where x."incident_id" = v_inc."id" and x."regime" = 'nis2' and x."stage" = 'notification';
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'early_warning', 'due', v_p."aware_at" + interval '24 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'notification', 'due', v_p."aware_at" + interval '72 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'nis2', 'stage', 'final', 'due', coalesce(v_notice_sub, v_p."aware_at" + interval '72 hours') + interval '1 month'));
  end if;
  if 'dora' = any(v_p."regimes") then
    v_initial_due := v_p."aware_at" + interval '24 hours';
    if v_p."classification" = 'major' and v_p."classified_at" is not null then
      v_initial_due := least(v_initial_due, v_p."classified_at" + interval '4 hours');
    end if;
    select x."submitted_at" into v_initial_sub from "better_supabase"."incident_regulatory_filings" x
    where x."incident_id" = v_inc."id" and x."regime" = 'dora' and x."stage" = 'initial';
    v_inter_due := coalesce(v_initial_sub, v_initial_due) + interval '72 hours';
    select x."submitted_at" into v_inter_sub from "better_supabase"."incident_regulatory_filings" x
    where x."incident_id" = v_inc."id" and x."regime" = 'dora' and x."stage" = 'intermediate';
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'initial', 'due', v_initial_due))
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'intermediate', 'due', v_inter_due))
      || jsonb_build_array(jsonb_build_object('regime', 'dora', 'stage', 'final', 'due', coalesce(v_inter_sub, v_inter_due) + interval '1 month'));
  end if;
  if 'cra' = any(v_p."regimes") then
    v_plan := v_plan
      || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'early_warning', 'due', v_p."aware_at" + interval '24 hours'))
      || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'notification', 'due', v_p."aware_at" + interval '72 hours'));
    if v_p."measure_available_at" is not null then
      v_plan := v_plan || jsonb_build_array(jsonb_build_object('regime', 'cra', 'stage', 'final', 'due', v_p."measure_available_at" + interval '14 days'));
    end if;
  end if;
  select coalesce(array_agg(e ->> 'regime' || ':' || (e ->> 'stage')), '{}') into v_keys from jsonb_array_elements(v_plan) e;
  delete from "better_supabase"."reminders" r
  where r."id" in (
    select x."reminder_id" from "better_supabase"."incident_regulatory_filings" x
    where x."incident_id" = plan_incident_filings.incident_id and x."submitted_at" is null and x."reminder_id" is not null
      and not (x."regime" || ':' || x."stage" = any(v_keys))
  );
  delete from "better_supabase"."incident_regulatory_filings" x
  where x."incident_id" = v_inc."id" and x."submitted_at" is null
    and not (x."regime" || ':' || x."stage" = any(v_keys));
  for v_el in select e from jsonb_array_elements(v_plan) e loop
    v_due := (v_el ->> 'due')::timestamptz;
    insert into "better_supabase"."incident_regulatory_filings" as fl ("tenant_id", "incident_id", "regime", "stage", "due_at")
    values (v_inc."tenant_id", v_inc."id", v_el ->> 'regime', v_el ->> 'stage', v_due)
    on conflict ("incident_id", "regime", "stage") do update set "due_at" = excluded."due_at"
    where fl."submitted_at" is null;
  end loop;
  for v_filing in
    select * from "better_supabase"."incident_regulatory_filings" x where x."incident_id" = plan_incident_filings.incident_id and x."submitted_at" is null
  loop
    v_at := case
      when v_filing."due_at" is null then null
      when v_filing."due_at" - interval '2 hours' > now() then v_filing."due_at" - interval '2 hours'
      when v_filing."due_at" > now() then v_filing."due_at"
    end;
    if v_at is null then
      if v_filing."reminder_id" is not null then
        delete from "better_supabase"."reminders" r where r."id" = v_filing."reminder_id";
        update "better_supabase"."incident_regulatory_filings" x set "reminder_id" = null where x."id" = v_filing."id";
      end if;
    elsif v_filing."reminder_id" is not null then
      update "better_supabase"."reminders" r set "remind_at" = v_at where r."id" = v_filing."reminder_id";
    elsif v_user is not null then
      insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
      values (v_inc."tenant_id", 'incident', v_inc."id"::text, v_user, 0, v_at)
      returning "id" into v_reminder;
      update "better_supabase"."incident_regulatory_filings" x set "reminder_id" = v_reminder where x."id" = v_filing."id";
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_consent_signal (
  subject_type text,
  subject_id   text,
  kind         text,
  value        text,
  purpose_keys text[] DEFAULT '{}'::text[],
  consent_id   uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case record_consent_signal.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_consent_signal.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_consent_signal.subject_id)::uuid)
      else null::text
    end))::uuid;
  v_value text := trim(coalesce(record_consent_signal.value, ''));
  v_keys text[] := coalesce(record_consent_signal.purpose_keys, '{}');
  v_parsed jsonb;
  v_key text;
  v_ids uuid[] := '{}';
  v_decision jsonb;
  v_row "better_supabase"."consent_signals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent_signal.subject_type, record_consent_signal.subject_id, 'read'), false))
      or ((v_tenant)::text, (record_consent_signal.subject_type)::text, (record_consent_signal.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent_signal.subject_type and r."target_id" = (record_consent_signal.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to record a consent signal for this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if record_consent_signal.kind is null or record_consent_signal.kind not in ('gpc', 'tcf', 'gpp') then
    raise exception 'kind is gpc, tcf or gpp' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  if length(v_value) not between 1 and 8192 then
    raise exception 'value is 1 to 8192 characters' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
  end if;
  if record_consent_signal.kind = 'gpc' then
    if v_value <> '1' then
      raise exception 'the Sec-GPC header is 1 when the person opts out' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
    end if;
    if cardinality(v_keys) = 0 then
      raise exception 'purpose_keys names the purposes the signal opts out of' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
    end if;
    if record_consent_signal.consent_id is not null then
      raise exception 'a Sec-GPC signal creates its own consents' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
    end if;
    v_parsed := jsonb_build_object('header', 'Sec-GPC', 'optOut', true, 'purposeKeys', to_jsonb(v_keys));
    foreach v_key in array v_keys loop
      v_decision := "better_supabase"."record_consent"(record_consent_signal.subject_type, record_consent_signal.subject_id, v_key, 'refused');
      v_ids := v_ids || (v_decision ->> 'id')::uuid;
    end loop;
  else
    if cardinality(v_keys) > 0 then
      raise exception 'purpose_keys applies to a Sec-GPC signal only' using errcode = '22023', hint = 'CONSENT_SIGNAL_INVALID';
    end if;
    v_parsed := case record_consent_signal.kind
      when 'tcf' then "better_supabase"."parse_tc_string"(v_value)
      else "better_supabase"."parse_gpp_string"(v_value)
    end;
    if record_consent_signal.consent_id is not null then
      if not exists (
        select 1 from "better_supabase"."consents" x
        where x."id" = record_consent_signal.consent_id and x."tenant_id" = v_tenant
          and x."subject_type" = record_consent_signal.subject_type and x."subject_id" = record_consent_signal.subject_id
      ) then
        raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
      end if;
      v_ids := array[record_consent_signal.consent_id];
    end if;
  end if;
  insert into "better_supabase"."consent_signals" ("tenant_id", "subject_type", "subject_id", "kind", "raw", "parsed", "consent_ids", "created_by")
  values (v_tenant, record_consent_signal.subject_type, record_consent_signal.subject_id, record_consent_signal.kind, v_value, v_parsed, v_ids, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('consent_signal.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'signalId', v_row."id", 'kind', v_row."kind", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'consent-signals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'raw', v_row."raw", 'parsed', v_row."parsed", 'consentIds', to_jsonb(v_row."consent_ids"), 'receivedAt', v_row."received_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refuse_data_subject_request (
  id     uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = refuse_data_subject_request.id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if refuse_data_subject_request.reason is null or length(trim(refuse_data_subject_request.reason)) = 0 then
    raise exception 'reason is required' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  update "better_supabase"."data_subject_requests" x set "status" = 'refused', "closed_at" = now(), "closed_by" = auth.uid(), "resolution" = trim(refuse_data_subject_request.reason)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.refused', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.refused',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
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
    when 'activity' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."activities" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.activities';
      v_reveal := 'activities_reveal';
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
    when 'rfq' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."rfqs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.rfqs';
      v_reveal := 'rfqs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'till' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tills" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tills';
      v_reveal := 'tills_reveal';
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
      from "better_supabase"."leases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.leases';
      v_reveal := 'leases_reveal';
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
    when 'compliance_policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."compliance_policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.compliance_policies';
      v_reveal := 'compliance_policies_reveal';
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
    when 'case' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."cases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.cases';
      v_reveal := 'cases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspections" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspections';
      v_reveal := 'inspections_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_program' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_programs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_programs';
      v_reveal := 'inspection_programs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_finding' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_findings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_findings';
      v_reveal := 'inspection_findings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meetings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meetings';
      v_reveal := 'meetings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting_decision' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meeting_decisions" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meeting_decisions';
      v_reveal := 'meeting_decisions_reveal';
      v_reveal_schema := 'better_supabase';
    when 'maintenance_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."maintenance_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.maintenance_plans';
      v_reveal := 'maintenance_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'dam_usage_right' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."dam_usage_rights" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.dam_usage_rights';
      v_reveal := 'dam_usage_rights_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lims_sample' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."lims_samples" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.lims_samples';
      v_reveal := 'lims_samples_reveal';
      v_reveal_schema := 'better_supabase';
    when 'tax_code' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tax_codes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tax_codes';
      v_reveal := 'tax_codes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'production_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."production_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.production_orders';
      v_reveal := 'production_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_center' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_centers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_centers';
      v_reveal := 'work_centers_reveal';
      v_reveal_schema := 'better_supabase';
    when 'bank_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bank_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bank_accounts';
      v_reveal := 'bank_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'care_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."care_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.care_plans';
      v_reveal := 'care_plans_reveal';
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
  from "better_supabase"."import_records" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.import_records', v_rows);
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
  from "better_supabase"."access_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.access_requests', v_rows);
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
  from "better_supabase"."moderation_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."automation_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.automation_evaluations', v_rows);
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
  from "better_supabase"."timeline_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.timeline_entries', v_rows);
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
  from "better_supabase"."consent_signals" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consent_signals', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consent_receipts" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consent_receipts', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."observations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.observations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."medication_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.medication_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_plans" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_plans', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."funding_awards" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.funding_awards', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_alerts" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_alerts', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."prescriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.prescriptions', v_rows);
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

CREATE OR REPLACE FUNCTION better_supabase.save_incident_regulatory_profile (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_inc "better_supabase"."incidents";
  v_old "better_supabase"."incident_regulatory_profiles";
  v_row "better_supabase"."incident_regulatory_profiles";
  v_regimes text[];
  v_aware timestamptz;
  v_class text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inc from "better_supabase"."incidents" x where x."id" = save_incident_regulatory_profile.incident_id;
  if v_inc."id" is null then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inc."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to change the regulatory profile' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if save_incident_regulatory_profile.attrs is null or jsonb_typeof(save_incident_regulatory_profile.attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  select * into v_old from "better_supabase"."incident_regulatory_profiles" x where x."incident_id" = v_inc."id";
  if save_incident_regulatory_profile.attrs ? 'regimes' then
    select coalesce(array_agg(distinct e), '{}') into v_regimes
    from jsonb_array_elements_text(save_incident_regulatory_profile.attrs -> 'regimes') e;
  else
    v_regimes := v_old."regimes";
  end if;
  if v_regimes is null or not (v_regimes <@ array['nis2', 'dora', 'cra']) then
    raise exception 'regimes must list nis2, dora or cra' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  v_aware := coalesce((save_incident_regulatory_profile.attrs ->> 'awareAt')::timestamptz, v_old."aware_at");
  if v_aware is null then
    raise exception 'awareAt is required: when the organization became aware of the incident' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  v_class := case when save_incident_regulatory_profile.attrs ? 'classification' then save_incident_regulatory_profile.attrs ->> 'classification' else v_old."classification" end;
  if v_class is not null and v_class not in ('major', 'non_major') then
    raise exception 'classification must be major or non_major' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incident_regulatory_profiles" ("incident_id", "tenant_id", "regimes", "aware_at", "classification", "classified_at", "significant", "actively_exploited", "measure_available_at")
  values (v_inc."id", v_inc."tenant_id", v_regimes, v_aware, v_class,
    case when save_incident_regulatory_profile.attrs ? 'classifiedAt' then (save_incident_regulatory_profile.attrs ->> 'classifiedAt')::timestamptz else v_old."classified_at" end,
    coalesce((save_incident_regulatory_profile.attrs ->> 'significant')::boolean, v_old."significant", false),
    coalesce((save_incident_regulatory_profile.attrs ->> 'activelyExploited')::boolean, v_old."actively_exploited", false),
    case when save_incident_regulatory_profile.attrs ? 'measureAvailableAt' then (save_incident_regulatory_profile.attrs ->> 'measureAvailableAt')::timestamptz else v_old."measure_available_at" end)
  on conflict ("incident_id") do update set
    "regimes" = excluded."regimes", "aware_at" = excluded."aware_at", "classification" = excluded."classification",
    "classified_at" = excluded."classified_at", "significant" = excluded."significant",
    "actively_exploited" = excluded."actively_exploited", "measure_available_at" = excluded."measure_available_at",
    "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."plan_incident_filings"(v_inc."id");
  perform "better_supabase".emit_event('incident_profile.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."incident_id", 'regimes', to_jsonb(v_row."regimes")), 'incidents/' || v_row."incident_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident_profile.updated',
    category => 'configuration',
    target_type => 'incident',
    record_id => v_row."incident_id"::text,
    summary => 'regulatory profile saved',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."incident_id", 'regimes', to_jsonb(v_row."regimes"))
  );
  return jsonb_build_object('incidentId', v_row."incident_id", 'organizationId', v_row."tenant_id", 'regimes', to_jsonb(v_row."regimes"), 'awareAt', v_row."aware_at", 'classification', v_row."classification", 'classifiedAt', v_row."classified_at", 'significant', v_row."significant", 'activelyExploited', v_row."actively_exploited", 'measureAvailableAt', v_row."measure_available_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('filings', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'incidentId', y."incident_id", 'regime', y."regime", 'stage', y."stage", 'dueAt', y."due_at", 'submittedAt', y."submitted_at", 'submittedBy', y."submitted_by", 'reference', y."reference", 'notes', y."notes", 'createdAt', y."created_at") order by y."due_at" nulls last, y."regime", y."stage") from "better_supabase"."incident_regulatory_filings" y where y."incident_id" = v_row."incident_id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_trusted_flagger (
  tenant     uuid,
  user_id    uuid,
  name       text    DEFAULT NULL::text,
  awarded_by text    DEFAULT NULL::text,
  active     boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_flaggers";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_trusted_flagger.tenant, 'moderation.manage'), false)) then
    raise exception 'not allowed to manage trusted flaggers' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if set_trusted_flagger.active is false then
    update "better_supabase"."moderation_flaggers" x set "revoked_at" = now()
    where x."tenant_id" = set_trusted_flagger.tenant and x."user_id" = set_trusted_flagger.user_id and x."revoked_at" is null
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'no active trusted flagger for this user' using errcode = 'P0002', hint = 'MODERATION_FLAGGER_NOT_FOUND';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'name', v_row."name", 'awardedBy', v_row."awarded_by", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at");
  end if;
  if set_trusted_flagger.name is null or length(trim(set_trusted_flagger.name)) not between 1 and 200 then
    raise exception 'a trusted flagger needs a name of at most 200 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  select * into v_row from "better_supabase"."moderation_flaggers" x
  where x."tenant_id" = set_trusted_flagger.tenant and x."user_id" = set_trusted_flagger.user_id and x."revoked_at" is null;
  if v_row."id" is null then
    insert into "better_supabase"."moderation_flaggers" ("tenant_id", "user_id", "name", "awarded_by")
    values (set_trusted_flagger.tenant, set_trusted_flagger.user_id, trim(set_trusted_flagger.name), nullif(trim(set_trusted_flagger.awarded_by), ''))
    returning * into v_row;
  else
    update "better_supabase"."moderation_flaggers" x
    set "name" = trim(set_trusted_flagger.name), "awarded_by" = nullif(trim(set_trusted_flagger.awarded_by), '')
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'name', v_row."name", 'awardedBy', v_row."awarded_by", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_incident_filing (
  incident_id  uuid,
  regime       text,
  stage        text,
  reference    text                     DEFAULT NULL::text,
  notes        text                     DEFAULT NULL::text,
  submitted_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."incident_regulatory_filings";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incident_regulatory_filings" x
  where x."incident_id" = submit_incident_filing.incident_id and x."regime" = submit_incident_filing.regime and x."stage" = submit_incident_filing.stage
  for update;
  if v_row."id" is null then
    raise exception 'no such filing is planned for this incident' using errcode = 'P0002', hint = 'INCIDENT_FILING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to record a filing' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if v_row."submitted_at" is not null then
    raise exception 'this filing was submitted already' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if length(submit_incident_filing.reference) > 200 or length(submit_incident_filing.notes) > 5000 then
    raise exception 'the reference holds at most 200 characters and the notes 5000' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  update "better_supabase"."incident_regulatory_filings" x
  set "submitted_at" = coalesce(submit_incident_filing.submitted_at, now()), "submitted_by" = auth.uid(),
    "reference" = nullif(trim(submit_incident_filing.reference), ''), "notes" = nullif(trim(submit_incident_filing.notes), '')
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."reminder_id" is not null then
    delete from "better_supabase"."reminders" r where r."id" = v_row."reminder_id";
    update "better_supabase"."incident_regulatory_filings" x set "reminder_id" = null where x."id" = v_row."id";
  end if;
  perform "better_supabase"."plan_incident_filings"(v_row."incident_id");
  select * into v_row from "better_supabase"."incident_regulatory_filings" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('incident_filing.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."incident_id", 'id', v_row."id", 'regime', v_row."regime", 'stage', v_row."stage", 'dueAt', v_row."due_at", 'reference', v_row."reference"), 'incidents/' || v_row."incident_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident_filing.submitted',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."incident_id"::text,
    summary => v_row."regime" || ' ' || v_row."stage" || ' submitted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."incident_id", 'id', v_row."id", 'regime', v_row."regime", 'stage', v_row."stage", 'dueAt', v_row."due_at", 'reference', v_row."reference")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'incidentId', v_row."incident_id", 'regime', v_row."regime", 'stage', v_row."stage", 'dueAt', v_row."due_at", 'submittedAt', v_row."submitted_at", 'submittedBy', v_row."submitted_by", 'reference', v_row."reference", 'notes', v_row."notes", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_notice (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  explanation    text,
  url            text DEFAULT NULL::text,
  notifier_name  text DEFAULT NULL::text,
  notifier_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_item uuid;
  v_trusted boolean;
  v_row "better_supabase"."moderation_notices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to submit a notice' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can('tenant', submit_notice.tenant, 'moderation.report'), false) then
    raise exception 'not allowed to submit a notice' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if submit_notice.subject_type is null or submit_notice.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or submit_notice.subject_id is null or length(submit_notice.subject_id) not between 1 and 200 then
    raise exception 'a notice needs a subject type and id' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if submit_notice.explanation is null or length(trim(submit_notice.explanation)) = 0 or length(submit_notice.explanation) > 5000 then
    raise exception 'a notice needs an explanation of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id")
  values (submit_notice.tenant, submit_notice.subject_type, submit_notice.subject_id)
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = submit_notice.tenant and x."subject_type" = submit_notice.subject_type and x."subject_id" = submit_notice.subject_id;
  select exists (
    select 1 from "better_supabase"."moderation_flaggers" x
    where x."tenant_id" = submit_notice.tenant and x."user_id" = v_me and x."revoked_at" is null
  ) into v_trusted;
  insert into "better_supabase"."moderation_notices" ("tenant_id", "item_id", "subject_type", "subject_id", "explanation", "url", "notifier_name", "notifier_email", "notifier_id", "trusted")
  values (submit_notice.tenant, v_item, submit_notice.subject_type, submit_notice.subject_id, trim(submit_notice.explanation), nullif(trim(submit_notice.url), ''), nullif(trim(submit_notice.notifier_name), ''), nullif(trim(submit_notice.notifier_email), ''), v_me, v_trusted)
  returning * into v_row;
  perform "better_supabase".emit_event('moderation_notice.received', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'itemId', v_row."item_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'trusted', v_row."trusted"), 'moderation-notices/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'explanation', v_row."explanation", 'url', v_row."url", 'notifierName', v_row."notifier_name", 'notifierEmail', v_row."notifier_email", 'notifierId', v_row."notifier_id", 'trusted', v_row."trusted", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transparency_report (
  tenant       uuid,
  period_start timestamp with time zone,
  period_end   timestamp with time zone
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_csv text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', transparency_report.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read the transparency report' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if transparency_report.period_start is null or transparency_report.period_end is null or transparency_report.period_end <= transparency_report.period_start then
    raise exception 'the period needs a start before its end' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  with rows (metric, dimension, value, sort) as (
    select 'notices', 'received', count(*), 10 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'notices', 'trusted_flagger', count(*), 11 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."trusted" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'notices', x."status", count(*), 12 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."status"
    union all
    select 'statements', x."restriction", count(*), 20 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."restriction"
    union all
    select 'statements', 'automated_detection', count(*), 21 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."automated_detection" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'statements', 'automated_decision', count(*), 22 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."automated_decision" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'appeals', 'received', count(*), 30 from "better_supabase"."moderation_appeals" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'appeals', x."status", count(*), 31 from "better_supabase"."moderation_appeals" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."status"
    union all
    select 'decisions', x."action"::text, count(*), 40 from "better_supabase"."moderation_actions" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."action"
    union all
    select 'reports', 'received', count(*), 50 from "better_supabase"."moderation_reports" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
  )
  select 'metric,dimension,value' || coalesce(E'\n' || string_agg(r.metric || ',' || r.dimension || ',' || r.value::text, E'\n' order by r.sort, r.dimension), '')
  into v_csv from rows r;
  return v_csv;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_data_subject_request (
  id     uuid,
  method text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = verify_data_subject_request.id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if verify_data_subject_request.method is null or length(trim(verify_data_subject_request.method)) = 0 then
    raise exception 'method is required' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  update "better_supabase"."data_subject_requests" x set "status" = 'verified', "verified_at" = now(), "verified_by" = auth.uid(), "verification_method" = trim(verify_data_subject_request.method)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.verified', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.verified',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
end;
$function$;

ALTER TABLE "better_supabase"."consent_receipts"
  ADD CONSTRAINT "consent_receipts_consent_id_fkey" FOREIGN KEY (consent_id) REFERENCES better_supabase.consents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_regulatory_filings"
  ADD CONSTRAINT "incident_regulatory_filings_incident_id_fkey" FOREIGN KEY (incident_id) REFERENCES better_supabase.incidents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_regulatory_profiles"
  ADD CONSTRAINT "incident_regulatory_profiles_incident_id_fkey" FOREIGN KEY (incident_id) REFERENCES better_supabase.incidents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."moderation_appeals"
  ADD CONSTRAINT "moderation_appeals_appellant_id_fkey" FOREIGN KEY (appellant_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."moderation_flaggers"
  ADD CONSTRAINT "moderation_flaggers_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."moderation_notices"
  ADD CONSTRAINT "moderation_notices_item_id_fkey" FOREIGN KEY (item_id) REFERENCES better_supabase.moderation_items(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."moderation_notices"
  ADD CONSTRAINT "moderation_notices_notifier_id_fkey" FOREIGN KEY (notifier_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."moderation_appeals"
  ADD CONSTRAINT "moderation_appeals_notice_id_fkey" FOREIGN KEY (notice_id) REFERENCES better_supabase.moderation_notices(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."moderation_statements"
  ADD CONSTRAINT "moderation_statements_item_id_fkey" FOREIGN KEY (item_id) REFERENCES better_supabase.moderation_items(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."moderation_appeals"
  ADD CONSTRAINT "moderation_appeals_statement_id_fkey" FOREIGN KEY (statement_id) REFERENCES better_supabase.moderation_statements(id) ON DELETE CASCADE;

CREATE INDEX consent_receipts_tenant_idx ON better_supabase.consent_receipts USING btree (tenant_id, issued_at DESC);

CREATE INDEX consent_signals_subject_idx ON better_supabase.consent_signals USING btree (tenant_id, subject_type, subject_id, received_at DESC);

CREATE INDEX data_subject_requests_open_idx ON better_supabase.data_subject_requests USING btree (organization_id, due_at)
  WHERE (closed_at IS NULL);

CREATE INDEX incident_regulatory_filings_tenant_idx ON better_supabase.incident_regulatory_filings USING btree (tenant_id, due_at)
  WHERE (submitted_at IS NULL);

CREATE INDEX incident_regulatory_profiles_tenant_idx ON better_supabase.incident_regulatory_profiles USING btree (tenant_id);

CREATE UNIQUE INDEX moderation_appeals_open_notice_idx ON better_supabase.moderation_appeals USING btree (notice_id)
  WHERE ((status = 'open'::text) AND (notice_id IS NOT NULL));

CREATE UNIQUE INDEX moderation_appeals_open_statement_idx ON better_supabase.moderation_appeals USING btree (statement_id)
  WHERE ((status = 'open'::text) AND (statement_id IS NOT NULL));

CREATE INDEX moderation_appeals_tenant_idx ON better_supabase.moderation_appeals USING btree (tenant_id, created_at DESC);

CREATE UNIQUE INDEX moderation_flaggers_active_idx ON better_supabase.moderation_flaggers USING btree (tenant_id, user_id)
  WHERE (revoked_at IS NULL);

CREATE INDEX moderation_notices_notifier_idx ON better_supabase.moderation_notices USING btree (notifier_id);

CREATE INDEX moderation_notices_queue_idx ON better_supabase.moderation_notices USING btree (tenant_id, TRUSTED DESC, created_at)
  WHERE (status = 'received'::text);

CREATE INDEX moderation_statements_item_idx ON better_supabase.moderation_statements USING btree (item_id, created_at DESC);

CREATE INDEX moderation_statements_tenant_idx ON better_supabase.moderation_statements USING btree (tenant_id, created_at DESC);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."consent_receipts"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."consent_receipts"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."consent_receipts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."consent_receipts"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "consent_receipts_read" ON "better_supabase"."consent_receipts"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."consent_signals"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."consent_signals"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."consent_signals"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text)) OR
    (created_by = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."consent_signals"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "consent_signals_read" ON "better_supabase"."consent_signals"
  FOR SELECT
  TO "authenticated"
  USING
    ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text))
    OR (created_by = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."incident_regulatory_filings"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."incident_regulatory_filings"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."incident_regulatory_filings"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."incident_regulatory_filings"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "incident_regulatory_filings_read" ON "better_supabase"."incident_regulatory_filings"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."incident_regulatory_profiles"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."incident_regulatory_profiles"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."incident_regulatory_profiles"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."incident_regulatory_profiles"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "incident_regulatory_profiles_read" ON "better_supabase"."incident_regulatory_profiles"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."moderation_appeals"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."moderation_appeals"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."moderation_appeals"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((appellant_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."moderation_appeals"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "moderation_appeals_read" ON "better_supabase"."moderation_appeals"
  FOR SELECT
  TO "authenticated"
  USING (((appellant_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."moderation_flaggers"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."moderation_flaggers"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."moderation_flaggers"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."moderation_flaggers"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "moderation_flaggers_read" ON "better_supabase"."moderation_flaggers"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."moderation_notices"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."moderation_notices"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."moderation_notices"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((notifier_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."moderation_notices"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "moderation_notices_read" ON "better_supabase"."moderation_notices"
  FOR SELECT
  TO "authenticated"
  USING (((notifier_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."moderation_statements"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."moderation_statements"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."moderation_statements"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."moderation_statements"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "moderation_statements_read" ON "better_supabase"."moderation_statements"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."apply_oscal_profile"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."apply_oscal_profile"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decide_appeal"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_appeal"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decide_notice"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_notice"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."export_oscal_assessment_results"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."export_oscal_assessment_results"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."extend_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."extend_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."file_appeal"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."file_appeal"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."fulfil_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fulfil_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_incident_regulatory_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_incident_regulatory_profile"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_oscal_catalog"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_oscal_catalog"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."issue_consent_receipt"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."issue_consent_receipt"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_consent_receipts"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_consent_receipts"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_consent_signals"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_consent_signals"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_data_subject_requests"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_data_subject_requests"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_incident_filings"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_incident_filings"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_notices"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_notices"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_statements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_statements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_data_subject_request"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_data_subject_request"(uuid, text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_consent_signal"(text, text, text, text, text[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_consent_signal"(text, text, text, text, text[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."refuse_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."refuse_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_incident_regulatory_profile"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_incident_regulatory_profile"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_trusted_flagger"(uuid, uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_trusted_flagger"(uuid, uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."submit_incident_filing"(uuid, text, text, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."submit_incident_filing"(uuid, text, text, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."submit_notice"(uuid, text, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."submit_notice"(uuid, text, text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."transparency_report"(uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."transparency_report"(uuid, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."verify_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."verify_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."apply_oscal_profile"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."apply_oscal_profile"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_appeal"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_appeal"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_notice"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_notice"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."export_oscal_assessment_results"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."export_oscal_assessment_results"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."file_appeal"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."file_appeal"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fulfil_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fulfil_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_incident_regulatory_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_incident_regulatory_profile"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_oscal_catalog"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_oscal_catalog"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."issue_consent_receipt"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."issue_consent_receipt"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_consent_receipts"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_consent_receipts"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_consent_signals"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_consent_signals"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_data_subject_requests"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_data_subject_requests"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_incident_filings"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_incident_filings"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notices"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_notices"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_statements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_statements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_data_subject_request"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_data_subject_request"(uuid, text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."parse_gpp_string"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."parse_tc_string"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."plan_incident_filings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."plan_incident_filings"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_consent_signal"(text, text, text, text, text[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_consent_signal"(text, text, text, text, text[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."refuse_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."refuse_data_subject_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_incident_regulatory_profile"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_incident_regulatory_profile"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_trusted_flagger"(uuid, uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_trusted_flagger"(uuid, uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."submit_incident_filing"(uuid, text, text, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."submit_incident_filing"(uuid, text, text, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."submit_notice"(uuid, text, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."submit_notice"(uuid, text, text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."transparency_report"(uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transparency_report"(uuid, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."verify_data_subject_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."verify_data_subject_request"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."consent_receipts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."consent_receipts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."consent_signals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."consent_signals" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."data_subject_requests" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incident_regulatory_filings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incident_regulatory_filings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incident_regulatory_profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incident_regulatory_profiles" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."moderation_appeals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."moderation_appeals" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."moderation_flaggers" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."moderation_flaggers" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."moderation_notices" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."moderation_notices" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."moderation_statements" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."moderation_statements" TO "service_role";

