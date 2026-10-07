SET local check_function_bodies = off;

CREATE SCHEMA "api";

CREATE TABLE "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "dismissed_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "announcement_dismissals_pkey" PRIMARY KEY (announcement_id, user_id)
);

ALTER TABLE "better_supabase"."announcement_dismissals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."announcements" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "title"       text                     NOT NULL,
  "body"        text                     NOT NULL DEFAULT ''::text,
  "severity"    text                     NOT NULL DEFAULT 'info'::text,
  "href"        text,
  "audience"    text                     NOT NULL DEFAULT 'all'::text,
  "targets"     text[]                   NOT NULL DEFAULT '{}'::text[],
  "starts_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "ends_at"     timestamp with time zone,
  "dismissible" boolean                  NOT NULL DEFAULT true,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "announcements_body_check" CHECK ((length(body) <= 10000)),
  CONSTRAINT "announcements_check1" CHECK (((audience = 'all'::text) = (cardinality(targets) = 0))),
  CONSTRAINT "announcements_check" CHECK (((ends_at IS NULL) OR (ends_at > starts_at))),
  CONSTRAINT "announcements_href_check" CHECK ((href ~ '^(https://|/)'::text)),
  CONSTRAINT "announcements_pkey" PRIMARY KEY (id),
  CONSTRAINT "announcements_severity_check" CHECK ((severity = ANY (ARRAY['info'::text, 'success'::text, 'warning'::text, 'critical'::text]))),
  CONSTRAINT "announcements_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200))),
  CONSTRAINT "bs_announcements_audience" CHECK ((audience = ANY (ARRAY['all'::text, 'tenant'::text, 'role'::text, 'plan'::text]))),
  "created_by"  uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."announcements"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."flag_overrides" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "flag_key"        text                     NOT NULL,
  "organization_id" uuid,
  "user_id"         uuid,
  "variant"         text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "flag_overrides_check" CHECK (((organization_id IS NULL) <> (user_id IS NULL))),
  CONSTRAINT "flag_overrides_flag_key_organization_id_user_id_key" UNIQUE NULLS NOT DISTINCT (flag_key, organization_id, user_id),
  CONSTRAINT "flag_overrides_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."flag_overrides"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."flags" (
  "key"                text                     NOT NULL,
  "type"               text                     NOT NULL DEFAULT 'boolean'::text,
  "description"        text,
  "variants"           jsonb                    NOT NULL DEFAULT '{"on": true, "off": false}'::jsonb,
  "default_variant"    text                     NOT NULL DEFAULT 'off'::text,
  "enabled"            boolean                  NOT NULL DEFAULT true,
  "rules"              jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "rollout_percentage" numeric(5,2)             NOT NULL DEFAULT 0,
  "rollout_variant"    text,
  "updated_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "flags_check1" CHECK (((rollout_variant IS NULL) OR (variants ? rollout_variant))),
  CONSTRAINT "flags_check" CHECK ((variants ? default_variant)),
  CONSTRAINT "flags_key_check" CHECK ((key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'::text)),
  CONSTRAINT "flags_pkey" PRIMARY KEY (key),
  CONSTRAINT "flags_rollout_percentage_check" CHECK (((rollout_percentage >= (0)::numeric) AND (rollout_percentage <= (100)::numeric))),
  CONSTRAINT "flags_rules_check" CHECK ((jsonb_typeof(rules) = 'array'::text)),
  CONSTRAINT "flags_type_check" CHECK ((type = ANY (ARRAY['boolean'::text, 'string'::text, 'number'::text, 'object'::text]))),
  CONSTRAINT "flags_variants_check" CHECK ((jsonb_typeof(variants) = 'object'::text))
);

ALTER TABLE "better_supabase"."flags"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."invitations" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "email"           text                     NOT NULL,
  "role"            text                     NOT NULL,
  "token_hash"      text                     NOT NULL,
  "expires_at"      timestamp with time zone NOT NULL,
  "accepted_at"     timestamp with time zone,
  "invited_by"      uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "accepted_by"     uuid,
  "declined_at"     timestamp with time zone,
  "revoked_at"      timestamp with time zone,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invitations_pkey" PRIMARY KEY (id),
  CONSTRAINT "invitations_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text]))),
  CONSTRAINT "invitations_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "better_supabase"."invitations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."onboarding_progress" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "checklist"       text                     NOT NULL,
  "step"            text                     NOT NULL,
  "user_id"         uuid,
  "organization_id" uuid,
  "completed_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "onboarding_progress_checklist_step_user_id_organization_id_key" UNIQUE NULLS NOT DISTINCT (checklist, step, user_id, organization_id),
  CONSTRAINT "onboarding_progress_check" CHECK (((user_id IS NULL) <> (organization_id IS NULL))),
  CONSTRAINT "onboarding_progress_pkey" PRIMARY KEY (id),
  "completed_by"    uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."onboarding_progress"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."profiles" (
  "id"                     uuid                     NOT NULL,
  "email"                  text,
  "username"               text,
  "full_name"              text,
  "first_name"             text,
  "last_name"              text,
  "avatar_url"             text,
  "active_organization_id" uuid,
  "active_team_id"         uuid,
  "onboarding"             jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "disabled_at"            timestamp with time zone,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id),
  CONSTRAINT "profiles_username_check"
    CHECK
    (((username IS NULL) OR (((length(username) >= 3) AND (length(username) <= 32)) AND (username ~* '^[a-z][a-z0-9_]*$'::text) AND (lower(username) <> ALL (ARRAY['admin'::text,
    'administrator'::text,
    'api'::text,
    'app'::text,
    'auth'::text,
    'billing'::text,
    'help'::text, 'login'::text, 'logout'::text, 'me'::text, 'null'::text, 'root'::text, 'settings'::text, 'signup'::text, 'support'::text, 'system'::text, 'www'::text])))))
);

ALTER TABLE "better_supabase"."profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."usage_counters" (
  "organization_id" uuid                     NOT NULL,
  "meter"           text                     NOT NULL,
  "day"             date                     NOT NULL,
  "value"           numeric                  NOT NULL DEFAULT 0,
  "reported_value"  numeric                  NOT NULL DEFAULT 0,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "usage_counters_meter_check" CHECK ((meter ~ '^[a-z][a-z0-9_.:-]{0,63}$'::text)),
  CONSTRAINT "usage_counters_pkey" PRIMARY KEY (organization_id, meter, day),
  CONSTRAINT "usage_counters_reported_value_check" CHECK ((reported_value >= (0)::numeric)),
  CONSTRAINT "usage_counters_value_check" CHECK ((value >= (0)::numeric))
);

ALTER TABLE "better_supabase"."usage_counters"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."usage_events" (
  "organization_id" uuid                     NOT NULL,
  "meter"           text                     NOT NULL,
  "idempotency_key" text                     NOT NULL,
  "quantity"        numeric                  NOT NULL,
  "recorded_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "usage_events_pkey" PRIMARY KEY (organization_id, meter, idempotency_key)
);

ALTER TABLE "better_supabase"."usage_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."usage_quotas" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid,
  "plan"            text,
  "meter"           text                     NOT NULL,
  "limit"           numeric,
  "period"          text                     NOT NULL DEFAULT 'month'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "usage_quotas_check" CHECK (((organization_id IS NULL) <> (plan IS NULL))),
  CONSTRAINT "usage_quotas_limit_check" CHECK (("limit" >= (0)::numeric)),
  CONSTRAINT "usage_quotas_meter_check" CHECK ((meter ~ '^[a-z][a-z0-9_.:-]{0,63}$'::text)),
  CONSTRAINT "usage_quotas_organization_id_plan_meter_key" UNIQUE NULLS NOT DISTINCT (organization_id, plan, meter),
  CONSTRAINT "usage_quotas_period_check" CHECK ((period = ANY (ARRAY['day'::text, 'week'::text, 'month'::text, 'year'::text, 'billing'::text]))),
  CONSTRAINT "usage_quotas_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."usage_quotas"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."memberships" (
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "role"            text                     NOT NULL DEFAULT 'member'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "last_used_at"    timestamp with time zone,
  CONSTRAINT "memberships_pkey" PRIMARY KEY (organization_id, user_id),
  CONSTRAINT "memberships_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text])))
);

