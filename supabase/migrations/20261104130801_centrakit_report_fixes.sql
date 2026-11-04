SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.accepting_invitation()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accepting_invitation"() $function$;

CREATE OR REPLACE FUNCTION api.accounting_balance_sheet (
  tenant     uuid,
  as_of      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_balance_sheet"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.accounting_budget_vs_actual (
  budget_id     uuid,
  period_number integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_budget_vs_actual"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.accounting_column_balance (
  tenant     uuid,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  dimensions jsonb   DEFAULT '{}'::jsonb,
  rollup     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_column_balance"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.accounting_fx_rate (
  tenant  uuid,
  base    text,
  quote   text,
  on_date date
)
  RETURNS numeric
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_fx_rate"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_general_ledger (
  account_id uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_general_ledger"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.accounting_journal_listing (
  tenant     uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date,
  journal_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_journal_listing"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_period_close_blockers (
  period_id uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_period_close_blockers"($1) $function$;

CREATE OR REPLACE FUNCTION api.accounting_period_trial_balance (
  period_id  uuid,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_period_trial_balance"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.accounting_profit_and_loss (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_profit_and_loss"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_tax_report (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_tax_report"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.accounting_trial_balance (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_trial_balance"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.acknowledgement_status (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."acknowledgement_status"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.acknowledgements_of (
  subject_type text,
  subject_id   text,
  version_id   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."acknowledgements_of"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.acting_member()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."acting_member"() $function$;

CREATE OR REPLACE FUNCTION api.active_announcements (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."active_announcements"($1) $function$;

CREATE OR REPLACE FUNCTION api.activity_notes (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."activity_notes"($1) $function$;

CREATE OR REPLACE FUNCTION api.activity_recordings (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."activity_recordings"($1) $function$;

CREATE OR REPLACE FUNCTION api.activity_transcript (
  recording uuid,
  after     integer,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."activity_transcript"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.activity_with_transcripts (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."activity_with_transcripts"($1) $function$;

CREATE OR REPLACE FUNCTION api.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."actor_may_write"() $function$;

CREATE OR REPLACE FUNCTION api.ai_chat_can_read (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_chat_can_read"($1) $function$;

CREATE OR REPLACE FUNCTION api.ai_chat_share_summaries (
  chats uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_chat_share_summaries"($1) $function$;

CREATE OR REPLACE FUNCTION api.ai_message_path (
  chat           uuid,
  leaf           text    DEFAULT NULL::text,
  include_native boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_message_path"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.ai_message_siblings (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_message_siblings"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ai_provider_keys_for (
  tenant    uuid,
  providers text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_provider_keys_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ai_sandbox_for (
  chat_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_sandbox_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ai_tool_policies_for (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_tool_policies_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.allowed_ai_models (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."allowed_ai_models"($1) $function$;

CREATE OR REPLACE FUNCTION api.ancestors (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ancestors"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.api_key_tenant()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."api_key_tenant"() $function$;

CREATE OR REPLACE FUNCTION api.application_detail (
  application uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."application_detail"($1) $function$;

CREATE OR REPLACE FUNCTION api.appraisal_review_hidden (
  review_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."appraisal_review_hidden"($1) $function$;

CREATE OR REPLACE FUNCTION api.approval_eligible (
  request_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."approval_eligible"($1) $function$;

CREATE OR REPLACE FUNCTION api.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."approval_eligible_ids"($1) $function$;

CREATE OR REPLACE FUNCTION api.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."approval_policy"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.approval_requirement (
  tenant       uuid,
  subject_type text,
  action       text,
  subject      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."approval_requirement"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.as_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."as_column_type"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.asset_assignment_history (
  asset_id  uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."asset_assignment_history"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.asset_locations_at (
  tenant    uuid,
  latitude  double precision,
  longitude double precision
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."asset_locations_at"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.assets_near (
  tenant        uuid,
  latitude      double precision,
  longitude     double precision,
  radius_meters double precision,
  kind          text             DEFAULT NULL::text,
  page_size     integer          DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."assets_near"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.assignment_history (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  max_count    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."assignment_history"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.attachment_fields_error (
  fields jsonb,
  data   jsonb
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."attachment_fields_error"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.attachment_schema_error (
  fields jsonb
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."attachment_schema_error"($1) $function$;

CREATE OR REPLACE FUNCTION api.audit_entries_correlated (
  correlation text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_entries_correlated"($1) $function$;

CREATE OR REPLACE FUNCTION api.audit_events_tenants (
  older_than interval DEFAULT '1 day'::interval
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."audit_events_tenants"($1) $function$;

CREATE OR REPLACE FUNCTION api.audit_read_tenants()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."audit_read_tenants"() $function$;

CREATE OR REPLACE FUNCTION api.audit_reads_all()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_reads_all"() $function$;

CREATE OR REPLACE FUNCTION api.audit_revert_source (
  entries text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_revert_source"($1) $function$;

CREATE OR REPLACE FUNCTION api.authz_version (
  p_user uuid
)
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."authz_version"($1) $function$;

CREATE OR REPLACE FUNCTION api.available_slots (
  service     uuid,
  range_start timestamp with time zone,
  range_end   timestamp with time zone,
  tz          text                     DEFAULT NULL::text,
  resource    uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."available_slots"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.bank_reconciliation_board (
  account_id uuid,
  line_limit integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bank_reconciliation_board"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.bank_reconciliation_status (
  account_id uuid,
  as_of      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bank_reconciliation_status"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.bom_where_used (
  variant_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bom_where_used"($1) $function$;

CREATE OR REPLACE FUNCTION api.booking_series_starts (
  rule        jsonb,
  first_start timestamp with time zone,
  tz          text
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."booking_series_starts"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.booking_slots (
  service       uuid,
  range_start   timestamp with time zone,
  range_end     timestamp with time zone,
  tz            text,
  only_resource uuid
)
  RETURNS TABLE (
    resource_id uuid,
    starts_at   timestamp with time zone,
    ends_at     timestamp with time zone,
    local_start timestamp without time zone,
    seats       integer
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."booking_slots"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.bsb_valid_bsn (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bsb_valid_bsn"($1) $function$;

CREATE OR REPLACE FUNCTION api.bsb_valid_iban (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bsb_valid_iban"($1) $function$;

CREATE OR REPLACE FUNCTION api.bulk_run (
  run_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bulk_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.calendar_busy_blocks (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS TABLE (
    user_id   uuid,
    kind      text,
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone,
    event_id  uuid,
    declines  boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."calendar_busy_blocks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.calendar_free_busy (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."calendar_free_busy"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.calendar_rule_starts (
  dtstart     timestamp with time zone,
  tz          text,
  rrule       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."calendar_rule_starts"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.caller_authz_version()
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."caller_authz_version"() $function$;

CREATE OR REPLACE FUNCTION api.can (
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.can_assign (
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_assign"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.can_assign_as (
  member uuid,
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_assign_as"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.can_conversation (
  conversation uuid,
  action       text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_conversation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_subject"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_subject_for"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_user"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.cap_allows (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."cap_allows"($1) $function$;

CREATE OR REPLACE FUNCTION api.care_decision_context (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."care_decision_context"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.care_plan_json (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."care_plan_json"($1) $function$;

CREATE OR REPLACE FUNCTION api.case_blockers_of (
  target better_supabase.cases
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."case_blockers_of"($1) $function$;

CREATE OR REPLACE FUNCTION api.case_close_blockers (
  case_id uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."case_close_blockers"($1) $function$;

CREATE OR REPLACE FUNCTION api.case_stats (
  tenant   uuid,
  kind     text DEFAULT NULL::text,
  since    date DEFAULT NULL::date,
  until    date DEFAULT NULL::date,
  group_by text DEFAULT 'severity'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."case_stats"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.channel_price (
  channel uuid,
  variant uuid,
  as_of   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."channel_price"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.channel_products (
  channel   uuid,
  locale    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer,
  after     text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."channel_products"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.channels_for_record (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."channels_for_record"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.check_expense_report (
  report_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."check_expense_report"($1) $function$;

CREATE OR REPLACE FUNCTION api.check_sso_provider (
  tenant  uuid,
  domains text[],
  actor   uuid   DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."check_sso_provider"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.check_usage (
  tenant  uuid,
  node_id uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."check_usage"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.comment_conversation (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."comment_conversation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."comment_counts"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.commission_amount (
  kind     text,
  rate_bps integer,
  tiers    jsonb,
  prior    bigint,
  basis    bigint
)
  RETURNS bigint
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_amount"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.commission_payroll_lines (
  tenant    uuid,
  from_date date,
  to_date   date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_payroll_lines"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.commission_plan_for (
  tenant       uuid,
  seller_id    uuid,
  subject_type text,
  subject_id   text,
  on_date      date
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_plan_for"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.commission_tiers_valid (
  tiers jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_tiers_valid"($1) $function$;

CREATE OR REPLACE FUNCTION api.company_people_of (
  company uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."company_people_of"($1) $function$;

CREATE OR REPLACE FUNCTION api.compare_rfq (
  rfq_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."compare_rfq"($1) $function$;

CREATE OR REPLACE FUNCTION api.consent_active (
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."consent_active"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.control_posture (
  tenant       uuid,
  framework_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."control_posture"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.conversation_read_at (
  conversation uuid,
  member       uuid DEFAULT NULL::uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."conversation_read_at"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.converted_into (
  tenant      uuid,
  origin_type text,
  origin_id   text,
  into_type   text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."converted_into"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.count_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."count_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) $function$;

CREATE OR REPLACE FUNCTION api.course_lesson (
  lesson_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."course_lesson"($1) $function$;

CREATE OR REPLACE FUNCTION api.course_outline (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."course_outline"($1) $function$;

CREATE OR REPLACE FUNCTION api.course_progress (
  course_id uuid,
  user_id   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."course_progress"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.credential_get (
  provider text,
  name     text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."credential_get"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.currency_minor_units (
  code text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."currency_minor_units"($1) $function$;

CREATE OR REPLACE FUNCTION api.data_lifecycle_credentials()
  RETURNS TABLE (
    name     text,
    tbl      text,
    col      text,
    user_col text
  )
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."data_lifecycle_credentials"() $function$;

CREATE OR REPLACE FUNCTION api.data_lifecycle_tables()
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
  AS $function$ select * from "better_supabase"."data_lifecycle_tables"() $function$;

CREATE OR REPLACE FUNCTION api.data_restore_tables()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."data_restore_tables"() $function$;

CREATE OR REPLACE FUNCTION api.deal_board (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."deal_board"($1) $function$;

CREATE OR REPLACE FUNCTION api.deal_forecast (
  tenant   uuid,
  pipeline uuid,
  since    date,
  until    date,
  currency text,
  target   bigint,
  owner    uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."deal_forecast"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.deal_health (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."deal_health"($1) $function$;

CREATE OR REPLACE FUNCTION api.default_service_principal (
  tenant uuid
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."default_service_principal"($1) $function$;

CREATE OR REPLACE FUNCTION api.descendants (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."descendants"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.discount_group_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."discount_group_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.discount_rule_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."discount_rule_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.dispatch_board (
  tenant      uuid,
  from_date   date,
  to_date     date,
  technicians uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."dispatch_board"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.document_access (
  document_id uuid,
  write       boolean
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_access"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_address (
  address jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_address"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_delivery_preference_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_delivery_preference_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_entity (
  tenant       uuid,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_entity"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_party (
  tenant     uuid,
  company_id text,
  contact_id text,
  buyer      jsonb DEFAULT NULL::jsonb,
  email      text  DEFAULT NULL::text,
  address    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_party"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.document_render_live (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_render_live"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.document_slot_rank (
  entity          uuid,
  wanted_entity   uuid,
  language        text,
  wanted_language text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_slot_rank"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.document_tax_summary (
  lines jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_tax_summary"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_template_contract (
  document_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_template_contract"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_template_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_template_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_text_block_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_text_block_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_topic_access (
  topic text,
  write boolean
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_topic_access"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_totals_by_billing_party (
  document uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_totals_by_billing_party"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_variables (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_delivery_note (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_delivery_note"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_dunning_letter (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_dunning_letter"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_invoice (
  tenant      uuid,
  document_id uuid,
  credit_note boolean
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_order (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_quote (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_quote"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_statement (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_statement"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_visible (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_visible"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.documents_to_compact (
  min_updates   integer DEFAULT 200,
  max_documents integer DEFAULT 50
)
  RETURNS uuid[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."documents_to_compact"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_approvals (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_approvals"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_attachment_allowed (
  subject_type text,
  subject_id   text,
  write        boolean
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_attachment_allowed"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_bin"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_can (
  node uuid,
  role text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_can"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_can_comment (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_can_comment"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_can_download (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_can_download"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_can_upload (
  folder uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_can_upload"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_changes (
  tenant    uuid,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 200,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_changes"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.drive_documents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_documents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_download_blocked (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_download_blocked"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_get (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_grants (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_grants"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_labeled (
  tenant    uuid,
  tag       uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_labeled"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_link (
  token text,
  node  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_link"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_list (
  tenant    uuid,
  parent    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 100,
  skip      integer DEFAULT 0,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_list"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.drive_marked (
  tenant    uuid,
  recent    boolean DEFAULT false,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_marked"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_node_access (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_access"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_node_held (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_held"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_node_readable (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_readable"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_node_writable (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_writable"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_object_allowed (
  bucket text,
  path   text,
  action text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_object_allowed"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_path (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_path"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_previews (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_previews"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_readable_ids()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."drive_readable_ids"() $function$;

CREATE OR REPLACE FUNCTION api.drive_retention_kind (
  label text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_retention_kind"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_revisions (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_revisions"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_role (
  node uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_role"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_search (
  tenant    uuid,
  query     text,
  page_size integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_search"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_share_link_allowed (
  node   text,
  tenant text,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_share_link_allowed"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_shared (
  tenant    uuid,
  page_size integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_shared"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_text_source (
  node       uuid DEFAULT NULL::uuid,
  attachment uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_text_source"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_uploaded_own (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_uploaded_own"($1) $function$;

CREATE OR REPLACE FUNCTION api.due_mail_accounts (
  max_count   integer,
  stale_after interval
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_mail_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.due_organization_deletions (
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_organization_deletions"($1) $function$;

CREATE OR REPLACE FUNCTION api.due_pledge_installments (
  tenant   uuid,
  through  date    DEFAULT NULL::date,
  max_rows integer DEFAULT 500
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_pledge_installments"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.due_template_occurrences (
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_template_occurrences"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.employee_contracts (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."employee_contracts"($1) $function$;

CREATE OR REPLACE FUNCTION api.employee_private_details (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."employee_private_details"($1) $function$;

CREATE OR REPLACE FUNCTION api.end_sessions (
  p_user uuid
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."end_sessions"($1) $function$;

CREATE OR REPLACE FUNCTION api.engagement_guest_readable (
  engagement uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."engagement_guest_readable"($1) $function$;

CREATE OR REPLACE FUNCTION api.enrichment_due (
  provider     text,
  max_count    integer  DEFAULT NULL::integer,
  stale_after  interval DEFAULT NULL::interval,
  subject_type text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrichment_due"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.enrichment_target (
  subject_type text,
  subject_id   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrichment_target"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.enrichments_of (
  subject_type text,
  subject_id   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrichments_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.enrollment (
  tenant       uuid,
  program      text,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrollment"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.enrollment_programs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrollment_programs"($1) $function$;

CREATE OR REPLACE FUNCTION api.entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."entitlement_value"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.expired_data_exports (
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."expired_data_exports"($1) $function$;

CREATE OR REPLACE FUNCTION api.expiring_ai_provider_files (
  horizon interval DEFAULT '1 day'::interval,
  batch   integer  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."expiring_ai_provider_files"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.expiring_connector_grants (
  before   timestamp with time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."expiring_connector_grants"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.expiring_lots (
  tenant uuid,
  before date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."expiring_lots"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.explode_bom (
  variant_id uuid,
  quantity   numeric
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."explode_bom"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.feature_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."feature_claims"($1) $function$;

CREATE OR REPLACE FUNCTION api.field_history (
  subject_type text,
  subject_id   text,
  field        text    DEFAULT NULL::text,
  before       bigint  DEFAULT NULL::bigint,
  max_count    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.field_lookup (
  owner text,
  value text
)
  RETURNS bytea
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_lookup"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.find_channel (
  tenant uuid,
  name   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_channel"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.find_e_endpoint_party (
  tenant      uuid,
  scheme      text,
  endpoint_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_e_endpoint_party"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.find_person_by_identity (
  tenant  uuid,
  channel text,
  address text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_person_by_identity"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.find_variants_by_identifier (
  tenant uuid,
  value  text,
  type   text DEFAULT NULL::text,
  party  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_variants_by_identifier"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.flag_bucket (
  flag   text,
  target text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_bucket"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.flag_condition_matches (
  condition      jsonb,
  tenant         text,
  member         text,
  role           text,
  plans          text[],
  context_values jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_condition_matches"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.flag_definitions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_definitions"() $function$;

CREATE OR REPLACE FUNCTION api.flag_enabled (
  key    text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_enabled"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.flag_evaluation (
  key      text,
  tenant   uuid  DEFAULT NULL::uuid,
  member   uuid  DEFAULT auth.uid(),
  contexts jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_evaluation"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.flag_history (
  key text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_history"($1) $function$;

CREATE OR REPLACE FUNCTION api.flag_rollout_percentage (
  percentage numeric,
  schedule   jsonb,
  at         timestamp with time zone DEFAULT now()
)
  RETURNS numeric
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_rollout_percentage"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.forecast_changes (
  from_snapshot uuid,
  to_snapshot   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."forecast_changes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.forecast_snapshot (
  snapshot uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."forecast_snapshot"($1) $function$;

CREATE OR REPLACE FUNCTION api.forecast_snapshots (
  tenant    uuid,
  pipeline  uuid    DEFAULT NULL::uuid,
  since     date    DEFAULT NULL::date,
  until     date    DEFAULT NULL::date,
  max_count integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."forecast_snapshots"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.form_nps (
  form_id uuid,
  field   text                     DEFAULT NULL::text,
  since   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  bucket  text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."form_nps"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.funding_award_usage (
  award_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."funding_award_usage"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_access_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_access_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_budget (
  budget_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_budget"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_settings"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_activity_recording (
  recording uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_activity_recording"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_agent (
  id     uuid DEFAULT NULL::uuid,
  tenant uuid DEFAULT NULL::uuid,
  slug   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_agent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_batch (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_chat (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_chat_by_link (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_chat_by_link"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_file"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_file_by_path (
  bucket text,
  path   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_file_by_path"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_provider_file (
  file_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_provider_file"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_tool_approvals (
  chat uuid,
  ids  text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_tool_approvals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_appraisal (
  appraisal_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_appraisal"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_approval"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_asset (
  asset_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_asset"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_asset_location (
  location_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_asset_location"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_attachment (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_attachment"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_bank_transaction (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_bank_transaction"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_bom (
  bom_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_bom"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_booking_series (
  series_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_booking_series"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_care_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_care_plan"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_case (
  case_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_case"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_channel (
  channel uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_channel"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_comment (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_comment"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_commission_statement"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_connector (
  id    uuid,
  owner uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_connector"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_connector_session (
  server_id uuid,
  chat_key  text DEFAULT ''::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_connector_session"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_content_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_content_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_contract (
  contract_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_contract"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_control (
  control_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_control"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_conversation (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_conversation"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_cycle_count_variance (
  count_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_cycle_count_variance"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_data_export (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_data_export"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_document_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_document_template"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_document_version (
  document_id uuid,
  version_id  uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_document_version"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_expense_report (
  report_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_expense_report"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_form (
  form_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_form"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_form_submission"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_form_version (
  version_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_form_version"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_gift (
  gift_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_gift"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_import_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_import_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_inbox_message (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_inbox_message"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_incident (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_incident"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_incident_regulatory_profile (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_incident_regulatory_profile"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_knowledge_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_knowledge_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_lease (
  lease_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_lease"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_legal_entity (
  legal_entity_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_legal_entity"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_legal_entity_settings (
  legal_entity_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_legal_entity_settings"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_mail_account (
  account uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_mail_account"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_mail_thread (
  thread uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_mail_thread"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_maintenance_request (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_maintenance_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_message (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_message"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_notification (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_notification"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_order (
  order_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_order"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_organization_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_organization_settings"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_pass (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_pass"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_payment_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_payroll_run (
  run_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_payroll_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_pick_list (
  pick_list_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_pick_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_platform_settings()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_platform_settings"() $function$;

CREATE OR REPLACE FUNCTION api.get_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_post"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_prescription"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_production_order (
  order_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_production_order"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_public_form (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_public_form"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_purchase_requisition (
  requisition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_purchase_requisition"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_rfq (
  rfq_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_rfq"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_sample (
  sample_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_sample"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_sequence (
  sequence_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_sequence"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_shared_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_shipment (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_shipment"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_signature_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_status_page (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_status_page"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_till_session (
  session_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_till_session"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_timesheet (
  tenant  uuid,
  week    date,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_timesheet"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_user_settings()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_user_settings"() $function$;

CREATE OR REPLACE FUNCTION api.get_version (
  version_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_version"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_work_item (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_work_item"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_work_order (
  work_order_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_work_order"($1) $function$;

CREATE OR REPLACE FUNCTION api.goal_progress (
  tenant  uuid,
  on_date date,
  owner   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."goal_progress"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.guest_can (
  subject_type text,
  subject_id   text,
  action       text DEFAULT 'read'::text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."guest_can"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.has_entitlement (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."has_entitlement"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.has_scope (
  scope text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."has_scope"($1) $function$;

CREATE OR REPLACE FUNCTION api.has_subject_role (
  subject_type text,
  subject_id   text,
  roles        text[]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."has_subject_role"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_resolve (
  run    uuid,
  entity text,
  keys   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_resolve"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_run()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_run"() $function$;

CREATE OR REPLACE FUNCTION api.inbox_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inbox_counts"($1) $function$;

CREATE OR REPLACE FUNCTION api.inspection_role (
  inspection_id uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inspection_role"($1) $function$;

CREATE OR REPLACE FUNCTION api.inspection_team_with_lead (
  team    jsonb,
  lead_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inspection_team_with_lead"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.instrument_status (
  tenant   uuid,
  asset_id uuid,
  on_date  date DEFAULT CURRENT_DATE
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."instrument_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.inventory_overview (
  tenant      uuid,
  row_limit   integer DEFAULT 20,
  expiry_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inventory_overview"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.invitation_preview (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."invitation_preview"($1) $function$;

CREATE OR REPLACE FUNCTION api.invoice_aging (
  tenant    uuid,
  currency  text,
  as_of     date,
  direction text DEFAULT 'sales'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_aging"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.invoice_approval_state (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_approval_state"($1) $function$;

CREATE OR REPLACE FUNCTION api.invoice_e_endpoints (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_e_endpoints"($1) $function$;

CREATE OR REPLACE FUNCTION api.invoice_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.is_approved (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_approved"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.is_held (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_held"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.is_platform (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_platform"($1) $function$;

CREATE OR REPLACE FUNCTION api.is_subject_member (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_subject_member"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.is_trashed (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_trashed"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.kitchen_queue (
  tenant    uuid,
  station   uuid,
  states    text[],
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."kitchen_queue"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.kitchen_stations (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."kitchen_stations"($1) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_collection_readable (
  collection_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_collection_readable"($1) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb,
  collections     uuid[]            DEFAULT NULL::uuid[],
  priority_order  boolean           DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_search"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_subject_readable (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_subject_readable"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.last_sign_ins (
  p_users uuid[]
)
  RETURNS TABLE (
    user_id         uuid,
    last_sign_in_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."last_sign_ins"($1) $function$;

CREATE OR REPLACE FUNCTION api.latest_observations (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."latest_observations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.lead_fields (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."lead_fields"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.legal_entities_disable_check (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."legal_entities_disable_check"($1) $function$;

CREATE OR REPLACE FUNCTION api.legal_entity_of (
  tenant uuid,
  id     uuid DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."legal_entity_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_access_requests (
  tenant    uuid,
  status    text                     DEFAULT NULL::text,
  mine      boolean                  DEFAULT false,
  page_size integer                  DEFAULT NULL::integer,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_access_requests"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_accounts (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_budgets (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_budgets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_dimensions (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_dimensions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_entries (
  tenant     uuid,
  journal_id uuid    DEFAULT NULL::uuid,
  status     text    DEFAULT NULL::text,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  page_size  integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_entries"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_journals (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_journals"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_opening_balances"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_periods (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_periods"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_acknowledgement_assignments (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_acknowledgement_assignments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_agents (
  tenant   uuid,
  filter   text    DEFAULT 'store'::text,
  search   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_agents"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_batch_items (
  id       uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_batch_items"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_batches (
  tenant   uuid,
  status   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_batches"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chat_participants (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chat_participants"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chat_shares"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chats (
  tenant   uuid    DEFAULT NULL::uuid,
  search   text    DEFAULT NULL::text,
  project  uuid    DEFAULT NULL::uuid,
  pinned   boolean DEFAULT NULL::boolean,
  archived boolean DEFAULT false,
  after    text    DEFAULT NULL::text,
  size     integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chats"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_document_versions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_files (
  chat_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_files"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_moderation_events (
  tenant uuid,
  size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_moderation_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_projects (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_projects"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_provider_keys (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_provider_keys"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_run_steps (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_run_steps"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_runs (
  chat   uuid    DEFAULT NULL::uuid,
  active boolean DEFAULT NULL::boolean,
  size   integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_runs"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_sandboxes (
  tenant  uuid,
  chat_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_sandboxes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_suggestions (
  document_id uuid,
  open_only   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_suggestions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_task_runs (
  task_id  uuid,
  max_rows integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_task_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_tasks (
  tenant uuid,
  mine   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_tasks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_allocations (
  tenant        uuid,
  document_type text,
  document_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_allocations"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_announcements()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_announcements"() $function$;

CREATE OR REPLACE FUNCTION api.list_api_keys (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_api_keys"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_applications (
  job   uuid,
  state text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_applications"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_appraisal_cycles (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_appraisal_cycles"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_appraisals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_appraisals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_approval_policies (
  tenant       uuid,
  subject_type text    DEFAULT NULL::text,
  page_size    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_approval_policies"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_approvals (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  assigned     boolean                  DEFAULT false,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_approvals"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_asset_depreciations (
  asset_id  uuid,
  page_size integer DEFAULT 600
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_asset_depreciations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_asset_locations (
  tenant           uuid,
  parent_id        uuid    DEFAULT NULL::uuid,
  include_archived boolean DEFAULT false,
  page_size        integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_asset_locations"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_assets (
  tenant               uuid,
  location_id          uuid                     DEFAULT NULL::uuid,
  include_sublocations boolean                  DEFAULT false,
  kind                 text                     DEFAULT NULL::text,
  status               text                     DEFAULT NULL::text,
  assignee_type        text                     DEFAULT NULL::text,
  assignee_id          text                     DEFAULT NULL::text,
  query                text                     DEFAULT NULL::text,
  before               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size            integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_assets"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.list_assignment_queues (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_assignment_queues"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_attachment_versions (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_attachment_versions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_at           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_id           text                     DEFAULT NULL::text,
  max_items           integer                  DEFAULT 50,
  ascending           boolean                  DEFAULT false,
  skip                integer                  DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18) $function$;

CREATE OR REPLACE FUNCTION api.list_bank_accounts (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bank_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_bank_rules (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bank_rules"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_bank_statements (
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bank_statements"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_bank_transactions (
  account_id uuid,
  filter     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bank_transactions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_bans (
  tenant    uuid,
  active    boolean DEFAULT true,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bans"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_bin_slots (
  tenant  uuid,
  filters jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bin_slots"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_boms (
  tenant  uuid,
  variant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_boms"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_booking_resources (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_booking_resources"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_booking_services (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_booking_services"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_bookings (
  tenant      uuid,
  range_start timestamp with time zone,
  range_end   timestamp with time zone,
  resource    uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bookings"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_calendar_events (
  calendar_ids uuid[],
  range_start  timestamp with time zone,
  range_end    timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_calendar_events"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_calendar_working_hours (
  tenant   uuid,
  user_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_calendar_working_hours"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_calendars (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_calendars"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_calibrations (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_calibrations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_care_alerts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_care_alerts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_care_plan_measures (
  tenant      uuid,
  active_only boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_care_plan_measures"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_care_plans (
  subject_type     text,
  subject_id       text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_care_plans"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_care_rules (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_care_rules"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_cases (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_cases"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_channels (
  tenant           uuid,
  browse           boolean DEFAULT false,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_channels"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_commission_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commission_plans"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_commission_statements (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commission_statements"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_commissions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_companies (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_companies"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.list_compliance_policies (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_compliance_policies"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_connector_servers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_connector_servers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_consent_purposes (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consent_purposes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_consent_receipts (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consent_receipts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_consent_signals (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consent_signals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_consents (
  subject_type    text,
  subject_id      text,
  include_history boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_consents"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_content_entries (
  tenant uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_content_entries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_contract_obligations (
  tenant      uuid,
  contract_id uuid    DEFAULT NULL::uuid,
  owner_id    uuid    DEFAULT NULL::uuid,
  open_only   boolean DEFAULT false,
  due_before  date    DEFAULT NULL::date,
  page_size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_contract_obligations"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_contracts (
  tenant            uuid,
  status            text                     DEFAULT NULL::text,
  counterparty_type text                     DEFAULT NULL::text,
  counterparty_id   text                     DEFAULT NULL::text,
  owner_id          uuid                     DEFAULT NULL::uuid,
  renewing_before   date                     DEFAULT NULL::date,
  before            timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size         integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_contracts"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.list_control_frameworks (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_control_frameworks"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_controls (
  tenant       uuid,
  framework_id uuid    DEFAULT NULL::uuid,
  status       text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  page_size    integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_controls"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_conversation_events (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_conversation_events"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_conversations (
  tenant   uuid,
  kinds    text[]  DEFAULT NULL::text[],
  max_rows integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_conversations"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_count_plans (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_count_plans"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_course_learners (
  course_id uuid,
  status    text                     DEFAULT NULL::text,
  page_size integer                  DEFAULT NULL::integer,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_course_learners"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_courses (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_courses"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_custom_emoji (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_custom_emoji"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_data_exports (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_data_exports"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_data_subject_requests (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  open_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_data_subject_requests"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_document_delivery_preferences (
  party uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_delivery_preferences"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_document_suggestions (
  document_id uuid,
  status      text DEFAULT 'open'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_suggestions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_document_templates (
  tenant          uuid,
  document_type   text    DEFAULT NULL::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active_only     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_templates"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_document_text_blocks (
  tenant          uuid,
  key             text DEFAULT NULL::text,
  legal_entity_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_text_blocks"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_versions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_donation_funds (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_donation_funds"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_donation_receipts (
  tenant     uuid,
  donor_type text    DEFAULT NULL::text,
  donor_id   text    DEFAULT NULL::text,
  year       integer DEFAULT NULL::integer,
  page_size  integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_donation_receipts"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_e_invoice_deliveries (
  tenant    uuid,
  direction text DEFAULT NULL::text,
  state     text DEFAULT NULL::text,
  invoice   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_e_invoice_deliveries"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_emergency_access (
  tenant     uuid,
  unreviewed boolean                  DEFAULT true,
  page_size  integer                  DEFAULT NULL::integer,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_emergency_access"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_enrollments (
  tenant       uuid,
  program      text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT NULL::integer,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_enrollments"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_evidence_tasks (
  tenant       uuid,
  control_id   uuid    DEFAULT NULL::uuid,
  assignee_id  uuid    DEFAULT NULL::uuid,
  overdue_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_evidence_tasks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_expense_categories (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_expense_categories"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_expense_reports (
  tenant    uuid,
  user_id   uuid    DEFAULT NULL::uuid,
  status    text    DEFAULT NULL::text,
  everyone  boolean DEFAULT false,
  page_size integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_expense_reports"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_field_definitions (
  tenant uuid,
  entity text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_field_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_file_anchors (
  attachment uuid,
  max_rows   integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_file_anchors"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_file_comments (
  attachment uuid,
  max_rows   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_file_comments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_flag_segments()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_flag_segments"() $function$;

CREATE OR REPLACE FUNCTION api.list_flags()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_flags"() $function$;

CREATE OR REPLACE FUNCTION api.list_form_submissions (
  form_id   uuid,
  status    text                     DEFAULT NULL::text,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_form_submissions"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_forms (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_forms"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_awards (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  include_ended boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_awards"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_claims (
  tenant    uuid,
  status    text DEFAULT NULL::text,
  funder_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_claims"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_deliveries (
  tenant uuid,
  filter jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_deliveries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_products (
  tenant          uuid,
  include_expired boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_products"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_gifts (
  tenant     uuid,
  donor_type text    DEFAULT NULL::text,
  donor_id   text    DEFAULT NULL::text,
  fund_id    uuid    DEFAULT NULL::uuid,
  pledge_id  uuid    DEFAULT NULL::uuid,
  status     text    DEFAULT NULL::text,
  page_size  integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_gifts"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_guest_grants (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_guest_grants"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_guests (
  tenant    uuid,
  status    text                     DEFAULT NULL::text,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_guests"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_import_runs (
  tenant    uuid,
  source    text    DEFAULT NULL::text,
  status    text    DEFAULT NULL::text,
  row_limit integer DEFAULT 50
)
  RETURNS SETOF jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_import_runs"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_inbox_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_inbox_conversations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_inbox_drafts (
  conversation uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_inbox_drafts"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_inbox_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_inbox_messages"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_incident_filings (
  tenant  uuid,
  pending boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_incident_filings"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_incidents (
  tenant       uuid,
  status       text                     DEFAULT NULL::text,
  severity     text                     DEFAULT NULL::text,
  component_id uuid                     DEFAULT NULL::uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_incidents"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_invite_codes (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invite_codes"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_allocations (
  tenant     uuid,
  reference  text DEFAULT NULL::text,
  invoice_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_allocations"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_approval_levels (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_approval_levels"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_dunning_history (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_dunning_history"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_dunning_levels (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_dunning_levels"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_dunning_run_items (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_dunning_run_items"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_dunning_runs (
  tenant uuid,
  max    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_dunning_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_payments (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_payments"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoiced_time (
  invoice   uuid,
  page_size integer DEFAULT 500
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoiced_time"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_jobs (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_jobs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_knowledge_collection_grants (
  collection_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_knowledge_collection_grants"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_knowledge_collections (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_knowledge_collections"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_knowledge_documents (
  tenant        uuid,
  scope         text    DEFAULT NULL::text,
  scope_id      uuid    DEFAULT NULL::uuid,
  max_rows      integer DEFAULT 100,
  collection_id uuid    DEFAULT NULL::uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_knowledge_documents"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_lease_charges (
  lease_id  uuid,
  page_size integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_lease_charges"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_leases (
  tenant     uuid,
  status     text    DEFAULT NULL::text,
  unit_id    uuid    DEFAULT NULL::uuid,
  party_type text    DEFAULT NULL::text,
  party_id   text    DEFAULT NULL::text,
  page_size  integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_leases"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_legal_entities (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_legal_entities"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_legal_holds (
  include_released boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_legal_holds"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_lims_methods (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_lims_methods"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_mail_threads (
  tenant    uuid,
  account   uuid,
  before    timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_mail_threads"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_meters (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_meters"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_plans"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_checklist (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_checklist"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_watchers (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_watchers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_requests (
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
  AS $function$ select "better_supabase"."list_maintenance_requests"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_medications (
  tenant           uuid,
  search           text    DEFAULT NULL::text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_medications"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_members (
  organization uuid
)
  RETURNS TABLE (
    user_id uuid,
    role    text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_members"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_message_edits (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_message_edits"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_messages (
  conversation uuid,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  after_id     uuid                     DEFAULT NULL::uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_messages"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_my_acknowledgements (
  tenant       uuid,
  pending_only boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_acknowledgements"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_my_organizations()
  RETURNS TABLE (
    id   uuid,
    name text,
    slug text,
    role text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_my_organizations"() $function$;

CREATE OR REPLACE FUNCTION api.list_my_reminders (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_reminders"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_my_sessions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_sessions"() $function$;

CREATE OR REPLACE FUNCTION api.list_notices (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notices"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_notification_preferences (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_preferences"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_notification_subscriptions (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_subscriptions"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_notification_suppressions (
  max_items integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_suppressions"($1) $function$;

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
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notifications"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $function$;

CREATE OR REPLACE FUNCTION api.list_observation_definitions (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
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
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_observations"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_order_variants (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_order_variants"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_organization_domains (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_organization_domains"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    expires_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_organization_invitations"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_party_credits (
  tenant   uuid,
  party_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_party_credits"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_pass_check_ins (
  pass_id   uuid,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pass_check_ins"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_pass_credits (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pass_credits"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_passes (
  tenant       uuid,
  holder_user  uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_passes"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_payment_batches (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_payment_batches"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_payment_terms (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_payment_terms"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_payroll_runs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_payroll_runs"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_pending_ai_tool_approvals (
  size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pending_ai_tool_approvals"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_people (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_people"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.list_periods (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_periods"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_person_identities (
  person uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_person_identities"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_pick_lists (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pick_lists"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_pick_waves (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pick_waves"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_pinned_messages (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pinned_messages"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_pipelines (
  tenant       uuid,
  subject_type text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pipelines"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_pledges (
  tenant     uuid,
  donor_type text    DEFAULT NULL::text,
  donor_id   text    DEFAULT NULL::text,
  status     text    DEFAULT NULL::text,
  page_size  integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pledges"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_post_boards (
  tenant   uuid,
  archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_post_boards"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_posts (
  tenant uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_posts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_prescriptions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_prescriptions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_production_orders (
  tenant uuid,
  filter jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_production_orders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_putaway_rules (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_putaway_rules"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_qualification_requirements (
  type_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_qualification_requirements"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_qualification_types (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_qualification_types"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_quote_variants (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_quote_variants"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_record_access_requests (
  subject_type text,
  subject_id   text,
  status       text    DEFAULT NULL::text,
  page_size    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_record_access_requests"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_record_mentions (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_record_mentions"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_referral_codes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_referral_codes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_referrals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_referrals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_reminder_schedule()
  RETURNS TABLE (
    reminder       uuid,
    dtstart        timestamp with time zone,
    tzid           text,
    rrule          text,
    offset_minutes integer,
    tenant         uuid,
    subject_type   text,
    subject_id     text,
    user_id        uuid
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_reminder_schedule"() $function$;

CREATE OR REPLACE FUNCTION api.list_renditions (
  tenant  uuid,
  node_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_renditions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_replies (
  message  uuid,
  after    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  after_id uuid                     DEFAULT NULL::uuid,
  max_rows integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_replies"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_representatives (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_representatives"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_retention_policies (
  kind text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_retention_policies"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_rfqs (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_rfqs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_roles (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_roles"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_samples (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_samples"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_scheduled_inbox_messages (
  conversation uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_scheduled_inbox_messages"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_score_models (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_score_models"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_segment_members (
  segment   uuid,
  after     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_count integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_segment_members"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_sequence_enrollments (
  tenant uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_sequence_enrollments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_sequences (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_sequences"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_share_links (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_share_links"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_shift_availability (
  tenant     uuid,
  from_date  date,
  until_date date,
  user_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shift_availability"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_shift_templates (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shift_templates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_shipments (
  tenant       uuid,
  status       text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  carrier      text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shipments"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_signature_requests (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  mine         boolean                  DEFAULT false,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_signature_requests"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_sso_providers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_sso_providers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_statements (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_statements"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_status_components (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_status_components"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_status_stages (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_status_stages"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_subject_deliveries (
  subject_type text,
  subject_id   text,
  tenant       uuid    DEFAULT NULL::uuid,
  max_items    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_subject_deliveries"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_subject_members (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_subject_members"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_tags (
  tenant uuid,
  kind   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_tags"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_teams (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_teams"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_template_schedule()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_template_schedule"() $function$;

CREATE OR REPLACE FUNCTION api.list_till_sessions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_till_sessions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_tills (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_tills"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_time_entries (
  tenant       uuid,
  user_id      uuid                     DEFAULT NULL::uuid,
  starts       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  ends         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  everyone     boolean                  DEFAULT false,
  page_size    integer                  DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_time_entries"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.list_time_rates (
  tenant       uuid,
  user_id      uuid    DEFAULT NULL::uuid,
  subject_type text    DEFAULT NULL::text,
  subject_id   text    DEFAULT NULL::text,
  page_size    integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_time_rates"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_timesheets (
  tenant    uuid,
  user_id   uuid    DEFAULT NULL::uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT 50,
  before    date    DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_timesheets"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_tracking_events (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_tracking_events"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_trash (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_trash"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_usage_rights (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_usage_rights"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_versions (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50,
  before       integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_versions"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_views (
  tenant uuid,
  list   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_views"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_waitlist (
  status         text    DEFAULT 'waiting'::text,
  page_size      integer DEFAULT 50,
  after_position bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_waitlist"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_webhook_endpoints (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_webhook_endpoints"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_centers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_centers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_checklist (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_checklist"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_watchers (
  work_item uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_watchers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_items (
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
  AS $function$ select "better_supabase"."list_work_items"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_work_order_parts (
  work_order_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_order_parts"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_orders (
  tenant       uuid,
  status       text                     DEFAULT NULL::text,
  technician   uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  from_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_orders"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.load_ai_harness_session (
  chat    uuid,
  harness text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."load_ai_harness_session"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.lot_genealogy (
  lot_id    uuid,
  direction text DEFAULT 'down'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."lot_genealogy"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.lot_recall (
  lot_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."lot_recall"($1) $function$;

CREATE OR REPLACE FUNCTION api.mail_accounts_of (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_accounts_of"($1) $function$;

CREATE OR REPLACE FUNCTION api.mail_template_stats (
  tenant uuid,
  since  timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_template_stats"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.mail_thread_visible (
  thread uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_thread_visible"($1) $function$;

CREATE OR REPLACE FUNCTION api.mail_threads_of (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  page_size    integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_threads_of"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_next_occurrence (
  dtstart timestamp with time zone,
  tz      text,
  rrule   text,
  after   timestamp with time zone
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_next_occurrence"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_request_tree (
  root uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_request_tree"($1) $function$;

CREATE OR REPLACE FUNCTION api.matching_rules (
  tenant       uuid,
  subject_type text,
  trigger      text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."matching_rules"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.material_requirements (
  tenant       uuid,
  horizon_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."material_requirements"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.medication_chart (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."medication_chart"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.medication_orders_of (
  subject_type    text,
  subject_id      text,
  include_stopped boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."medication_orders_of"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.meeting_role (
  meeting_id uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."meeting_role"($1) $function$;

CREATE OR REPLACE FUNCTION api.member_can (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_can"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.member_can_while_deleting (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_can_while_deleting"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.member_permissions (
  member uuid,
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_permissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.memory_document_read (
  scope_key text,
  path      text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_document_read"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_list"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_view"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.messaging_file_anchor_valid (
  anchor jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."messaging_file_anchor_valid"($1) $function$;

CREATE OR REPLACE FUNCTION api.metric_definitions()
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_definitions"() $function$;

CREATE OR REPLACE FUNCTION api.metric_series (
  p_metric   text,
  p_tenant   uuid,
  p_from     timestamp with time zone,
  p_until    timestamp with time zone,
  p_grain    text                     DEFAULT 'day'::text,
  p_dims     jsonb                    DEFAULT '{}'::jsonb,
  p_group_by text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_series"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.metric_value (
  p_metric text,
  p_tenant uuid,
  p_from   timestamp with time zone,
  p_until  timestamp with time zone,
  p_dims   jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_value"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.moderation_hidden (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."moderation_hidden"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.moderation_item (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."moderation_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.moderation_queue (
  tenant       uuid,
  status       text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."moderation_queue"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.moderation_statuses (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."moderation_statuses"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.my_guest_access()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_guest_access"() $function$;

CREATE OR REPLACE FUNCTION api.my_invitations()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_invitations"() $function$;

CREATE OR REPLACE FUNCTION api.my_passes()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_passes"() $function$;

CREATE OR REPLACE FUNCTION api.my_permissions (
  tenant uuid,
  keys   text[] DEFAULT NULL::text[]
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_permissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_profile"() $function$;

CREATE OR REPLACE FUNCTION api.my_reminders_due (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS TABLE (
    reminder     uuid,
    subject_type text,
    subject_id   text,
    at           timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."my_reminders_due"($1) $function$;

CREATE OR REPLACE FUNCTION api.my_shifts (
  since timestamp with time zone DEFAULT now(),
  until timestamp with time zone DEFAULT (now() + '30 days'::interval)
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_shifts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.my_subjects (
  tenant       uuid,
  subject_type text    DEFAULT NULL::text,
  page_size    integer DEFAULT 100,
  cursor       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_subjects"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.my_work (
  tenant    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_work"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.next_activity (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."next_activity"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.notification_actors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_actors"($1) $function$;

CREATE OR REPLACE FUNCTION api.notification_cadence (
  member  uuid,
  tenant  uuid,
  type    text,
  channel text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_cadence"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.notification_counts (
  tenant     uuid   DEFAULT NULL::uuid,
  actionable text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
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
  STABLE
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
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_page"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.object_scan (
  bucket text,
  path   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."object_scan"($1, $2) $function$;

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
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."observation_series"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.onboarding_progress (
  checklist text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."onboarding_progress"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.open_activities (
  tenant     uuid,
  owner      uuid,
  due_before timestamp with time zone,
  page_size  integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_activities"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.open_enrollment_steps (
  tenant        uuid,
  assignee_role text                     DEFAULT NULL::text,
  assignee_user uuid                     DEFAULT NULL::uuid,
  due_before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_enrollment_steps"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.open_item_ageing (
  tenant uuid,
  side   text DEFAULT NULL::text,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_item_ageing"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.open_items_for_party (
  tenant   uuid,
  party_id text DEFAULT NULL::text,
  as_of    date DEFAULT NULL::date,
  side     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_items_for_party"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."operation_permission"($1) $function$;

CREATE OR REPLACE FUNCTION api.order_board (
  tenant    uuid,
  since     timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_board"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.order_status_board (
  tenant     uuid,
  per_status integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_status_board"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.order_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.org_chart (
  tenant uuid,
  root   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."org_chart"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.organization_credential_refs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_credential_refs"($1) $function$;

CREATE OR REPLACE FUNCTION api.organization_deletion (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_deletion"($1) $function$;

CREATE OR REPLACE FUNCTION api.organization_domain (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_domain"($1) $function$;

CREATE OR REPLACE FUNCTION api.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_overview"($1) $function$;

CREATE OR REPLACE FUNCTION api.organization_setting (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_setting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_slug_problem"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.outbox_dead_letters (
  consumer text,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."outbox_dead_letters"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.outbox_history (
  subject    text    DEFAULT NULL::text,
  event_type text    DEFAULT NULL::text,
  after      bigint  DEFAULT 0,
  max_events integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."outbox_history"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.pass_occupancy (
  resource_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pass_occupancy"($1) $function$;

CREATE OR REPLACE FUNCTION api.payment_term_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."payment_term_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_activity_recordings (
  batch integer
)
  RETURNS uuid[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_activity_recordings"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_inbound_events (
  max          integer DEFAULT 100,
  max_attempts integer DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_inbound_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pending_inbox_files (
  max integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_inbox_files"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_knowledge_chunks (
  document_id uuid,
  batch       integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_knowledge_chunks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pending_knowledge_documents (
  batch integer DEFAULT 10
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_knowledge_documents"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_memory_embeddings (
  batch integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_memory_embeddings"($1) $function$;

CREATE OR REPLACE FUNCTION api.period_close_blockers (
  period_id uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."period_close_blockers"($1) $function$;

CREATE OR REPLACE FUNCTION api.period_is_open (
  tenant  uuid,
  kind    text,
  on_date date
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."period_is_open"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.permission_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_claims"($1) $function$;

CREATE OR REPLACE FUNCTION api.permission_claims (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_claims"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.permission_matches (
  granted text,
  wanted  text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_matches"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pipeline_board (
  subject_type text,
  pipeline     uuid,
  owner        uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pipeline_board"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.pipeline_health (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pipeline_health"($1) $function$;

CREATE OR REPLACE FUNCTION api.pipeline_stats (
  pipeline uuid,
  since    timestamp with time zone,
  until    timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pipeline_stats"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.platform_can (
  member     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."platform_can"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.platform_can_assign (
  member uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."platform_can_assign"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.portal_parties()
  RETURNS TABLE (
    tenant     text,
    party_type text,
    party_id   text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."portal_parties"() $function$;

CREATE OR REPLACE FUNCTION api.portal_subjects (
  action text
)
  RETURNS TABLE (
    tenant       text,
    subject_type text,
    subject_id   text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."portal_subjects"($1) $function$;

CREATE OR REPLACE FUNCTION api.product_identifier_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_identifier_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.product_media (
  product uuid,
  locale  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_media"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.product_text (
  product uuid,
  locale  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_text"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.project_costs (
  project_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."project_costs"($1) $function$;

CREATE OR REPLACE FUNCTION api.public_content_entries (
  tenant    uuid,
  type      text                     DEFAULT NULL::text,
  locale    text                     DEFAULT NULL::text,
  page_size integer                  DEFAULT 20,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."public_content_entries"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.public_content_entry (
  tenant uuid,
  type   text,
  slug   text,
  locale text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."public_content_entry"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.public_status_page (
  slug text,
  days integer DEFAULT 90
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."public_status_page"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pull_document_updates (
  document_id uuid,
  after_seq   bigint
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pull_document_updates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purchase_invoice_approval_status (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."purchase_invoice_approval_status"($1) $function$;

CREATE OR REPLACE FUNCTION api.push_tickets_for (
  delivery uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."push_tickets_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.push_tokens_for (
  users uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."push_tokens_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.qualification_gaps (
  tenant      uuid,
  holder_type text  DEFAULT 'member'::text,
  filters     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."qualification_gaps"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.qualifications_of (
  holder_type text,
  holder_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."qualifications_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.qualified_holders (
  tenant      uuid,
  type_key    text,
  holder_type text DEFAULT 'member'::text,
  on_date     date DEFAULT CURRENT_DATE
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."qualified_holders"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.quote_totals_by_billing_party (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."quote_totals_by_billing_party"($1) $function$;

CREATE OR REPLACE FUNCTION api.quote_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."quote_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.rank_between (
  previous text,
  next     text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rank_between"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rank_key (
  nth   bigint,
  total bigint
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rank_key"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.reaction_list (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."reaction_list"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.reaction_summary (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."reaction_summary"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.relation_rollup (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  of_type      text,
  column_name  text,
  agg          text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."relation_rollup"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.relation_walk (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  up           boolean,
  max_depth    integer
)
  RETURNS TABLE (
    type  text,
    id    text,
    depth integer
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."relation_walk"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.relations_by_kind (
  tenant uuid,
  kind   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."relations_by_kind"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.relations_of (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  kind         text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."relations_of"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.render_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text    DEFAULT NULL::text,
  fresh         boolean DEFAULT false,
  template_name text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."render_document"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.replacement_variant (
  variant uuid
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."replacement_variant"($1) $function$;

CREATE OR REPLACE FUNCTION api.reports_of (
  manager  uuid,
  indirect boolean
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."reports_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.represented_by_me (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."represented_by_me"($1) $function$;

CREATE OR REPLACE FUNCTION api.requires_consent (
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."requires_consent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.resolve_document_blocks (
  tenant          uuid,
  keys            text[],
  legal_entity_id uuid   DEFAULT NULL::uuid,
  language        text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_document_blocks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.resolve_document_template (
  tenant          uuid,
  document_type   text,
  legal_entity_id uuid DEFAULT NULL::uuid,
  language        text DEFAULT NULL::text,
  name            text DEFAULT 'default'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_document_template"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.resolve_line_discount (
  tenant   uuid,
  party    text,
  product  uuid,
  quantity numeric,
  "on"     date,
  currency text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_line_discount"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.resolve_setting (
  tenant       uuid,
  key          text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_setting"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.resolve_workflow_definition (
  tenant       uuid,
  purpose      text DEFAULT 'lifecycle'::text,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_workflow_definition"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.retention_cutoff (
  kind     text,
  fallback interval
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."retention_cutoff"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.retention_floor (
  kind text
)
  RETURNS interval
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."retention_floor"($1) $function$;

CREATE OR REPLACE FUNCTION api.retention_for (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS interval
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."retention_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.roster (
  tenant     uuid,
  from_date  date,
  until_date date,
  team_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."roster"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.rule_boolean (
  value jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_boolean"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_bounds (
  kind      text,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS timestamp WITHOUT time zone[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_bounds"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.rule_check (
  node   jsonb,
  fields jsonb,
  depth  integer DEFAULT 1
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_check"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_date (
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_date"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.rule_equal (
  type    text,
  operand jsonb,
  value   jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_equal"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_evaluate (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_evaluate"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_evaluations_list (
  rule      uuid,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_evaluations_list"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_field_map (
  subject_type text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_field_map"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_fields_list (
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_fields_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_get (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_list (
  value jsonb
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_matches (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_matches"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_moment (
  kind  text,
  value jsonb
)
  RETURNS timestamp WITHOUT time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_moment"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rule_node (
  node      jsonb,
  subject   jsonb,
  fields    jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_node"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_numeric (
  value jsonb
)
  RETURNS numeric
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_numeric"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_positive (
  type      text,
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_positive"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.rule_text (
  value jsonb
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_text"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_versions_list (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_versions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.running_timer (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."running_timer"($1) $function$;

CREATE OR REPLACE FUNCTION api.running_timers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."running_timers"($1) $function$;

CREATE OR REPLACE FUNCTION api.scim_get_group (
  tenant uuid,
  id     uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scim_get_group"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.scim_get_user (
  tenant uuid,
  id     uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scim_get_user"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.scim_group_role (
  display_name text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scim_group_role"($1) $function$;

CREATE OR REPLACE FUNCTION api.scim_list_groups (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scim_list_groups"($1) $function$;

CREATE OR REPLACE FUNCTION api.scim_list_users (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scim_list_users"($1) $function$;

CREATE OR REPLACE FUNCTION api.scope_permissions (
  scope text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."scope_permissions"($1) $function$;

CREATE OR REPLACE FUNCTION api.score_history (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."score_history"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.search (
  q           text,
  types       text[]  DEFAULT NULL::text[],
  tenant      uuid    DEFAULT NULL::uuid,
  max_results integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."search"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.search_favorites (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_favorites"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_recents (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_recents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_supplier_items (
  tenant    uuid,
  query     text,
  supplier  uuid    DEFAULT NULL::uuid,
  row_limit integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_supplier_items"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.segment_get (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."segment_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.segments_list (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."segments_list"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.segments_of (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."segments_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.service_principals_list (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."service_principals_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.sessions_overview()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sessions_overview"() $function$;

CREATE OR REPLACE FUNCTION api.shift_hours (
  tenant     uuid,
  week_start date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."shift_hours"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.signing_jwks (
  owner_type text,
  owner_id   text,
  grace      interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."signing_jwks"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.signing_key (
  owner_type text,
  owner_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."signing_key"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sla_clocks_of (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sla_clocks_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sla_due_at (
  start    timestamp with time zone,
  minutes  integer,
  business boolean
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sla_due_at"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.sources_ready_to_invoice (
  tenant uuid,
  party  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sources_ready_to_invoice"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sso_access_token_check (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sso_access_token_check"($1) $function$;

CREATE OR REPLACE FUNCTION api.sso_domain_for (
  email text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sso_domain_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.sso_provider (
  provider uuid,
  actor    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sso_provider"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.start_test_run (
  definition   uuid,
  version      uuid  DEFAULT NULL::uuid,
  trigger_node text  DEFAULT NULL::text,
  input        jsonb DEFAULT NULL::jsonb,
  stubs        jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."start_test_run"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.status_state (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."status_state"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.stock_count_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stock_count_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.stock_detail (
  variant  uuid,
  location uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stock_detail"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.stock_valuation (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stock_valuation"($1) $function$;

CREATE OR REPLACE FUNCTION api.storefront_products()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."storefront_products"() $function$;

CREATE OR REPLACE FUNCTION api.storefront_tenants()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."storefront_tenants"() $function$;

CREATE OR REPLACE FUNCTION api.stream_kv_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_kv_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.stream_read (
  stream_id text,
  from_idx  integer DEFAULT 0,
  max       integer DEFAULT 1000
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_read"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.stream_status (
  stream_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_status"($1) $function$;

CREATE OR REPLACE FUNCTION api.subject_access_log (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_access_log"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.subject_presence_allowed (
  topic text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_presence_allowed"($1) $function$;

CREATE OR REPLACE FUNCTION api.subject_scores (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_scores"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_tags"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_title"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_titles"($1) $function$;

CREATE OR REPLACE FUNCTION api.subject_types()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_types"() $function$;

CREATE OR REPLACE FUNCTION api.subject_url (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_url"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.subjects_tags (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."subjects_tags"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.suggest_bank_matches (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."suggest_bank_matches"($1) $function$;

CREATE OR REPLACE FUNCTION api.suggest_putaway (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."suggest_putaway"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.suggest_receipt_putaway (
  receipt_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."suggest_receipt_putaway"($1) $function$;

CREATE OR REPLACE FUNCTION api.suggest_slotting (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."suggest_slotting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_from_row (
  tenant   uuid,
  supplier uuid,
  source   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_from_row"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_mapping (
  tenant   uuid,
  supplier uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_mapping"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.supplier_status_from_qualifications (
  party uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_status_from_qualifications"($1) $function$;

CREATE OR REPLACE FUNCTION api.team_ids_of (
  member uuid
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."team_ids_of"($1) $function$;

CREATE OR REPLACE FUNCTION api.technician_day (
  tenant     uuid,
  day        date,
  technician uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."technician_day"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.template_applications_list (
  tenant       uuid,
  template_id  uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_applications_list"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.template_apply_target (
  template_id uuid,
  tenant      uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_apply_target"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.template_get (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.template_schedules_list (
  tenant      uuid,
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_schedules_list"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.template_versions_list (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_versions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.template_workflow_input_errors (
  definition uuid,
  inputs     jsonb
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_workflow_input_errors"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.template_workflows_list (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_workflows_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.templates_list (
  tenant   uuid,
  type     text,
  language text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."templates_list"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.tenant_disabled (
  tenant uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_disabled"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_entitlement_value"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.tenant_entitlements (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_entitlements"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with (
  permission text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with_entitlement (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with_entitlement"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with_flag (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with_flag"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_plans (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_plans"($1) $function$;

CREATE OR REPLACE FUNCTION api.thread_summary (
  conversation uuid DEFAULT NULL::uuid,
  thread       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."thread_summary"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.time_lines_for_invoice (
  tenant   uuid,
  scope    jsonb,
  group_by text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."time_lines_for_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.time_rate (
  tenant       uuid,
  user_id      uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  on_day       date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."time_rate"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.time_week (
  at timestamp with time zone
)
  RETURNS date
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."time_week"($1) $function$;

CREATE OR REPLACE FUNCTION api.top_scores (
  tenant    uuid,
  model_key text,
  band      text    DEFAULT NULL::text,
  min_score numeric DEFAULT NULL::numeric,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."top_scores"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.transparency_report (
  tenant       uuid,
  period_start timestamp with time zone,
  period_end   timestamp with time zone
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."transparency_report"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unbilled_time (
  tenant   uuid,
  scope    jsonb DEFAULT NULL::jsonb,
  group_by text  DEFAULT 'subject'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."unbilled_time"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unchecked_push_tickets (
  max_items  integer  DEFAULT 1000,
  older_than interval DEFAULT '00:15:00'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."unchecked_push_tickets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.unread_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."unread_counts"($1) $function$;

CREATE OR REPLACE FUNCTION api.unreported_usage (
  max_rows     integer DEFAULT 500,
  skip_meters  text[]  DEFAULT '{}'::text[],
  skip_tenants uuid[]  DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."unreported_usage"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.usage_breakdown (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_breakdown"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_history (
  tenant    uuid,
  meter     text    DEFAULT NULL::text,
  max_rows  integer DEFAULT 100,
  before_id bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_history"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.usage_meters()
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_meters"() $function$;

CREATE OR REPLACE FUNCTION api.usage_overview (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_overview"($1) $function$;

CREATE OR REPLACE FUNCTION api.usage_quota (
  tenant uuid,
  meter  text
)
  RETURNS TABLE (
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."usage_quota"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_status (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_status"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_used (
  tenant uuid,
  meter  text,
  period text DEFAULT 'month'::text
)
  RETURNS numeric
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_used"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.usage_window (
  tenant uuid,
  period text DEFAULT 'month'::text
)
  RETURNS TABLE (
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."usage_window"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_window_start (
  tenant uuid,
  period text,
  day    date
)
  RETURNS date
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_window_start"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.user_disabled (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."user_disabled"($1) $function$;

CREATE OR REPLACE FUNCTION api.validate_document_template (
  document_type text,
  body          text,
  text_block    boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."validate_document_template"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.validate_workflow_graph (
  graph jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."validate_workflow_graph"($1) $function$;

CREATE OR REPLACE FUNCTION api.variant_identifiers (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."variant_identifiers"($1) $function$;

CREATE OR REPLACE FUNCTION api.variant_price (
  variant    uuid,
  currency   text,
  price_list uuid                     DEFAULT NULL::uuid,
  as_of      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."variant_price"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.variant_relations (
  variant uuid,
  kind    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."variant_relations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.verify_course_certificate (
  code text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."verify_course_certificate"($1) $function$;

CREATE OR REPLACE FUNCTION api.vote_summary (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."vote_summary"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.vote_tally (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."vote_tally"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.waitlist_admit (
  email text,
  code  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."waitlist_admit"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.webhook_secrets (
  endpoint uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."webhook_secrets"($1) $function$;

CREATE OR REPLACE FUNCTION api.wip_valuation (
  tenant uuid,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."wip_valuation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.within_quota (
  tenant   uuid,
  meter    text,
  quantity bigint DEFAULT 1
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."within_quota"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.work_item_tree (
  root uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."work_item_tree"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_admission_active (
  key text
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_admission_active"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_alerts_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_alerts_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_credential_get (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_credential_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_credentials_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_credentials_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definition_get (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definition_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definition_grants_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definition_grants_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definitions_list (
  tenant       uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definitions_list"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_graph_permissions (
  graph jsonb
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_graph_permissions"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_node_kinds_list()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_node_kinds_list"() $function$;

CREATE OR REPLACE FUNCTION api.workflow_node_runs_list (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_node_runs_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_run_get (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_run_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_run_principal (
  version uuid,
  tenant  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
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
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_runs_list"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.workflow_schedules_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_schedules_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_start_target (
  definition uuid,
  tenant     uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_start_target"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_steps_list()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_steps_list"() $function$;

CREATE OR REPLACE FUNCTION api.workflow_subject_start_target (
  definition   uuid,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_subject_start_target"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.workflow_triggers_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_triggers_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_version_get (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_version_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_versions_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_versions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_webhook_target (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_webhook_target"($1) $function$;

CREATE OR REPLACE FUNCTION api.yearly_giving_summary (
  tenant     uuid,
  donor_type text,
  donor_id   text,
  year       integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."yearly_giving_summary"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select r."id" from "better_supabase"."approval_requests" r
  where r."status" = 'pending'
    and (approval_eligible_ids.tenant is null or r."tenant_id" = approval_eligible_ids.tenant)
    and "better_supabase"."approval_eligible"(r."id")
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
  impersonation_reason text  DEFAULT NULL::text
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
      and l."organization_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event.target_type is not null and audit_event.record_id is not null then
    perform pg_catalog.set_config('bsb.recorded', coalesce(pg_catalog.current_setting('bsb.recorded', true), '') || E'\n' || audit_event.target_type || ':' || audit_event.record_id, true);
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
  impersonation_reason text  DEFAULT NULL::text
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
      and l."organization_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event_trusted.target_type is not null and audit_event_trusted.record_id is not null then
    perform pg_catalog.set_config('bsb.recorded', coalesce(pg_catalog.current_setting('bsb.recorded', true), '') || E'\n' || audit_event_trusted.target_type || ':' || audit_event_trusted.record_id, true);
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
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('bsb.recorded', true), '') || E'\n') > 0 then
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
    v_label := better_supabase.memo_get('audit.tenant_label.' || row_tenant::text);
    if v_label is null then
      v_label := (select o."name"::text from "public"."organizations" o where o."id" = row_tenant);
      perform better_supabase.memo_set('audit.tenant_label.' || row_tenant::text, coalesce(v_label, ''));
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
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    v_label,
    row_data ->> entry.label_column,
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
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
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
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('bsb.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
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
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('bsb.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
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
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('bsb.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
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
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
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

CREATE OR REPLACE FUNCTION better_supabase.end_sessions (
  p_user uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  ended int;
begin
  with gone as (
    delete from auth.sessions s where s.user_id = end_sessions.p_user returning s.id
  )
  select count(*)::int into ended from gone;
  delete from auth.refresh_tokens t where t.user_id = end_sessions.p_user::text;
  return ended;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_approvals (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  assigned     boolean                  DEFAULT false,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
  v_read boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approvals.tenant, 'approvals.read'), false);
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'mode', coalesce(x."policy" ->> 'mode', 'authorize'), 'fingerprint', x."fingerprint", 'consumedAt', x."consumed_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then x."id" in (select "better_supabase"."approval_eligible_ids"(list_approvals.tenant))
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'purchase_requisition', 'timesheet', 'expense_report', 'content_entry', 'care_plan_action', 'case', 'appraisal') or (case when x."subject_type" = 'drive_node' then coalesce(case when x."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((x."subject_id")::uuid, 'viewer') end, false) else case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end end))))) or x."id" in (select "better_supabase"."approval_eligible_ids"(list_approvals.tenant))
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."approval_eligible_ids"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approval_eligible_ids"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."end_sessions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."end_sessions"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_eligible_ids"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approval_eligible_ids"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."end_sessions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."end_sessions"(uuid) TO "service_role";
