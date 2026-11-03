SET local check_function_bodies = off;

DROP VIEW "api"."notification_preferences";

DROP VIEW "better_supabase"."maintenance_jobs";

ALTER TABLE "better_supabase"."accounting_account_roles"
  DROP CONSTRAINT "accounting_account_roles_role_check";

ALTER TABLE "better_supabase"."notification_deliveries"
  DROP CONSTRAINT "notification_deliveries_status_check";

CREATE TABLE "better_supabase"."accounting_recognition_rows" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "schedule_id" uuid                     NOT NULL,
  "tenant_id"   uuid                     NOT NULL,
  "due_on"      date                     NOT NULL,
  "amount"      bigint                   NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'pending'::text,
  "entry_id"    uuid,
  "posted_at"   timestamp with time zone,
  CONSTRAINT "accounting_recognition_rows_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "accounting_recognition_rows_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_recognition_rows_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text])))
);

ALTER TABLE "better_supabase"."accounting_recognition_rows"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_recognition_schedules" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"         uuid                     NOT NULL,
  "source_type"       text                     NOT NULL,
  "source_id"         text                     NOT NULL,
  "line_ref"          text                     NOT NULL DEFAULT ''::text,
  "amount"            bigint                   NOT NULL,
  "currency"          text                     NOT NULL,
  "starts_on"         date                     NOT NULL,
  "ends_on"           date                     NOT NULL,
  "deferral_entry_id" uuid,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_recognition_schedu_tenant_id_source_type_source__key" UNIQUE (tenant_id, source_type, source_id, line_ref),
  CONSTRAINT "accounting_recognition_schedules_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "accounting_recognition_schedules_check" CHECK ((ends_on >= starts_on)),
  CONSTRAINT "accounting_recognition_schedules_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_recognition_schedules_line_ref_check" CHECK ((length(line_ref) <= 200)),
  CONSTRAINT "accounting_recognition_schedules_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_recognition_schedules_source_id_check" CHECK (((length(source_id) >= 1) AND (length(source_id) <= 200))),
  CONSTRAINT "accounting_recognition_schedules_source_type_check" CHECK (((length(source_type) >= 1) AND (length(source_type) <= 100)))
);

ALTER TABLE "better_supabase"."accounting_recognition_schedules"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."commission_assignments" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "plan_id"      uuid                     NOT NULL,
  "seller_id"    uuid                     NOT NULL,
  "subject_type" text,
  "subject_id"   text,
  "starts_on"    date                     NOT NULL DEFAULT CURRENT_DATE,
  "ends_on"      date,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "commission_assignments_check1" CHECK (((ends_on IS NULL) OR (ends_on >= starts_on))),
  CONSTRAINT "commission_assignments_check" CHECK (((subject_type IS NULL) = (subject_id IS NULL))),
  CONSTRAINT "commission_assignments_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."commission_assignments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."commission_plans" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "kind"        text                     NOT NULL,
  "rate_bps"    integer,
  "tiers"       jsonb,
  "archived_at" timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "commission_plans_check" CHECK ((((kind = 'flat'::text) AND (rate_bps IS
    NOT NULL) AND (tiers IS NULL)) OR ((kind = 'tiered'::text) AND (rate_bps IS NULL) AND (tiers IS NOT NULL)))),
  CONSTRAINT "commission_plans_kind_check" CHECK ((kind = ANY (ARRAY['flat'::text, 'tiered'::text]))),
  CONSTRAINT "commission_plans_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "commission_plans_pkey" PRIMARY KEY (id),
  CONSTRAINT "commission_plans_rate_bps_check" CHECK (((rate_bps >= 0) AND (rate_bps <= 10000))),
  CONSTRAINT "commission_plans_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "commission_plans_tiers_check" CHECK (((tiers IS NULL) OR (jsonb_typeof(tiers) = 'array'::text)))
);

ALTER TABLE "better_supabase"."commission_plans"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."commission_statements" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"             uuid                     NOT NULL,
  "seller_id"             uuid                     NOT NULL,
  "currency"              text                     NOT NULL,
  "starts_on"             date                     NOT NULL,
  "ends_on"               date                     NOT NULL,
  "status"                text                     NOT NULL DEFAULT 'open'::text,
  "total"                 bigint                   NOT NULL DEFAULT 0,
  "ledger_transaction_id" uuid,
  "finalized_at"          timestamp with time zone,
  "paid_at"               timestamp with time zone,
  "paid_by"               uuid,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "commission_statements_check" CHECK ((ends_on >= starts_on)),
  CONSTRAINT "commission_statements_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "commission_statements_pkey" PRIMARY KEY (id),
  CONSTRAINT "commission_statements_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'finalized'::text, 'paid'::text]))),
  CONSTRAINT "commission_statements_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "commission_statements_tenant_id_seller_id_currency_starts_o_key" UNIQUE (tenant_id, seller_id, currency, starts_on)
);

ALTER TABLE "better_supabase"."commission_statements"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."commissions" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"             uuid                     NOT NULL,
  "plan_id"               uuid                     NOT NULL,
  "seller_id"             uuid                     NOT NULL,
  "source_type"           text                     NOT NULL,
  "source_id"             text                     NOT NULL,
  "basis"                 bigint                   NOT NULL,
  "amount"                bigint                   NOT NULL,
  "currency"              text                     NOT NULL,
  "occurred_on"           date                     NOT NULL,
  "status"                text                     NOT NULL DEFAULT 'accrued'::text,
  "statement_id"          uuid,
  "ledger_transaction_id" uuid,
  "reversed_at"           timestamp with time zone,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "commissions_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "commissions_basis_check" CHECK ((basis > 0)),
  CONSTRAINT "commissions_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "commissions_pkey" PRIMARY KEY (id),
  CONSTRAINT "commissions_source_id_check" CHECK (((length(source_id) >= 1) AND (length(source_id) <= 200))),
  CONSTRAINT "commissions_source_type_check" CHECK (((length(source_type) >= 1) AND (length(source_type) <= 100))),
  CONSTRAINT "commissions_status_check" CHECK ((status = ANY (ARRAY['accrued'::text, 'reversed'::text]))),
  CONSTRAINT "commissions_tenant_id_source_type_source_id_seller_id_key" UNIQUE (tenant_id, source_type, source_id, seller_id)
);

ALTER TABLE "better_supabase"."commissions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."notification_digests" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"             uuid                     NOT NULL,
  "organization_id"     uuid,
  "channel"             text                     NOT NULL,
  "cadence"             text                     NOT NULL,
  "items"               jsonb                    NOT NULL,
  "item_count"          integer                  NOT NULL,
  "status"              text                     NOT NULL DEFAULT 'pending'::text,
  "attempts"            integer                  NOT NULL DEFAULT 0,
  "attempted_at"        timestamp with time zone,
  "error"               text,
  "provider_message_id" text,
  "sent_at"             timestamp with time zone,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_digests_cadence_check" CHECK ((cadence = ANY (ARRAY['daily'::text, 'weekly'::text]))),
  CONSTRAINT "notification_digests_pkey" PRIMARY KEY (id),
  CONSTRAINT "notification_digests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'skipped'::text])))
);

ALTER TABLE "better_supabase"."notification_digests"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."referral_codes" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "code"          text                     NOT NULL,
  "referrer_id"   uuid                     NOT NULL,
  "invitation_id" uuid,
  "reward_amount" bigint                   NOT NULL DEFAULT 0,
  "reward_unit"   text,
  "max_uses"      integer,
  "uses"          integer                  NOT NULL DEFAULT 0,
  "active"        boolean                  NOT NULL DEFAULT true,
  "expires_at"    timestamp with time zone,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "referral_codes_check" CHECK (((reward_amount = 0) OR (reward_unit IS NOT NULL))),
  CONSTRAINT "referral_codes_code_check" CHECK ((code ~ '^[A-Z0-9]{4,32}$'::text)),
  CONSTRAINT "referral_codes_max_uses_check" CHECK (((max_uses IS NULL) OR (max_uses > 0))),
  CONSTRAINT "referral_codes_pkey" PRIMARY KEY (id),
  CONSTRAINT "referral_codes_reward_amount_check" CHECK ((reward_amount >= 0)),
  CONSTRAINT "referral_codes_reward_unit_check" CHECK (((reward_unit IS NULL) OR ((length(reward_unit) >= 1) AND (length(reward_unit) <= 32)))),
  CONSTRAINT "referral_codes_tenant_id_code_key" UNIQUE (tenant_id, code),
  CONSTRAINT "referral_codes_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."referral_codes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."referrals" (
  "id"                       uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"                uuid                     NOT NULL,
  "code_id"                  uuid                     NOT NULL,
  "referrer_id"              uuid                     NOT NULL,
  "referred_user_id"         uuid,
  "referred_organization_id" uuid,
  "referred_email"           text,
  "status"                   text                     NOT NULL DEFAULT 'attributed'::text,
  "reward_amount"            bigint                   NOT NULL DEFAULT 0,
  "reward_unit"              text,
  "qualified_at"             timestamp with time zone,
  "qualified_by"             text,
  "rewarded_at"              timestamp with time zone,
  "ledger_transaction_id"    uuid,
  "voided_at"                timestamp with time zone,
  "created_at"               timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "referrals_check" CHECK (((referred_user_id IS NOT NULL) OR (referred_organization_id IS NOT NULL) OR (referred_email IS NOT NULL))),
  CONSTRAINT "referrals_pkey" PRIMARY KEY (id),
  CONSTRAINT "referrals_referred_email_check" CHECK (((referred_email IS NULL) OR (length(referred_email) <= 320))),
  CONSTRAINT "referrals_reward_amount_check" CHECK ((reward_amount >= 0)),
  CONSTRAINT "referrals_status_check" CHECK ((status = ANY (ARRAY['attributed'::text, 'qualified'::text, 'rewarded'::text, 'void'::text])))
);

ALTER TABLE "better_supabase"."referrals"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."notification_preferences"
  ADD COLUMN "cadence" text NOT NULL DEFAULT 'immediate'::text;