ALTER TABLE "public"."memberships"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."plan_features" (
  "plan_key"    text    NOT NULL,
  "feature_key" text    NOT NULL,
  "included"    boolean NOT NULL DEFAULT true,
  "value"       jsonb,
  CONSTRAINT "plan_features_pkey" PRIMARY KEY (plan_key, feature_key)
);

ALTER TABLE "public"."plan_features"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."plan_features" FROM "anon";

CREATE TABLE "public"."plans" (
  "key"         text    NOT NULL,
  "name"        text    NOT NULL,
  "price_cents" integer NOT NULL DEFAULT 0,
  "position"    integer NOT NULL DEFAULT 0,
  CONSTRAINT "plans_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."plans"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."plans" FROM "anon";

CREATE TABLE "public"."subscriptions" (
  "organization_id"    uuid                     NOT NULL,
  "plan_key"           text                     NOT NULL,
  "status"             text                     NOT NULL DEFAULT 'active'::text,
  "current_period_end" timestamp with time zone,
  "updated_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "subscriptions_pkey" PRIMARY KEY (organization_id),
  CONSTRAINT "subscriptions_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'trialing'::text, 'past_due'::text, 'canceled'::text])))
);

ALTER TABLE "public"."subscriptions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."subscriptions" FROM "anon";

CREATE OR REPLACE FUNCTION api.accept_invitation (
  token text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accept_invitation"($1) $function$;

CREATE OR REPLACE FUNCTION api.accept_invitation_by_id (
  invitation_id uuid
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accept_invitation_by_id"($1) $function$;

CREATE OR REPLACE FUNCTION api.active_announcements (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."active_announcements"($1) $function$;

CREATE OR REPLACE FUNCTION api.allocate_username (
  base    text,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."allocate_username"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.api_key_tenant()
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."api_key_tenant"() $function$;

CREATE OR REPLACE FUNCTION api.audit_event (
  event_type      text,
  category        text  DEFAULT NULL::text,
  outcome         text  DEFAULT 'success'::text,
  source          text  DEFAULT NULL::text,
  target_type     text  DEFAULT NULL::text,
  record_id       text  DEFAULT NULL::text,
  tenant          uuid  DEFAULT NULL::uuid,
  metadata        jsonb DEFAULT '{}'::jsonb,
  idempotency_key text  DEFAULT NULL::text,
  restricted      jsonb DEFAULT NULL::jsonb,
  actor_id        uuid  DEFAULT NULL::uuid,
  summary         text  DEFAULT NULL::text,
  target_label    text  DEFAULT NULL::text,
  correlation_id  text  DEFAULT NULL::text,
  actor_kind      text  DEFAULT NULL::text,
  actor_label     text  DEFAULT NULL::text,
  ip              inet  DEFAULT NULL::inet,
  user_agent      text  DEFAULT NULL::text,
  session_id      text  DEFAULT NULL::text,
  request_id      text  DEFAULT NULL::text,
  scope           text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_event"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21) $function$;

CREATE OR REPLACE FUNCTION api.audit_event_trusted (
  event_type      text,
  category        text  DEFAULT NULL::text,
  outcome         text  DEFAULT 'success'::text,
  source          text  DEFAULT NULL::text,
  target_type     text  DEFAULT NULL::text,
  record_id       text  DEFAULT NULL::text,
  tenant          uuid  DEFAULT NULL::uuid,
  metadata        jsonb DEFAULT '{}'::jsonb,
  idempotency_key text  DEFAULT NULL::text,
  restricted      jsonb DEFAULT NULL::jsonb,
  actor_id        uuid  DEFAULT NULL::uuid,
  summary         text  DEFAULT NULL::text,
  target_label    text  DEFAULT NULL::text,
  correlation_id  text  DEFAULT NULL::text,
  actor_kind      text  DEFAULT NULL::text,
  actor_label     text  DEFAULT NULL::text,
  ip              inet  DEFAULT NULL::inet,
  user_agent      text  DEFAULT NULL::text,
  session_id      text  DEFAULT NULL::text,
  request_id      text  DEFAULT NULL::text,
  scope           text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_event_trusted"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21) $function$;

CREATE OR REPLACE FUNCTION api.audit_events_tenants (
  older_than interval DEFAULT '1 day'::interval
)
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."audit_events_tenants"($1) $function$;

CREATE OR REPLACE FUNCTION api.backfill_profiles()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."backfill_profiles"() $function$;

CREATE OR REPLACE FUNCTION api.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."comment_counts"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.complete_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_onboarding_step"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.consume_quota (
  tenant          uuid,
  meter           text,
  quantity        numeric DEFAULT 1,
  idempotency_key text    DEFAULT NULL::text,
  source          text    DEFAULT NULL::text,
  metadata        jsonb   DEFAULT NULL::jsonb,
  actor           uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."consume_quota"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.copy_comments (
  tenant    uuid,
  from_type text,
  from_id   text,
  to_type   text,
  to_id     text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."copy_comments"($1, $2, $3, $4, $5) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."count_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) $function$;

CREATE OR REPLACE FUNCTION api.create_api_key (
  name        text,
  public_id   text,
  secret_hash text,
  tenant      uuid                     DEFAULT NULL::uuid,
  personal    boolean                  DEFAULT false,
  scopes      text[]                   DEFAULT '{}'::text[],
  expires_at  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  rate_limit  integer                  DEFAULT NULL::integer,
  prefix      text                     DEFAULT 'bs'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_api_key"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.create_comment (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  body         text,
  mentions     uuid[] DEFAULT '{}'::uuid[],
  parent       uuid   DEFAULT NULL::uuid,
  document     jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_comment"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.create_invitation (
  organization  uuid,
  invitee_email text,
  invitee_role  text     DEFAULT 'member'::text,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_invitation"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.create_organization (
  attrs jsonb
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_organization"($1) $function$;

CREATE OR REPLACE FUNCTION api.decline_invitation (
  token text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decline_invitation"($1) $function$;

CREATE OR REPLACE FUNCTION api.decline_invitation_by_id (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decline_invitation_by_id"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_comment (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_comment"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_flag (
  key text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_flag"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_organization"($1) $function$;

CREATE OR REPLACE FUNCTION api.dismiss_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."dismiss_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION api.edit_comment (
  id             uuid,
  body           text,
  mentions       uuid[]  DEFAULT NULL::uuid[],
  document       jsonb   DEFAULT NULL::jsonb,
  clear_document boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."edit_comment"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."entitlement_value"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.feature_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."feature_claims"($1) $function$;

CREATE OR REPLACE FUNCTION api.flag_bucket (
  flag   text,
  target text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_bucket"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.flag_definitions()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_definitions"() $function$;

CREATE OR REPLACE FUNCTION api.flag_enabled (
  key    text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_enabled"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.flag_evaluation (
  key    text,
  tenant uuid DEFAULT NULL::uuid,
  member uuid DEFAULT auth.uid()
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_evaluation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_organization_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_organization_settings"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_platform_settings()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_platform_settings"() $function$;

CREATE OR REPLACE FUNCTION api.get_user_settings()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_user_settings"() $function$;

CREATE OR REPLACE FUNCTION api.has_entitlement (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."has_entitlement"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.has_scope (
  scope text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."has_scope"($1) $function$;

CREATE OR REPLACE FUNCTION api.invitation_preview (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invitation_preview"($1) $function$;

CREATE OR REPLACE FUNCTION api.invite_member (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval,
  prefill       jsonb    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invite_member"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.leave_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."leave_organization"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_activity"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_announcements()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_announcements"() $function$;

CREATE OR REPLACE FUNCTION api.list_api_keys (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_api_keys"($1) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18) $function$;

CREATE OR REPLACE FUNCTION api.list_comments (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100,
  skip         integer                  DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_comments"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_flags()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_flags"() $function$;

CREATE OR REPLACE FUNCTION api.mark_usage_reported (
  tenant uuid,
  meter  text,
  day    date,
  value  numeric
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_usage_reported"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.mark_used (
  organization uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_used"($1) $function$;

CREATE OR REPLACE FUNCTION api.my_invitations()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_invitations"() $function$;

CREATE OR REPLACE FUNCTION api.onboarding_progress (
  checklist text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."onboarding_progress"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_slug_problem"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_audit_log (
  older_than interval DEFAULT '1 year'::interval,
  batch      integer  DEFAULT 10000,
  tenant     uuid     DEFAULT NULL::uuid,
  for_tenant boolean  DEFAULT false
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_audit_log"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.purge_usage_events (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_usage_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_usage_history (
  older_than interval DEFAULT '400 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_usage_history"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_activity (
  batch jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_activity"($1) $function$;

CREATE OR REPLACE FUNCTION api.record_usage (
  tenant          uuid,
  meter           text,
  quantity        numeric DEFAULT 1,
  idempotency_key text    DEFAULT NULL::text,
  source          text    DEFAULT NULL::text,
  metadata        jsonb   DEFAULT NULL::jsonb,
  actor           uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_usage"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.record_usage_batch (
  tenant          uuid,
  entries         jsonb,
  idempotency_key text  DEFAULT NULL::text,
  "check" boolean DEFAULT false,
  source          text  DEFAULT NULL::text,
  metadata        jsonb DEFAULT NULL::jsonb,
  actor           uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_usage_batch"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.remove_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_member"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.resend_invitation (
  invitation_id uuid,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resend_invitation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.reset_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reset_onboarding_step"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.reset_organization_setting (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reset_organization_setting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.reset_platform_setting (
  key text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reset_platform_setting"($1) $function$;

CREATE OR REPLACE FUNCTION api.reset_user_setting (
  key text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reset_user_setting"($1) $function$;

CREATE OR REPLACE FUNCTION api.revoke_api_key (
  key uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revoke_api_key"($1) $function$;

CREATE OR REPLACE FUNCTION api.revoke_invitation (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revoke_invitation"($1) $function$;

CREATE OR REPLACE FUNCTION api.rotate_api_key (
  key         uuid,
  public_id   text,
  secret_hash text,
  grace       interval DEFAULT '1 day'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_api_key"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_announcement (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_announcement"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_flag (
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_flag"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_flag_override (
  key     text,
  variant text,
  tenant  uuid DEFAULT NULL::uuid,
  member  uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_flag_override"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_organization_setting (
  tenant uuid,
  key    text,
  value  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_organization_setting"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_platform_setting (
  key   text,
  value jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_platform_setting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_user_setting (
  key   text,
  value jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_user_setting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.switch_organization (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."switch_organization"($1) $function$;

CREATE OR REPLACE FUNCTION api.sync_profile (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sync_profile"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_entitlement_value"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.tenant_entitlements (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_entitlements"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with_entitlement (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with_entitlement"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with_flag (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with_flag"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_plans (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_plans"($1) $function$;

CREATE OR REPLACE FUNCTION api.transfer_ownership (
  organization uuid,
  new_owner    uuid,
  former_role  text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."transfer_ownership"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unreported_usage (
  max_rows     integer DEFAULT 500,
  skip_meters  text[]  DEFAULT '{}'::text[],
  skip_tenants uuid[]  DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unreported_usage"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.update_invitation (
  invitation_id uuid,
  invitee_email text  DEFAULT NULL::text,
  invitee_role  text  DEFAULT NULL::text,
  prefill       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_invitation"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.update_member_role (
  organization uuid,
  member       uuid,
  role         text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_member_role"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_organization"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_breakdown (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE sql
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
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_history"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.usage_meters()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_meters"() $function$;

CREATE OR REPLACE FUNCTION api.usage_overview (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
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
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."usage_quota"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_status (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_status"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_used (
  tenant uuid,
  meter  text,
  period text DEFAULT 'month'::text
)
  RETURNS numeric
  LANGUAGE sql
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
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."usage_window"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.usage_window_start (
  tenant uuid,
  period text,
  day    date
)
  RETURNS date
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_window_start"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.verify_api_key (
  public_id   text,
  secret_hash text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."verify_api_key"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.within_quota (
  tenant   uuid,
  meter    text,
  quantity bigint DEFAULT 1
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."within_quota"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation (
  token text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  
  
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation_by_id (
  invitation_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."id" = invitation_id
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  
  
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.active_announcements (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        when 'plan' then v_tenant is not null and x."targets" && better_supabase.tenant_entitlements(v_tenant)
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.allocate_username (
  base    text,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type      text,
  category        text  DEFAULT NULL::text,
  outcome         text  DEFAULT 'success'::text,
  source          text  DEFAULT NULL::text,
  target_type     text  DEFAULT NULL::text,
  record_id       text  DEFAULT NULL::text,
  tenant          uuid  DEFAULT NULL::uuid,
  metadata        jsonb DEFAULT '{}'::jsonb,
  idempotency_key text  DEFAULT NULL::text,
  restricted      jsonb DEFAULT NULL::jsonb,
  actor_id        uuid  DEFAULT NULL::uuid,
  summary         text  DEFAULT NULL::text,
  target_label    text  DEFAULT NULL::text,
  correlation_id  text  DEFAULT NULL::text,
  actor_kind      text  DEFAULT NULL::text,
  actor_label     text  DEFAULT NULL::text,
  ip              inet  DEFAULT NULL::inet,
  user_agent      text  DEFAULT NULL::text,
  session_id      text  DEFAULT NULL::text,
  request_id      text  DEFAULT NULL::text,
  scope           text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set sql.modules.audit.options.restricted to true.';
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
  elsif actor_id is null then
    actor_id := auth.uid();
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
    case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end,
    auth.jwt() -> 'act' ->> 'reason',
    case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end,
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
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
    coalesce(request_id, better_supabase.request_header('x-request-id')),
    coalesce(correlation_id, better_supabase.request_header('x-correlation-id')),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type      text,
  category        text  DEFAULT NULL::text,
  outcome         text  DEFAULT 'success'::text,
  source          text  DEFAULT NULL::text,
  target_type     text  DEFAULT NULL::text,
  record_id       text  DEFAULT NULL::text,
  tenant          uuid  DEFAULT NULL::uuid,
  metadata        jsonb DEFAULT '{}'::jsonb,
  idempotency_key text  DEFAULT NULL::text,
  restricted      jsonb DEFAULT NULL::jsonb,
  actor_id        uuid  DEFAULT NULL::uuid,
  summary         text  DEFAULT NULL::text,
  target_label    text  DEFAULT NULL::text,
  correlation_id  text  DEFAULT NULL::text,
  actor_kind      text  DEFAULT NULL::text,
  actor_label     text  DEFAULT NULL::text,
  ip              inet  DEFAULT NULL::inet,
  user_agent      text  DEFAULT NULL::text,
  session_id      text  DEFAULT NULL::text,
  request_id      text  DEFAULT NULL::text,
  scope           text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set sql.modules.audit.options.restricted to true.';
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
    case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end,
    auth.jwt() -> 'act' ->> 'reason',
    case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end,
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
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
    coalesce(request_id, better_supabase.request_header('x-request-id')),
    coalesce(correlation_id, better_supabase.request_header('x-correlation-id')),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
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
begin
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
      settings ->> 'label_column' as label_column
    into entry;
  else
    select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
      coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
      a.label_column
    into entry
    from (select 1) one
    left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
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
    auth.uid(),
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
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    (select o."name"::text from "public"."organizations" o where o."id" = row_tenant),
    row_data ->> entry.label_column,
    null,
    (v_headers ->> 'x-request-id'),
    (v_headers ->> 'x-correlation-id'),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.backfill_profiles()
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_announcement()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign (
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or (auth.uid() is not null and better_supabase.can_assign_as(auth.uid(), tenant, role))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign_as (
  member uuid,
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    (better_supabase.member_can(member, tenant, 'members.invite')
      or better_supabase.member_can(member, tenant, 'members.update_role'))
    and better_supabase.role_rank(better_supabase.organization_member_role(tenant, member))
      >= better_supabase.role_rank(role)
    and better_supabase.role_rank(role) > 0,
    false
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    scope = 'tenant'
      and r.role is not null
      and exists (
        select 1 from unnest(better_supabase.role_permissions(r.role)) k(key)
        where k.key = '*' or k.key = permission
      ),
    false
  )
  from (select better_supabase.organization_member_role(scope_id, member) as role) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clear_tenant_claim()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update auth.users u
  set raw_app_meta_data = u.raw_app_meta_data - 'tenant_id'
  where u.id = old.user_id
    and u.raw_app_meta_data ->> 'tenant_id' = old.organization_id::text;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  v_scope := (select s.scope from (values ('getting-started', 'customer', 'organization'), ('getting-started', 'invite', 'organization'), ('getting-started', 'api-key', 'organization'), ('getting-started', 'plan', 'organization')) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  insert into "better_supabase"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.consume_quota (
  tenant          uuid,
  meter           text,
  quantity        numeric DEFAULT 1,
  idempotency_key text    DEFAULT NULL::text,
  source          text    DEFAULT NULL::text,
  metadata        jsonb   DEFAULT NULL::jsonb,
  actor           uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  quota record;
  used numeric;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.record'), false)) then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.consume_quota'), hashtext(tenant::text || '/' || meter));
  if idempotency_key is not null and exists (
    select 1 from "better_supabase"."usage_events" e
    where e."organization_id" = consume_quota.tenant and e."meter" = consume_quota.meter and e."idempotency_key" = consume_quota.idempotency_key
  ) then
    return jsonb_build_object('recorded', false, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  if quota.quota_limit is not null then
    used := "better_supabase"."usage_used"(tenant, meter, quota.period);
    if used + quantity > quota.quota_limit then
      select * into win from "better_supabase"."usage_window"(tenant, quota.period);
      raise exception 'Quota for % exceeded', meter using
        errcode = 'BSQ29',
        hint = 'QUOTA_EXCEEDED',
        detail = jsonb_build_object(
          'meter', meter,
          'limit', quota.quota_limit,
          'used', used,
          'retry_after', greatest(1, ceil(extract(epoch from win.ends_at - now()))::integer)
        )::text;
    end if;
  end if;
  return "better_supabase"."record_usage"(tenant, meter, quantity, idempotency_key, source, metadata, actor);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_invitation (
  organization  uuid,
  invitee_email text,
  invitee_role  text     DEFAULT 'member'::text,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select "better_supabase"."invite_member"($1, $2, $3, $4) ->> 'token'
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
  values (organization, owner, 'owner');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  
  return organization;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
begin
  update "better_supabase"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation_by_id (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
  invitee_email text;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_flag (
  key text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  perform better_supabase.audit_event(
    event_type => 'organization.deleted',
    category => 'organization',
    tenant => organization,
    metadata => jsonb_build_object('mode', 'hard')
  );
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dismiss_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_organization_owner()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from "public"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "public"."memberships" m where m."organization_id" = old."organization_id" and m."role" = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case when better_supabase.has_organization_role(tenant) then better_supabase.tenant_entitlement_value(tenant, key) end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.feature_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(r.tenant, to_jsonb(r.keys)), '{}'::jsonb)
  from (
    select m."organization_id"::text as tenant, e.keys
    from "public"."memberships" m
    cross join lateral (select better_supabase.tenant_entitlements(m."organization_id") as keys) e
    where m."user_id" = feature_claims.user_id
      and cardinality(e.keys) > 0
    order by 1
  ) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_bucket (
  flag   text,
  target text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select (('x' || substr(encode(extensions.digest(flag || '.' || target, 'sha256'), 'hex'), 1, 8))::bit(32)::bigint % 10000)::integer
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_definitions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', x."key",
    'type', x."type",
    'variants', x."variants",
    'default_variant', x."default_variant",
    'enabled', x."enabled",
    'rules', x."rules",
    'rollout_percentage', x."rollout_percentage",
    'rollout_variant', x."rollout_variant",
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v."organization_id", 'user_id', v."user_id", 'variant', v."variant"))
      from "better_supabase"."flag_overrides" v where v."flag_key" = x."key"
    ), '[]'::jsonb)
  ) order by x."key"), '[]'::jsonb)
  from "better_supabase"."flags" x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_enabled (
  key    text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(("better_supabase"."flag_evaluation"(key, tenant) -> 'value') = 'true'::jsonb, false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_evaluation (
  key    text,
  tenant uuid DEFAULT NULL::uuid,
  member uuid DEFAULT auth.uid()
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  flag "better_supabase"."flags";
  chosen text;
  reason text := 'DEFAULT';
  rule jsonb;
  role text;
  tenant_plans text[];
  target text := coalesce(member::text, tenant::text);
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
  select x."variant" into chosen from "better_supabase"."flag_overrides" x
  where x."flag_key" = flag."key"
    and ((member is not null and x."user_id" = member) or (tenant is not null and x."organization_id" = tenant))
  order by (x."user_id" is not null) desc
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    -- The role and plan lookups run only for flags with rules that read them.
    if tenant is not null and flag."rules" @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and flag."rules" @? '$[*].plans' then
      tenant_plans := better_supabase.tenant_entitlements(tenant);
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if (not rule ? 'tenants' or rule -> 'tenants' ? coalesce(tenant::text, ''))
        and (not rule ? 'users' or rule -> 'users' ? coalesce(member::text, ''))
        and (not rule ? 'roles' or rule -> 'roles' ? coalesce(role, ''))
        and (not rule ? 'plans' or rule -> 'plans' ?| coalesce(tenant_plans, '{}'))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;
  if chosen is null and flag."rollout_variant" is not null and target is not null
    and "better_supabase"."flag_bucket"(flag."key", target) < flag."rollout_percentage" * 100 then
    chosen := flag."rollout_variant";
    reason := 'SPLIT';
  end if;
  if chosen is null or not flag."variants" ? chosen then
    chosen := flag."default_variant";
    reason := 'DEFAULT';
  end if;
  return jsonb_build_object('value', flag."variants" -> chosen, 'variant', chosen, 'reason', reason);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if not (current_user in ('anon', 'authenticated')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new."role" is not distinct from old."role" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role"::text end
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership_role (
  target_tenant   uuid,
  target_member   uuid,
  target_role     text,
  previous_tenant uuid,
  previous_role   text
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, target_role::text)
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, previous_role::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_profile()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.has_entitlement (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select better_supabase.has_organization_role(tenant)
    and key = any (better_supabase.tenant_entitlements(tenant))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invitation_extra (
  invitation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  hook regprocedure := to_regprocedure('"public"."invitation_preview_extra"(uuid)');
  extra jsonb;
begin
  if hook is null or invitation is null then
    return '{}'::jsonb;
  end if;
  -- Not a literal name, so plpgsql_check passes without the hook.
  execute format('select %s($1)', hook::oid::regproc) into extra using invitation;
  return coalesce(extra, '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invitation_preview (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  preview jsonb;
  invitation uuid;
begin
  select jsonb_build_object(
    'status', case
    when i."accepted_at" is not null then 'accepted'
    when i."declined_at" is not null then 'declined'
    when i."revoked_at" is not null then 'revoked'
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role",
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = i."organization_id"),
    'prefill', '{}'::jsonb
  ), i."id"
  into preview, invitation
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(invitation_preview.token, 'sha256'), 'hex');
  if preview is not null then
    preview := preview || "better_supabase"."invitation_extra"(invitation);
  end if;
  return preview;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invitation_tenant_ids()
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query select better_supabase.tenant_ids_with('members.invite');
end;
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
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    raise exception 'Platform invitations need platform roles: sql.modules.access.model ''catalog'' with platform assignments, or sql.modules.invitations.options.platformRoles under ''permdock''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
  end if;
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

CREATE OR REPLACE FUNCTION better_supabase.leave_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_announcements()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_flags()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return "better_supabase"."flag_definitions"();
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_usage_reported (
  tenant uuid,
  meter  text,
  day    date,
  value  numeric
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with updated as (
    update "better_supabase"."usage_counters" c set "reported_value" = greatest(c."reported_value", mark_usage_reported.value)
    where c."organization_id" = mark_usage_reported.tenant
      and c."meter" = mark_usage_reported.meter
      and c."day" = mark_usage_reported.day
    returning 1
  )
  select exists (select 1 from updated)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_used (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "public"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_can (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select better_supabase.can_user(member, 'tenant', tenant, permission)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_organization_ids (
  roles text[] DEFAULT NULL::text[]
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select m.organization_id
  from public.memberships m
  where m.user_id = auth.uid() and (roles is null or m.role = any (roles))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.membership_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(
    jsonb_build_object('scope', 'tenant', 'id', m.organization_id, 'roles', jsonb_build_array(m.role))
    order by m.created_at, m.organization_id
  ), '[]'::jsonb)
  from public.memberships m
  where m.user_id = membership_claims.user_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mirror_profile_email()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_invitations()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  invitee_email text;
  result jsonb := '[]'::jsonb;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return result;
  end if;
  select coalesce(jsonb_agg(x.invitation order by x.expires_at), '[]'::jsonb)
  into result
  from (
    select (jsonb_build_object(
    'id', i."id",
    'tenant', i."organization_id",
    'email', i."email",
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = i."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  ) x;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.on_auth_user_created()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.onboarding_progress (
  checklist text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (values ('getting-started', 'customer', 'organization'), ('getting-started', 'invite', 'organization'), ('getting-started', 'api-key', 'organization'), ('getting-started', 'plan', 'organization')) as s(checklist, step, scope) where s.checklist = onboarding_progress.checklist and (null::text is null or s.step = null::text) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', onboarding_progress.tenant, 'onboarding.read'), false)) then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', x."step",
      'completedAt', x."completed_at",
      'completedBy', x."completed_by"
    ) order by x."completed_at"), '[]'::jsonb)
    from "better_supabase"."onboarding_progress" x
    where x."checklist" = onboarding_progress.checklist
      and (case when v_scope = 'organization' then x."organization_id" = onboarding_progress.tenant else x."user_id" = auth.uid() end)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_member_role (
  organization uuid,
  member       uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select m.role
  from public.memberships m
  where m.organization_id = organization and m.user_id = member
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when false then 'reserved'
    when exists (
      select 1 from "public"."organizations" o
      where lower(o."slug"::text) = lower(value)
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_usage_events (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with gone as (
    delete from "better_supabase"."usage_events" x
    where (x."organization_id", x."meter", x."idempotency_key") in (
      select e."organization_id", e."meter", e."idempotency_key" from "better_supabase"."usage_events" e
      where e."recorded_at" < now() - coalesce(older_than, '30 days')
      order by e."recorded_at" limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_usage_history (
  older_than interval DEFAULT '400 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_usage (
  tenant          uuid,
  meter           text,
  quantity        numeric DEFAULT 1,
  idempotency_key text    DEFAULT NULL::text,
  source          text    DEFAULT NULL::text,
  metadata        jsonb   DEFAULT NULL::jsonb,
  actor           uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.record'), false)) then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  if quantity is null or quantity < 0 then
    raise exception 'quantity must be zero or more' using errcode = '22023', hint = 'USAGE_QUANTITY';
  end if;
  if idempotency_key is not null then
    insert into "better_supabase"."usage_events" ("organization_id", "meter", "idempotency_key", "quantity")
    values (tenant, meter, idempotency_key, quantity)
    on conflict do nothing;
    if not found then
      return jsonb_build_object('recorded', false, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
    end if;
  end if;
  insert into "better_supabase"."usage_counters" as c ("organization_id", "meter", "day", "value")
  values (tenant, meter, today, quantity)
  on conflict ("organization_id", "meter", "day") do update
    set "value" = c."value" + excluded."value", "updated_at" = now();
  return jsonb_build_object('recorded', true, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_usage_batch (
  tenant          uuid,
  entries         jsonb,
  idempotency_key text  DEFAULT NULL::text,
  "check" boolean DEFAULT false,
  source          text  DEFAULT NULL::text,
  metadata        jsonb DEFAULT NULL::jsonb,
  actor           uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry jsonb;
  outcome jsonb;
  recorded boolean := false;
  used jsonb := '{}';
  today_used jsonb := '{}';
begin
  -- A JSON text of the array, as a transport that sends arrays as text passes it.
  if jsonb_typeof(entries) = 'string' then
    entries := (entries #>> '{}')::jsonb;
  end if;
  if jsonb_typeof(entries) <> 'array' or jsonb_array_length(entries) = 0 then
    raise exception 'entries must be a non-empty array of { meter, quantity }' using errcode = '22023', hint = 'USAGE_ENTRIES';
  end if;
  for entry in select value from jsonb_array_elements(entries) loop
    if jsonb_typeof(entry -> 'meter') <> 'string' then
      raise exception 'Every entry needs a meter' using errcode = '22023', hint = 'USAGE_ENTRIES';
    end if;
    if record_usage_batch."check" then
      outcome := "better_supabase"."consume_quota"(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    else
      outcome := "better_supabase"."record_usage"(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    end if;
    recorded := recorded or (outcome ->> 'recorded')::boolean;
    used := used || jsonb_build_object(entry ->> 'meter', outcome -> 'used');
    today_used := today_used || jsonb_build_object(entry ->> 'meter', outcome -> 'today');
  end loop;
  return jsonb_build_object('recorded', recorded, 'used', used, 'today', today_used);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resend_invitation (
  invitation_id uuid,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated "better_supabase"."invitations";
begin
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "better_supabase"."invitations" i
  set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(updated."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_count integer;
begin
  v_scope := (select s.scope from (values ('getting-started', 'customer', 'organization'), ('getting-started', 'invite', 'organization'), ('getting-started', 'api-key', 'organization'), ('getting-started', 'plan', 'organization')) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  delete from "better_supabase"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_invitation (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant text;
begin
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
    
    return true;
  end if;
  return false;
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
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_rank (
  role text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role when 'owner' then 3 when 'admin' then 2 when 'member' then 1 else 0 end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_announcement (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
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
  d jsonb := coalesce(definition, '{}');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    d ->> 'rollout_variant'
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key     text,
  variant text,
  tenant  uuid DEFAULT NULL::uuid,
  member  uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if (tenant is null) = (member is null) then
    raise exception 'Pass a tenant or a member, not both' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member;
    return found;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.variant)
  on conflict ("flag_key", "organization_id", "user_id") do update set "variant" = excluded."variant";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.switch_organization (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('tenant_id', organization::text)
  where id = me;
  update "public"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  
  return jsonb_build_object('organization_id', organization, 'refresh', true);
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
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
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

CREATE OR REPLACE FUNCTION better_supabase.tenant_entitlement_value (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(to_jsonb(f."value"), 'true'::jsonb)
    from "public"."subscriptions" s
    join "public"."plan_features" f on f."plan_key"::text = s."plan_key"::text
    where s."organization_id" = tenant_entitlement_value.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and f."included"
      and f."feature_key"::text = tenant_entitlement_value.key
    order by case when jsonb_typeof(to_jsonb(f."value")) = 'number' then (to_jsonb(f."value") #>> '{}')::numeric end desc nulls last,
      s."plan_key"::text
    limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_entitlements (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(distinct f."feature_key"::text order by f."feature_key"::text), '{}')
    from "public"."subscriptions" s
    join "public"."plan_features" f on f."plan_key"::text = s."plan_key"::text
    where s."organization_id" = tenant_entitlements.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and f."included"
      and f."feature_key" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_ids_with_entitlement (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  ROWS 1
  SET search_path TO ''
  AS $function$
  select t.id from better_supabase.member_organization_ids() as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_ids_with_flag (
  key text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select t.id from better_supabase.member_organization_ids() as t(id)
  where "better_supabase"."flag_enabled"(tenant_ids_with_flag.key, t.id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_plans (
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(distinct s."plan_key"::text order by s."plan_key"::text), '{}')
    from "public"."subscriptions" s
    where s."organization_id" = tenant_plans.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and s."plan_key" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transfer_ownership (
  organization uuid,
  new_owner    uuid,
  former_role  text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and m."role" = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners (PermDock's transferOnly) sees the transfer as a whole.
  update "public"."memberships" m set "role" = case
      when m."user_id" = new_owner then 'owner'
      else former_role
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and m."role" = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unreported_usage (
  max_rows     integer DEFAULT 500,
  skip_meters  text[]  DEFAULT '{}'::text[],
  skip_tenants uuid[]  DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', c."organization_id",
    'meter', c."meter",
    'day', c."day",
    'value', c."value",
    'reported_value', c."reported_value",
    'included', q.quota_limit,
    'unlimited', q.period is not null and q.quota_limit is null,
    'window_before', (
      select coalesce(sum(o."value"), 0)
      from "better_supabase"."usage_counters" o
      where o."organization_id" = c."organization_id" and o."meter" = c."meter"
        and o."day" < c."day"
        and o."day" >= w.since
    )
  ) order by c."day", c."meter"), '[]'::jsonb)
  from (
    select * from "better_supabase"."usage_counters" c
    where c."value" > c."reported_value"
      and c."meter" <> all (coalesce(unreported_usage.skip_meters, '{}'))
      and c."organization_id" <> all (coalesce(unreported_usage.skip_tenants, '{}'))
    order by c."day"
    limit max_rows
  ) c
  left join lateral "better_supabase"."usage_quota"(c."organization_id", c."meter") q on true
  cross join lateral (
    select "better_supabase"."usage_window_start"(c."organization_id", q.period, c."day") as since
  ) w
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_invitation (
  invitation_id uuid,
  invitee_email text  DEFAULT NULL::text,
  invitee_role  text  DEFAULT NULL::text,
  prefill       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  current_invite "better_supabase"."invitations";
  updated "better_supabase"."invitations";
  tenant uuid;
begin
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "better_supabase"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, (invitee_role)::text))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  if invitee_email is not null then
    delete from "better_supabase"."invitations" i
    where i."organization_id" = tenant
      and lower(i."email") = lower(btrim(invitee_email))
      and i."id" <> invitation_id
      and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  end if;
  updated := current_invite;
    if invitee_email is not null then
      updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      updated."role" := invitee_role;
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(updated."id")) - 'token';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_member_role (
  organization uuid,
  member       uuid,
  role         text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever sql.modules.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_breakdown (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  quota record;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  select * into win from "better_supabase"."usage_window"(tenant, coalesce(quota.period, 'month'));
  return '[]'::jsonb;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_history (
  tenant    uuid,
  meter     text    DEFAULT NULL::text,
  max_rows  integer DEFAULT 100,
  before_id bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return '[]'::jsonb;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_meters()
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select '{}'::jsonb
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_overview (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg("better_supabase"."usage_status"(usage_overview.tenant, m.meter) order by m.meter), '[]'::jsonb)
    from (
      select jsonb_object_keys("better_supabase"."usage_meters"()) as meter
      union
      select q."meter" from "better_supabase"."usage_quotas" q
      where q."organization_id" = usage_overview.tenant
        or (q."organization_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(usage_overview.tenant)) or q."plan" = any (better_supabase.tenant_plans(usage_overview.tenant))))
      union
      select distinct c."meter" from "better_supabase"."usage_counters" c
      where c."organization_id" = usage_overview.tenant
    ) m
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_quota (
  tenant uuid,
  meter  text
)
  RETURNS TABLE (
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select q."limit", q."period"
  from "better_supabase"."usage_quotas" q
  where q."meter" = usage_quota.meter
    and (q."organization_id" = usage_quota.tenant or (q."organization_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(tenant)) or q."plan" = any (better_supabase.tenant_plans(tenant)))))
  order by (q."organization_id" is not null) desc, q."limit" desc nulls first
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_status (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  quota record;
  used numeric;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  select * into win from "better_supabase"."usage_window"(tenant, coalesce(quota.period, 'month'));
  used := "better_supabase"."usage_used"(tenant, meter, coalesce(quota.period, 'month'));
  return jsonb_build_object(
    'meter', meter,
    'used', used,
    'limit', quota.quota_limit,
    'remaining', case when quota.quota_limit is null then null else greatest(quota.quota_limit - used, 0) end,
    'unlimited', quota.period is not null and quota.quota_limit is null,
    'period', coalesce(quota.period, 'month'),
    'resets_at', win.ends_at,
    'starts_at', win.starts_at
  ) || coalesce("better_supabase"."usage_meters"() -> meter, '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_used (
  tenant uuid,
  meter  text,
  period text DEFAULT 'month'::text
)
  RETURNS numeric
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(sum(c."value"), 0)::numeric
  from "better_supabase"."usage_counters" c, "better_supabase"."usage_window"(usage_used.tenant, usage_used.period) w
  where c."organization_id" = usage_used.tenant
    and c."meter" = usage_used.meter
    and c."day" >= (w.starts_at at time zone 'utc')::date
    and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_window (
  tenant uuid,
  period text DEFAULT 'month'::text
)
  RETURNS TABLE (
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_period text := coalesce(usage_window.period, 'month');
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_period = 'billing' then
    if to_regprocedure('"public"."usage_billing_period"(uuid)') is not null then
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select h.starts_at, h.ends_at from %s($1) h', to_regprocedure('"public"."usage_billing_period"(uuid)')::oid::regproc)
        into v_start, v_end using usage_window.tenant;
    end if;
    if v_start is null or v_end is null or v_end <= v_start then
      v_period := 'month';
      v_start := null;
    end if;
  end if;
  if v_start is null then
    v_start := date_trunc(v_period, now() at time zone 'utc') at time zone 'utc';
    v_end := v_start + ('1 ' || v_period)::interval;
  end if;
  return query select v_start, v_end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_window_start (
  tenant uuid,
  period text,
  day    date
)
  RETURNS date
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_length interval;
  v_steps integer := 0;
begin
  if usage_window_start.period is null then
    return usage_window_start.day;
  end if;
  if usage_window_start.period <> 'billing' then
    return date_trunc(usage_window_start.period, usage_window_start.day)::date;
  end if;
  select w.starts_at, w.ends_at into v_start, v_end
  from "better_supabase"."usage_window"(usage_window_start.tenant, 'billing') w;
  v_length := age(v_end, v_start);
  while usage_window_start.day < (v_start at time zone 'utc')::date and v_steps < 120 loop
    v_start := v_start - v_length;
    v_steps := v_steps + 1;
  end loop;
  if usage_window_start.day < (v_start at time zone 'utc')::date then
    return date_trunc('month', usage_window_start.day)::date;
  end if;
  return (v_start at time zone 'utc')::date;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.within_quota (
  tenant   uuid,
  meter    text,
  quantity bigint DEFAULT 1
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  quota record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.has_organization_role(tenant), false)) then
    return false;
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  if quota.quota_limit is null then
    return true;
  end if;
  return "better_supabase"."usage_used"(tenant, meter, quota.period) + quantity <= quota.quota_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_organizations()
  RETURNS TABLE (
    id           uuid,
    name         text,
    slug         text,
    role         text,
    plan         text,
    last_used_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select o.id, o.name, o.slug, m.role, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
  order by o.name;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."my_organizations"() FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.my_profile()
  RETURNS TABLE (
    full_name  text,
    email      text,
    username   text,
    avatar_url text
  )
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return query
  select p.full_name, p.email, p.username, p.avatar_url
  from better_supabase.profiles p
  where p.id = (select auth.uid());
end;
$function$;

REVOKE ALL ON FUNCTION "public"."my_profile"() FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    invited_by text,
    created_at timestamp with time zone,
    expires_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.invite') then
    raise exception 'Not allowed to list invitations' using errcode = '42501';
  end if;
  return query
  select i.id, i.email, i.role, coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.organization_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."organization_invitations"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id    uuid,
    role       text,
    full_name  text,
    email      text,
    avatar_url text,
    joined_at  timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.read') then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, m.role, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, m.created_at
  from public.memberships m
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by better_supabase.role_rank(m.role) desc, coalesce(p.full_name, u.email::text);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.update_my_profile (
  full_name text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  update better_supabase.profiles p
  set full_name = nullif(btrim(update_my_profile.full_name), ''), updated_at = now()
  where p.id = (select auth.uid());
end;
$function$;

REVOKE ALL ON FUNCTION "public"."update_my_profile"(text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION rbac.custom_access_token_hook (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  claims jsonb := event -> 'claims';
  user_role rbac.app_role;
begin
  select ur.role into user_role
  from rbac.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
  end if;

  -- Every organization the user belongs to, and each one's plan features
  -- (supabase/schemas/045_access_contract.sql and the entitlements module).
  claims := jsonb_set(claims, '{memberships}', better_supabase.membership_claims((event ->> 'user_id')::uuid));
  claims := jsonb_set(claims, '{features}', better_supabase.feature_claims((event ->> 'user_id')::uuid));

  return jsonb_set(event, '{claims}', claims);
end;
$function$;

ALTER TABLE "better_supabase"."announcement_dismissals"
  ADD CONSTRAINT "announcement_dismissals_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."announcement_dismissals"
  ADD CONSTRAINT "announcement_dismissals_announcement_id_fkey" FOREIGN KEY (announcement_id) REFERENCES better_supabase.announcements(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_flag_key_fkey" FOREIGN KEY (flag_key) REFERENCES better_supabase.flags(key) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE "better_supabase"."invitations"
  ADD CONSTRAINT "invitations_accepted_by_fkey" FOREIGN KEY (accepted_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."invitations"
  ADD CONSTRAINT "invitations_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."onboarding_progress"
  ADD CONSTRAINT "onboarding_progress_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."profiles"
  ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."plan_features"
  ADD CONSTRAINT "plan_features_plan_key_fkey" FOREIGN KEY (plan_key) REFERENCES public.plans(key) ON DELETE CASCADE;

ALTER TABLE "public"."subscriptions"
  ADD CONSTRAINT "subscriptions_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE "public"."subscriptions"
  ADD CONSTRAINT "subscriptions_plan_key_fkey" FOREIGN KEY (plan_key) REFERENCES public.plans(key);

CREATE INDEX announcement_dismissals_user_idx ON better_supabase.announcement_dismissals USING btree (user_id);

CREATE INDEX announcements_window_idx ON better_supabase.announcements USING btree (starts_at, ends_at);

CREATE INDEX flag_overrides_user_idx ON better_supabase.flag_overrides USING btree (user_id);

CREATE INDEX invitations_accepted_by_idx ON better_supabase.invitations USING btree (accepted_by);

CREATE INDEX invitations_invited_by_idx ON better_supabase.invitations USING btree (invited_by);

CREATE UNIQUE INDEX invitations_open_email_idx ON better_supabase.invitations USING btree (organization_id, lower(email))
  WHERE ((accepted_at IS NULL) AND (declined_at IS NULL) AND (revoked_at IS NULL));

CREATE INDEX invitations_tenant_created_idx ON better_supabase.invitations USING btree (organization_id, created_at);

CREATE INDEX onboarding_progress_tenant_idx ON better_supabase.onboarding_progress USING btree (organization_id);

CREATE INDEX onboarding_progress_user_idx ON better_supabase.onboarding_progress USING btree (user_id);

CREATE UNIQUE INDEX profiles_username_idx ON better_supabase.profiles USING btree (lower(username));

CREATE INDEX usage_counters_unreported_idx ON better_supabase.usage_counters USING btree (day)
  WHERE (VALUE > reported_value);

CREATE INDEX usage_events_recorded_at_idx ON better_supabase.usage_events USING btree (recorded_at);

CREATE INDEX memberships_user_idx ON public.memberships USING btree (user_id);

CREATE INDEX subscriptions_plan_key_idx ON public.subscriptions USING btree (plan_key);

CREATE TRIGGER bs_profile_email
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.mirror_profile_email();

CREATE TRIGGER bs_profile_sync
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.on_auth_user_created();

CREATE TRIGGER bs_announcements_broadcast
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.announcements
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.broadcast_announcement();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.invitations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bs_profile_guard
  BEFORE UPDATE ON better_supabase.profiles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_profile();

CREATE CONSTRAINT TRIGGER bs_organization_owner
  AFTER DELETE OR UPDATE OF ROLE, organization_id ON public.memberships DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ensure_organization_owner();

CREATE TRIGGER bs_organization_role_guard
  BEFORE INSERT OR UPDATE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_membership();

CREATE TRIGGER memberships_clear_tenant_claim
  AFTER DELETE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.clear_tenant_claim();

CREATE TRIGGER subscriptions_set_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE POLICY "bs_invitations_read" ON "better_supabase"."invitations"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.invitation_tenant_ids() AS invitation_tenant_ids)));

CREATE POLICY "onboarding_progress_read" ON "better_supabase"."onboarding_progress"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('onboarding.read'::text) AS tenant_ids_with))));

CREATE POLICY "bs_profiles_read" ON "better_supabase"."profiles"
  FOR SELECT
  TO "authenticated"
  USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_profiles_update" ON "better_supabase"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING ((id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "usage_counters_read" ON "better_supabase"."usage_counters"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('usage.read'::text) AS tenant_ids_with)));

CREATE POLICY "usage_quotas_read" ON "better_supabase"."usage_quotas"
  FOR SELECT
  TO "authenticated"
  USING (((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('usage.read'::text) AS tenant_ids_with))));

CREATE POLICY "memberships_no_client_delete" ON "public"."memberships"
  FOR DELETE
  TO "authenticated"
  USING (false);

CREATE POLICY "memberships_no_client_insert" ON "public"."memberships"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (false);

CREATE POLICY "memberships_no_client_update" ON "public"."memberships"
  FOR UPDATE
  TO "authenticated"
  USING (false);

CREATE POLICY "memberships_read" ON "public"."memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))));

CREATE POLICY "plan_features_read" ON "public"."plan_features"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "plans_read" ON "public"."plans"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "subscriptions_member_read" ON "public"."subscriptions"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));

CREATE POLICY "subscriptions_no_client_delete" ON "public"."subscriptions"
  FOR DELETE
  TO "authenticated"
  USING (false);

CREATE POLICY "subscriptions_no_client_insert" ON "public"."subscriptions"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (false);

CREATE POLICY "subscriptions_no_client_update" ON "public"."subscriptions"
  FOR UPDATE
  TO "authenticated"
  USING (false);

CREATE POLICY "bs_announcements_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) = 'announcements'::text)));

REVOKE ALL ON FUNCTION "api"."accept_invitation"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accept_invitation"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."accept_invitation_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accept_invitation_by_id"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."active_announcements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."active_announcements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."allocate_username"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."allocate_username"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."api_key_tenant"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."api_key_tenant"() TO "anon", "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "service_role";

REVOKE ALL
  ON FUNCTION "api"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "api"."audit_events_tenants"(interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_events_tenants"(interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."backfill_profiles"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."backfill_profiles"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."comment_counts"(uuid, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."comment_counts"(uuid, text, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."complete_onboarding_step"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_onboarding_step"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."copy_comments"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."copy_comments"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp WITH time zone)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp WITH time zone)
  TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_api_key"(text, text, text, uuid, boolean, text[], timestamp WITH time zone, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_api_key"(text, text, text, uuid, boolean, text[], timestamp WITH time zone, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_invitation"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_invitation"(uuid, text, text, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_organization"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_organization"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decline_invitation"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decline_invitation"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decline_invitation_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decline_invitation_by_id"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."delete_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_comment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_comment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_flag"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_flag"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."dismiss_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."dismiss_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."edit_comment"(uuid, text, uuid[], jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."edit_comment"(uuid, text, uuid[], jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."entitlement_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."entitlement_value"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."feature_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."feature_claims"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."flag_bucket"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_bucket"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."flag_definitions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_definitions"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."flag_enabled"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_enabled"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."flag_evaluation"(text, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_evaluation"(text, uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_organization_settings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_organization_settings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_platform_settings"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_platform_settings"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_user_settings"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_user_settings"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."has_entitlement"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."has_entitlement"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."has_scope"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."has_scope"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."invitation_preview"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invitation_preview"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."invite_member"(uuid, text, text, interval, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invite_member"(uuid, text, text, interval, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."leave_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."leave_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_announcements"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_announcements"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_api_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_api_keys"(uuid) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_flags"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_flags"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_usage_reported"(uuid, text, date, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_usage_reported"(uuid, text, date, numeric) TO "service_role";

REVOKE ALL ON FUNCTION "api"."mark_used"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_used"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."my_invitations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."my_invitations"() TO "authenticated";

REVOKE ALL ON FUNCTION "api"."onboarding_progress"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."onboarding_progress"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."organization_slug_problem"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."organization_slug_problem"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_audit_log"(interval, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_audit_log"(interval, integer, uuid, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_usage_events"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_usage_events"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_usage_history"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_usage_history"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_activity"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_activity"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resend_invitation"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resend_invitation"(uuid, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reset_onboarding_step"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reset_onboarding_step"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reset_organization_setting"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reset_organization_setting"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reset_platform_setting"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reset_platform_setting"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reset_user_setting"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reset_user_setting"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."revoke_api_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revoke_api_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."revoke_invitation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revoke_invitation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rotate_api_key"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_api_key"(uuid, text, text, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_announcement"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_announcement"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_flag"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_flag"(text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_flag_override"(text, text, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_flag_override"(text, text, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_organization_setting"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_organization_setting"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_platform_setting"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_platform_setting"(text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_user_setting"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_user_setting"(text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."switch_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."switch_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sync_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sync_profile"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_entitlement_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_entitlement_value"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_entitlements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_entitlements"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_ids_with_entitlement"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_ids_with_entitlement"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_ids_with_flag"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_ids_with_flag"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_plans"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_plans"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."transfer_ownership"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."transfer_ownership"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."unreported_usage"(integer, text[], uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unreported_usage"(integer, text[], uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."update_invitation"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_invitation"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_member_role"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_member_role"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_organization"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_organization"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_breakdown"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_breakdown"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_history"(uuid, text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_history"(uuid, text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_meters"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_meters"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_overview"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_quota"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_quota"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."usage_status"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_status"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_used"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_used"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."usage_window"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_window"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."usage_window_start"(uuid, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_window_start"(uuid, text, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."verify_api_key"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."verify_api_key"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."within_quota"(uuid, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."within_quota"(uuid, text, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accept_invitation"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accept_invitation"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."accept_invitation_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accept_invitation_by_id"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."active_announcements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."active_announcements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."allocate_username"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allocate_username"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."backfill_profiles"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."backfill_profiles"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."broadcast_announcement"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clear_tenant_claim"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."complete_onboarding_step"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_onboarding_step"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_invitation"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_invitation"(uuid, text, text, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_organization"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_organization"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decline_invitation"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decline_invitation"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decline_invitation_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decline_invitation_by_id"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."delete_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_flag"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_flag"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."dismiss_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."dismiss_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."entitlement_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."entitlement_value"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."feature_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."feature_claims"(uuid) TO "service_role", "supabase_auth_admin";

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_bucket"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."flag_definitions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_definitions"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."flag_enabled"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_enabled"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."flag_evaluation"(text, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_evaluation"(text, uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."has_entitlement"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."has_entitlement"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invitation_extra"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."invitation_preview"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invitation_preview"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invitation_tenant_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invitation_tenant_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invite_member"(uuid, text, text, interval, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invite_member"(uuid, text, text, interval, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."leave_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."leave_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_announcements"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_announcements"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_flags"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_flags"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_usage_reported"(uuid, text, date, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_usage_reported"(uuid, text, date, numeric) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_used"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_used"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_invitations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_invitations"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."onboarding_progress"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."onboarding_progress"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_usage_events"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_usage_events"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_usage_history"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_usage_history"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resend_invitation"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resend_invitation"(uuid, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reset_onboarding_step"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reset_onboarding_step"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revoke_invitation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revoke_invitation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."role_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_permissions"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."role_rank"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_rank"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_announcement"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_announcement"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_flag"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_flag"(text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_flag_override"(text, text, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_flag_override"(text, text, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."switch_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."switch_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_profile"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_entitlement_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_entitlement_value"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_entitlements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_entitlements"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_ids_with_entitlement"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_ids_with_entitlement"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_ids_with_flag"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_ids_with_flag"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_plans"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_plans"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unreported_usage"(integer, text[], uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unreported_usage"(integer, text[], uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_invitation"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_invitation"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_breakdown"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_breakdown"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_history"(uuid, text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_history"(uuid, text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_meters"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_meters"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_overview"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_quota"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_quota"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_status"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_status"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_used"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_used"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_window"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_window"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_window_start"(uuid, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_window_start"(uuid, text, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."within_quota"(uuid, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."within_quota"(uuid, text, bigint) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_organizations"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_profile"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."organization_invitations"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_my_profile"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"(text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"(text) TO "service_role";

GRANT USAGE ON SCHEMA "api" TO "anon", "authenticated", "service_role";

REVOKE ALL ON SCHEMA "better_supabase" FROM "supabase_auth_admin";

GRANT USAGE ON SCHEMA "better_supabase" TO "supabase_auth_admin";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."announcement_dismissals" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."announcements" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."flag_overrides" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."flags" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."invitations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invitations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."onboarding_progress" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."onboarding_progress" TO "service_role";

GRANT UPDATE ("avatar_url") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("first_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("full_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("last_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("onboarding") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("updated_at") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("username") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT SELECT ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."profiles" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."usage_counters" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."usage_counters" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."usage_events" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."usage_quotas" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."usage_quotas" TO "service_role";

REVOKE ALL ON TABLE "public"."memberships" FROM "anon";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."memberships" TO "anon";

REVOKE ALL ON TABLE "public"."memberships" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."memberships" TO "authenticated";

REVOKE ALL ON TABLE "public"."memberships" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."memberships" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."memberships" TO "service_role";

REVOKE ALL ON TABLE "public"."plan_features" FROM "authenticated";

GRANT SELECT ON TABLE "public"."plan_features" TO "authenticated";

REVOKE ALL ON TABLE "public"."plan_features" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."plan_features" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."plan_features" TO "service_role";

REVOKE ALL ON TABLE "public"."plans" FROM "authenticated";

GRANT SELECT ON TABLE "public"."plans" TO "authenticated";

REVOKE ALL ON TABLE "public"."plans" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."plans" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."plans" TO "service_role";

REVOKE ALL ON TABLE "public"."subscriptions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."subscriptions" TO "authenticated";

REVOKE ALL ON TABLE "public"."subscriptions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."subscriptions" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."subscriptions" TO "service_role";

ALTER TABLE "better_supabase"."announcements"
  ADD CONSTRAINT "announcements_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX announcements_created_by_idx ON better_supabase.announcements USING btree (created_by);

ALTER TABLE "better_supabase"."onboarding_progress"
  ADD CONSTRAINT "onboarding_progress_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX onboarding_progress_completed_by_idx ON better_supabase.onboarding_progress USING btree (completed_by);