CREATE OR REPLACE FUNCTION api.accrue_commission (
  tenant       uuid,
  seller_id    uuid,
  source_type  text,
  source_id    text,
  basis        bigint,
  currency     text,
  occurred_on  date   DEFAULT NULL::date,
  subject_type text   DEFAULT NULL::text,
  subject_id   text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accrue_commission"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.assign_commission_plan (
  tenant       uuid,
  plan_id      uuid,
  seller_id    uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  starts_on    date DEFAULT NULL::date,
  ends_on      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."assign_commission_plan"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.attribute_referral (
  tenant         uuid,
  code           text,
  referred_user  uuid DEFAULT NULL::uuid,
  referred_org   uuid DEFAULT NULL::uuid,
  referred_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."attribute_referral"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.build_commission_statement (
  tenant    uuid,
  seller_id uuid,
  currency  text,
  starts_on date,
  ends_on   date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."build_commission_statement"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.claim_notification_digests (
  max_items    integer  DEFAULT 50,
  lease        interval DEFAULT '00:05:00'::interval,
  max_attempts integer  DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_notification_digests"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.commission_accrue (
  tenant       uuid,
  seller_id    uuid,
  source_type  text,
  source_id    text,
  basis        bigint,
  currency     text,
  occurred_on  date   DEFAULT NULL::date,
  subject_type text   DEFAULT NULL::text,
  subject_id   text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_accrue"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.commission_amount (
  kind     text,
  rate_bps integer,
  tiers    jsonb,
  prior    bigint,
  basis    bigint
)
  RETURNS bigint
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_amount"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.commission_close_range (
  tenant    uuid,
  starts_on date,
  ends_on   date
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_close_range"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.commission_payroll_lines (
  tenant    uuid,
  from_date date,
  to_date   date
)
  RETURNS jsonb
  LANGUAGE sql
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
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_plan_for"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.commission_statement_build (
  tenant    uuid,
  seller_id uuid,
  currency  text,
  starts_on date,
  ends_on   date
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_statement_build"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.commission_statement_finalize (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_statement_finalize"($1) $function$;

CREATE OR REPLACE FUNCTION api.commission_tiers_valid (
  tiers jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."commission_tiers_valid"($1) $function$;

CREATE OR REPLACE FUNCTION api.complete_notification_digest (
  digest              uuid,
  status              text,
  provider_message_id text    DEFAULT NULL::text,
  error               text    DEFAULT NULL::text,
  max_attempts        integer DEFAULT 5
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_notification_digest"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.create_referral_code (
  tenant        uuid,
  referrer_id   uuid                     DEFAULT NULL::uuid,
  code          text                     DEFAULT NULL::text,
  invitation_id uuid                     DEFAULT NULL::uuid,
  reward_amount bigint                   DEFAULT 0,
  reward_unit   text                     DEFAULT NULL::text,
  max_uses      integer                  DEFAULT NULL::integer,
  expires_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_referral_code"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.end_commission_assignment (
  assignment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."end_commission_assignment"($1) $function$;

CREATE OR REPLACE FUNCTION api.finalize_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."finalize_commission_statement"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_commission_statement"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_commission_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commission_plans"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_commission_statements (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commission_statements"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_commissions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_commissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_referral_codes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_referral_codes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_referrals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_referrals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.notification_cadence (
  member  uuid,
  tenant  uuid,
  type    text,
  channel text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_cadence"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.pay_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pay_commission_statement"($1) $function$;

CREATE OR REPLACE FUNCTION api.qualify_referral (
  tenant        uuid,
  referred_user uuid DEFAULT NULL::uuid,
  referred_org  uuid DEFAULT NULL::uuid,
  source        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."qualify_referral"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.referral_attribute (
  tenant         uuid,
  code           text,
  referred_user  uuid DEFAULT NULL::uuid,
  referred_org   uuid DEFAULT NULL::uuid,
  referred_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."referral_attribute"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.requires_consent (
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."requires_consent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.reverse_commission (
  commission_id uuid,
  reason        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reverse_commission"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.run_notification_digests (
  max_digests integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."run_notification_digests"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_commission_plan (
  tenant   uuid,
  name     text,
  kind     text,
  rate_bps integer DEFAULT NULL::integer,
  tiers    jsonb   DEFAULT NULL::jsonb,
  plan_id  uuid    DEFAULT NULL::uuid,
  archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_commission_plan"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.seed_accounting_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_accounting_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.seed_attachments_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_attachments_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.seed_calendar_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_calendar_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.seed_inbox_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_inbox_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.seed_pipelines_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_pipelines_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_notification_cadence (
  type    text,
  channel text,
  cadence text,
  tenant  uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_notification_cadence"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.void_referral (
  referral_id uuid,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."void_referral"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accrue_commission (
  tenant       uuid,
  seller_id    uuid,
  source_type  text,
  source_id    text,
  basis        bigint,
  currency     text,
  occurred_on  date   DEFAULT NULL::date,
  subject_type text   DEFAULT NULL::text,
  subject_id   text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (accrue_commission.tenant is not null and coalesce(better_supabase.can('tenant', accrue_commission.tenant, 'commissions.write'), false))) then
    raise exception 'not allowed to accrue commissions' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return "better_supabase"."commission_accrue"(accrue_commission.tenant, accrue_commission.seller_id, accrue_commission.source_type, accrue_commission.source_id,
    accrue_commission.basis, accrue_commission.currency, accrue_commission.occurred_on, accrue_commission.subject_type, accrue_commission.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_commission_plan (
  tenant       uuid,
  plan_id      uuid,
  seller_id    uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  starts_on    date DEFAULT NULL::date,
  ends_on      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."commission_assignments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (assign_commission_plan.tenant is not null and coalesce(better_supabase.can('tenant', assign_commission_plan.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to assign commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if assign_commission_plan.seller_id is null or (assign_commission_plan.subject_type is null) <> (assign_commission_plan.subject_id is null)
    or (assign_commission_plan.ends_on is not null and assign_commission_plan.ends_on < coalesce(assign_commission_plan.starts_on, current_date)) then
    raise exception 'an assignment needs a seller, a subject with both parts and a range that ends after it starts' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."commission_plans" x
    where x."id" = assign_commission_plan.plan_id and x."tenant_id" = assign_commission_plan.tenant and x."archived_at" is null
  ) then
    raise exception 'no such open commission plan' using errcode = 'P0002', hint = 'COMMISSION_PLAN_NOT_FOUND';
  end if;
  insert into "better_supabase"."commission_assignments" ("tenant_id", "plan_id", "seller_id", "subject_type", "subject_id", "starts_on", "ends_on")
  values (assign_commission_plan.tenant, assign_commission_plan.plan_id, assign_commission_plan.seller_id, assign_commission_plan.subject_type,
    assign_commission_plan.subject_id, coalesce(assign_commission_plan.starts_on, current_date), assign_commission_plan.ends_on)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'planId', v_row."plan_id", 'sellerId', v_row."seller_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attribute_referral (
  tenant         uuid,
  code           text,
  referred_user  uuid DEFAULT NULL::uuid,
  referred_org   uuid DEFAULT NULL::uuid,
  referred_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.build_commission_statement (
  tenant    uuid,
  seller_id uuid,
  currency  text,
  starts_on date,
  ends_on   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_statement "better_supabase"."commission_statements";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (build_commission_statement.tenant is not null and coalesce(better_supabase.can('tenant', build_commission_statement.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to build commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if build_commission_statement.seller_id is null or upper(build_commission_statement.currency) !~ '^[A-Z]{3}$'
    or build_commission_statement.starts_on is null or build_commission_statement.ends_on is null
    or build_commission_statement.ends_on < build_commission_statement.starts_on then
    raise exception 'a statement needs a seller, a currency code and a range that ends on or after it starts' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  v_id := "better_supabase"."commission_statement_build"(build_commission_statement.tenant, build_commission_statement.seller_id,
    upper(build_commission_statement.currency), build_commission_statement.starts_on, build_commission_statement.ends_on);
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = v_id;
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
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
    'email', u.email,
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

CREATE OR REPLACE FUNCTION better_supabase.close_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."periods" x where x."id" = close_period.period_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.read'), false))) then
    raise exception 'no such period' using errcode = 'P0002', hint = 'PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.manage'), false))) then
    raise exception 'not allowed to close periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  v_blockers := "better_supabase"."period_close_blockers"(v_row."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'PERIOD_CLOSE_BLOCKED', detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
  end if;
  if v_row."kind" = 'fiscal_period' then
    perform "better_supabase"."accounting_close_range"(v_row."tenant_id", v_row."starts_on", v_row."ends_on");
  end if;
  if v_row."kind" = 'commission_period' then
    perform "better_supabase"."commission_close_range"(v_row."tenant_id", v_row."starts_on", v_row."ends_on");
  end if;
  update "better_supabase"."periods" x set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('period.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status"), 'periods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/periods');
  perform better_supabase.audit_event(
    event_type => 'period.closed',
    category => 'data',
    target_type => 'period',
    record_id => v_row."id"::text,
    target_label => v_row."kind" || ' ' || v_row."starts_on"::text,
    summary => 'period closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_accrue (
  tenant       uuid,
  seller_id    uuid,
  source_type  text,
  source_id    text,
  basis        bigint,
  currency     text,
  occurred_on  date   DEFAULT NULL::date,
  subject_type text   DEFAULT NULL::text,
  subject_id   text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_entry "better_supabase"."commissions";
  v_plan "better_supabase"."commission_plans";
  v_on date := coalesce(commission_accrue.occurred_on, current_date);
  v_currency text := upper(commission_accrue.currency);
  v_prior bigint;
  v_amount bigint;
  v_tx uuid;
begin
  if commission_accrue.seller_id is null or nullif(trim(commission_accrue.source_type), '') is null
    or nullif(trim(commission_accrue.source_id), '') is null or coalesce(commission_accrue.basis, 0) <= 0
    or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'a commission needs a seller, a source, a positive basis and a currency code' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(commission_accrue.tenant::text || commission_accrue.seller_id::text, 0));
  select * into v_entry from "better_supabase"."commissions" x
  where x."tenant_id" = commission_accrue.tenant and x."source_type" = commission_accrue.source_type
    and x."source_id" = commission_accrue.source_id and x."seller_id" = commission_accrue.seller_id;
  if found then
    return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
  end if;
  select y.* into v_plan from "better_supabase"."commission_plans" y
  where y."id" = "better_supabase"."commission_plan_for"(commission_accrue.tenant, commission_accrue.seller_id, commission_accrue.subject_type, commission_accrue.subject_id, v_on);
  if not found then
    return null;
  end if;
  select coalesce(sum(x."basis"), 0) into v_prior from "better_supabase"."commissions" x
  where x."tenant_id" = commission_accrue.tenant and x."seller_id" = commission_accrue.seller_id
    and x."plan_id" = v_plan."id" and x."currency" = v_currency and x."status" = 'accrued'
    and date_trunc('month', x."occurred_on"::timestamp) = date_trunc('month', v_on::timestamp);
  v_amount := "better_supabase"."commission_amount"(v_plan."kind", v_plan."rate_bps", v_plan."tiers", v_prior, commission_accrue.basis);
  if v_amount <= 0 then
    return null;
  end if;
  v_tx := "better_supabase"."ledger_post"(commission_accrue.tenant, 'commission.accrual',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(commission_accrue.tenant, 'expense', 'commissions:expense:' || v_currency::text, 'Commissions', v_currency::text, 0::smallint, null, null, null, true, 'commissions.read', 'commissions', null), 'amount', (-v_amount)::text),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(commission_accrue.tenant, 'payable', 'commissions:payable:' || commission_accrue.seller_id::text || ':' || v_currency::text, 'Commissions payable', v_currency::text, 0::smallint, null, null, commission_accrue.seller_id, true, 'commissions.read', 'commissions', null), 'amount', v_amount::text)),
    'commissions', commission_accrue.source_type || '/' || commission_accrue.source_id, null,
    'commission:' || commission_accrue.source_type || ':' || commission_accrue.source_id || ':' || commission_accrue.seller_id::text,
    v_on::timestamptz,
    jsonb_build_object('sellerId', commission_accrue.seller_id, 'planId', v_plan."id"));
  insert into "better_supabase"."commissions" ("tenant_id", "plan_id", "seller_id", "source_type", "source_id", "basis", "amount", "currency", "occurred_on", "ledger_transaction_id")
  values (commission_accrue.tenant, v_plan."id", commission_accrue.seller_id, commission_accrue.source_type, commission_accrue.source_id,
    commission_accrue.basis, v_amount, v_currency, v_on, v_tx)
  returning * into v_entry;
  perform "better_supabase".emit_event('commission.accrued', jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency"), 'commissions/' || v_entry."id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission.accrued',
    category => 'billing',
    target_type => 'commission',
    record_id => v_entry."id"::text,
    summary => 'accrued a commission',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency")
  );
  return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_amount (
  kind     text,
  rate_bps integer,
  tiers    jsonb,
  prior    bigint,
  basis    bigint
)
  RETURNS bigint
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tier jsonb;
  v_lower numeric := 0;
  v_upper numeric;
  v_before numeric := 0;
  v_after numeric := 0;
begin
  if commission_amount.kind = 'flat' then
    return round(commission_amount.basis * commission_amount.rate_bps / 10000.0)::bigint;
  end if;
  for v_tier in
    select t.value from jsonb_array_elements(commission_amount.tiers) with ordinality as t(value, n) order by t.n
  loop
    v_upper := (v_tier ->> 'upTo')::numeric;
    v_before := v_before + greatest(0, least(coalesce(v_upper, commission_amount.prior), commission_amount.prior) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    v_after := v_after + greatest(0, least(coalesce(v_upper, commission_amount.prior + commission_amount.basis), commission_amount.prior + commission_amount.basis) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    exit when v_upper is null;
    v_lower := v_upper;
  end loop;
  return round(v_after)::bigint - round(v_before)::bigint;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_close_range (
  tenant    uuid,
  starts_on date,
  ends_on   date
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row record;
  v_id uuid;
begin
  for v_row in
    select distinct x."seller_id" as seller, x."currency" as currency from "better_supabase"."commissions" x
    where x."tenant_id" = commission_close_range.tenant and x."status" = 'accrued' and x."statement_id" is null
      and x."occurred_on" between commission_close_range.starts_on and commission_close_range.ends_on
  loop
    perform "better_supabase"."commission_statement_build"(commission_close_range.tenant, v_row.seller, v_row.currency, commission_close_range.starts_on, commission_close_range.ends_on);
  end loop;
  for v_id in
    select x."id" from "better_supabase"."commission_statements" x
    where x."tenant_id" = commission_close_range.tenant and x."status" = 'open'
      and x."starts_on" >= commission_close_range.starts_on and x."ends_on" <= commission_close_range.ends_on
  loop
    perform "better_supabase"."commission_statement_finalize"(v_id);
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_payroll_lines (
  tenant    uuid,
  from_date date,
  to_date   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (commission_payroll_lines.tenant is not null and coalesce(better_supabase.can('tenant', commission_payroll_lines.tenant, 'commissions.read'), false))) then
    raise exception 'not allowed to read commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('userId', y.seller, 'currency', y.currency, 'amount', y.amount::text, 'statementIds', y.ids) order by y.seller, y.currency)
    from (
      select x."seller_id" as seller, x."currency" as currency, sum(x."total") as amount, jsonb_agg(x."id" order by x."ends_on") as ids
      from "better_supabase"."commission_statements" x
      where x."tenant_id" = commission_payroll_lines.tenant and x."status" in ('finalized', 'paid')
        and x."ends_on" between commission_payroll_lines.from_date and commission_payroll_lines.to_date and x."total" > 0
      group by x."seller_id", x."currency"
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_plan_for (
  tenant       uuid,
  seller_id    uuid,
  subject_type text,
  subject_id   text,
  on_date      date
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."plan_id" from "better_supabase"."commission_assignments" x
  join "better_supabase"."commission_plans" y on y."id" = x."plan_id" and y."archived_at" is null
  where x."tenant_id" = commission_plan_for.tenant and x."seller_id" = commission_plan_for.seller_id
    and x."starts_on" <= commission_plan_for.on_date and (x."ends_on" is null or x."ends_on" >= commission_plan_for.on_date)
    and (x."subject_type" is null or (x."subject_type" = commission_plan_for.subject_type and x."subject_id" = commission_plan_for.subject_id))
  order by (x."subject_type" is not null) desc, x."starts_on" desc, x."created_at" desc
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_statement_build (
  tenant    uuid,
  seller_id uuid,
  currency  text,
  starts_on date,
  ends_on   date
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x
  where x."tenant_id" = commission_statement_build.tenant and x."seller_id" = commission_statement_build.seller_id
    and x."currency" = commission_statement_build.currency and x."starts_on" = commission_statement_build.starts_on
  for update;
  if found and v_statement."status" <> 'open' then
    raise exception 'the statement of this range is no longer open' using errcode = '55000', hint = 'COMMISSION_STATEMENT_LOCKED';
  end if;
  if not found then
    insert into "better_supabase"."commission_statements" ("tenant_id", "seller_id", "currency", "starts_on", "ends_on")
    values (commission_statement_build.tenant, commission_statement_build.seller_id, commission_statement_build.currency,
      commission_statement_build.starts_on, commission_statement_build.ends_on)
    returning * into v_statement;
  end if;
  update "better_supabase"."commissions" x set "statement_id" = v_statement."id"
  where x."tenant_id" = commission_statement_build.tenant and x."seller_id" = commission_statement_build.seller_id
    and x."currency" = commission_statement_build.currency and x."status" = 'accrued' and x."statement_id" is null
    and x."occurred_on" between commission_statement_build.starts_on and commission_statement_build.ends_on;
  update "better_supabase"."commission_statements" x set "ends_on" = commission_statement_build.ends_on, "total" = coalesce((select sum(e."amount") from "better_supabase"."commissions" e where e."statement_id" = x."id" and e."status" = 'accrued'), 0)
  where x."id" = v_statement."id";
  return v_statement."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_statement_finalize (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = commission_statement_finalize.statement_id for update;
  if not found then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if v_statement."status" <> 'open' then
    return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
  end if;
  update "better_supabase"."commission_statements" x set "status" = 'finalized', "finalized_at" = now(), "total" = coalesce((select sum(e."amount") from "better_supabase"."commissions" e where e."statement_id" = x."id" and e."status" = 'accrued'), 0)
  where x."id" = v_statement."id" returning * into v_statement;
  perform "better_supabase".emit_event('commission_statement.finalized', jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status"), 'commission-statements/' || v_statement."id"::text, (v_statement."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_statement.finalized',
    category => 'billing',
    target_type => 'commission_statement',
    record_id => v_statement."id"::text,
    summary => 'finalized a commission statement',
    tenant => (v_statement."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status")
  );
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commission_tiers_valid (
  tiers jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_tier jsonb;
  v_last numeric := 0;
  v_count integer;
  v_n integer := 0;
begin
  if jsonb_typeof(commission_tiers_valid.tiers) is distinct from 'array' then
    return false;
  end if;
  v_count := jsonb_array_length(commission_tiers_valid.tiers);
  if v_count = 0 or v_count > 50 then
    return false;
  end if;
  for v_tier in select t.value from jsonb_array_elements(commission_tiers_valid.tiers) with ordinality as t(value, n) order by t.n loop
    v_n := v_n + 1;
    if jsonb_typeof(v_tier) is distinct from 'object'
      or coalesce(v_tier ->> 'bps', '') !~ '^[0-9]{1,5}$' or (v_tier ->> 'bps')::integer > 10000 then
      return false;
    end if;
    if v_tier ->> 'upTo' is null then
      return v_n = v_count;
    end if;
    if v_tier ->> 'upTo' !~ '^[0-9]{1,18}$' or (v_tier ->> 'upTo')::numeric <= v_last then
      return false;
    end if;
    v_last := (v_tier ->> 'upTo')::numeric;
  end loop;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_notification_digest (
  digest              uuid,
  status              text,
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
  v_outcome text := complete_notification_digest.status;
begin
  if v_outcome is null or v_outcome not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'status must be sent, failed, skipped or pending' using errcode = '22023', hint = 'NOTIFICATION_STATUS_UNKNOWN';
  end if;
  if v_outcome = 'pending' and exists (
    select 1 from "better_supabase"."notification_digests" x
    where x."id" = complete_notification_digest.digest
      and x."attempts" >= greatest(1, coalesce(complete_notification_digest.max_attempts, 5))
  ) then
    v_outcome := 'failed';
  end if;
  update "better_supabase"."notification_digests" x set "status" = v_outcome,
    "provider_message_id" = coalesce(complete_notification_digest.provider_message_id, x."provider_message_id"),
    "error" = complete_notification_digest.error,
    "sent_at" = case when v_outcome = 'sent' then now() else x."sent_at" end,
    "attempted_at" = case when v_outcome = 'pending' then null else x."attempted_at" end
  where x."id" = complete_notification_digest.digest;
  return v_outcome;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.consent_missing (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_purpose uuid;
  v_basis text;
begin
  if purpose_key is null or tenant is null then
    return false;
  end if;
  select x."id", x."legal_basis"::text into v_purpose, v_basis from "better_supabase"."consent_purposes" x
  where x."key" = purpose_key
    and (x."tenant_id" = tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  if v_purpose is null or v_basis <> 'consent' then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."consents" x
    where x."tenant_id" = tenant and x."purpose_id" = v_purpose
      and x."subject_type" = subject_type and x."subject_id" = subject_id
      and (x."status" = 'granted' and (x."valid_until" is null or x."valid_until" > now()))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_organization (
  attrs jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "public"."organizations" ("name", "slug")
  select r."name", r."slug"
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  returning "id" into organization;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, (select r."id" from "better_supabase"."roles" r where (r."id"::text = ('owner')::text or r."key" = ('owner')::text) order by (r."id"::text = ('owner')::text) desc limit 1));
  perform "better_supabase"."seed_tenant_defaults"(organization);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  perform "better_supabase".emit_event('organization.created', jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  perform better_supabase.audit_event(
    event_type => 'organization.created',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner')
  );
  return organization;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_referral_code (
  tenant        uuid,
  referrer_id   uuid                     DEFAULT NULL::uuid,
  code          text                     DEFAULT NULL::text,
  invitation_id uuid                     DEFAULT NULL::uuid,
  reward_amount bigint                   DEFAULT 0,
  reward_unit   text                     DEFAULT NULL::text,
  max_uses      integer                  DEFAULT NULL::integer,
  expires_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  perform "better_supabase".emit_event('referral_code.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id"), 'referral-codes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral_code.created',
    category => 'data',
    target_type => 'referral_code',
    record_id => v_row."id"::text,
    target_label => v_row."code",
    summary => 'created a referral code',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
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
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.default_pipeline (
  tenant       uuid,
  subject_type text,
  scope_id     text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  case default_pipeline.subject_type
    when 'deal' then
      begin
        perform "better_supabase"."seed_pipelines_defaults"(default_pipeline.tenant, 'b2b-sales');
      exception when unique_violation then
        null;
      end;
      select x."id" into v_id from "better_supabase"."pipelines" x
      where x."tenant_id" = default_pipeline.tenant
        and x."subject_type" = default_pipeline.subject_type
        and x."scope_id" is null
        and x."archived_at" is null
      order by x."is_default" desc, x."rank" collate "C"
      limit 1;
    when 'work_item' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('triage', 'Triage', 'triage', 'open', null::smallint, '7'),
          ('backlog', 'Backlog', 'backlog', 'open', null::smallint, 'E'),
          ('todo', 'Todo', 'unstarted', 'open', null::smallint, 'L'),
          ('in_progress', 'In progress', 'started', 'open', null::smallint, 'S'),
          ('in_review', 'In review', 'started', 'open', null::smallint, 'Z'),
          ('done', 'Done', 'completed', 'success', null::smallint, 'g'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
    when 'maintenance_request' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('triage', 'Triage', 'triage', 'open', null::smallint, '7'),
          ('backlog', 'Backlog', 'backlog', 'open', null::smallint, 'E'),
          ('todo', 'Todo', 'unstarted', 'open', null::smallint, 'L'),
          ('in_progress', 'In progress', 'started', 'open', null::smallint, 'S'),
          ('in_review', 'In review', 'started', 'open', null::smallint, 'Z'),
          ('done', 'Done', 'completed', 'success', null::smallint, 'g'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
    when 'application' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('applied', 'Applied', 'active', 'open', null::smallint, '7'),
          ('screening', 'Screening', 'active', 'open', null::smallint, 'E'),
          ('interview', 'Interview', 'active', 'open', null::smallint, 'L'),
          ('offer', 'Offer', 'active', 'open', null::smallint, 'S'),
          ('hired', 'Hired', 'hired', 'success', null::smallint, 'Z'),
          ('rejected', 'Rejected', 'rejected', 'failure', null::smallint, 'g'),
          ('withdrawn', 'Withdrawn', 'withdrawn', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
    when 'case' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('reported', 'Reported', 'open', 'open', null::smallint, '8'),
          ('investigating', 'Investigating', 'open', 'open', null::smallint, 'G'),
          ('acting', 'Acting', 'open', 'open', null::smallint, 'O'),
          ('verifying', 'Verifying', 'open', 'open', null::smallint, 'W'),
          ('closed', 'Closed', 'closed', 'success', null::smallint, 'e'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'm')
      ) x(key, name, category, outcome, probability, rank);
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_commission_assignment (
  assignment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."commission_assignments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."commission_assignments" x where x."id" = end_commission_assignment.assignment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such assignment' using errcode = 'P0002', hint = 'COMMISSION_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to assign commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  update "better_supabase"."commission_assignments" x set "ends_on" = greatest(current_date, x."starts_on")
  where x."id" = v_row."id" and (x."ends_on" is null or x."ends_on" > current_date)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'planId', v_row."plan_id", 'sellerId', v_row."seller_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finalize_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."commission_statements" x where x."id" = finalize_commission_statement.statement_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'commissions.read'), false))) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to finalize commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return "better_supabase"."commission_statement_finalize"(finalize_commission_statement.statement_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = get_commission_statement.statement_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.read'), false))) or v_statement."seller_id" = (select auth.uid())) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at") || jsonb_build_object('entries', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'planId', y."plan_id", 'sellerId', y."seller_id", 'sourceType', y."source_type", 'sourceId', y."source_id", 'basis', y."basis"::text, 'amount', y."amount"::text, 'currency', y."currency", 'occurredOn', y."occurred_on", 'status', y."status", 'statementId', y."statement_id", 'ledgerTransactionId', y."ledger_transaction_id", 'reversedAt', y."reversed_at", 'createdAt', y."created_at") order by y."occurred_on", y."created_at")
    from "better_supabase"."commissions" y where y."statement_id" = v_statement."id"
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commission_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_plans.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_plans.tenant, 'commissions.read'), false))) then
    raise exception 'not allowed to read commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'kind', y."kind", 'rateBps', y."rate_bps", 'tiers', y."tiers", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = y."id"
      ), '[]'::jsonb)) order by y."created_at" desc)
    from (
      select * from "better_supabase"."commission_plans" z
      where z."tenant_id" = list_commission_plans.tenant
        and (coalesce((v_filters ->> 'archived')::boolean, false) or z."archived_at" is null)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commission_statements (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_statements.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_statements.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_statements.tenant, 'commissions.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sellerId', y."seller_id", 'currency', y."currency", 'startsOn', y."starts_on", 'endsOn', y."ends_on", 'status', y."status", 'total', y."total"::text, 'ledgerTransactionId', y."ledger_transaction_id", 'finalizedAt', y."finalized_at", 'paidAt', y."paid_at", 'paidBy', y."paid_by", 'createdAt', y."created_at") order by y."ends_on" desc, y."created_at" desc)
    from (
      select * from "better_supabase"."commission_statements" z
      where z."tenant_id" = list_commission_statements.tenant
        and (v_all or z."seller_id" = (select auth.uid()))
        and (not v_filters ? 'seller' or z."seller_id" = (v_filters ->> 'seller')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."ends_on" desc, z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commissions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commissions.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commissions.tenant is not null and coalesce(better_supabase.can('tenant', list_commissions.tenant, 'commissions.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'planId', y."plan_id", 'sellerId', y."seller_id", 'sourceType', y."source_type", 'sourceId', y."source_id", 'basis', y."basis"::text, 'amount', y."amount"::text, 'currency', y."currency", 'occurredOn', y."occurred_on", 'status', y."status", 'statementId', y."statement_id", 'ledgerTransactionId', y."ledger_transaction_id", 'reversedAt', y."reversed_at", 'createdAt', y."created_at") order by y."occurred_on" desc, y."created_at" desc)
    from (
      select * from "better_supabase"."commissions" z
      where z."tenant_id" = list_commissions.tenant
        and (v_all or z."seller_id" = (select auth.uid()))
        and (not v_filters ? 'seller' or z."seller_id" = (v_filters ->> 'seller')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."occurred_on" desc, z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
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
    'cadence', p."cadence",
    'tenant', p."organization_id"
  ) order by p."organization_id" nulls first, p."type", p."channel"), '[]')
  from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and (list_notification_preferences.tenant is null or p."organization_id" is null or p."organization_id" = list_notification_preferences.tenant)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_referral_codes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_referrals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_user_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_cadence (
  member  uuid,
  tenant  uuid,
  type    text,
  channel text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select p."cadence" from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_cadence.member
      and p."channel" = notification_cadence.channel
      and (p."type" = notification_cadence.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_cadence.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), 'immediate')
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
    select p."enabled" and p."cadence" is distinct from 'off'
    from "better_supabase"."notification_preferences" p
    where p."user_id" = notification_enabled.member
      and p."channel" = notification_enabled.channel
      and (p."type" = notification_enabled.type or p."type" = '*')
      and (p."organization_id" is null or p."organization_id" = notification_enabled.tenant)
    order by p."organization_id" is null, p."type" = '*'
    limit 1
  ), case notification_enabled.channel when 'in_app' then true else false end)
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
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
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
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
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
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
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
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
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

CREATE OR REPLACE FUNCTION better_supabase.pay_commission_statement (
  statement_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = pay_commission_statement.statement_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to pay commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_statement."status" = 'paid' then
    return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
  end if;
  if v_statement."status" <> 'finalized' then
    raise exception 'finalize the statement before paying it' using errcode = '55000', hint = 'COMMISSION_STATEMENT_OPEN';
  end if;
  if v_statement."total" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_statement."tenant_id", 'commission.payout',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_statement."tenant_id", 'payable', 'commissions:payable:' || v_statement."seller_id"::text || ':' || v_statement."currency"::text, 'Commissions payable', v_statement."currency"::text, 0::smallint, null, null, v_statement."seller_id", true, 'commissions.read', 'commissions', null), 'amount', (-v_statement."total")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_statement."tenant_id", 'paid', 'commissions:paid:' || v_statement."currency"::text, 'Commissions paid', v_statement."currency"::text, 0::smallint, null, null, null, true, 'commissions.read', 'commissions', null), 'amount', v_statement."total"::text)),
      'commission-statements', v_statement."id"::text, null,
      'commission-statement:' || v_statement."id"::text, null,
      jsonb_build_object('sellerId', v_statement."seller_id"));
  end if;
  update "better_supabase"."commission_statements" x set "status" = 'paid', "paid_at" = now(), "paid_by" = auth.uid(), "ledger_transaction_id" = v_tx
  where x."id" = v_statement."id" returning * into v_statement;
  perform "better_supabase".emit_event('commission_statement.paid', jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status"), 'commission-statements/' || v_statement."id"::text, (v_statement."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_statement.paid',
    category => 'billing',
    target_type => 'commission_statement',
    record_id => v_statement."id"::text,
    summary => 'paid a commission statement',
    tenant => (v_statement."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status")
  );
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.period_for (
  tenant  uuid,
  kind    text,
  on_date date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (period_for.tenant is not null and coalesce(better_supabase.can('tenant', period_for.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."periods" x
  where x."tenant_id" = period_for.tenant and x."kind" = period_for.kind
    and period_for.on_date between x."starts_on" and x."ends_on";
  if found then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  if period_for.kind = 'commission_period' then
      insert into "better_supabase"."periods" ("tenant_id", "kind", "starts_on", "ends_on")
      values (period_for.tenant, period_for.kind, date_trunc('month', period_for.on_date::timestamp)::date, (date_trunc('month', period_for.on_date::timestamp) + case 'month' when 'week' then interval '1 week' when 'month' then interval '1 month' when 'quarter' then interval '3 months' else interval '1 year' end - interval '1 day')::date)
      on conflict do nothing;
      select * into v_row from "better_supabase"."periods" x
      where x."tenant_id" = period_for.tenant and x."kind" = period_for.kind
        and period_for.on_date between x."starts_on" and x."ends_on";
    end if;
  if v_row."id" is null then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.qualify_referral (
  tenant        uuid,
  referred_user uuid DEFAULT NULL::uuid,
  referred_org  uuid DEFAULT NULL::uuid,
  source        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_user_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.qualified', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.qualified',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral qualified',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    perform "better_supabase".emit_event('referral.rewarded', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.rewarded',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral rewarded',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit")
  );
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.referral_attribute (
  tenant         uuid,
  code           text,
  referred_user  uuid DEFAULT NULL::uuid,
  referred_org   uuid DEFAULT NULL::uuid,
  referred_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_user_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_user_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  perform "better_supabase".emit_event('referral.attributed', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.attributed',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral attributed',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
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
  from "better_supabase"."commission_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.commission_assignments', v_rows);
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

CREATE OR REPLACE FUNCTION better_supabase.requires_consent (
  subject_type text,
  subject_id   text,
  purpose_key  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case requires_consent.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (requires_consent.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (requires_consent.subject_id)::uuid)
      else null::text
    end))::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(requires_consent.subject_type, requires_consent.subject_id, 'read'), false))
      or ((v_tenant)::text, (requires_consent.subject_type)::text, (requires_consent.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (requires_consent.subject_type)::text, (requires_consent.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = requires_consent.subject_type and r."target_id" = (requires_consent.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    return true;
  end if;
  return "better_supabase"."consent_missing"(v_tenant, subject_type, subject_id, purpose_key);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_commission (
  commission_id uuid,
  reason        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_entry "better_supabase"."commissions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_entry from "better_supabase"."commissions" x where x."id" = reverse_commission.commission_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_entry."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_entry."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such commission' using errcode = 'P0002', hint = 'COMMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_entry."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_entry."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to reverse commissions' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_entry."status" = 'reversed' then
    return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
  end if;
  if v_entry."statement_id" is not null then
    select y."status" into v_status from "better_supabase"."commission_statements" y where y."id" = v_entry."statement_id";
    if v_status <> 'open' then
      raise exception 'the commission is on a statement that is no longer open' using errcode = '55000', hint = 'COMMISSION_STATEMENT_LOCKED';
    end if;
  end if;
  perform "better_supabase"."ledger_post"(v_entry."tenant_id", 'commission.reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_entry."ledger_transaction_id"),
    'commissions', v_entry."source_type" || '/' || v_entry."source_id", nullif(trim(reverse_commission.reason), ''),
    'commission-reversal:' || v_entry."id"::text, null,
    jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_commission.reason), '')),
    v_entry."ledger_transaction_id");
  update "better_supabase"."commissions" x set "status" = 'reversed', "reversed_at" = now()
  where x."id" = v_entry."id" returning * into v_entry;
  if v_entry."statement_id" is not null then
    update "better_supabase"."commission_statements" y set "total" = coalesce((select sum(x."amount") from "better_supabase"."commissions" x where x."statement_id" = y."id" and x."status" = 'accrued'), 0)
    where y."id" = v_entry."statement_id";
  end if;
  perform "better_supabase".emit_event('commission.reversed', jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency"), 'commissions/' || v_entry."id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission.reversed',
    category => 'billing',
    target_type => 'commission',
    record_id => v_entry."id"::text,
    summary => 'reversed a commission',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency")
  );
  return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.run_due_sequences (
  max_count integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_due uuid;
  v_row "better_supabase"."enrollments";
  v_sequence "better_supabase"."sequences";
  v_current text;
  v_next_run timestamptz;
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x."id" from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" o on o."enrollment_id" = x."id" and o."completed_at" is null
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where o."due_at" <= now() and x."status" = 'active' and x."paused_at" is null and y."status" = 'active'
    order by o."due_at", x."id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_row from "better_supabase"."enrollments" x where x."id" = v_due;
      v_current := null;
      v_next_run := null;
      select o."step", o."due_at" into v_current, v_next_run from "better_supabase"."enrollment_steps" o where o."enrollment_id" = v_due and o."completed_at" is null limit 1;
      exit when v_row."status" <> 'active' or v_row."paused_at" is not null or v_current is null or v_next_run > now();
      select * into v_sequence from "better_supabase"."sequences" x where x."id" = v_row."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_current);
      if v_step is null then
        delete from "better_supabase"."enrollment_steps" y where y."enrollment_id" = v_due and y."completed_at" is null;
        perform "better_supabase"."sequence_place"(v_due);
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        if v_step ? 'consentPurpose' and "better_supabase"."consent_missing"(v_row."tenant_id", v_row."subject_type", v_row."subject_id", v_step ->> 'consentPurpose') then
          perform "better_supabase"."sequence_step_done"(v_due, v_current);
          v_ran := v_ran + 1;
          continue;
        end if;
        update "better_supabase"."enrollment_steps" y set "due_at" = now() + interval '10 minutes'
        where y."enrollment_id" = v_due and y."completed_at" is null;
        update "better_supabase"."enrollments" x
        set "sequence_attempts" = x."sequence_attempts" + 1, "updated_at" = now()
        where x."id" = v_due
        returning * into v_row;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_row."id", 'sequenceId', v_row."sequence_id", 'organizationId', v_row."tenant_id",
          'accountId', coalesce(v_row."sequence_mail_account_id", v_sequence."mail_account_id"), 'threadId', v_row."sequence_mail_thread_id",
          'to', jsonb_build_object('address', v_row."sequence_address", 'name', v_row."sequence_name"),
          'step', v_step, 'variables', v_row."sequence_variables", 'attempt', v_row."sequence_attempts",
          'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"));
        exit;
      end if;
      if v_step ->> 'kind' = 'task' then
        perform "better_supabase"."create_work_item"(v_row."tenant_id", jsonb_build_object(
          'title', trim(v_step ->> 'title'),
          'body', v_step ->> 'body',
          'dueAt', case when v_step ? 'dueInMinutes' then now() + make_interval(mins => (v_step ->> 'dueInMinutes')::integer) end),
          case when v_row."enrolled_by" is null then '{}'::uuid[] else array[v_row."enrolled_by"] end);
      end if;
      perform "better_supabase"."sequence_step_done"(v_due, v_current);
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.run_notification_digests (
  max_digests integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_group record;
  v_ids uuid[];
  v_digests integer := 0;
  v_items integer := 0;
  v_count integer;
begin
  for v_group in
    select rc."user_id" as member, ev."organization_id" as tenant, d."channel" as channel,
      min(case "better_supabase"."notification_cadence"(rc."user_id", ev."organization_id", ev."type", d."channel") when 'weekly' then 'weekly' else 'daily' end) as cadence
    from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where d."status" = 'held'
      and d."created_at" <= now() - case "better_supabase"."notification_cadence"(rc."user_id", ev."organization_id", ev."type", d."channel") when 'weekly' then interval '7 days' else interval '1 day' end
    group by 1, 2, 3
    limit greatest(1, coalesce(run_notification_digests.max_digests, 100))
  loop
    select coalesce(array_agg(d."id"), '{}') into v_ids
    from (
      select d."id" from "better_supabase"."notification_deliveries" d
      join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where d."status" = 'held' and d."channel" = v_group.channel
        and rc."user_id" = v_group.member and ev."organization_id" is not distinct from v_group.tenant
      for update of d skip locked
    ) d;
    if cardinality(v_ids) = 0 then
      continue;
    end if;
    insert into "better_supabase"."notification_digests" ("user_id", "organization_id", "channel", "cadence", "items", "item_count")
    select v_group.member, v_group.tenant, v_group.channel, v_group.cadence,
      coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at", rc."id"), '[]'), count(*)
    from "better_supabase"."notification_deliveries" d
    join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where d."id" = any(v_ids);
    update "better_supabase"."notification_deliveries" d set "status" = 'digested' where d."id" = any(v_ids);
    get diagnostics v_count = row_count;
    v_digests := v_digests + 1;
    v_items := v_items + v_count;
  end loop;
  return jsonb_build_object('digests', v_digests, 'items', v_items);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_commission_plan (
  tenant   uuid,
  name     text,
  kind     text,
  rate_bps integer DEFAULT NULL::integer,
  tiers    jsonb   DEFAULT NULL::jsonb,
  plan_id  uuid    DEFAULT NULL::uuid,
  archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."commission_plans";
  v_created boolean := save_commission_plan.plan_id is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_commission_plan.tenant is not null and coalesce(better_supabase.can('tenant', save_commission_plan.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to manage commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if nullif(trim(save_commission_plan.name), '') is null or length(trim(save_commission_plan.name)) > 200 then
    raise exception 'a plan needs a name of at most 200 characters' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if save_commission_plan.kind = 'flat' then
    if save_commission_plan.rate_bps is null or save_commission_plan.rate_bps not between 0 and 10000 or save_commission_plan.tiers is not null then
      raise exception 'a flat plan takes rate_bps from 0 to 10000 and no tiers' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
  elsif save_commission_plan.kind = 'tiered' then
    if save_commission_plan.rate_bps is not null or not "better_supabase"."commission_tiers_valid"(save_commission_plan.tiers) then
      raise exception 'a tiered plan takes rising { upTo, bps } tiers with a last tier that has no upTo' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
  else
    raise exception 'a plan is flat or tiered' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_created then
    insert into "better_supabase"."commission_plans" ("tenant_id", "name", "kind", "rate_bps", "tiers", "archived_at")
    values (save_commission_plan.tenant, trim(save_commission_plan.name), save_commission_plan.kind, save_commission_plan.rate_bps, save_commission_plan.tiers,
      case when save_commission_plan.archived then now() end)
    returning * into v_plan;
    perform "better_supabase".emit_event('commission_plan.created', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind"), 'commission-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_plan.created',
    category => 'billing',
    target_type => 'commission_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."name",
    summary => 'created a commission plan',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind")
  );
  else
    update "better_supabase"."commission_plans" x set "name" = trim(save_commission_plan.name), "kind" = save_commission_plan.kind,
      "rate_bps" = save_commission_plan.rate_bps, "tiers" = save_commission_plan.tiers,
      "archived_at" = case when save_commission_plan.archived then coalesce(x."archived_at", now()) end,
      "updated_at" = now()
    where x."id" = save_commission_plan.plan_id and x."tenant_id" = save_commission_plan.tenant
    returning * into v_plan;
    if not found then
      raise exception 'no such commission plan' using errcode = 'P0002', hint = 'COMMISSION_PLAN_NOT_FOUND';
    end if;
    perform "better_supabase".emit_event('commission_plan.updated', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind"), 'commission-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_plan.updated',
    category => 'billing',
    target_type => 'commission_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."name",
    summary => 'updated a commission plan',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind")
  );
  end if;
  return jsonb_build_object('id', v_plan."id", 'organizationId', v_plan."tenant_id", 'name', v_plan."name", 'kind', v_plan."kind", 'rateBps', v_plan."rate_bps", 'tiers', v_plan."tiers", 'archivedAt', v_plan."archived_at", 'createdAt', v_plan."created_at", 'updatedAt', v_plan."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_accounting_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  select p_tenant, 'cost_center', 'Cost center'
  where not exists (select 1 from "better_supabase"."accounting_dimensions" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'cost_center');
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  select p_tenant, 'cost_object', 'Cost object'
  where not exists (select 1 from "better_supabase"."accounting_dimensions" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'cost_object');
  if (p_variant is null or p_variant = 'generic') then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1000', 'Bank', 'asset', 'bank', true, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1100', 'Cash', 'asset', 'cash', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1100');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1200', 'Accounts receivable', 'asset', 'receivable', true, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1200');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1300', 'Inventory', 'asset', 'inventory', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1300');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1350', 'Work in progress', 'asset', 'inventory', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1350');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1400', 'Tax receivable', 'asset', 'current_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1400');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1500', 'Fixed assets', 'asset', 'fixed_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1500');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1510', 'Accumulated depreciation', 'asset', 'fixed_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1510');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1900', 'Suspense', 'asset', 'current_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '2000', 'Accounts payable', 'liability', 'payable', true, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '2000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '2100', 'Tax payable', 'liability', 'tax', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '2100');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '2200', 'Deferred revenue', 'liability', 'current_liability', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '2200');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '3000', 'Share capital', 'equity', 'equity', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '3000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '3900', 'Retained earnings', 'equity', 'equity', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '3900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '4000', 'Revenue', 'income', 'revenue', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '4000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '4900', 'Exchange gains', 'income', 'other_income', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '4900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '4910', 'Gains on asset disposals', 'income', 'other_income', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '4910');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '5000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '6000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '6800');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '6900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '6910', 'Losses on asset disposals', 'expense', 'other_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '6910');
  end if;
  if (p_variant is null or p_variant = 'generic') then
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'bank', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'bank');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'receivable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1200' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'receivable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'inventory', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1300' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'inventory');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'work_in_progress', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1350' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'work_in_progress');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'tax_receivable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1400' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'tax_receivable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fixed_asset', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1500' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fixed_asset');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'accumulated_depreciation', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1510' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'accumulated_depreciation');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'suspense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'suspense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'payable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '2000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'payable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'tax_payable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '2100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'tax_payable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'deferred_revenue', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '2200' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'deferred_revenue');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'retained_earnings', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '3900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'retained_earnings');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'revenue', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '4000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'revenue');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fx_gain', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '4900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fx_gain');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'disposal_gain', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '4910' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'disposal_gain');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'cogs', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '5000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'cogs');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'expense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '6000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'expense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'depreciation_expense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '6800' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'depreciation_expense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fx_loss', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '6900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fx_loss');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'disposal_loss', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '6910' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'disposal_loss');
  end if;
  if (p_variant is null or p_variant = 'generic') then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'SAL', 'Sales', 'sales', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'SAL');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'PUR', 'Purchases', 'purchase', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'PUR');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'BNK', 'Bank', 'bank', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'BNK');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'CSH', 'Cash', 'cash', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'CSH');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'GEN', 'General', 'general', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'GEN');
  end if;
  if p_variant is not distinct from 'nl-rgs' then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '0100', 'Vaste activa', 'asset', 'fixed_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '0100');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '0190', 'Cumulatieve afschrijvingen', 'asset', 'fixed_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '0190');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1000', 'Kas', 'asset', 'cash', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1100', 'Bank', 'asset', 'bank', true, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1100');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1200', 'Debiteuren', 'asset', 'receivable', true, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1200');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1300', 'Voorraad', 'asset', 'inventory', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1300');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1350', 'Onderhanden werk', 'asset', 'inventory', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1350');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1400', 'Te vorderen btw', 'asset', 'current_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1400');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '1900', 'Kruisposten', 'asset', 'current_asset', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '1900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '2000', 'Eigen vermogen', 'equity', 'equity', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '2000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '2900', 'Overige reserves', 'equity', 'equity', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '2900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '3000', 'Crediteuren', 'liability', 'payable', true, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '3000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '3100', 'Te betalen btw', 'liability', 'tax', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '3100');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '3200', 'Vooruitontvangen opbrengsten', 'liability', 'current_liability', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '3200');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '4000', 'Bedrijfskosten', 'expense', 'operating_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '4000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '4800', 'Afschrijvingen', 'expense', 'operating_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '4800');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '7000', 'Kostprijs van de omzet', 'expense', 'cogs', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '7000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '8000', 'Omzet', 'income', 'revenue', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '8000');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '8900', 'Koerswinsten', 'income', 'other_income', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '8900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '8910', 'Boekwinst op verkoop van activa', 'income', 'other_income', false, 'credit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '8910');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '9900', 'Koersverliezen', 'expense', 'other_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '9900');
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    select p_tenant, '9910', 'Boekverlies op verkoop van activa', 'expense', 'other_expense', false, 'debit'
    where not exists (select 1 from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" is not distinct from '9910');
  end if;
  if p_variant is not distinct from 'nl-rgs' then
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fixed_asset', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '0100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fixed_asset');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'accumulated_depreciation', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '0190' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'accumulated_depreciation');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'bank', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'bank');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'receivable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1200' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'receivable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'inventory', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1300' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'inventory');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'work_in_progress', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1350' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'work_in_progress');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'tax_receivable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1400' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'tax_receivable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'suspense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'suspense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'retained_earnings', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '2900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'retained_earnings');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'payable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '3000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'payable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'tax_payable', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '3100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'tax_payable');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'deferred_revenue', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '3200' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'deferred_revenue');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'expense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '4000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'expense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'depreciation_expense', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '4800' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'depreciation_expense');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'cogs', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '7000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'cogs');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'revenue', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '8000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'revenue');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fx_gain', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '8900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fx_gain');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'disposal_gain', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '8910' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'disposal_gain');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'fx_loss', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '9900' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'fx_loss');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select p_tenant, 'disposal_loss', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '9910' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_account_roles" x where x."tenant_id" = p_tenant and x."role" is not distinct from 'disposal_loss');
  end if;
  if p_variant is not distinct from 'nl-rgs' then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'VK', 'Verkoop', 'sales', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'VK');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'IK', 'Inkoop', 'purchase', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'IK');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'BNK', 'Bank', 'bank', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1100' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'BNK');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'KAS', 'Kas', 'cash', (select x."id" from "better_supabase"."accounting_accounts" x where x."tenant_id" = p_tenant and x."code" = '1000' limit 1)
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'KAS');
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select p_tenant, 'MEM', 'Memoriaal', 'general', null
    where not exists (select 1 from "better_supabase"."accounting_journals" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'MEM');
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_attachments_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'contract', 'Contract', '{"counterparty":{"type":"text","required":true},"signed_on":{"type":"date"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'contract');
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'invoice', 'Invoice', '{"number":{"type":"text","required":true},"issued_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'invoice');
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'receipt', 'Receipt', '{"merchant":{"type":"text"},"paid_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'receipt');
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'identity', 'Identity document', '{"number":{"type":"text"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'identity');
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'report', 'Report', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'report');
  insert into "better_supabase"."attachment_document_types" ("organization_id", "key", "name", "fields")
  select p_tenant, 'other', 'Other', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."organization_id" = p_tenant and x."key" is not distinct from 'other');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_calendar_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."calendars" ("tenant_id", "name", "tz")
    select p_tenant, 'Public holidays (NL)', 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Public holidays (NL)');
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Nieuwjaarsdag', (timestamp '2026-01-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-01-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-04-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Goede Vrijdag', (timestamp '2026-04-03 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-04-04 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-04-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-04-05', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Paasdag', (timestamp '2026-04-05 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-04-06 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-04-05');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-04-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Paasdag', (timestamp '2026-04-06 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-04-07 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-04-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-04-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Koningsdag', (timestamp '2026-04-27 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-04-28 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-04-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-05-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Hemelvaartsdag', (timestamp '2026-05-14 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-05-15 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-05-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-05-24', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Pinksterdag', (timestamp '2026-05-24 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-05-25 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-05-24');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Pinksterdag', (timestamp '2026-05-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-05-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Kerstdag', (timestamp '2026-12-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-12-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2026-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Kerstdag', (timestamp '2026-12-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2026-12-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2026-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Nieuwjaarsdag', (timestamp '2027-01-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-01-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-03-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Goede Vrijdag', (timestamp '2027-03-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-03-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-03-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-03-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Paasdag', (timestamp '2027-03-28 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-03-29 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-03-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-03-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Paasdag', (timestamp '2027-03-29 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-03-30 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-03-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-04-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Koningsdag', (timestamp '2027-04-27 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-04-28 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-04-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-05-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Hemelvaartsdag', (timestamp '2027-05-06 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-05-07 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-05-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-05-16', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Pinksterdag', (timestamp '2027-05-16 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-05-17 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-05-16');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-05-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Pinksterdag', (timestamp '2027-05-17 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-05-18 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-05-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Kerstdag', (timestamp '2027-12-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-12-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2027-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Kerstdag', (timestamp '2027-12-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2027-12-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2027-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Nieuwjaarsdag', (timestamp '2028-01-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-01-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-04-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Goede Vrijdag', (timestamp '2028-04-14 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-04-15 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-04-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-04-16', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Paasdag', (timestamp '2028-04-16 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-04-17 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-04-16');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-04-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Paasdag', (timestamp '2028-04-17 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-04-18 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-04-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-04-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Koningsdag', (timestamp '2028-04-27 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-04-28 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-04-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Hemelvaartsdag', (timestamp '2028-05-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-05-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-06-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Pinksterdag', (timestamp '2028-06-04 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-06-05 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-06-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-06-05', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Pinksterdag', (timestamp '2028-06-05 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-06-06 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-06-05');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Kerstdag', (timestamp '2028-12-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-12-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2028-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Kerstdag', (timestamp '2028-12-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2028-12-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2028-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Nieuwjaarsdag', (timestamp '2029-01-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-01-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-03-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Goede Vrijdag', (timestamp '2029-03-30 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-03-31 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-03-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-04-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Paasdag', (timestamp '2029-04-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-04-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-04-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-04-02', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Paasdag', (timestamp '2029-04-02 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-04-03 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-04-02');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-04-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Koningsdag', (timestamp '2029-04-27 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-04-28 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-04-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-05-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Hemelvaartsdag', (timestamp '2029-05-10 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-05-11 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-05-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-05-20', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Pinksterdag', (timestamp '2029-05-20 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-05-21 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-05-20');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-05-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Pinksterdag', (timestamp '2029-05-21 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-05-22 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-05-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Kerstdag', (timestamp '2029-12-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-12-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2029-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Kerstdag', (timestamp '2029-12-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2029-12-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2029-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Nieuwjaarsdag', (timestamp '2030-01-01 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-01-02 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-04-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Goede Vrijdag', (timestamp '2030-04-19 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-04-20 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-04-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-04-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Paasdag', (timestamp '2030-04-21 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-04-22 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-04-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-04-22', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Paasdag', (timestamp '2030-04-22 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-04-23 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-04-22');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-04-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Koningsdag', (timestamp '2030-04-27 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-04-28 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-04-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-05-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Hemelvaartsdag', (timestamp '2030-05-30 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-05-31 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-05-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-06-09', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Pinksterdag', (timestamp '2030-06-09 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-06-10 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-06-09');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-06-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Pinksterdag', (timestamp '2030-06-10 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-06-11 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-06-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Eerste Kerstdag', (timestamp '2030-12-25 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-12-26 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-nl-2030-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (NL)' limit 1), 'Tweede Kerstdag', (timestamp '2030-12-26 00:00' at time zone 'Europe/Amsterdam'), (timestamp '2030-12-27 00:00' at time zone 'Europe/Amsterdam'), true, 'Europe/Amsterdam'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-nl-2030-12-26');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."calendars" ("tenant_id", "name", "tz")
    select p_tenant, 'Public holidays (DE)', 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Public holidays (DE)');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Neujahr', (timestamp '2026-01-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-01-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-04-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Karfreitag', (timestamp '2026-04-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-04-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-04-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-04-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Ostermontag', (timestamp '2026-04-06 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-04-07 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-04-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Arbeit', (timestamp '2026-05-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-05-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-05-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Christi Himmelfahrt', (timestamp '2026-05-14 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-05-15 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-05-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Pfingstmontag', (timestamp '2026-05-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-05-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-10-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Deutschen Einheit', (timestamp '2026-10-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-10-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-10-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '1. Weihnachtstag', (timestamp '2026-12-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-12-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2026-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '2. Weihnachtstag', (timestamp '2026-12-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2026-12-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2026-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Neujahr', (timestamp '2027-01-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-01-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-03-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Karfreitag', (timestamp '2027-03-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-03-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-03-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-03-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Ostermontag', (timestamp '2027-03-29 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-03-30 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-03-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Arbeit', (timestamp '2027-05-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-05-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-05-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Christi Himmelfahrt', (timestamp '2027-05-06 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-05-07 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-05-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-05-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Pfingstmontag', (timestamp '2027-05-17 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-05-18 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-05-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-10-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Deutschen Einheit', (timestamp '2027-10-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-10-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-10-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '1. Weihnachtstag', (timestamp '2027-12-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-12-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2027-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '2. Weihnachtstag', (timestamp '2027-12-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2027-12-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2027-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Neujahr', (timestamp '2028-01-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-01-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-04-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Karfreitag', (timestamp '2028-04-14 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-04-15 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-04-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-04-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Ostermontag', (timestamp '2028-04-17 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-04-18 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-04-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Arbeit', (timestamp '2028-05-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-05-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Christi Himmelfahrt', (timestamp '2028-05-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-05-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-06-05', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Pfingstmontag', (timestamp '2028-06-05 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-06-06 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-06-05');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-10-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Deutschen Einheit', (timestamp '2028-10-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-10-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-10-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '1. Weihnachtstag', (timestamp '2028-12-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-12-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2028-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '2. Weihnachtstag', (timestamp '2028-12-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2028-12-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2028-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Neujahr', (timestamp '2029-01-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-01-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-03-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Karfreitag', (timestamp '2029-03-30 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-03-31 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-03-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-04-02', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Ostermontag', (timestamp '2029-04-02 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-04-03 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-04-02');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Arbeit', (timestamp '2029-05-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-05-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-05-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Christi Himmelfahrt', (timestamp '2029-05-10 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-05-11 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-05-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-05-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Pfingstmontag', (timestamp '2029-05-21 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-05-22 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-05-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-10-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Deutschen Einheit', (timestamp '2029-10-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-10-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-10-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '1. Weihnachtstag', (timestamp '2029-12-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-12-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2029-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '2. Weihnachtstag', (timestamp '2029-12-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2029-12-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2029-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Neujahr', (timestamp '2030-01-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-01-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-04-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Karfreitag', (timestamp '2030-04-19 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-04-20 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-04-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-04-22', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Ostermontag', (timestamp '2030-04-22 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-04-23 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-04-22');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Arbeit', (timestamp '2030-05-01 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-05-02 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-05-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Christi Himmelfahrt', (timestamp '2030-05-30 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-05-31 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-05-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-06-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Pfingstmontag', (timestamp '2030-06-10 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-06-11 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-06-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-10-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), 'Tag der Deutschen Einheit', (timestamp '2030-10-03 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-10-04 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-10-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '1. Weihnachtstag', (timestamp '2030-12-25 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-12-26 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-de-2030-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (DE)' limit 1), '2. Weihnachtstag', (timestamp '2030-12-26 00:00' at time zone 'Europe/Berlin'), (timestamp '2030-12-27 00:00' at time zone 'Europe/Berlin'), true, 'Europe/Berlin'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-de-2030-12-26');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."calendars" ("tenant_id", "name", "tz")
    select p_tenant, 'Public holidays (FR)', 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Public holidays (FR)');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Jour de l''An', (timestamp '2026-01-01 00:00' at time zone 'Europe/Paris'), (timestamp '2026-01-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-04-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pâques', (timestamp '2026-04-06 00:00' at time zone 'Europe/Paris'), (timestamp '2026-04-07 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-04-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête du Travail', (timestamp '2026-05-01 00:00' at time zone 'Europe/Paris'), (timestamp '2026-05-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-05-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Victoire 1945', (timestamp '2026-05-08 00:00' at time zone 'Europe/Paris'), (timestamp '2026-05-09 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-05-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-05-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Ascension', (timestamp '2026-05-14 00:00' at time zone 'Europe/Paris'), (timestamp '2026-05-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-05-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pentecôte', (timestamp '2026-05-25 00:00' at time zone 'Europe/Paris'), (timestamp '2026-05-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-07-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête nationale', (timestamp '2026-07-14 00:00' at time zone 'Europe/Paris'), (timestamp '2026-07-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-07-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-08-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Assomption', (timestamp '2026-08-15 00:00' at time zone 'Europe/Paris'), (timestamp '2026-08-16 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-08-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-11-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Toussaint', (timestamp '2026-11-01 00:00' at time zone 'Europe/Paris'), (timestamp '2026-11-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-11-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Armistice 1918', (timestamp '2026-11-11 00:00' at time zone 'Europe/Paris'), (timestamp '2026-11-12 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2026-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Noël', (timestamp '2026-12-25 00:00' at time zone 'Europe/Paris'), (timestamp '2026-12-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2026-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Jour de l''An', (timestamp '2027-01-01 00:00' at time zone 'Europe/Paris'), (timestamp '2027-01-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-03-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pâques', (timestamp '2027-03-29 00:00' at time zone 'Europe/Paris'), (timestamp '2027-03-30 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-03-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête du Travail', (timestamp '2027-05-01 00:00' at time zone 'Europe/Paris'), (timestamp '2027-05-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-05-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Victoire 1945', (timestamp '2027-05-08 00:00' at time zone 'Europe/Paris'), (timestamp '2027-05-09 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-05-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-05-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Ascension', (timestamp '2027-05-06 00:00' at time zone 'Europe/Paris'), (timestamp '2027-05-07 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-05-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-05-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pentecôte', (timestamp '2027-05-17 00:00' at time zone 'Europe/Paris'), (timestamp '2027-05-18 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-05-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-07-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête nationale', (timestamp '2027-07-14 00:00' at time zone 'Europe/Paris'), (timestamp '2027-07-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-07-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-08-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Assomption', (timestamp '2027-08-15 00:00' at time zone 'Europe/Paris'), (timestamp '2027-08-16 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-08-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-11-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Toussaint', (timestamp '2027-11-01 00:00' at time zone 'Europe/Paris'), (timestamp '2027-11-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-11-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Armistice 1918', (timestamp '2027-11-11 00:00' at time zone 'Europe/Paris'), (timestamp '2027-11-12 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2027-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Noël', (timestamp '2027-12-25 00:00' at time zone 'Europe/Paris'), (timestamp '2027-12-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2027-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Jour de l''An', (timestamp '2028-01-01 00:00' at time zone 'Europe/Paris'), (timestamp '2028-01-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-04-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pâques', (timestamp '2028-04-17 00:00' at time zone 'Europe/Paris'), (timestamp '2028-04-18 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-04-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête du Travail', (timestamp '2028-05-01 00:00' at time zone 'Europe/Paris'), (timestamp '2028-05-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-05-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Victoire 1945', (timestamp '2028-05-08 00:00' at time zone 'Europe/Paris'), (timestamp '2028-05-09 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-05-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Ascension', (timestamp '2028-05-25 00:00' at time zone 'Europe/Paris'), (timestamp '2028-05-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-06-05', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pentecôte', (timestamp '2028-06-05 00:00' at time zone 'Europe/Paris'), (timestamp '2028-06-06 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-06-05');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-07-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête nationale', (timestamp '2028-07-14 00:00' at time zone 'Europe/Paris'), (timestamp '2028-07-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-07-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-08-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Assomption', (timestamp '2028-08-15 00:00' at time zone 'Europe/Paris'), (timestamp '2028-08-16 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-08-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-11-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Toussaint', (timestamp '2028-11-01 00:00' at time zone 'Europe/Paris'), (timestamp '2028-11-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-11-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Armistice 1918', (timestamp '2028-11-11 00:00' at time zone 'Europe/Paris'), (timestamp '2028-11-12 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2028-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Noël', (timestamp '2028-12-25 00:00' at time zone 'Europe/Paris'), (timestamp '2028-12-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2028-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Jour de l''An', (timestamp '2029-01-01 00:00' at time zone 'Europe/Paris'), (timestamp '2029-01-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-04-02', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pâques', (timestamp '2029-04-02 00:00' at time zone 'Europe/Paris'), (timestamp '2029-04-03 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-04-02');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête du Travail', (timestamp '2029-05-01 00:00' at time zone 'Europe/Paris'), (timestamp '2029-05-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-05-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Victoire 1945', (timestamp '2029-05-08 00:00' at time zone 'Europe/Paris'), (timestamp '2029-05-09 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-05-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-05-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Ascension', (timestamp '2029-05-10 00:00' at time zone 'Europe/Paris'), (timestamp '2029-05-11 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-05-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-05-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pentecôte', (timestamp '2029-05-21 00:00' at time zone 'Europe/Paris'), (timestamp '2029-05-22 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-05-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-07-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête nationale', (timestamp '2029-07-14 00:00' at time zone 'Europe/Paris'), (timestamp '2029-07-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-07-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-08-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Assomption', (timestamp '2029-08-15 00:00' at time zone 'Europe/Paris'), (timestamp '2029-08-16 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-08-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-11-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Toussaint', (timestamp '2029-11-01 00:00' at time zone 'Europe/Paris'), (timestamp '2029-11-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-11-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Armistice 1918', (timestamp '2029-11-11 00:00' at time zone 'Europe/Paris'), (timestamp '2029-11-12 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2029-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Noël', (timestamp '2029-12-25 00:00' at time zone 'Europe/Paris'), (timestamp '2029-12-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2029-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Jour de l''An', (timestamp '2030-01-01 00:00' at time zone 'Europe/Paris'), (timestamp '2030-01-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-04-22', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pâques', (timestamp '2030-04-22 00:00' at time zone 'Europe/Paris'), (timestamp '2030-04-23 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-04-22');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête du Travail', (timestamp '2030-05-01 00:00' at time zone 'Europe/Paris'), (timestamp '2030-05-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-05-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Victoire 1945', (timestamp '2030-05-08 00:00' at time zone 'Europe/Paris'), (timestamp '2030-05-09 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-05-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-05-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Ascension', (timestamp '2030-05-30 00:00' at time zone 'Europe/Paris'), (timestamp '2030-05-31 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-05-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-06-10', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Lundi de Pentecôte', (timestamp '2030-06-10 00:00' at time zone 'Europe/Paris'), (timestamp '2030-06-11 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-06-10');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-07-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Fête nationale', (timestamp '2030-07-14 00:00' at time zone 'Europe/Paris'), (timestamp '2030-07-15 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-07-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-08-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Assomption', (timestamp '2030-08-15 00:00' at time zone 'Europe/Paris'), (timestamp '2030-08-16 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-08-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-11-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Toussaint', (timestamp '2030-11-01 00:00' at time zone 'Europe/Paris'), (timestamp '2030-11-02 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-11-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Armistice 1918', (timestamp '2030-11-11 00:00' at time zone 'Europe/Paris'), (timestamp '2030-11-12 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-fr-2030-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (FR)' limit 1), 'Noël', (timestamp '2030-12-25 00:00' at time zone 'Europe/Paris'), (timestamp '2030-12-26 00:00' at time zone 'Europe/Paris'), true, 'Europe/Paris'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-fr-2030-12-25');
  end if;
  if p_locale = any (array['en-gb']) then
    insert into "better_supabase"."calendars" ("tenant_id", "name", "tz")
    select p_tenant, 'Public holidays (GB)', 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Public holidays (GB)');
  end if;
  if p_locale = any (array['en-gb']) then
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'New Year''s Day', (timestamp '2026-01-01 00:00' at time zone 'Europe/London'), (timestamp '2026-01-02 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-04-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Good Friday', (timestamp '2026-04-03 00:00' at time zone 'Europe/London'), (timestamp '2026-04-04 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-04-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-04-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Easter Monday', (timestamp '2026-04-06 00:00' at time zone 'Europe/London'), (timestamp '2026-04-07 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-04-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-05-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Early May bank holiday', (timestamp '2026-05-04 00:00' at time zone 'Europe/London'), (timestamp '2026-05-05 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-05-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Spring bank holiday', (timestamp '2026-05-25 00:00' at time zone 'Europe/London'), (timestamp '2026-05-26 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-08-31', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Summer bank holiday', (timestamp '2026-08-31 00:00' at time zone 'Europe/London'), (timestamp '2026-09-01 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-08-31');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Christmas Day', (timestamp '2026-12-25 00:00' at time zone 'Europe/London'), (timestamp '2026-12-26 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2026-12-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Boxing Day', (timestamp '2026-12-28 00:00' at time zone 'Europe/London'), (timestamp '2026-12-29 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2026-12-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'New Year''s Day', (timestamp '2027-01-01 00:00' at time zone 'Europe/London'), (timestamp '2027-01-02 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-03-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Good Friday', (timestamp '2027-03-26 00:00' at time zone 'Europe/London'), (timestamp '2027-03-27 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-03-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-03-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Easter Monday', (timestamp '2027-03-29 00:00' at time zone 'Europe/London'), (timestamp '2027-03-30 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-03-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-05-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Early May bank holiday', (timestamp '2027-05-03 00:00' at time zone 'Europe/London'), (timestamp '2027-05-04 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-05-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-05-31', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Spring bank holiday', (timestamp '2027-05-31 00:00' at time zone 'Europe/London'), (timestamp '2027-06-01 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-05-31');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-08-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Summer bank holiday', (timestamp '2027-08-30 00:00' at time zone 'Europe/London'), (timestamp '2027-08-31 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-08-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-12-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Christmas Day', (timestamp '2027-12-27 00:00' at time zone 'Europe/London'), (timestamp '2027-12-28 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-12-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2027-12-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Boxing Day', (timestamp '2027-12-28 00:00' at time zone 'Europe/London'), (timestamp '2027-12-29 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2027-12-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-01-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'New Year''s Day', (timestamp '2028-01-03 00:00' at time zone 'Europe/London'), (timestamp '2028-01-04 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-01-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-04-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Good Friday', (timestamp '2028-04-14 00:00' at time zone 'Europe/London'), (timestamp '2028-04-15 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-04-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-04-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Easter Monday', (timestamp '2028-04-17 00:00' at time zone 'Europe/London'), (timestamp '2028-04-18 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-04-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-05-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Early May bank holiday', (timestamp '2028-05-01 00:00' at time zone 'Europe/London'), (timestamp '2028-05-02 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-05-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-05-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Spring bank holiday', (timestamp '2028-05-29 00:00' at time zone 'Europe/London'), (timestamp '2028-05-30 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-05-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-08-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Summer bank holiday', (timestamp '2028-08-28 00:00' at time zone 'Europe/London'), (timestamp '2028-08-29 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-08-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Christmas Day', (timestamp '2028-12-25 00:00' at time zone 'Europe/London'), (timestamp '2028-12-26 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2028-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Boxing Day', (timestamp '2028-12-26 00:00' at time zone 'Europe/London'), (timestamp '2028-12-27 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2028-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'New Year''s Day', (timestamp '2029-01-01 00:00' at time zone 'Europe/London'), (timestamp '2029-01-02 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-03-30', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Good Friday', (timestamp '2029-03-30 00:00' at time zone 'Europe/London'), (timestamp '2029-03-31 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-03-30');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-04-02', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Easter Monday', (timestamp '2029-04-02 00:00' at time zone 'Europe/London'), (timestamp '2029-04-03 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-04-02');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-05-07', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Early May bank holiday', (timestamp '2029-05-07 00:00' at time zone 'Europe/London'), (timestamp '2029-05-08 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-05-07');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-05-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Spring bank holiday', (timestamp '2029-05-28 00:00' at time zone 'Europe/London'), (timestamp '2029-05-29 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-05-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-08-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Summer bank holiday', (timestamp '2029-08-27 00:00' at time zone 'Europe/London'), (timestamp '2029-08-28 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-08-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Christmas Day', (timestamp '2029-12-25 00:00' at time zone 'Europe/London'), (timestamp '2029-12-26 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2029-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Boxing Day', (timestamp '2029-12-26 00:00' at time zone 'Europe/London'), (timestamp '2029-12-27 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2029-12-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'New Year''s Day', (timestamp '2030-01-01 00:00' at time zone 'Europe/London'), (timestamp '2030-01-02 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-04-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Good Friday', (timestamp '2030-04-19 00:00' at time zone 'Europe/London'), (timestamp '2030-04-20 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-04-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-04-22', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Easter Monday', (timestamp '2030-04-22 00:00' at time zone 'Europe/London'), (timestamp '2030-04-23 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-04-22');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-05-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Early May bank holiday', (timestamp '2030-05-06 00:00' at time zone 'Europe/London'), (timestamp '2030-05-07 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-05-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-05-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Spring bank holiday', (timestamp '2030-05-27 00:00' at time zone 'Europe/London'), (timestamp '2030-05-28 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-05-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-08-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Summer bank holiday', (timestamp '2030-08-26 00:00' at time zone 'Europe/London'), (timestamp '2030-08-27 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-08-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Christmas Day', (timestamp '2030-12-25 00:00' at time zone 'Europe/London'), (timestamp '2030-12-26 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-gb-2030-12-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (GB)' limit 1), 'Boxing Day', (timestamp '2030-12-26 00:00' at time zone 'Europe/London'), (timestamp '2030-12-27 00:00' at time zone 'Europe/London'), true, 'Europe/London'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-gb-2030-12-26');
  end if;
  if p_locale = any (array['en-us']) then
    insert into "better_supabase"."calendars" ("tenant_id", "name", "tz")
    select p_tenant, 'Public holidays (US)', 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Public holidays (US)');
  end if;
  if p_locale = any (array['en-us']) then
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'New Year''s Day', (timestamp '2026-01-01 00:00' at time zone 'America/New_York'), (timestamp '2026-01-02 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-01-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Martin Luther King Jr. Day', (timestamp '2026-01-19 00:00' at time zone 'America/New_York'), (timestamp '2026-01-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-01-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-02-16', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Presidents'' Day', (timestamp '2026-02-16 00:00' at time zone 'America/New_York'), (timestamp '2026-02-17 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-02-16');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-05-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Memorial Day', (timestamp '2026-05-25 00:00' at time zone 'America/New_York'), (timestamp '2026-05-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-05-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-06-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Juneteenth', (timestamp '2026-06-19 00:00' at time zone 'America/New_York'), (timestamp '2026-06-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-06-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-07-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Independence Day', (timestamp '2026-07-04 00:00' at time zone 'America/New_York'), (timestamp '2026-07-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-07-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-09-07', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Labor Day', (timestamp '2026-09-07 00:00' at time zone 'America/New_York'), (timestamp '2026-09-08 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-09-07');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-10-12', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Columbus Day', (timestamp '2026-10-12 00:00' at time zone 'America/New_York'), (timestamp '2026-10-13 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-10-12');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Veterans Day', (timestamp '2026-11-11 00:00' at time zone 'America/New_York'), (timestamp '2026-11-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-11-26', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Thanksgiving Day', (timestamp '2026-11-26 00:00' at time zone 'America/New_York'), (timestamp '2026-11-27 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-11-26');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2026-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Christmas Day', (timestamp '2026-12-25 00:00' at time zone 'America/New_York'), (timestamp '2026-12-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2026-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'New Year''s Day', (timestamp '2027-01-01 00:00' at time zone 'America/New_York'), (timestamp '2027-01-02 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-01-18', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Martin Luther King Jr. Day', (timestamp '2027-01-18 00:00' at time zone 'America/New_York'), (timestamp '2027-01-19 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-01-18');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-02-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Presidents'' Day', (timestamp '2027-02-15 00:00' at time zone 'America/New_York'), (timestamp '2027-02-16 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-02-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-05-31', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Memorial Day', (timestamp '2027-05-31 00:00' at time zone 'America/New_York'), (timestamp '2027-06-01 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-05-31');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-06-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Juneteenth', (timestamp '2027-06-19 00:00' at time zone 'America/New_York'), (timestamp '2027-06-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-06-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-07-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Independence Day', (timestamp '2027-07-04 00:00' at time zone 'America/New_York'), (timestamp '2027-07-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-07-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-09-06', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Labor Day', (timestamp '2027-09-06 00:00' at time zone 'America/New_York'), (timestamp '2027-09-07 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-09-06');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-10-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Columbus Day', (timestamp '2027-10-11 00:00' at time zone 'America/New_York'), (timestamp '2027-10-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-10-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Veterans Day', (timestamp '2027-11-11 00:00' at time zone 'America/New_York'), (timestamp '2027-11-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-11-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Thanksgiving Day', (timestamp '2027-11-25 00:00' at time zone 'America/New_York'), (timestamp '2027-11-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-11-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2027-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Christmas Day', (timestamp '2027-12-25 00:00' at time zone 'America/New_York'), (timestamp '2027-12-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2027-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'New Year''s Day', (timestamp '2028-01-01 00:00' at time zone 'America/New_York'), (timestamp '2028-01-02 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-01-17', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Martin Luther King Jr. Day', (timestamp '2028-01-17 00:00' at time zone 'America/New_York'), (timestamp '2028-01-18 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-01-17');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-02-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Presidents'' Day', (timestamp '2028-02-21 00:00' at time zone 'America/New_York'), (timestamp '2028-02-22 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-02-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-05-29', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Memorial Day', (timestamp '2028-05-29 00:00' at time zone 'America/New_York'), (timestamp '2028-05-30 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-05-29');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-06-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Juneteenth', (timestamp '2028-06-19 00:00' at time zone 'America/New_York'), (timestamp '2028-06-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-06-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-07-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Independence Day', (timestamp '2028-07-04 00:00' at time zone 'America/New_York'), (timestamp '2028-07-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-07-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-09-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Labor Day', (timestamp '2028-09-04 00:00' at time zone 'America/New_York'), (timestamp '2028-09-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-09-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-10-09', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Columbus Day', (timestamp '2028-10-09 00:00' at time zone 'America/New_York'), (timestamp '2028-10-10 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-10-09');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Veterans Day', (timestamp '2028-11-11 00:00' at time zone 'America/New_York'), (timestamp '2028-11-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-11-23', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Thanksgiving Day', (timestamp '2028-11-23 00:00' at time zone 'America/New_York'), (timestamp '2028-11-24 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-11-23');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2028-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Christmas Day', (timestamp '2028-12-25 00:00' at time zone 'America/New_York'), (timestamp '2028-12-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2028-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'New Year''s Day', (timestamp '2029-01-01 00:00' at time zone 'America/New_York'), (timestamp '2029-01-02 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-01-15', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Martin Luther King Jr. Day', (timestamp '2029-01-15 00:00' at time zone 'America/New_York'), (timestamp '2029-01-16 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-01-15');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-02-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Presidents'' Day', (timestamp '2029-02-19 00:00' at time zone 'America/New_York'), (timestamp '2029-02-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-02-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-05-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Memorial Day', (timestamp '2029-05-28 00:00' at time zone 'America/New_York'), (timestamp '2029-05-29 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-05-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-06-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Juneteenth', (timestamp '2029-06-19 00:00' at time zone 'America/New_York'), (timestamp '2029-06-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-06-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-07-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Independence Day', (timestamp '2029-07-04 00:00' at time zone 'America/New_York'), (timestamp '2029-07-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-07-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-09-03', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Labor Day', (timestamp '2029-09-03 00:00' at time zone 'America/New_York'), (timestamp '2029-09-04 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-09-03');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-10-08', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Columbus Day', (timestamp '2029-10-08 00:00' at time zone 'America/New_York'), (timestamp '2029-10-09 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-10-08');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Veterans Day', (timestamp '2029-11-11 00:00' at time zone 'America/New_York'), (timestamp '2029-11-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-11-22', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Thanksgiving Day', (timestamp '2029-11-22 00:00' at time zone 'America/New_York'), (timestamp '2029-11-23 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-11-22');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2029-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Christmas Day', (timestamp '2029-12-25 00:00' at time zone 'America/New_York'), (timestamp '2029-12-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2029-12-25');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-01-01', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'New Year''s Day', (timestamp '2030-01-01 00:00' at time zone 'America/New_York'), (timestamp '2030-01-02 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-01-01');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-01-21', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Martin Luther King Jr. Day', (timestamp '2030-01-21 00:00' at time zone 'America/New_York'), (timestamp '2030-01-22 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-01-21');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-02-18', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Presidents'' Day', (timestamp '2030-02-18 00:00' at time zone 'America/New_York'), (timestamp '2030-02-19 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-02-18');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-05-27', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Memorial Day', (timestamp '2030-05-27 00:00' at time zone 'America/New_York'), (timestamp '2030-05-28 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-05-27');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-06-19', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Juneteenth', (timestamp '2030-06-19 00:00' at time zone 'America/New_York'), (timestamp '2030-06-20 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-06-19');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-07-04', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Independence Day', (timestamp '2030-07-04 00:00' at time zone 'America/New_York'), (timestamp '2030-07-05 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-07-04');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-09-02', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Labor Day', (timestamp '2030-09-02 00:00' at time zone 'America/New_York'), (timestamp '2030-09-03 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-09-02');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-10-14', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Columbus Day', (timestamp '2030-10-14 00:00' at time zone 'America/New_York'), (timestamp '2030-10-15 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-10-14');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-11-11', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Veterans Day', (timestamp '2030-11-11 00:00' at time zone 'America/New_York'), (timestamp '2030-11-12 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-11-11');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-11-28', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Thanksgiving Day', (timestamp '2030-11-28 00:00' at time zone 'America/New_York'), (timestamp '2030-11-29 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-11-28');
    insert into "better_supabase"."calendar_events" ("tenant_id", "uid", "calendar_id", "title", "starts_at", "ends_at", "all_day", "tz")
    select p_tenant, 'holiday-en-us-2030-12-25', (select x."id" from "better_supabase"."calendars" x where x."tenant_id" = p_tenant and x."name" = 'Public holidays (US)' limit 1), 'Christmas Day', (timestamp '2030-12-25 00:00' at time zone 'America/New_York'), (timestamp '2030-12-26 00:00' at time zone 'America/New_York'), true, 'America/New_York'
    where not exists (select 1 from "better_supabase"."calendar_events" x where x."tenant_id" = p_tenant and x."uid" is not distinct from 'holiday-en-us-2030-12-25');
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_inbox_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."inboxes" ("tenant_id", "name", "channel", "bot_mode")
  select p_tenant, 'Help', 'in_app', 'human'
  where not exists (select 1 from "better_supabase"."inboxes" x where x."tenant_id" = p_tenant and x."name" is not distinct from 'Help');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_pipelines_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if (p_variant is null or p_variant = 'b2b-sales') then
    insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
    select p_tenant, 'deal', null, 'default', 'Default', (not exists (select 1 from "better_supabase"."pipelines" d where d."tenant_id" = p_tenant and d."subject_type" = 'deal' and d."scope_id" is null and d."is_default" and d."archived_at" is null))
    where not exists (select 1 from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" is not distinct from 'deal' and x."scope_id" is not distinct from null and x."key" is not distinct from 'default');
  end if;
  if (p_variant is null or p_variant = 'b2b-sales') then
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'qualified', 'Qualified', ('open'), ('open'), '8', 'qualified', 20
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'qualified');
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'discovery', 'Discovery', ('open'), ('open'), 'G', 'discovery', 35
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'discovery');
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'proposal', 'Proposal', ('open'), ('open'), 'O', 'proposal', 55
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'proposal');
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'negotiation', 'Negotiation', ('open'), ('open'), 'W', 'negotiation', 75
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'negotiation');
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'closed_won', 'Closed won', ('won'), ('success'), 'e', 'closed_won', 100
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'closed_won');
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'closed_lost', 'Closed lost', ('lost'), ('failure'), 'm', 'closed_lost', 0
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'closed_lost');
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_tenant_defaults (
  p_tenant   uuid,
  p_variants jsonb DEFAULT '{}'::jsonb,
  p_locale   text  DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform "better_supabase"."seed_attachments_defaults"(p_tenant, p_variants ->> 'attachments', p_locale);
  perform "better_supabase"."seed_inbox_defaults"(p_tenant, p_variants ->> 'inbox', p_locale);
  perform "better_supabase"."seed_calendar_defaults"(p_tenant, p_variants ->> 'calendar', p_locale);
  perform "better_supabase"."seed_cases_defaults"(p_tenant, p_variants ->> 'cases', p_locale);
  perform "better_supabase"."seed_pipelines_defaults"(p_tenant, p_variants ->> 'pipelines', p_locale);
  perform "better_supabase"."seed_risks_defaults"(p_tenant, p_variants ->> 'risks', p_locale);
  perform "better_supabase"."seed_tax_defaults"(p_tenant, p_variants ->> 'tax', p_locale);
  perform "better_supabase"."seed_accounting_defaults"(p_tenant, p_variants ->> 'accounting', p_locale);
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
  if nullif(notification ->> 'consent_purpose', '') is not null
    and "better_supabase"."consent_missing"(v_tenant, v_subject_type, v_subject_id, notification ->> 'consent_purpose') then
    return null;
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
  
  if nullif(notification ->> 'permission', '') is not null and v_tenant is null then
    raise exception 'A permission audience needs a tenant' using errcode = '22023', hint = 'NOTIFICATION_PERMISSION_NEEDS_TENANT';
  end if;
  if nullif(notification ->> 'permission', '') is not null then
    v_recipients := v_recipients || coalesce(array(
      select m."user_id"
      from "public"."memberships" m
      where m."organization_id" = v_tenant
        and coalesce(better_supabase.can_user(m."user_id", 'tenant', v_tenant, notification ->> 'permission'), false)
      
      union
      select a."user_id"
      from "better_supabase"."platform_roles" a
      where coalesce(better_supabase.platform_can(a."user_id", notification ->> 'permission'), false)
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
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) and p."cadence" is distinct from 'off' as enabled
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
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else case when "better_supabase"."notification_cadence"(rc."user_id", v_tenant, v_type, c) in ('daily', 'weekly') then 'held' else 'pending' end end, case when c = 'in_app' then now() end
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

CREATE OR REPLACE FUNCTION better_supabase.sequence_steps_check (
  steps jsonb,
  mail  boolean
)
  RETURNS void
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_step jsonb;
  v_ids text[] := '{}';
  v_id text;
begin
  if sequence_steps_check.steps is null or jsonb_typeof(sequence_steps_check.steps) <> 'array' then
    raise exception 'steps must be an array' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    raise exception 'a sequence has at most 50 steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'each step must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      raise exception 'step id: use lowercase letters, digits, "_" or "-"' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_id = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          raise exception 'a wait step waits 1 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          raise exception 'email steps need the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          raise exception 'an email step needs a subject of 1 to 300 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          raise exception 'an email step needs text or html' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          raise exception 'an email step''s body is at most 200000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          raise exception 'track must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'consentPurpose' and coalesce(v_step ->> 'consentPurpose', '') !~ '^[a-z][a-z0-9_.-]{0,62}$' then
          raise exception 'consentPurpose must be a consent purpose key' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          raise exception 'templateVersionId must be a uuid' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          raise exception 'a task step needs a title of 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          raise exception 'a task step''s body is at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          raise exception 'dueInMinutes must be 0 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      else
        raise exception 'a step''s kind must be email, task or wait' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end case;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_accounting_account_role (
  tenant     uuid,
  role       text,
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_account_role.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'work_in_progress', 'tax_payable', 'tax_receivable', 'deferred_revenue', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'disposal_gain', 'disposal_loss', 'expense', 'suspense') then
    raise exception 'unknown account role' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_ROLE_INVALID';
  end if;
  if set_accounting_account_role.account_id is null then
    delete from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant and y."role" = set_accounting_account_role.role;
  else
    if not exists (
      select 1 from "better_supabase"."accounting_accounts" y where y."id" = set_accounting_account_role.account_id
        and y."tenant_id" = set_accounting_account_role.tenant and y."archived_at" is null
    ) then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    values (set_accounting_account_role.tenant, set_accounting_account_role.role, set_accounting_account_role.account_id)
    on conflict ("tenant_id", "role") do update set "account_id" = excluded."account_id", "updated_at" = now();
  end if;
  return coalesce((
    select jsonb_object_agg(y."role", y."account_id") from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant
  ), '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_notification_cadence (
  type    text,
  channel text,
  cadence text,
  tenant  uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_cadence.cadence is null or set_notification_cadence.cadence not in ('immediate', 'daily', 'weekly', 'off') then
    raise exception 'cadence must be immediate, daily, weekly or off' using errcode = '22023', hint = 'NOTIFICATION_CADENCE_UNKNOWN';
  end if;
  update "better_supabase"."notification_preferences" x set "cadence" = set_notification_cadence.cadence
  where x."user_id" = auth.uid() and x."type" = set_notification_cadence.type
    and x."channel" = set_notification_cadence.channel
    and x."organization_id" is not distinct from set_notification_cadence.tenant;
  if not found then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "cadence")
    values (auth.uid(), set_notification_cadence.tenant, set_notification_cadence.type, set_notification_cadence.channel, set_notification_cadence.cadence);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.setup_accounting (
  tenant                  uuid,
  functional_currency     text    DEFAULT NULL::text,
  fiscal_year_start_month integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_settings"%rowtype;
  v_currency text := upper(coalesce(nullif(trim(setup_accounting.functional_currency), ''), 'EUR'));
  v_month integer := coalesce(setup_accounting.fiscal_year_start_month, 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', setup_accounting.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the functional currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  if v_month < 1 or v_month > 12 then
    raise exception 'the fiscal year starts in a month from 1 to 12' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  select * into v_row from "better_supabase"."accounting_settings" y where y."tenant_id" = setup_accounting.tenant for update;
  if found then
    if setup_accounting.functional_currency is not null and v_row."functional_currency" <> v_currency
      and exists (select 1 from "better_supabase"."accounting_entries" y where y."tenant_id" = setup_accounting.tenant and y."status" <> 'draft') then
      raise exception 'the functional currency can''t change once entries are posted' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    if setup_accounting.fiscal_year_start_month is not null and v_row."fiscal_year_start_month" <> v_month
      and exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = setup_accounting.tenant) then
      raise exception 'the fiscal year start can''t change once periods exist' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    update "better_supabase"."accounting_settings" y set
      "functional_currency" = case when setup_accounting.functional_currency is null then y."functional_currency" else v_currency end,
      "fiscal_year_start_month" = case when setup_accounting.fiscal_year_start_month is null then y."fiscal_year_start_month" else v_month end,
      "updated_at" = now()
    where y."tenant_id" = setup_accounting.tenant
    returning * into v_row;
  else
    insert into "better_supabase"."accounting_settings" ("tenant_id", "functional_currency", "fiscal_year_start_month")
    values (setup_accounting.tenant, v_currency, v_month)
    returning * into v_row;
  end if;
  -- Cost center and cost object are built in: every organization has both.
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (setup_accounting.tenant, 'cost_center', 'Cost center'), (setup_accounting.tenant, 'cost_object', 'Cost object')
  on conflict ("tenant_id", "key") do nothing;
  if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant) then
    perform "better_supabase"."seed_accounting_defaults"(setup_accounting.tenant, 'generic');
  end if;
  return jsonb_build_object('organizationId', v_row."tenant_id", 'functionalCurrency', v_row."functional_currency", 'fiscalYearStartMonth', v_row."fiscal_year_start_month", 'lockDate', v_row."lock_date", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_referral (
  referral_id uuid,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.voided', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.voided',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral voided',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_user_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$function$;

ALTER TABLE "better_supabase"."accounting_account_roles"
  ADD CONSTRAINT "accounting_account_roles_role_check"
    CHECK
    ((role = ANY (ARRAY['receivable'::text, 'payable'::text, 'bank'::text, 'revenue'::text, 'cogs'::text, 'inventory'::text, 'work_in_progress'::text, 'tax_payable'::text,
    'tax_receivable'::text,
    'deferred_revenue'::text,
    'retained_earnings'::text,
    'fx_gain'::text,
    'fx_loss'::text,
    'fixed_asset'::text, 'accumulated_depreciation'::text, 'depreciation_expense'::text, 'disposal_gain'::text, 'disposal_loss'::text, 'expense'::text, 'suspense'::text])));

ALTER TABLE "better_supabase"."accounting_recognition_rows"
  ADD CONSTRAINT "accounting_recognition_rows_schedule_id_fkey" FOREIGN KEY (schedule_id) REFERENCES better_supabase.accounting_recognition_schedules(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."commission_assignments"
  ADD CONSTRAINT "commission_assignments_tenant_id_plan_id_fkey" FOREIGN KEY (tenant_id, plan_id) REFERENCES better_supabase.commission_plans(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."commissions"
  ADD CONSTRAINT "commissions_tenant_id_plan_id_fkey" FOREIGN KEY (tenant_id, plan_id) REFERENCES better_supabase.commission_plans(tenant_id, id);

ALTER TABLE "better_supabase"."commissions"
  ADD CONSTRAINT "commissions_tenant_id_statement_id_fkey" FOREIGN KEY (tenant_id, statement_id) REFERENCES better_supabase.commission_statements(tenant_id, id);

ALTER TABLE "better_supabase"."notification_deliveries"
  ADD CONSTRAINT "notification_deliveries_status_check"
    CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'skipped'::text, 'held'::text, 'digested'::text])));

ALTER TABLE "better_supabase"."notification_digests"
  ADD CONSTRAINT "notification_digests_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."notification_preferences"
  ADD CONSTRAINT "notification_preferences_cadence_check" CHECK ((cadence = ANY (ARRAY['immediate'::text, 'daily'::text, 'weekly'::text, 'off'::text])));

ALTER TABLE "better_supabase"."referrals"
  ADD CONSTRAINT "referrals_tenant_id_code_id_fkey" FOREIGN KEY (tenant_id, code_id) REFERENCES better_supabase.referral_codes(tenant_id, id) ON DELETE CASCADE;

CREATE VIEW "api"."notification_preferences" WITH (security_invoker=true) AS  SELECT id,
    user_id,
    organization_id,
    type,
    channel,
    enabled,
    cadence,
    created_at,
    updated_at
   FROM better_supabase.notification_preferences;

CREATE VIEW "better_supabase"."maintenance_jobs" WITH (security_invoker=true) AS  SELECT j.job,
    j.fn AS function,
    j.every_interval AS every,
    s.last_run_at,
    s.last_status,
    s.last_error,
    COALESCE(s.runs, (0)::bigint) AS runs,
    ((s.last_run_at IS NULL) OR ((s.last_run_at + j.every_interval) <= now())) AS due
   FROM (( VALUES ('digest_run'::text,'"better_supabase"."run_notification_digests"'::text,'01:00:00'::interval), ('expire_approvals'::text,'"better_supabase"."expire_approvals"'::text,'00:15:00'::interval), ('purge_chat_state'::text,'"better_supabase"."purge_chat_state"'::text,'00:15:00'::interval), ('purge_expired_trash'::text,'"better_supabase"."purge_expired_trash"'::text,'1 day'::interval), ('purge_rate_limits'::text,'better_supabase.purge_rate_limits'::text,'00:15:00'::interval), ('purge_usage_events'::text,'"better_supabase"."purge_usage_events"'::text,'1 day'::interval), ('purge_webhook_deliveries'::text,'"better_supabase"."purge_webhook_deliveries"'::text,'1 day'::interval)) j(job, fn, every_interval)
     LEFT JOIN better_supabase.maintenance_state s ON ((s.job = j.job)));

CREATE INDEX accounting_recognition_rows_due_idx ON better_supabase.accounting_recognition_rows USING btree (tenant_id, due_on)
  WHERE (status = 'pending'::text);

CREATE INDEX accounting_recognition_rows_schedule_idx ON better_supabase.accounting_recognition_rows USING btree (schedule_id);

CREATE INDEX commission_assignments_plan_idx ON better_supabase.commission_assignments USING btree (tenant_id, plan_id);

CREATE INDEX commission_assignments_seller_idx ON better_supabase.commission_assignments USING btree (tenant_id, seller_id, starts_on DESC);

CREATE INDEX commission_plans_tenant_idx ON better_supabase.commission_plans USING btree (tenant_id, created_at DESC);

CREATE INDEX commission_statements_range_idx ON better_supabase.commission_statements USING btree (tenant_id, ends_on, status);

CREATE INDEX commissions_plan_idx ON better_supabase.commissions USING btree (tenant_id, plan_id);

CREATE INDEX commissions_seller_idx ON better_supabase.commissions USING btree (tenant_id, seller_id, currency, occurred_on);

CREATE INDEX commissions_statement_idx ON better_supabase.commissions USING btree (tenant_id, statement_id);

CREATE INDEX notification_digests_pending_idx ON better_supabase.notification_digests USING btree (created_at)
  WHERE (status = 'pending'::text);

CREATE INDEX notification_digests_user_idx ON better_supabase.notification_digests USING btree (user_id);

CREATE UNIQUE INDEX referral_codes_invitation_key ON better_supabase.referral_codes USING btree (tenant_id, invitation_id)
  WHERE (invitation_id IS NOT NULL);

CREATE INDEX referral_codes_referrer_idx ON better_supabase.referral_codes USING btree (tenant_id, referrer_id);

CREATE INDEX referrals_code_idx ON better_supabase.referrals USING btree (tenant_id, code_id);

CREATE UNIQUE INDEX referrals_organization_key ON better_supabase.referrals USING btree (tenant_id, referred_organization_id)
  WHERE (referred_organization_id IS NOT NULL);

CREATE INDEX referrals_referrer_idx ON better_supabase.referrals USING btree (tenant_id, referrer_id, created_at DESC);

CREATE UNIQUE INDEX referrals_user_key ON better_supabase.referrals USING btree (tenant_id, referred_user_id)
  WHERE (referred_user_id IS NOT NULL);

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.commission_assignments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "commission_assignment", "event_prefix": "commission_assignment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.commission_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "commission_plan", "event_prefix": "commission_plan"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.commission_statements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "commission_statement", "event_prefix": "commission_statement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.commissions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "commission", "event_prefix": "commission"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.referral_codes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "referral_code", "event_prefix": "referral_code"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.referrals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "referral", "event_prefix": "referral"}');

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."commission_assignments"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."commission_assignments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."commission_assignments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."commission_assignments"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "commission_assignments_read" ON "better_supabase"."commission_assignments"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."commission_plans"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."commission_plans"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."commission_plans"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."commission_plans"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "commission_plans_read" ON "better_supabase"."commission_plans"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."commission_statements"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."commission_statements"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."commission_statements"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."commission_statements"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "commission_statements_read" ON "better_supabase"."commission_statements"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."commissions"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."commissions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."commissions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."commissions"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "commissions_read" ON "better_supabase"."commissions"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('commissions.read'::text) AS tenant_ids_with)) OR (seller_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."referral_codes"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."referral_codes"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."referral_codes"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('referrals.read'::text) AS tenant_ids_with)) OR (referrer_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."referral_codes"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "referral_codes_read" ON "better_supabase"."referral_codes"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('referrals.read'::text) AS tenant_ids_with)) OR (referrer_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."referrals"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."referrals"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."referrals"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('referrals.read'::text) AS tenant_ids_with)) OR (referrer_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."referrals"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "referrals_read" ON "better_supabase"."referrals"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('referrals.read'::text) AS tenant_ids_with)) OR (referrer_id = ( SELECT auth.uid() AS uid))));

REVOKE ALL ON FUNCTION "api"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."attribute_referral"(uuid, text, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."attribute_referral"(uuid, text, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."build_commission_statement"(uuid, uuid, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."build_commission_statement"(uuid, uuid, text, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_notification_digests"(integer, interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_notification_digests"(integer, interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_amount"(text, integer, jsonb, bigint, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_amount"(text, integer, jsonb, bigint, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_close_range"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_close_range"(uuid, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_payroll_lines"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_payroll_lines"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."commission_plan_for"(uuid, uuid, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_plan_for"(uuid, uuid, text, text, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_statement_build"(uuid, uuid, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_statement_build"(uuid, uuid, text, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_statement_finalize"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_statement_finalize"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."commission_tiers_valid"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."commission_tiers_valid"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."complete_notification_digest"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_notification_digest"(uuid, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."end_commission_assignment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."end_commission_assignment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."finalize_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."finalize_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_commission_plans"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_commission_plans"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_commission_statements"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_commission_statements"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_commissions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_commissions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_referral_codes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_referral_codes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_referrals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_referrals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_cadence"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_cadence"(uuid, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."pay_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pay_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."qualify_referral"(uuid, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."qualify_referral"(uuid, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."referral_attribute"(uuid, text, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."referral_attribute"(uuid, text, uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."requires_consent"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."requires_consent"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reverse_commission"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reverse_commission"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."run_notification_digests"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."run_notification_digests"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."seed_accounting_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_accounting_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."seed_attachments_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_attachments_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."seed_calendar_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_calendar_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."seed_inbox_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_inbox_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."seed_pipelines_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_pipelines_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_notification_cadence"(text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_notification_cadence"(text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."void_referral"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."void_referral"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."build_commission_statement"(uuid, uuid, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."build_commission_statement"(uuid, uuid, text, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_notification_digests"(integer, interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_notification_digests"(integer, interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_amount"(text, integer, jsonb, bigint, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_amount"(text, integer, jsonb, bigint, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_close_range"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_close_range"(uuid, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_payroll_lines"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_payroll_lines"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_plan_for"(uuid, uuid, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_plan_for"(uuid, uuid, text, text, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_statement_build"(uuid, uuid, text, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_statement_build"(uuid, uuid, text, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_statement_finalize"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_statement_finalize"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."commission_tiers_valid"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."commission_tiers_valid"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_notification_digest"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_notification_digest"(uuid, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."consent_missing"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."consent_missing"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."end_commission_assignment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."end_commission_assignment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."finalize_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."finalize_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_commission_plans"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_commission_plans"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_commission_statements"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_commission_statements"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_commissions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_commissions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_referral_codes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_referral_codes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_referrals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_referrals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_cadence"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_cadence"(uuid, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pay_commission_statement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pay_commission_statement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."requires_consent"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."requires_consent"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reverse_commission"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reverse_commission"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."run_notification_digests"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."run_notification_digests"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_accounting_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_accounting_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_attachments_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_attachments_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_calendar_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_calendar_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_inbox_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_inbox_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_pipelines_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_pipelines_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_notification_cadence"(text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_notification_cadence"(text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."void_referral"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."void_referral"(uuid, text) TO "authenticated", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_recognition_rows" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_recognition_schedules" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."commission_assignments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."commission_assignments" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."commission_plans" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."commission_plans" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."commission_statements" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."commission_statements" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."commissions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."commissions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_digests" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."referral_codes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."referral_codes" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."referrals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."referrals" TO "service_role";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "api"."notification_preferences" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "api"."notification_preferences" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_jobs" TO "service_role";
