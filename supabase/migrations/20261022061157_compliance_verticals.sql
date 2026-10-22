SET local check_function_bodies = off;

DROP POLICY "activity_entries_read" ON "better_supabase"."activity_entries";

CREATE TABLE "better_supabase"."contract_obligations" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "contract_id"  uuid                     NOT NULL,
  "title"        text                     NOT NULL,
  "description"  text,
  "due_on"       date,
  "owner_id"     uuid,
  "status"       text                     NOT NULL DEFAULT 'open'::text,
  "completed_at" timestamp with time zone,
  "completed_by" uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "contract_obligations_description_check" CHECK (((description IS NULL) OR (length(description) <= 4000))),
  CONSTRAINT "contract_obligations_pkey" PRIMARY KEY (id),
  CONSTRAINT "contract_obligations_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'waived'::text]))),
  CONSTRAINT "contract_obligations_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."contract_obligations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."contracts" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"            uuid                     NOT NULL,
  "title"                text                     NOT NULL,
  "description"          text,
  "counterparty_type"    text,
  "counterparty_id"      text,
  "owner_id"             uuid,
  "status"               text                     NOT NULL DEFAULT 'draft'::text,
  "value"                bigint,
  "currency"             text,
  "starts_on"            date,
  "ends_on"              date,
  "auto_renew"           boolean                  NOT NULL DEFAULT false,
  "renewal_months"       integer                  NOT NULL DEFAULT 12,
  "notice_days"          integer                  NOT NULL DEFAULT 30,
  "renewed_count"        integer                  NOT NULL DEFAULT 0,
  "signature_request_id" uuid,
  "signed_at"            timestamp with time zone,
  "terminated_at"        timestamp with time zone,
  "termination_reason"   text,
  "created_by"           uuid,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "contracts_check1" CHECK (((value IS NULL) = (currency IS NULL))),
  CONSTRAINT "contracts_check2" CHECK (((ends_on IS NULL) OR (starts_on IS NULL) OR (ends_on >= starts_on))),
  CONSTRAINT "contracts_check" CHECK (((counterparty_type IS NULL) = (counterparty_id IS NULL))),
  CONSTRAINT "contracts_currency_check" CHECK (((currency IS NULL) OR (currency ~ '^[A-Z]{3}$'::text))),
  CONSTRAINT "contracts_description_check" CHECK (((description IS NULL) OR (length(description) <= 10000))),
  CONSTRAINT "contracts_notice_days_check" CHECK (((notice_days >= 0) AND (notice_days <= 3650))),
  CONSTRAINT "contracts_pkey" PRIMARY KEY (id),
  CONSTRAINT "contracts_renewal_months_check" CHECK (((renewal_months >= 1) AND (renewal_months <= 120))),
  CONSTRAINT "contracts_status_check"
    CHECK ((status = ANY (ARRAY['draft'::text, 'in_review'::text, 'out_for_signature'::text, 'active'::text, 'expired'::text, 'terminated'::text]))),
  CONSTRAINT "contracts_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "contracts_termination_reason_check" CHECK (((termination_reason IS NULL) OR (length(termination_reason) <= 2000))),
  CONSTRAINT "contracts_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200))),
  CONSTRAINT "contracts_value_check" CHECK (((value IS NULL) OR (value >= 0)))
);

ALTER TABLE "better_supabase"."contracts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."control_evidence" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "control_id"    uuid                     NOT NULL,
  "task_id"       uuid,
  "attachment_id" uuid,
  "note"          text,
  "collected_by"  uuid,
  "collected_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "valid_until"   date,
  CONSTRAINT "control_evidence_check" CHECK (((attachment_id IS NOT NULL) OR (note IS NOT NULL))),
  CONSTRAINT "control_evidence_note_check" CHECK (((note IS NULL) OR (length(note) <= 4000))),
  CONSTRAINT "control_evidence_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."control_evidence"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."control_frameworks" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "key"         text                     NOT NULL,
  "name"        text                     NOT NULL,
  "version"     text,
  "description" text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "control_frameworks_description_check" CHECK (((description IS NULL) OR (length(description) <= 4000))),
  CONSTRAINT "control_frameworks_key_check" CHECK ((key ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'::text)),
  CONSTRAINT "control_frameworks_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "control_frameworks_pkey" PRIMARY KEY (id),
  CONSTRAINT "control_frameworks_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "control_frameworks_tenant_id_key_key" UNIQUE (tenant_id, key),
  CONSTRAINT "control_frameworks_version_check" CHECK (((version IS NULL) OR (length(version) <= 50)))
);

ALTER TABLE "better_supabase"."control_frameworks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."controls" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "framework_id" uuid                     NOT NULL,
  "code"         text                     NOT NULL,
  "title"        text                     NOT NULL,
  "description"  text,
  "owner_id"     uuid,
  "applicable"   boolean                  NOT NULL DEFAULT true,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "controls_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 50))),
  CONSTRAINT "controls_description_check" CHECK (((description IS NULL) OR (length(description) <= 10000))),
  CONSTRAINT "controls_framework_id_code_key" UNIQUE (framework_id, code),
  CONSTRAINT "controls_pkey" PRIMARY KEY (id),
  CONSTRAINT "controls_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "controls_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."controls"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."evidence_tasks" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"         uuid                     NOT NULL,
  "control_id"        uuid                     NOT NULL,
  "title"             text                     NOT NULL,
  "assignee_id"       uuid,
  "interval_days"     integer                  NOT NULL,
  "due_on"            date                     NOT NULL,
  "last_collected_at" timestamp with time zone,
  "notified_for"      date,
  "active"            boolean                  NOT NULL DEFAULT true,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "evidence_tasks_interval_days_check" CHECK (((interval_days >= 1) AND (interval_days <= 3650))),
  CONSTRAINT "evidence_tasks_pkey" PRIMARY KEY (id),
  CONSTRAINT "evidence_tasks_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."evidence_tasks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incident_impacts" (
  "tenant_id"    uuid NOT NULL,
  "incident_id"  uuid NOT NULL,
  "component_id" uuid NOT NULL,
  "impact"       text NOT NULL,
  CONSTRAINT "incident_impacts_impact_check" CHECK ((impact = ANY (ARRAY['maintenance'::text, 'degraded'::text, 'partial_outage'::text, 'major_outage'::text]))),
  CONSTRAINT "incident_impacts_pkey" PRIMARY KEY (incident_id, component_id)
);

ALTER TABLE "better_supabase"."incident_impacts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incident_postmortems" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "incident_id"  uuid                     NOT NULL,
  "summary"      text,
  "impact"       text,
  "root_cause"   text,
  "resolution"   text,
  "action_items" jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "status"       text                     NOT NULL DEFAULT 'draft'::text,
  "published_at" timestamp with time zone,
  "author_id"    uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "incident_postmortems_action_items_check" CHECK ((jsonb_typeof(action_items) = 'array'::text)),
  CONSTRAINT "incident_postmortems_impact_check" CHECK (((impact IS NULL) OR (length(impact) <= 10000))),
  CONSTRAINT "incident_postmortems_incident_id_key" UNIQUE (incident_id),
  CONSTRAINT "incident_postmortems_pkey" PRIMARY KEY (id),
  CONSTRAINT "incident_postmortems_resolution_check" CHECK (((resolution IS NULL) OR (length(resolution) <= 10000))),
  CONSTRAINT "incident_postmortems_root_cause_check" CHECK (((root_cause IS NULL) OR (length(root_cause) <= 10000))),
  CONSTRAINT "incident_postmortems_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text]))),
  CONSTRAINT "incident_postmortems_summary_check" CHECK (((summary IS NULL) OR (length(summary) <= 4000)))
);

ALTER TABLE "better_supabase"."incident_postmortems"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incident_updates" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "incident_id" uuid                     NOT NULL,
  "status"      text                     NOT NULL,
  "body"        text                     NOT NULL,
  "public"      boolean                  NOT NULL DEFAULT false,
  "author_id"   uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "incident_updates_body_check" CHECK (((length(body) >= 1) AND (length(body) <= 10000))),
  CONSTRAINT "incident_updates_pkey" PRIMARY KEY (id),
  CONSTRAINT "incident_updates_status_check" CHECK ((status = ANY (ARRAY['investigating'::text, 'identified'::text, 'monitoring'::text, 'resolved'::text])))
);

ALTER TABLE "better_supabase"."incident_updates"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incidents" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "title"        text                     NOT NULL,
  "description"  text,
  "severity"     text                     NOT NULL DEFAULT 'sev3'::text,
  "status"       text                     NOT NULL DEFAULT 'investigating'::text,
  "public"       boolean                  NOT NULL DEFAULT false,
  "commander_id" uuid,
  "started_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "resolved_at"  timestamp with time zone,
  "created_by"   uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "incidents_check" CHECK (((status = 'resolved'::text) = (resolved_at IS NOT NULL))),
  CONSTRAINT "incidents_description_check" CHECK (((description IS NULL) OR (length(description) <= 10000))),
  CONSTRAINT "incidents_pkey" PRIMARY KEY (id),
  CONSTRAINT "incidents_severity_check" CHECK ((severity = ANY (ARRAY['sev1'::text, 'sev2'::text, 'sev3'::text, 'sev4'::text]))),
  CONSTRAINT "incidents_status_check" CHECK ((status = ANY (ARRAY['investigating'::text, 'identified'::text, 'monitoring'::text, 'resolved'::text]))),
  CONSTRAINT "incidents_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "incidents_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."incidents"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."policies" (
  "id"                       uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"                uuid                     NOT NULL,
  "key"                      text                     NOT NULL,
  "title"                    text                     NOT NULL,
  "owner_id"                 uuid,
  "requires_acknowledgement" boolean                  NOT NULL DEFAULT true,
  "current_version_id"       uuid,
  "version_number"           integer,
  "published_at"             timestamp with time zone,
  "archived_at"              timestamp with time zone,
  "created_at"               timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"               timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "policies_key_check" CHECK ((key ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'::text)),
  CONSTRAINT "policies_pkey" PRIMARY KEY (id),
  CONSTRAINT "policies_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "policies_tenant_id_key_key" UNIQUE (tenant_id, key),
  CONSTRAINT "policies_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."policies"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."policy_acknowledgements" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "policy_id"       uuid                     NOT NULL,
  "version_id"      uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "acknowledged_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "policy_acknowledgements_pkey" PRIMARY KEY (id),
  CONSTRAINT "policy_acknowledgements_policy_id_version_id_user_id_key" UNIQUE (policy_id, version_id, user_id)
);

ALTER TABLE "better_supabase"."policy_acknowledgements"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."signature_requests" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"           uuid                     NOT NULL,
  "subject_type"        text                     NOT NULL,
  "subject_id"          text                     NOT NULL,
  "version_id"          uuid                     NOT NULL,
  "content_hash"        text                     NOT NULL,
  "signers"             uuid[]                   NOT NULL,
  "sign_order"          text                     NOT NULL DEFAULT 'parallel'::text,
  "status"              text                     NOT NULL DEFAULT 'pending'::text,
  "approval_request_id" uuid,
  "message"             text,
  "requested_by"        uuid,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "completed_at"        timestamp with time zone,
  CONSTRAINT "signature_requests_message_check" CHECK (((message IS NULL) OR (length(message) <= 2000))),
  CONSTRAINT "signature_requests_pkey" PRIMARY KEY (id),
  CONSTRAINT "signature_requests_sign_order_check" CHECK ((sign_order = ANY (ARRAY['parallel'::text, 'sequential'::text]))),
  CONSTRAINT "signature_requests_signers_check" CHECK ((((cardinality(signers) >= 1) AND (cardinality(signers) <= 20)) AND (array_position(signers, NULL::uuid) IS NULL))),
  CONSTRAINT "signature_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'declined'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."signature_requests"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."signatures" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "request_id"          uuid                     NOT NULL,
  "tenant_id"           uuid                     NOT NULL,
  "signer"              uuid                     NOT NULL,
  "method"              text                     NOT NULL,
  "typed_name"          text,
  "image_attachment_id" uuid,
  "signed_hash"         text                     NOT NULL,
  "ip"                  text,
  "user_agent"          text,
  "signed_at"           timestamp with time zone NOT NULL,
  CONSTRAINT "signatures_check1" CHECK (((method <> 'drawn'::text) OR (image_attachment_id IS NOT NULL))),
  CONSTRAINT "signatures_check" CHECK (((method <> 'typed'::text) OR (typed_name IS NOT NULL))),
  CONSTRAINT "signatures_ip_check" CHECK (((ip IS NULL) OR (length(ip) <= 64))),
  CONSTRAINT "signatures_method_check" CHECK ((method = ANY (ARRAY['drawn'::text, 'typed'::text, 'click'::text]))),
  CONSTRAINT "signatures_pkey" PRIMARY KEY (id),
  CONSTRAINT "signatures_request_id_signer_key" UNIQUE (request_id, signer),
  CONSTRAINT "signatures_typed_name_check" CHECK (((typed_name IS NULL) OR ((length(typed_name) >= 1) AND (length(typed_name) <= 200)))),
  CONSTRAINT "signatures_user_agent_check" CHECK (((user_agent IS NULL) OR (length(user_agent) <= 512)))
);

ALTER TABLE "better_supabase"."signatures"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."status_component_history" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "component_id" uuid                     NOT NULL,
  "status"       text                     NOT NULL,
  "started_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "ended_at"     timestamp with time zone,
  CONSTRAINT "status_component_history_check" CHECK (((ended_at IS NULL) OR (ended_at >= started_at))),
  CONSTRAINT "status_component_history_pkey" PRIMARY KEY (id),
  CONSTRAINT "status_component_history_status_check"
    CHECK ((status = ANY (ARRAY['operational'::text, 'maintenance'::text, 'degraded'::text, 'partial_outage'::text, 'major_outage'::text])))
);

ALTER TABLE "better_supabase"."status_component_history"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."status_components" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "description" text,
  "group_name"  text,
  "public"      boolean                  NOT NULL DEFAULT true,
  "status"      text                     NOT NULL DEFAULT 'operational'::text,
  "position"    integer                  NOT NULL DEFAULT 0,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "status_components_description_check" CHECK (((description IS NULL) OR (length(description) <= 2000))),
  CONSTRAINT "status_components_group_name_check" CHECK (((group_name IS NULL) OR (length(group_name) <= 100))),
  CONSTRAINT "status_components_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "status_components_pkey" PRIMARY KEY (id),
  CONSTRAINT "status_components_status_check"
    CHECK ((status = ANY (ARRAY['operational'::text, 'maintenance'::text, 'degraded'::text, 'partial_outage'::text, 'major_outage'::text]))),
  CONSTRAINT "status_components_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."status_components"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."status_pages" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "slug"        text                     NOT NULL,
  "title"       text                     NOT NULL,
  "description" text,
  "published"   boolean                  NOT NULL DEFAULT false,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "status_pages_description_check" CHECK (((description IS NULL) OR (length(description) <= 2000))),
  CONSTRAINT "status_pages_pkey" PRIMARY KEY (id),
  CONSTRAINT "status_pages_slug_check" CHECK ((slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'::text)),
  CONSTRAINT "status_pages_slug_key" UNIQUE (slug),
  CONSTRAINT "status_pages_tenant_id_key" UNIQUE (tenant_id),
  CONSTRAINT "status_pages_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."status_pages"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.acknowledge_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."acknowledge_policy"($1) $function$;

CREATE OR REPLACE FUNCTION api.add_control_evidence (
  control_id    uuid,
  attachment_id uuid DEFAULT NULL::uuid,
  note          text DEFAULT NULL::text,
  valid_until   date DEFAULT NULL::date,
  task_id       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_control_evidence"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.archive_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_policy"($1) $function$;

CREATE OR REPLACE FUNCTION api.cancel_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_signature_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.control_posture (
  tenant       uuid,
  framework_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."control_posture"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_contract (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_contract"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_signature_request"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.decline_signature_request (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decline_signature_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_obligation (
  obligation_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_obligation"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_status_component (
  component_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_status_component"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_contract (
  contract_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_contract"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_control (
  control_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_control"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_incident (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_incident"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_signature_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_status_page (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_status_page"($1) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_contracts"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.list_control_frameworks (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
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
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_controls"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_evidence_tasks (
  tenant       uuid,
  control_id   uuid    DEFAULT NULL::uuid,
  assignee_id  uuid    DEFAULT NULL::uuid,
  overdue_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_evidence_tasks"($1, $2, $3, $4) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_incidents"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_obligations (
  tenant      uuid,
  contract_id uuid    DEFAULT NULL::uuid,
  owner_id    uuid    DEFAULT NULL::uuid,
  open_only   boolean DEFAULT false,
  due_before  date    DEFAULT NULL::date,
  page_size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_obligations"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_policies (
  tenant           uuid,
  include_archived boolean DEFAULT false,
  pending_only     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_policies"($1, $2, $3) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_signature_requests"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_status_components (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_status_components"($1) $function$;

CREATE OR REPLACE FUNCTION api.notify_overdue_evidence_tasks()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notify_overdue_evidence_tasks"() $function$;

CREATE OR REPLACE FUNCTION api.open_incident (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_incident"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.policy_acknowledgements (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."policy_acknowledgements"($1) $function$;

CREATE OR REPLACE FUNCTION api.post_incident_update (
  incident_id uuid,
  status      text,
  body        text,
  is_public   boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_incident_update"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.public_status_page (
  slug text,
  days integer DEFAULT 90
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."public_status_page"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.publish_policy (
  policy_id uuid,
  content   jsonb,
  label     text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."publish_policy"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.publish_postmortem (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."publish_postmortem"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_control_evidence (
  evidence_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_control_evidence"($1) $function$;

CREATE OR REPLACE FUNCTION api.run_contract_renewals (
  as_of date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."run_contract_renewals"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_control"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_control_framework (
  tenant      uuid,
  key         text,
  name        text,
  version     text DEFAULT NULL::text,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_control_framework"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_evidence_task (
  control_id    uuid,
  title         text,
  interval_days integer,
  due_on        date    DEFAULT NULL::date,
  assignee_id   uuid    DEFAULT NULL::uuid,
  active        boolean DEFAULT true,
  task_id       uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_evidence_task"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_obligation (
  contract_id   uuid,
  title         text,
  due_on        date DEFAULT NULL::date,
  owner_id      uuid DEFAULT NULL::uuid,
  description   text DEFAULT NULL::text,
  obligation_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_obligation"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.save_policy (
  tenant                   uuid,
  key                      text,
  title                    text,
  owner_id                 uuid    DEFAULT NULL::uuid,
  requires_acknowledgement boolean DEFAULT true,
  policy_id                uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_policy"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.save_postmortem (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_postmortem"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_status_component (
  tenant        uuid,
  name          text,
  description   text    DEFAULT NULL::text,
  group_name    text    DEFAULT NULL::text,
  is_public     boolean DEFAULT true,
  sort_position integer DEFAULT 0,
  component_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_status_component"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_status_page (
  tenant      uuid,
  slug        text,
  title       text,
  description text    DEFAULT NULL::text,
  published   boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_status_page"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.send_contract_for_signature (
  contract_id uuid,
  signers     uuid[],
  sign_order  text   DEFAULT 'parallel'::text,
  message     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."send_contract_for_signature"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_incident_impacts (
  incident_id uuid,
  impacts     jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_incident_impacts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_obligation_status (
  obligation_id uuid,
  status        text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_obligation_status"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sign_signature (
  request_id          uuid,
  method              text,
  typed_name          text DEFAULT NULL::text,
  image_attachment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sign_signature"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.transition_contract (
  contract_id uuid,
  action      text,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."transition_contract"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.update_contract (
  contract_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_contract"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.update_incident (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_incident"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.acknowledge_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    perform "better_supabase".emit_event('policy.acknowledged', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/controls');
  perform better_supabase.audit_event(
    event_type => 'policy.acknowledged',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'acknowledged policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me)
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.activity_subject_deliveries (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  max_rows     integer
)
  RETURNS TABLE (
    entry jsonb,
    at    timestamp with time zone,
    id    text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select jsonb_build_object('id', d."id"::text, 'organization_id', ev."organization_id", 'event_id', null::text, 'type', 'delivery.' || d."status", 'actor_id', null::uuid, 'subject_type', activity_subject_deliveries.subject_type, 'subject_id', activity_subject_deliveries.subject_id, 'summary', ev."summary", 'data', jsonb_strip_nulls(jsonb_build_object('notificationId', ev."id", 'notificationType', ev."type", 'channel', d."channel", 'status', d."status", 'userId', rc."user_id", 'providerStatus', d."provider_status", 'templateKey', d."template_key", 'error', d."error", 'deliveredAt', d."delivered_at")), 'occurred_at', d."created_at", 'source', 'delivery'),
    d."created_at", d."id"::text
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where activity_subject_deliveries.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,asset,asset_location,lease,maintenance_request,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,document,customer,drive_node,application,project,task}'::text[])
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
      or (coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'activity.read'), false) and coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'notifications.send'), false)))
    and ev."organization_id" = activity_subject_deliveries.tenant
    and ev."subject_type" = activity_subject_deliveries.subject_type
    and ev."subject_id" = activity_subject_deliveries.subject_id
    and (activity_subject_deliveries.before is null or d."created_at" < activity_subject_deliveries.before)
  order by d."created_at" desc, d."id" desc
  limit least(greatest(coalesce(activity_subject_deliveries.max_rows, 50), 1), 500);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_control_evidence (
  control_id    uuid,
  attachment_id uuid DEFAULT NULL::uuid,
  note          text DEFAULT NULL::text,
  valid_until   date DEFAULT NULL::date,
  task_id       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'controls.collect'), false)) or (v_task."assignee_id" is not null and v_task."assignee_id" = auth.uid())) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = add_control_evidence.attachment_id
      and a."organization_id" = v_control."tenant_id"
  ) then
    raise exception 'the attachment isn''t a file in this organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  perform "better_supabase".emit_event('control.evidence_added', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id"), 'controls/' || v_row."control_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/controls');
  perform better_supabase.audit_event(
    event_type => 'control.evidence_added',
    category => 'data',
    target_type => 'control',
    record_id => v_row."control_id"::text,
    summary => 'collected evidence for control ' || v_control."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_to_job (
  job       uuid,
  candidate jsonb,
  source    text,
  owner     uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job "better_supabase"."jobs";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'HIRING_JOB_NOT_OPEN';
  end if;
  if v_id is null or not (case v_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_type, v_id, 'read')) then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_user_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('application.created', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select subject_type is null or (((tenant)::text, (subject_type)::text, (subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    else false
  end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."attachments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billable_time_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    delete from "better_supabase"."time_rates" x where x."subject_type" = v_type and x."subject_id" = v_drop and exists (select 1 from "better_supabase"."time_rates" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."tenant_id" is not distinct from x."tenant_id" and y."user_id" is not distinct from x."user_id" and y."effective_from" is not distinct from x."effective_from");
    update "better_supabase"."time_rates" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'maintenance_request' then
      return exists (
        select 1 from "better_supabase"."maintenance_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.maintain'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'maintenance_request' then
      return exists (
        select 1 from "better_supabase"."maintenance_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.maintain'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = cancel_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature.cancelled', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.cancelled',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'cancelled a signature request',
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select (((tenant)::text, (subject_type)::text, (subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    else false
  end)
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
    perform "better_supabase".emit_event('comment.deleted', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id"), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
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
      and case new."subject_type" when 'comment' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false) when 'company' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'person' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'deal' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'deals.read'), false) when 'engagement' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'engagements.read'), false) when 'work_item' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'work_items.read'), false) when 'employee' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'employees.read'), false) when 'ledger_account' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'ledger.read'), false) when 'product' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'product_variant' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'calendar_event' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'calendar.read'), false) when 'asset' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'assets.read'), false) when 'asset_location' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'assets.read'), false) when 'lease' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'leases.read'), false) when 'maintenance_request' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'leases.read'), false) when 'expense_report' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'expenses.read'), false) when 'expense_line' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'expenses.read'), false) when 'donation_fund' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'donations.read'), false) when 'work_order' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'dispatch.read'), false) when 'shipment' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'shipments.read'), false) when 'contract' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'contracts.read'), false) when 'control' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'controls.read'), false) when 'policy' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'controls.read'), false) when 'incident' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'incidents.read'), false) when 'document' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'documents.read'), false) when 'customer' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'customers.read'), false) when 'drive_node' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'drive.read'), false) when 'application' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'hiring.read'), false) else true end
  );
  if tg_op = 'INSERT' then
    perform "better_supabase".emit_event('comment.created', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id", 'parentId', new."parent_id", 'mentionIds', to_jsonb(new."mentions")), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
  end if;
  if cardinality(v_new) > 0 then
    perform "better_supabase".emit_event('comment.mentioned', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id", 'mentionIds', to_jsonb(v_new)), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
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

CREATE OR REPLACE FUNCTION better_supabase.comments_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."comments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.contract_apply_status (
  contract_id uuid,
  status      text,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_from text;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = contract_apply_status.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  v_from := v_row."status";
  if v_from = contract_apply_status.status then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."contracts" x set
    "status" = contract_apply_status.status,
    "starts_on" = case when contract_apply_status.status = 'active' then coalesce(x."starts_on", current_date) else x."starts_on" end,
    "signed_at" = case when contract_apply_status.status = 'active' and x."signature_request_id" is not null then now() else x."signed_at" end,
    "signature_request_id" = case when contract_apply_status.status in ('draft', 'in_review') then null else x."signature_request_id" end,
    "terminated_at" = case when contract_apply_status.status = 'terminated' then now() else x."terminated_at" end,
    "termination_reason" = case when contract_apply_status.status = 'terminated' then nullif(trim(contract_apply_status.reason), '') else x."termination_reason" end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase"."contract_schedule_renewal"(v_row."id");
  perform "better_supabase".emit_event('contract.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'status', v_row."status", 'previousStatus', v_from), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.status_changed',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'moved contract ' || v_row."title" || ' from ' || v_from || ' to ' || v_row."status",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'status', v_row."status", 'previousStatus', v_from)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.contract_schedule_renewal (
  contract_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = contract_schedule_renewal.contract_id;
  if not found then
    return;
  end if;
  if v_row."status" <> 'active' or v_row."ends_on" is null then
    delete from "better_supabase"."reminders" x where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract' and x."subject_id" = v_row."id"::text;
    delete from "better_supabase"."recurrence_rules" x where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract' and x."subject_id" = v_row."id"::text;
    return;
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid")
  values (v_row."tenant_id", 'contract', v_row."id"::text, ((case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end)::timestamp + interval '9 hours') at time zone 'UTC', 'UTC')
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid";
  if v_row."owner_id" is not null and not exists (
    select 1 from "better_supabase"."reminders" x
    where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract'
      and x."subject_id" = v_row."id"::text and x."user_id" = v_row."owner_id"
  ) then
    insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
    values (v_row."tenant_id", 'contract', v_row."id"::text, v_row."owner_id", 20160);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.contract_signature_settled()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  for v_id in
    select x."id" from "better_supabase"."contracts" x
    where x."signature_request_id" = new."id" and x."status" = 'out_for_signature'
  loop
    perform "better_supabase"."contract_apply_status"(v_id, case when new."status" = 'completed' then 'active' else 'in_review' end);
  end loop;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.contracts_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."contracts" x set "counterparty_id" = v_keep where x."counterparty_type" = v_type and x."counterparty_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.control_posture (
  tenant       uuid,
  framework_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_contract (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_contract.tenant, 'contracts.write'), false)) then
    raise exception 'not allowed to create contracts' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if jsonb_typeof(create_contract.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  v_row."tenant_id" := create_contract.tenant;
  v_row."auto_renew" := false;
  v_row."renewal_months" := 12;
  v_row."notice_days" := 30;
  v_row."owner_id" := auth.uid();
  v_row."title" := case when create_contract.attrs ? 'title' then (create_contract.attrs ->> 'title')::text else v_row."title" end;
  v_row."description" := case when create_contract.attrs ? 'description' then (create_contract.attrs ->> 'description')::text else v_row."description" end;
  v_row."counterparty_type" := case when create_contract.attrs ? 'counterpartyType' then (create_contract.attrs ->> 'counterpartyType')::text else v_row."counterparty_type" end;
  v_row."counterparty_id" := case when create_contract.attrs ? 'counterpartyId' then (create_contract.attrs ->> 'counterpartyId')::text else v_row."counterparty_id" end;
  v_row."owner_id" := case when create_contract.attrs ? 'ownerId' then (create_contract.attrs ->> 'ownerId')::uuid else v_row."owner_id" end;
  v_row."value" := case when create_contract.attrs ? 'value' then (create_contract.attrs ->> 'value')::bigint else v_row."value" end;
  v_row."currency" := case when create_contract.attrs ? 'currency' then (create_contract.attrs ->> 'currency')::text else v_row."currency" end;
  v_row."starts_on" := case when create_contract.attrs ? 'startsOn' then (create_contract.attrs ->> 'startsOn')::date else v_row."starts_on" end;
  v_row."ends_on" := case when create_contract.attrs ? 'endsOn' then (create_contract.attrs ->> 'endsOn')::date else v_row."ends_on" end;
  v_row."auto_renew" := case when create_contract.attrs ? 'autoRenew' then (create_contract.attrs ->> 'autoRenew')::boolean else v_row."auto_renew" end;
  v_row."renewal_months" := case when create_contract.attrs ? 'renewalMonths' then (create_contract.attrs ->> 'renewalMonths')::integer else v_row."renewal_months" end;
  v_row."notice_days" := case when create_contract.attrs ? 'noticeDays' then (create_contract.attrs ->> 'noticeDays')::integer else v_row."notice_days" end;
  v_row."title" := nullif(trim(v_row."title"), '');
  if v_row."title" is null then
    raise exception 'a contract needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."counterparty_type" is not null and not (case v_row."counterparty_type"
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."counterparty_type", v_row."counterparty_id", 'read')) then
    raise exception 'the counterparty is unknown or not in this organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."owner_id" is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."owner_id") then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  insert into "better_supabase"."contracts" ("tenant_id", "title", "description", "counterparty_type", "counterparty_id", "owner_id", "value", "currency", "starts_on", "ends_on", "auto_renew", "renewal_months", "notice_days", "created_by")
  values (v_row."tenant_id", v_row."title", v_row."description", v_row."counterparty_type", v_row."counterparty_id", v_row."owner_id", v_row."value", upper(v_row."currency"), v_row."starts_on", v_row."ends_on", coalesce(v_row."auto_renew", false), coalesce(v_row."renewal_months", 12), coalesce(v_row."notice_days", 30), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('contract.created', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.created',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'created contract' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_deal (
  tenant   uuid,
  attrs    jsonb,
  contacts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id",
      "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period",
      "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind",
      "flags", "source", "note", "created_by")
    values (create_deal.tenant, v_seq, v_identifier, trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion', create_deal.attrs ->> 'priority', create_deal.attrs ->> 'product', (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0), coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')), coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid, (create_deal.attrs ->> 'stageId')::uuid, (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast', (create_deal.attrs ->> 'closeOn')::date, create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz, create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source', create_deal.attrs ->> 'note', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  perform "better_supabase".emit_event('deal.created', jsonb_build_object('organizationId', create_deal.tenant, 'dealId', v_deal, 'subjectType', 'deal', 'subjectId', v_deal::text, 'name', v_row."name"), 'deals/' || v_deal::text, (create_deal.tenant::text)::text, null, 'better-supabase/deals');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_invoice (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_invoice.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    raise exception 'an invoice needs a title' using errcode = '23502', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "created_by")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), coalesce((create_invoice.attrs ->> 'termsDays')::integer, 30),
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'invoice', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'invoice' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_lease (
  tenant     uuid,
  unit_id    uuid,
  party_type text,
  party_id   text,
  starts_on  date,
  rent       bigint,
  currency   text,
  frequency  text   DEFAULT 'monthly'::text,
  ends_on    date   DEFAULT NULL::date,
  deposit    bigint DEFAULT 0,
  title      text   DEFAULT NULL::text,
  metadata   jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."lease_agreements"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not (case create_lease.party_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      else false
    end and "better_supabase"."can_subject"(create_lease.party_type, create_lease.party_id, 'read')) then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."lease_agreements" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('lease.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.created',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_pledge (
  tenant            uuid,
  donor_type        text,
  donor_id          text,
  amount            bigint,
  currency          text,
  frequency         text   DEFAULT 'monthly'::text,
  fund_id           uuid   DEFAULT NULL::uuid,
  starts_on         date   DEFAULT NULL::date,
  ends_on           date   DEFAULT NULL::date,
  provider          text   DEFAULT NULL::text,
  provider_customer text   DEFAULT NULL::text,
  note              text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not (case create_pledge.donor_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_pledge.donor_id)::uuid and s."organization_id"::text = create_pledge.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_pledge.donor_id)::uuid and s."organization_id"::text = create_pledge.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_pledge.donor_id)::uuid and s."tenant_id"::text = create_pledge.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_pledge.donor_id)::uuid and s."organization_id"::text = create_pledge.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_pledge.donor_id)::uuid and s."organization_id"::text = create_pledge.tenant::text)
      else false
    end and "better_supabase"."can_subject"(create_pledge.donor_type, create_pledge.donor_id, 'read')) then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pledge.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status"), 'pledges/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'pledge.created',
    category => 'billing',
    target_type => 'pledge',
    record_id => v_row."id"::text,
    summary => 'created a pledge',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('quote.created', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_share_link (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  role         text,
  version_id   uuid                     DEFAULT NULL::uuid,
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_uses     integer                  DEFAULT NULL::integer
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    v_subject_ok := case create_share_link.subject_type
    when 'ai-chat' then exists (select 1 from "better_supabase".ai_chats s where s.id::text = create_share_link.subject_id and s.organization_id::text = create_share_link.tenant::text and s.owner_id = auth.uid())
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'calendar' then exists (select 1 from "better_supabase"."calendars" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'booking_service' then exists (select 1 from "better_supabase"."booking_services" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    else case create_share_link.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'customers.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'hiring.read'), false)
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
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "expires_at", "max_uses", "created_by", "version_id")
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid(), create_share_link.version_id)
  returning "id" into v_id;
  perform "better_supabase".emit_event('share_link.created', jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id), 'share-links/' || v_id::text, (create_share_link.tenant)::text, null, 'better-supabase/share-links');
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_shipment (
  tenant           uuid,
  from_address     jsonb,
  to_address       jsonb,
  packages         jsonb,
  reference        text  DEFAULT NULL::text,
  from_location_id uuid  DEFAULT NULL::uuid,
  subject_type     text  DEFAULT NULL::text,
  subject_id       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_shipment.tenant, 'shipments.manage'), false)) then
    raise exception 'not allowed to manage shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  if not coalesce((jsonb_typeof(create_shipment.from_address) = 'object' and coalesce(create_shipment.from_address ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce(create_shipment.from_address ->> 'line1', ''))) >= 1 and length(btrim(coalesce(create_shipment.from_address ->> 'city', ''))) >= 1 and length(create_shipment.from_address::text) <= 4000) and (jsonb_typeof(create_shipment.to_address) = 'object' and coalesce(create_shipment.to_address ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce(create_shipment.to_address ->> 'line1', ''))) >= 1 and length(btrim(coalesce(create_shipment.to_address ->> 'city', ''))) >= 1 and length(create_shipment.to_address::text) <= 4000), false) then
    raise exception 'each address needs line1, city and a two-letter country' using errcode = '22023', hint = 'SHIPMENT_ADDRESS_INVALID';
  end if;
  if jsonb_typeof(create_shipment.packages) is distinct from 'array'
    or jsonb_array_length(create_shipment.packages) < 1
    or jsonb_array_length(create_shipment.packages) > 50 then
    raise exception 'a shipment holds 1 to 50 packages' using errcode = '22023', hint = 'SHIPMENT_EMPTY';
  end if;
  if (create_shipment.subject_type is null) <> (create_shipment.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'SHIPMENT_SUBJECT_INVALID';
  end if;
  if create_shipment.subject_type is not null
    and (case create_shipment.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (create_shipment.subject_id)::uuid)
      else null::text
    end) is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" l
    where l."id" = create_shipment.from_location_id and l."tenant_id" = create_shipment.tenant
  ) then
    raise exception 'the location does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_LOCATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."shipments" ("tenant_id", "reference", "from_address", "to_address", "from_location_id", "subject_type", "subject_id", "created_by")
    values (create_shipment.tenant,
      coalesce(nullif(btrim(create_shipment.reference), ''), 'SHP-' || upper(substr(md5(gen_random_uuid()::text), 1, 10))),
      create_shipment.from_address, create_shipment.to_address, create_shipment.from_location_id,
      create_shipment.subject_type, create_shipment.subject_id, auth.uid())
    returning * into v_ship;
  exception when check_violation then
    raise exception 'a shipment reference has 1 to 100 characters' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end;
  begin
    insert into "better_supabase"."shipment_packages" ("tenant_id", "shipment_id", "position", "weight_grams", "length_mm", "width_mm", "height_mm", "reference")
    select v_ship."tenant_id", v_ship."id", k.position,
      (k.item ->> 'weightGrams')::integer, (k.item ->> 'lengthMm')::integer, (k.item ->> 'widthMm')::integer, (k.item ->> 'heightMm')::integer,
      nullif(k.item ->> 'reference', '')
    from jsonb_array_elements(create_shipment.packages) with ordinality as k(item, position);
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'each package needs a weightGrams and sizes in whole millimeters above zero' using errcode = '22023', hint = 'SHIPMENT_PACKAGE_INVALID';
  end;
  perform "better_supabase".emit_event('shipment.created', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'reference', v_ship."reference", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.created',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'created shipment',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'reference', v_ship."reference", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and case create_signature_request.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    else false
  end)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    raise exception 'sign_order must be parallel or sequential' using errcode = '22023', hint = 'SIGNATURE_ORDER_INVALID';
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and 20
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    raise exception 'name between 1 and 20 different signers' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" a
    where a."id" = create_signature_request.approval_request_id
      and a."tenant_id" = create_signature_request.tenant
      and a."subject_type" = create_signature_request.subject_type
      and a."subject_id" = create_signature_request.subject_id
  ) then
    raise exception 'the approval request isn''t for this record' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_NOT_FOUND';
  end if;
  if v_version is null then
    v_version := ("better_supabase"."snapshot_version"(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x."content_hash" into v_hash
    from "better_supabase"."versions" x
    where x."id" = v_version
      and x."tenant_id" = create_signature_request.tenant
      and x."subject_type" = create_signature_request.subject_type
      and x."subject_id" = create_signature_request.subject_id;
  if v_hash is null then
    raise exception 'the version isn''t a version of this record' using errcode = '22023', hint = 'SIGNATURE_VERSION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_request"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version;
    end if;
  end;
  update "better_supabase"."versions" x set "frozen" = true where x."id" = v_version and not x."frozen";
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('signature.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id"), 'signature-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.requested',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_row."id"::text,
    summary => 'requested signatures on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_order (
  tenant       uuid,
  title        text,
  description  text                     DEFAULT NULL::text,
  priority     text                     DEFAULT 'normal'::text,
  location_id  uuid                     DEFAULT NULL::uuid,
  asset_id     uuid                     DEFAULT NULL::uuid,
  booking_id   uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  address      text                     DEFAULT NULL::text,
  technician   uuid                     DEFAULT NULL::uuid,
  starts_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  ends_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_starts timestamptz := create_work_order.starts_at;
  v_ends timestamptz := create_work_order.ends_at;
  v_during tstzrange;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_work_order.tenant, 'dispatch.manage'), false)) then
    raise exception 'not allowed to manage work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if (create_work_order.subject_type is null) <> (create_work_order.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'DISPATCH_SUBJECT_INVALID';
  end if;
  if create_work_order.subject_type is not null
    and (case create_work_order.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (create_work_order.subject_id)::uuid)
      else null::text
    end) is distinct from create_work_order.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_SUBJECT_NOT_FOUND';
  end if;
  if create_work_order.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" l
    where l."id" = create_work_order.location_id and l."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_LOCATION_NOT_FOUND';
  end if;
  if create_work_order.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = create_work_order.asset_id and a."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
  end if;
  if create_work_order.booking_id is not null then
    select bk."during" into v_during from "better_supabase"."bookings" bk
      where bk."id" = create_work_order.booking_id and bk."tenant_id" = create_work_order.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_BOOKING_NOT_FOUND';
    end if;
  end if;
  if create_work_order.booking_id is not null and v_starts is null then
    v_starts := lower(v_during);
    v_ends := upper(v_during);
  end if;
  if v_starts is not null then
    if create_work_order.technician is null then
      raise exception 'a scheduled work order needs a technician' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_REQUIRED';
    end if;
    v_ends := coalesce(v_ends, v_starts + '1 hour'::interval);
  if not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  if v_ends <= v_starts then
    raise exception 'a slot ends after it starts' using errcode = '22023', hint = 'DISPATCH_SLOT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bs:dispatch:' || create_work_order.technician::text, 0));
  if exists (
    select 1 from "better_supabase"."work_orders" o
    where o."tenant_id" = create_work_order.tenant and o."technician_id" = create_work_order.technician
      and o."id" is distinct from null::uuid
      and o."status" in ('scheduled', 'en_route', 'on_site')
      and o."starts_at" < v_ends and o."ends_at" > v_starts
  ) then
    raise exception 'the technician already has a work order in that slot' using errcode = '23P01', hint = 'DISPATCH_SLOT_TAKEN';
  end if;
  elsif create_work_order.technician is not null
    and not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  begin
    insert into "better_supabase"."work_orders" ("tenant_id", "title", "description", "priority", "status", "technician_id", "starts_at", "ends_at", "location_id", "asset_id", "booking_id", "subject_type", "subject_id", "address", "created_by")
    values (create_work_order.tenant, btrim(create_work_order.title), create_work_order.description, coalesce(create_work_order.priority, 'normal'),
      case when v_starts is null then 'unscheduled' else 'scheduled' end, create_work_order.technician, v_starts, v_ends,
      create_work_order.location_id, create_work_order.asset_id, create_work_order.booking_id,
      create_work_order.subject_type, create_work_order.subject_id, nullif(btrim(create_work_order.address), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation then
    raise exception 'a work order needs a title of 1 to 200 characters and a known priority' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end;
  perform "better_supabase".emit_event('work_order.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.created',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  if v_row."status" = 'scheduled' then
    perform "better_supabase".emit_event('work_order.scheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.scheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.comments', '"better_supabase"."comments"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.conversation_participants', '"better_supabase"."conversation_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_reads', '"better_supabase"."conversation_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
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
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.maintenance_requests', '"better_supabase"."maintenance_requests"', 'reported_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comments', '"better_supabase"."comments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_messages', '"better_supabase"."inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.collections', '"better_supabase"."collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.jobs', '"better_supabase"."jobs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.maintenance_requests', '"better_supabase"."maintenance_requests"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_signature_request (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = decline_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if v_me is null or not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'declined', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature.declined', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.declined',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'declined to sign' || coalesce(': ' || left(decline_signature_request.reason, 200), ''),
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me)
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_obligation (
  obligation_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contract_obligations" x where x."id" = delete_obligation.obligation_id;
  if not found then
    raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contract obligations' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  delete from "better_supabase"."contract_obligations" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_status_component (
  component_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."status_components"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."status_components" x where x."id" = delete_status_component.component_id;
  if not found then
    raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to manage status components' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."status_components" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'deleted', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispatch_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."work_orders" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_access (
  document_id uuid,
  write       boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.maintain'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.donations_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."donations" x set "donor_id" = v_keep where x."donor_type" = v_type and x."donor_id" = v_drop;
    update "better_supabase"."pledges" x set "donor_id" = v_keep where x."donor_type" = v_type and x."donor_id" = v_drop;
    update "better_supabase"."donation_receipts" x set "donor_id" = v_keep where x."donor_type" = v_type and x."donor_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.employee_from_application (
  application uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."jobs";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', (case v_application."candidate_type"
      when 'comment' then (select s."body"::text from "better_supabase"."comments" s where s."id" = (v_application."candidate_id")::uuid)
      when 'company' then (select s."name"::text from "better_supabase"."companies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'person' then (select s."name"::text from "better_supabase"."people" s where s."id" = (v_application."candidate_id")::uuid)
      when 'deal' then (select s."name"::text from "better_supabase"."deals" s where s."id" = (v_application."candidate_id")::uuid)
      when 'engagement' then (select s."title"::text from "better_supabase"."engagements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_item' then (select s."title"::text from "better_supabase"."work_items" s where s."id" = (v_application."candidate_id")::uuid)
      when 'employee' then (select s."name"::text from "better_supabase"."employees" s where s."id" = (v_application."candidate_id")::uuid)
      when 'ledger_account' then (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product' then (select s."title"::text from "better_supabase"."products" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product_variant' then (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (v_application."candidate_id")::uuid)
      when 'calendar_event' then (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset' then (select s."name"::text from "better_supabase"."assets" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset_location' then (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (v_application."candidate_id")::uuid)
      when 'lease' then (select s."title"::text from "better_supabase"."lease_agreements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'maintenance_request' then (select s."title"::text from "better_supabase"."maintenance_requests" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_report' then (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_line' then (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (v_application."candidate_id")::uuid)
      when 'donation_fund' then (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_order' then (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (v_application."candidate_id")::uuid)
      when 'shipment' then (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (v_application."candidate_id")::uuid)
      when 'contract' then (select s."title"::text from "better_supabase"."contracts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'control' then (select s."title"::text from "better_supabase"."controls" s where s."id" = (v_application."candidate_id")::uuid)
      when 'policy' then (select s."title"::text from "better_supabase"."policies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'incident' then (select s."title"::text from "better_supabase"."incidents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'document' then (select s."name"::text from "better_supabase"."documents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'customer' then (select s."name"::text from "public"."customers" s where s."id" = (v_application."candidate_id")::uuid)
      when 'drive_node' then (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (v_application."candidate_id")::uuid)
      when 'project' then (select s."name"::text from "public"."projects" s where s."id" = (v_application."candidate_id")::uuid)
      when 'task' then (select s."title"::text from "public"."tasks" s where s."id" = (v_application."candidate_id")::uuid)
      else null::text
    end),
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet', 'expense_report') or case v_req."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end)))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "better_supabase"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_contract (
  contract_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = get_contract.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_control (
  control_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_document_version (
  document_id uuid,
  version_id  uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_state text;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = get_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."content" ->> 'state' into v_state from "better_supabase"."versions" x
  where x."id" = get_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text;
  if v_state is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  return v_state;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_incident (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'severity', x."severity", 'status', x."status", 'public', x."public", 'commanderId', x."commander_id", 'startedAt', x."started_at", 'resolvedAt', x."resolved_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = x."id")) || jsonb_build_object(
    'updates', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'incidentId', y."incident_id", 'status', y."status", 'body', y."body", 'public', y."public", 'authorId', y."author_id", 'createdAt', y."created_at") order by y."created_at", y."id"), '[]'::jsonb) from "better_supabase"."incident_updates" y where y."incident_id" = x."id"),
    'postmortem', (select jsonb_build_object('id', z."id", 'incidentId', z."incident_id", 'summary', z."summary", 'impact', z."impact", 'rootCause', z."root_cause", 'resolution', z."resolution", 'actionItems', z."action_items", 'status', z."status", 'publishedAt', z."published_at", 'authorId', z."author_id", 'createdAt', z."created_at", 'updatedAt', z."updated_at") from "better_supabase"."incident_postmortems" z where z."incident_id" = x."id")
  )
  from "better_supabase"."incidents" x
  where x."id" = get_incident.incident_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_items jsonb;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = get_signature_request.request_id;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (v_req."signers") or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and case v_req."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_status_page (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'slug', x."slug", 'title', x."title", 'description', x."description", 'published', x."published", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."status_pages" x where x."tenant_id" = get_status_page.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.grant_guest_access (
  guest_id     uuid,
  subject_type text,
  subject_id   text,
  actions      text[]                   DEFAULT ARRAY['read'::text],
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_guest "better_supabase"."guests"%rowtype;
  v_row "better_supabase"."guest_grants"%rowtype;
  v_actions text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_guest from "better_supabase"."guests" x where x."id" = grant_guest_access.guest_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_guest."tenant_id", 'guests.manage'), false)) then
    raise exception 'guest not found' using errcode = 'P0002', hint = 'GUEST_NOT_FOUND';
  end if;
  if v_guest."status" = 'revoked' then
    raise exception 'invite the guest again before granting access' using errcode = '55000', hint = 'GUEST_REVOKED';
  end if;
  if not (coalesce(grant_guest_access.actions, '{}') <@ array['read', 'comment', 'upload']::text[]) then
    raise exception 'actions are read, comment and upload' using errcode = '22023', hint = 'GUEST_ACTION_INVALID';
  end if;
  select array_agg(a order by array_position(array['read', 'comment', 'upload']::text[], a)) into v_actions
    from (select distinct a from unnest(array_append(coalesce(grant_guest_access.actions, '{}'), 'read')) a) z;
  if grant_guest_access.expires_at is not null and grant_guest_access.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'GUEST_EXPIRES_IN_PAST';
  end if;
  if (case grant_guest_access.subject_type
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id"::text = grant_guest_access.subject_id)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id"::text = grant_guest_access.subject_id)
      else (case grant_guest_access.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (grant_guest_access.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (grant_guest_access.subject_id)::uuid)
      else null::text
    end)
    end) is distinct from v_guest."tenant_id"::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'GUEST_SUBJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."guest_grants" as y ("tenant_id", "guest_id", "subject_type", "subject_id", "actions", "granted_by", "expires_at")
  values (v_guest."tenant_id", v_guest."id", grant_guest_access.subject_type, grant_guest_access.subject_id, v_actions, auth.uid(), grant_guest_access.expires_at)
  on conflict ("guest_id", "subject_type", "subject_id") do update set
    "actions" = excluded."actions",
    "granted_by" = excluded."granted_by",
    "expires_at" = excluded."expires_at",
    "updated_at" = now()
  returning * into v_row;
  perform "better_supabase".emit_event('guest_grant.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'guestId', v_row."guest_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'actions', to_jsonb(v_row."actions")), 'guest-grants/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/guests');
  perform better_supabase.audit_event(
    event_type => 'guest_grant.created',
    category => 'access',
    target_type => 'guest_grant',
    record_id => v_row."id"::text,
    summary => 'granted guest access to ' || v_row."subject_type" || '/' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'guestId', v_row."guest_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'actions', to_jsonb(v_row."actions"))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'guestId', v_row."guest_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'actions', to_jsonb(v_row."actions"), 'grantedBy', v_row."granted_by", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guests_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    delete from "better_supabase"."guest_grants" x where x."subject_type" = v_type and x."subject_id" = v_drop and exists (select 1 from "better_supabase"."guest_grants" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."guest_id" is not distinct from x."guest_id");
    update "better_supabase"."guest_grants" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.incident_apply_impacts (
  incident_id uuid,
  impacts     jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_before uuid[];
  v_item jsonb;
  v_component uuid;
begin
  select * into v_row from "better_supabase"."incidents" x where x."id" = incident_apply_impacts.incident_id;
  if jsonb_typeof(coalesce(incident_apply_impacts.impacts, '[]'::jsonb)) <> 'array' then
    raise exception 'impacts must be an array' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  select coalesce(array_agg(x."component_id"), '{}') into v_before
    from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id";
  delete from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id";
  for v_item in select value from jsonb_array_elements(coalesce(incident_apply_impacts.impacts, '[]'::jsonb))
  loop
    v_component := nullif(v_item ->> 'componentId', '')::uuid;
    if not exists (
      select 1 from "better_supabase"."status_components" x where x."id" = v_component and x."tenant_id" = v_row."tenant_id"
    ) then
      raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
    end if;
    if coalesce(v_item ->> 'impact', '') not in ('maintenance', 'degraded', 'partial_outage', 'major_outage') then
      raise exception 'impact must be degraded, partial_outage, major_outage or maintenance' using errcode = '22023', hint = 'INCIDENTS_INVALID';
    end if;
    insert into "better_supabase"."incident_impacts" ("tenant_id", "incident_id", "component_id", "impact")
    values (v_row."tenant_id", v_row."id", v_component, v_item ->> 'impact')
    on conflict ("incident_id", "component_id") do update set "impact" = excluded."impact";
  end loop;
  perform "better_supabase"."incident_refresh_components"(
    v_before || array(select x."component_id" from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.incident_refresh_components (
  component_ids uuid[]
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_component "better_supabase"."status_components"%rowtype;
  v_status text;
begin
  for v_component in
    select * from "better_supabase"."status_components" x where x."id" = any(incident_refresh_components.component_ids) for update
  loop
    select coalesce(
      (array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], im."impact"))],
      'operational'
    ) into v_status
    from "better_supabase"."incident_impacts" im
    join "better_supabase"."incidents" ii on ii."id" = im."incident_id"
    where im."component_id" = v_component."id" and ii."status" <> 'resolved';
    continue when v_status = v_component."status";
    update "better_supabase"."status_components" x set "status" = v_status, "updated_at" = now()
      where x."id" = v_component."id";
    update "better_supabase"."status_component_history" x set "ended_at" = now()
      where x."component_id" = v_component."id" and x."ended_at" is null;
    insert into "better_supabase"."status_component_history" ("tenant_id", "component_id", "status")
    values (v_component."tenant_id", v_component."id", v_status);
    perform "better_supabase".emit_event('status_component.changed', jsonb_build_object('organizationId', v_component."tenant_id", 'statusComponentId', v_component."id", 'status', v_status, 'previousStatus', v_component."status"), 'status-components/' || v_component."id"::text, (v_component."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'status_component.changed',
    category => 'data',
    target_type => 'status_component',
    record_id => v_component."id"::text,
    summary => 'status of ' || v_component."name" || ' changed to ' || v_status,
    tenant => (v_component."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_component."tenant_id", 'statusComponentId', v_component."id", 'status', v_status, 'previousStatus', v_component."status")
  );
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_guest (
  tenant     uuid,
  email      text,
  name       text                     DEFAULT NULL::text,
  party_type text                     DEFAULT NULL::text,
  party_id   text                     DEFAULT NULL::text,
  expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."guests"%rowtype;
  v_token text;
  v_email text := lower(btrim(invite_guest.email));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invite_guest.tenant, 'guests.manage'), false)) then
    raise exception 'not allowed to manage guests' using errcode = '42501', hint = 'GUEST_FORBIDDEN';
  end if;
  if (invite_guest.party_type is null) <> (invite_guest.party_id is null) then
    raise exception 'pass party_type and party_id together' using errcode = '22023', hint = 'GUEST_PARTY_INVALID';
  end if;
  if invite_guest.party_type is not null
    and (case invite_guest.party_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (invite_guest.party_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (invite_guest.party_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (invite_guest.party_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (invite_guest.party_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (invite_guest.party_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (invite_guest.party_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (invite_guest.party_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (invite_guest.party_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (invite_guest.party_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (invite_guest.party_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (invite_guest.party_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (invite_guest.party_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (invite_guest.party_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (invite_guest.party_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (invite_guest.party_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (invite_guest.party_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (invite_guest.party_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (invite_guest.party_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (invite_guest.party_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (invite_guest.party_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (invite_guest.party_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (invite_guest.party_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (invite_guest.party_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (invite_guest.party_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (invite_guest.party_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (invite_guest.party_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (invite_guest.party_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (invite_guest.party_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (invite_guest.party_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (invite_guest.party_id)::uuid)
      else null::text
    end) is distinct from invite_guest.tenant::text then
    raise exception 'the party does not exist in this organization' using errcode = 'P0002', hint = 'GUEST_PARTY_NOT_FOUND';
  end if;
  if invite_guest.expires_at is not null and invite_guest.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'GUEST_EXPIRES_IN_PAST';
  end if;
  select * into v_row from "better_supabase"."guests" x
    where x."tenant_id" = invite_guest.tenant and lower(x."email") = v_email
    for update;
  if found and v_row."status" = 'active' then
    update "better_supabase"."guests" x set
      "name" = coalesce(invite_guest.name, x."name"),
      "party_type" = coalesce(invite_guest.party_type, x."party_type"),
      "party_id" = coalesce(invite_guest.party_id, x."party_id"),
      "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('token', null);
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  if found then
    update "better_supabase"."guests" x set
      "name" = coalesce(invite_guest.name, x."name"),
      "party_type" = coalesce(invite_guest.party_type, x."party_type"),
      "party_id" = coalesce(invite_guest.party_id, x."party_id"),
      "status" = 'invited',
      "user_id" = null,
      "token_hash" = encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'),
      "invited_by" = auth.uid(),
      "expires_at" = invite_guest.expires_at,
      "revoked_at" = null,
      "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  else
    insert into "better_supabase"."guests" ("tenant_id", "email", "name", "party_type", "party_id", "token_hash", "invited_by", "expires_at")
    values (invite_guest.tenant, v_email, invite_guest.name, invite_guest.party_type, invite_guest.party_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid(), invite_guest.expires_at)
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('guest.invited', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'email', v_row."email", 'partyType', v_row."party_type", 'partyId', v_row."party_id"), 'guests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/guests');
  perform better_supabase.audit_event(
    event_type => 'guest.invited',
    category => 'access',
    target_type => 'guest',
    record_id => v_row."id"::text,
    target_label => v_row."email",
    summary => 'invited guest ' || v_row."email",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'email', v_row."email", 'partyType', v_row."party_type", 'partyId', v_row."party_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_pass (
  tenant       uuid,
  kind         text                     DEFAULT 'ticket'::text,
  holder_user  uuid                     DEFAULT NULL::uuid,
  holder_name  text                     DEFAULT NULL::text,
  holder_email text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  booking_id   uuid                     DEFAULT NULL::uuid,
  resource_id  uuid                     DEFAULT NULL::uuid,
  uses_allowed integer                  DEFAULT NULL::integer,
  valid_from   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  valid_until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
  v_resource uuid := issue_pass.resource_id;
  v_until timestamptz := issue_pass.valid_until;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_pass.tenant, 'passes.manage'), false)) then
    raise exception 'not allowed to issue passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  if (issue_pass.subject_type is null) <> (issue_pass.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'PASS_SUBJECT_INVALID';
  end if;
  if issue_pass.subject_type is not null
    and (case issue_pass.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (issue_pass.subject_id)::uuid)
      else null::text
    end) is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null then
    select * into v_booking from "better_supabase"."bookings" bk
      where bk."id" = issue_pass.booking_id and bk."tenant_id" = issue_pass.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
    end if;
    if v_booking."status" = 'cancelled' then
      raise exception 'the booking is cancelled' using errcode = '55000', hint = 'PASS_BOOKING_CANCELLED';
    end if;
    if issue_pass.resource_id is not null and issue_pass.resource_id <> v_booking."resource_id" then
      raise exception 'the booking is for another resource' using errcode = '22023', hint = 'PASS_RESOURCE_MISMATCH';
    end if;
    v_resource := v_booking."resource_id";
    v_until := coalesce(v_until, upper(v_booking."during"));
  elsif issue_pass.resource_id is not null then
    if not exists (
      select 1 from "better_supabase"."booking_resources" rs
      where rs."id" = issue_pass.resource_id and rs."tenant_id" = issue_pass.tenant
    ) then
      raise exception 'the resource does not exist in this organization' using errcode = 'P0002', hint = 'PASS_RESOURCE_NOT_FOUND';
    end if;
  end if;
  if v_until is not null and v_until <= coalesce(issue_pass.valid_from, now()) then
    raise exception 'valid_until must be after valid_from and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "better_supabase"."passes" ("tenant_id", "kind", "holder_user_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "valid_from", "valid_until", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.valid_from, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pass.issued', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.issued',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'issued pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.leases_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."lease_agreements" x set "party_id" = v_keep where x."party_type" = v_type and x."party_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case link.source_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    else false
  end)
     or not (case link.target_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relations:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', link.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old."target_type", 'targetId', v_old."target_id"), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    perform "better_supabase".emit_event('subject.linked', jsonb_build_object('organizationId', link.tenant, 'id', v_id, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
  elsif link.data is not null then
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
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
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,asset,asset_location,lease,maintenance_request,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,document,customer,drive_node,application,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'comment' then 'better_supabase.comments'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'engagement' then 'better_supabase.engagements'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'asset' then 'better_supabase.assets'
      when 'asset_location' then 'better_supabase.asset_locations'
      when 'lease' then 'better_supabase.lease_agreements'
      when 'maintenance_request' then 'better_supabase.maintenance_requests'
      when 'expense_report' then 'better_supabase.expense_reports'
      when 'expense_line' then 'better_supabase.expense_lines'
      when 'donation_fund' then 'better_supabase.donation_funds'
      when 'work_order' then 'better_supabase.work_orders'
      when 'shipment' then 'better_supabase.shipments'
      when 'contract' then 'better_supabase.contracts'
      when 'control' then 'better_supabase.controls'
      when 'policy' then 'better_supabase.policies'
      when 'incident' then 'better_supabase.incidents'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
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
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
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
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,asset,asset_location,lease,maintenance_request,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,document,customer,drive_node,application,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet', 'expense_report') or case x."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)))) or "better_supabase"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_contracts (
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
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."contracts" y
    where (list_contracts.tenant is null or y."tenant_id" = list_contracts.tenant)
      and (list_contracts.status is null or y."status" = list_contracts.status)
      and (list_contracts.counterparty_type is null or (y."counterparty_type" = list_contracts.counterparty_type and y."counterparty_id" = list_contracts.counterparty_id))
      and (list_contracts.owner_id is null or y."owner_id" = list_contracts.owner_id)
      and (list_contracts.renewing_before is null or (y."status" = 'active' and case when y."ends_on" is null then null else y."ends_on" - y."notice_days" end <= list_contracts.renewing_before))
      and (list_contracts.before is null or y."created_at" < list_contracts.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(list_contracts.page_size, 50), 1), 200)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_control_frameworks (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_controls (
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
  AS $function$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_versions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" x
    where x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_evidence_tasks (
  tenant       uuid,
  control_id   uuid    DEFAULT NULL::uuid,
  assignee_id  uuid    DEFAULT NULL::uuid,
  overdue_only boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_guest_grants (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant text := (case list_guest_grants.subject_type
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id"::text = list_guest_grants.subject_id)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id"::text = list_guest_grants.subject_id)
      else (case list_guest_grants.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (list_guest_grants.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (list_guest_grants.subject_id)::uuid)
      else null::text
    end)
    end);
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant::uuid, 'guests.read'), false)) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'guestId', y."guest_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'actions', to_jsonb(y."actions"), 'grantedBy', y."granted_by", 'expiresAt', y."expires_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") || jsonb_build_object('guest', jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")) order by y."created_at", y."id"), '[]'::jsonb)
    from "better_supabase"."guest_grants" y
    join "better_supabase"."guests" x on x."id" = y."guest_id"
    where y."tenant_id"::text = v_tenant
      and y."subject_type" = list_guest_grants.subject_type
      and y."subject_id" = list_guest_grants.subject_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_incidents (
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
  AS $function$
  select coalesce(jsonb_agg(row_json order by started desc, id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'severity', x."severity", 'status', x."status", 'public', x."public", 'commanderId', x."commander_id", 'startedAt', x."started_at", 'resolvedAt', x."resolved_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = x."id")) as row_json, x."started_at" as started, x."id" as id
    from "better_supabase"."incidents" x
    where x."tenant_id" = list_incidents.tenant
      and (list_incidents.status is null
        or (list_incidents.status = 'open' and x."status" <> 'resolved')
        or (list_incidents.status = 'resolved' and x."status" = 'resolved'))
      and (list_incidents.severity is null or x."severity" = list_incidents.severity)
      and (list_incidents.component_id is null or exists (
        select 1 from "better_supabase"."incident_impacts" y where y."incident_id" = x."id" and y."component_id" = list_incidents.component_id
      ))
      and (list_incidents.before is null or x."started_at" < list_incidents.before)
    order by x."started_at" desc, x."id" desc
    limit least(greatest(coalesce(list_incidents.page_size, 50), 1), 200)
  ) page
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_obligations (
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
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."due_on" nulls last, x."created_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."contract_obligations" y
    where y."tenant_id" = list_obligations.tenant
      and (list_obligations.contract_id is null or y."contract_id" = list_obligations.contract_id)
      and (list_obligations.owner_id is null or y."owner_id" = list_obligations.owner_id)
      and (not coalesce(list_obligations.open_only, false) or y."status" = 'open')
      and (list_obligations.due_before is null or y."due_on" <= list_obligations.due_before)
    order by y."due_on" nulls last, y."created_at"
    limit least(greatest(coalesce(list_obligations.page_size, 100), 1), 500)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_policies (
  tenant           uuid,
  include_archived boolean DEFAULT false,
  pending_only     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_policies.tenant, 'controls.read'), false)) or coalesce(better_supabase.can('tenant', list_policies.tenant, 'controls.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_policies.tenant
      and (coalesce(list_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_signature_requests (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  mine         boolean                  DEFAULT false,
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or list_signature_requests.mine or coalesce(better_supabase.can('tenant', list_signature_requests.tenant, 'signatures.read'), false)) then
    raise exception 'not allowed to list signature requests' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."signature_requests" x
    where x."tenant_id" = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x."subject_type" = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x."subject_id" = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x."status" = list_signature_requests.status)
      and (list_signature_requests.before is null or x."created_at" < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x."signers"))
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
    order by x."created_at" desc
    limit least(greatest(coalesce(list_signature_requests.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_components (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'group', x."group_name", 'public', x."public", 'status', x."status", 'position', x."position", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."position", x."name"), '[]'::jsonb)
  from "better_supabase"."status_components" x
  where x."tenant_id" = list_status_components.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_engagement (
  tenant   uuid,
  attrs    jsonb,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner,
    (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz,
    (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid())
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at",
    "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_time (
  tenant        uuid,
  started_at    timestamp with time zone,
  ended_at      timestamp with time zone,
  subject_type  text                     DEFAULT NULL::text,
  subject_id    text                     DEFAULT NULL::text,
  billable      boolean                  DEFAULT false,
  rate          bigint                   DEFAULT NULL::bigint,
  rate_currency text                     DEFAULT NULL::text,
  note          text                     DEFAULT NULL::text,
  user_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (log_time.rate is null) <> (log_time.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_overdue_evidence_tasks()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    perform "better_supabase".emit_event('evidence_task.missed', jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on"), 'evidence-tasks/' || v_task."id"::text, (v_task."tenant_id")::text, null, 'better-supabase/controls');
  perform better_supabase.audit_event(
    event_type => 'evidence_task.missed',
    category => 'data',
    target_type => 'evidence_task',
    record_id => v_task."id"::text,
    summary => 'evidence task overdue: ' || v_task."title",
    tenant => (v_task."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on")
  );
    if coalesce(v_task."assignee_id", v_owner) is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task."tenant_id",
        'actor', null,
        'subject_type', 'control',
        'subject_id', v_task."control_id"::text,
        'summary', v_task."title",
        'recipients', to_jsonb(array[coalesce(v_task."assignee_id", v_owner)]),
        'key', 'evidence_task.missed:' || v_task."id"::text || ':' || v_task."due_on"::text,
        'data', jsonb_build_object('evidenceTaskId', v_task."id", 'dueOn', v_task."due_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_document (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  name         text DEFAULT 'body'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.maintain'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) then
        raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
      end if;
      raise exception 'not allowed to open this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name;
    end if;
  end;
    insert into "better_supabase"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      perform "better_supabase".emit_event('document.created', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.created',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name")
  );
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "better_supabase"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.maintain'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "better_supabase"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_gift (
  tenant       uuid,
  donor_type   text,
  donor_id     text,
  amount       bigint,
  currency     text,
  fund_id      uuid   DEFAULT NULL::uuid,
  pledge_id    uuid   DEFAULT NULL::uuid,
  period_start date   DEFAULT NULL::date,
  provider     text   DEFAULT NULL::text,
  note         text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not (case open_gift.donor_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (open_gift.donor_id)::uuid and s."organization_id"::text = open_gift.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (open_gift.donor_id)::uuid and s."organization_id"::text = open_gift.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (open_gift.donor_id)::uuid and s."tenant_id"::text = open_gift.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (open_gift.donor_id)::uuid and s."organization_id"::text = open_gift.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (open_gift.donor_id)::uuid and s."organization_id"::text = open_gift.tenant::text)
      else false
    end and "better_supabase"."can_subject"(open_gift.donor_type, open_gift.donor_id, 'read')) then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_incident (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_incident.tenant, 'incidents.write'), false)) then
    raise exception 'not allowed to open incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(open_incident.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if nullif(trim(open_incident.attrs ->> 'title'), '') is null then
    raise exception 'an incident needs a title' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if coalesce(open_incident.attrs ->> 'severity', 'sev3') not in ('sev1', 'sev2', 'sev3', 'sev4') then
    raise exception 'severity must be sev1, sev2, sev3 or sev4' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if open_incident.attrs ? 'commanderId' and open_incident.attrs ->> 'commanderId' is not null
    and not exists (select 1 from "public"."memberships" mm where mm."organization_id" = open_incident.tenant and mm."user_id" = (open_incident.attrs ->> 'commanderId')::uuid) then
    raise exception 'the commander must be a member of the organization' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incidents" ("tenant_id", "title", "description", "severity", "public", "commander_id", "created_by")
  values (open_incident.tenant, trim(open_incident.attrs ->> 'title'), open_incident.attrs ->> 'description',
    coalesce(open_incident.attrs ->> 'severity', 'sev3'), coalesce((open_incident.attrs ->> 'public')::boolean, false),
    (open_incident.attrs ->> 'commanderId')::uuid, auth.uid())
  returning * into v_row;
  if nullif(trim(open_incident.attrs ->> 'message'), '') is not null then
    insert into "better_supabase"."incident_updates" ("tenant_id", "incident_id", "status", "body", "public", "author_id")
    values (v_row."tenant_id", v_row."id", v_row."status", trim(open_incident.attrs ->> 'message'), v_row."public", auth.uid());
  end if;
  perform "better_supabase"."incident_apply_impacts"(v_row."id", open_incident.attrs -> 'impacts');
  perform "better_supabase".emit_event('incident.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'title', v_row."title", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident.opened',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'opened incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'title', v_row."title", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public")
  );
  if v_row."commander_id" is not null and v_row."commander_id" is distinct from auth.uid() then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'incident.opened',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'incident',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(array[v_row."commander_id"]),
      'key', 'incident.opened:' || v_row."id"::text,
      'data', jsonb_build_object('incidentId', v_row."id", 'severity', v_row."severity")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.passes_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."passes" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.policy_acknowledgements (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "public"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_incident_update (
  incident_id uuid,
  status      text,
  body        text,
  is_public   boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_from text;
  v_update "better_supabase"."incident_updates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = post_incident_update.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to update incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if post_incident_update.status is not null and post_incident_update.status not in ('investigating', 'identified', 'monitoring', 'resolved') then
    raise exception 'status must be investigating, identified, monitoring or resolved' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if nullif(trim(post_incident_update.body), '') is null then
    raise exception 'an update needs a body' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  v_from := v_row."status";
  update "better_supabase"."incidents" x set
    "status" = coalesce(post_incident_update.status, x."status"),
    "resolved_at" = case
      when coalesce(post_incident_update.status, x."status") <> 'resolved' then null
      else coalesce(x."resolved_at", now())
    end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  insert into "better_supabase"."incident_updates" ("tenant_id", "incident_id", "status", "body", "public", "author_id")
  values (v_row."tenant_id", v_row."id", v_row."status", trim(post_incident_update.body),
    coalesce(post_incident_update.is_public, v_row."public"), auth.uid())
  returning * into v_update;
  if v_from is distinct from v_row."status" then
    perform "better_supabase"."incident_refresh_components"(
      array(select x."component_id" from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id")
    );
  end if;
  perform "better_supabase".emit_event('incident.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'updateId', v_update."id", 'status', v_row."status", 'public', v_update."public"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident.updated',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'posted an update on incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'updateId', v_update."id", 'status', v_row."status", 'public', v_update."public")
  );
  if v_row."status" = 'resolved' and v_from <> 'resolved' then
    perform "better_supabase".emit_event('incident.resolved', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'severity', v_row."severity"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident.resolved',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'resolved incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'severity', v_row."severity")
  );
  end if;
  return jsonb_build_object('id', v_update."id", 'incidentId', v_update."incident_id", 'status', v_update."status", 'body', v_update."body", 'public', v_update."public", 'authorId', v_update."author_id", 'createdAt', v_update."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.public_status_page (
  slug text,
  days integer DEFAULT 90
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_page "better_supabase"."status_pages"%rowtype;
  v_days integer := least(greatest(coalesce(public_status_page.days, 90), 1), 90);
  v_from timestamptz;
begin
  select * into v_page from "better_supabase"."status_pages" x where x."slug" = public_status_page.slug and x."published";
  if not found then
    return null;
  end if;
  v_from := (current_date - (v_days - 1))::timestamp at time zone 'UTC';
  return jsonb_build_object(
    'slug', v_page."slug",
    'title', v_page."title",
    'description', v_page."description",
    'days', v_days,
    'status', (
      select coalesce((array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], sc."status"))], 'operational')
      from "better_supabase"."status_components" sc
      where sc."tenant_id" = v_page."tenant_id" and sc."public"
    ),
    'components', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', pc."id",
        'name', pc."name",
        'description', pc."description",
        'group', pc."group_name",
        'status', pc."status",
        'uptimePercent', (
          select round(100 * (1 - coalesce(sum(extract(epoch from (
            least(coalesce(uh."ended_at", now()), now()) - greatest(uh."started_at", v_from)
          ))), 0) / greatest(extract(epoch from (now() - v_from)), 1))::numeric, 3)
          from "better_supabase"."status_component_history" uh
          where uh."component_id" = pc."id"
            and uh."status" in ('partial_outage', 'major_outage')
            and coalesce(uh."ended_at", now()) > v_from
        ),
        'uptime', (
          select jsonb_agg(jsonb_build_object('date', dd.d, 'status', coalesce(w.worst, 'operational'), 'downMinutes', coalesce(w.down, 0)) order by dd.d)
          from (select (current_date - n)::date as d from generate_series(0, v_days - 1) n) dd
          cross join lateral (
            select (array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], dh."status"))] as worst,
              (coalesce(sum(extract(epoch from (
                least(coalesce(dh."ended_at", now()), (dd.d + 1)::timestamp at time zone 'UTC')
                - greatest(dh."started_at", dd.d::timestamp at time zone 'UTC')
              ))) filter (where dh."status" in ('partial_outage', 'major_outage')), 0) / 60)::integer as down
            from "better_supabase"."status_component_history" dh
            where dh."component_id" = pc."id"
              and dh."started_at" < (dd.d + 1)::timestamp at time zone 'UTC'
              and coalesce(dh."ended_at", now()) > dd.d::timestamp at time zone 'UTC'
          ) w
        )
      ) order by pc."position", pc."name"), '[]'::jsonb)
      from "better_supabase"."status_components" pc
      where pc."tenant_id" = v_page."tenant_id" and pc."public"
    ),
    'incidents', (
      select coalesce(jsonb_agg(jsonb_build_object(
      'id', pi0."id",
      'title', pi0."title",
      'severity', pi0."severity",
      'status', pi0."status",
      'startedAt', pi0."started_at",
      'resolvedAt', pi0."resolved_at",
      'components', (
        select coalesce(jsonb_agg(jsonb_build_object('id', pc."id", 'name', pc."name", 'impact', pi."impact") order by pc."position", pc."name"), '[]'::jsonb)
        from "better_supabase"."incident_impacts" pi join "better_supabase"."status_components" pc on pc."id" = pi."component_id"
        where pi."incident_id" = pi0."id" and pc."public"
      ),
      'updates', (
        select coalesce(jsonb_agg(jsonb_build_object('status', pu."status", 'body', pu."body", 'createdAt', pu."created_at") order by pu."created_at" desc), '[]'::jsonb)
        from "better_supabase"."incident_updates" pu
        where pu."incident_id" = pi0."id" and pu."public"
      ),
      'postmortem', (
        select jsonb_build_object('summary', pp."summary", 'publishedAt', pp."published_at")
        from "better_supabase"."incident_postmortems" pp
        where pp."incident_id" = pi0."id" and pp."status" = 'published'
      )
    ) order by pi0."started_at" desc), '[]'::jsonb)
      from "better_supabase"."incidents" pi0
      where pi0."tenant_id" = v_page."tenant_id" and pi0."public"
        and (pi0."resolved_at" is null or pi0."resolved_at" >= v_from)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_policy (
  policy_id uuid,
  content   jsonb,
  label     text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'POLICY_ARCHIVED';
  end if;
  if publish_policy.content is null or jsonb_typeof(publish_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'policy', v_row."id"::text, publish_policy.content,
    null, coalesce(publish_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('policy.published', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number"), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/controls');
  perform better_supabase.audit_event(
    event_type => 'policy.published',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'published policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_postmortem (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = publish_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to publish postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if v_row."status" <> 'resolved' then
    raise exception 'only a resolved incident''s postmortem can be published' using errcode = '55000', hint = 'INCIDENT_NOT_RESOLVED';
  end if;
  update "better_supabase"."incident_postmortems" x set "status" = 'published', "published_at" = coalesce(x."published_at", now()), "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  if not found then
    raise exception 'the incident has no postmortem' using errcode = 'P0002', hint = 'POSTMORTEM_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('postmortem.published', jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'postmortem.published',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'published the postmortem of incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id")
  );
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actionItems', v_post."action_items", 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pull_document_updates (
  document_id uuid,
  after_seq   bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "better_supabase"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "better_supabase"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_document_update (
  document_id uuid,
  payload     text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.maintain'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  return v_seq;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case reaction_subject_visible.subject_type
    when 'inbox_message' then exists (select 1 from "better_supabase"."inbox_messages" m where m."id"::text = reaction_subject_visible.subject_id and m."tenant_id" = reaction_subject_visible.tenant)
    else case reaction_subject_visible.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    delete from "better_supabase"."reactions" x where x."subject_type" = v_type and x."subject_id" = v_drop and exists (select 1 from "better_supabase"."reactions" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."actor" is not distinct from x."actor" and y."emoji" is not distinct from x."emoji");
    update "better_supabase"."reactions" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_gift (
  tenant       uuid,
  donor_type   text,
  donor_id     text,
  amount       bigint,
  currency     text,
  fund_id      uuid   DEFAULT NULL::uuid,
  received_on  date   DEFAULT NULL::date,
  method       text   DEFAULT NULL::text,
  note         text   DEFAULT NULL::text,
  pledge_id    uuid   DEFAULT NULL::uuid,
  period_start date   DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not (case record_gift.donor_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (record_gift.donor_id)::uuid and s."organization_id"::text = record_gift.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_gift.donor_id)::uuid and s."organization_id"::text = record_gift.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_gift.donor_id)::uuid and s."tenant_id"::text = record_gift.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_gift.donor_id)::uuid and s."organization_id"::text = record_gift.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_gift.donor_id)::uuid and s."organization_id"::text = record_gift.tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_gift.donor_type, record_gift.donor_id, 'read')) then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_sla_event (
  subject_type text,
  subject_id   text,
  event        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case record_sla_event.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_sla_event.subject_id)::uuid)
      else null::text
    end);
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or (case record_sla_event.subject_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_sla_event.subject_type, record_sla_event.subject_id, 'read'))) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    perform "better_supabase".emit_event('sla.completed', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at", 'late', v_clock."met_at" > v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relation_rollup (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  of_type      text,
  column_name  text,
  agg          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_table text;
  v_id_col text;
  v_tenant_col text;
  v_ids text[];
  v_result jsonb;
begin
  if relation_rollup.agg is null or relation_rollup.agg not in ('count', 'sum', 'avg', 'min', 'max') then
    raise exception 'agg must be count, sum, avg, min or max' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  if relation_rollup.agg <> 'count' and relation_rollup.column_name is null then
    raise exception 'this aggregate needs a column' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  case relation_rollup.of_type
    when 'comment' then v_table := '"better_supabase"."comments"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'company' then v_table := '"better_supabase"."companies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'person' then v_table := '"better_supabase"."people"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'deal' then v_table := '"better_supabase"."deals"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'engagement' then v_table := '"better_supabase"."engagements"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_item' then v_table := '"better_supabase"."work_items"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'employee' then v_table := '"better_supabase"."employees"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'ledger_account' then v_table := '"better_supabase"."ledger_accounts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product' then v_table := '"better_supabase"."products"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product_variant' then v_table := '"better_supabase"."product_variants"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'calendar_event' then v_table := '"better_supabase"."calendar_events"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'asset' then v_table := '"better_supabase"."assets"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'asset_location' then v_table := '"better_supabase"."asset_locations"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'lease' then v_table := '"better_supabase"."lease_agreements"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'maintenance_request' then v_table := '"better_supabase"."maintenance_requests"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'expense_report' then v_table := '"better_supabase"."expense_reports"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'expense_line' then v_table := '"better_supabase"."expense_lines"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'donation_fund' then v_table := '"better_supabase"."donation_funds"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_order' then v_table := '"better_supabase"."work_orders"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'shipment' then v_table := '"better_supabase"."shipments"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'contract' then v_table := '"better_supabase"."contracts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'control' then v_table := '"better_supabase"."controls"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'policy' then v_table := '"better_supabase"."policies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'incident' then v_table := '"better_supabase"."incidents"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'document' then v_table := '"better_supabase"."documents"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'customer' then v_table := '"public"."customers"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'drive_node' then v_table := '"better_supabase"."drive_nodes"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'application' then v_table := '"better_supabase"."applications"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'project' then v_table := '"public"."projects"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'task' then v_table := '"public"."tasks"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    else null;
  end case;
  if v_table is null then
    raise exception 'this subject type has no table' using errcode = '22023', hint = 'RELATION_SUBJECT_UNKNOWN';
  end if;
  select array_agg(w.id) into v_ids
  from "better_supabase"."relation_walk"(relation_rollup.tenant, relation_rollup.kind, relation_rollup.subject_type, relation_rollup.subject_id, false, null) w
  where w.type = relation_rollup.of_type;
  execute format(
    'select to_jsonb(%s) from %s s where s.%I::text = any ($1)%s',
    case when relation_rollup.agg = 'count' and relation_rollup.column_name is null then 'count(*)'
      else format('%s(s.%I)', relation_rollup.agg, relation_rollup.column_name) end,
    v_table,
    v_id_col,
    case when v_tenant_col is null then '' else format(' and s.%I = $2', v_tenant_col) end
  ) into v_result using coalesce(v_ids, '{}'::text[]), relation_rollup.tenant;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    declare
      v_row record;
      v_st text; v_si text; v_tt text; v_ti text;
    begin
      for v_row in
        select x."id" as id, x."tenant_id"::text as tenant, x."kind" as kind, x."source_type" as st, x."source_id" as si, x."target_type" as tt, x."target_id" as ti
        from "better_supabase"."relations" x
        where (x."source_type" = v_type and x."source_id" = v_drop) or (x."target_type" = v_type and x."target_id" = v_drop)
        for update
      loop
        v_st := v_row.st; v_tt := v_row.tt;
        v_si := case when v_row.st = v_type and v_row.si = v_drop then v_keep else v_row.si end;
        v_ti := case when v_row.tt = v_type and v_row.ti = v_drop then v_keep else v_row.ti end;
        if v_row.kind in ('relates') and (v_st, v_si) > (v_tt, v_ti) then
          select v_tt, v_ti, v_st, v_si into v_st, v_si, v_tt, v_ti;
        end if;
        if (v_st = v_tt and v_si = v_ti) or exists (
          select 1 from "better_supabase"."relations" y
          where y."id" <> v_row.id and y."tenant_id"::text = v_row.tenant and y."kind" = v_row.kind
            and y."source_type" = v_st and y."source_id" = v_si and y."target_type" = v_tt and y."target_id" = v_ti
        ) then
          delete from "better_supabase"."relations" y where y."id" = v_row.id;
        else
          update "better_supabase"."relations" y set "source_type" = v_st, "source_id" = v_si, "target_type" = v_tt, "target_id" = v_ti
          where y."id" = v_row.id;
        end if;
      end loop;
    end;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_control_evidence (
  evidence_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_policy jsonb := "better_supabase"."approval_policy"(request_approval.subject_type, request_approval.action);
begin
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and case request_approval.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    else false
  end)) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload);
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
      'tags.read', 'tags.apply', 'tags.manage',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin',
      'attachments.read', 'attachments.upload', 'attachments.manage', 'sso.manage',
      'waitlist.manage', 'teams.read', 'teams.manage', 'catalog.read', 'catalog.manage',
      'inventory.read', 'inventory.manage', 'inventory.reserve', 'inventory.purchase',
      'orders.read', 'orders.manage', 'promotions.read', 'promotions.manage', 'custom_fields.read',
      'custom_fields.manage', 'custom_fields.sensitive.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'imports.manage',
      'views.read', 'views.share', 'relations.read', 'relations.manage', 'bulk.run',
      'calendar.read', 'calendar.write', 'calendar.manage', 'bookings.read', 'bookings.create',
      'bookings.manage', 'versions.read', 'versions.create', 'versions.restore',
      'versions.manage', 'trash.read', 'trash.create', 'trash.restore', 'trash.manage',
      'reactions.read', 'reactions.create', 'reactions.manage', 'approvals.read',
      'approvals.request', 'approvals.manage', 'access_requests.read', 'access_requests.create',
      'access_requests.manage', 'documents.read', 'documents.write', 'documents.manage',
      'drive.read', 'drive.create', 'drive.manage', 'forms.read', 'forms.submit',
      'forms.review', 'forms.manage', 'templates.read', 'templates.apply', 'templates.manage',
      'time_tracking.read', 'time_tracking.track', 'time_tracking.approve', 'time_tracking.manage',
      'service_principals.read', 'service_principals.manage', 'pipelines.read',
      'pipelines.manage', 'parties.read', 'parties.write', 'parties.manage', 'engagements.read',
      'engagements.write', 'engagements.manage', 'deals.read', 'deals.write', 'deals.manage',
      'work_items.read', 'work_items.write', 'work_items.manage', 'quotes.read',
      'quotes.write', 'quotes.manage', 'invoices.read', 'invoices.write', 'invoices.manage',
      'sla.read', 'sla.manage', 'targets.read', 'targets.manage', 'hiring.read',
      'hiring.write', 'hiring.manage', 'employees.read', 'employees.write', 'employees.view_sensitive',
      'webhooks.read', 'webhooks.manage', 'organization.export',
      'rules.read', 'rules.edit', 'rules.publish', 'rules.admin',
      'assets.read', 'assets.manage', 'assets.assign',
      'scores.read', 'scores.manage', 'scores.compute',
      'moderation.read', 'moderation.report', 'moderation.manage', 'moderation.ban',
      'enrollments.read', 'enrollments.enroll', 'enrollments.manage',
      'dispatch.read', 'dispatch.manage', 'dispatch.work', 'shipments.read', 'shipments.manage',
      'signatures.read', 'signatures.request', 'signatures.manage',
      'contracts.read', 'contracts.write', 'contracts.manage',
      'controls.read', 'controls.manage', 'controls.collect', 'controls.acknowledge',
      'incidents.read', 'incidents.write', 'incidents.manage'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'tags.read', 'tags.apply', 'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share',
      'attachments.read', 'attachments.upload', 'teams.read', 'catalog.read', 'inventory.read',
      'orders.read', 'promotions.read', 'custom_fields.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'views.read',
      'views.share', 'relations.read', 'relations.manage', 'calendar.read', 'calendar.write',
      'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'trash.read',
      'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read',
      'approvals.request', 'access_requests.read', 'access_requests.create', 'documents.read',
      'documents.write', 'drive.read', 'drive.create', 'forms.read', 'forms.submit',
      'templates.read', 'templates.apply', 'time_tracking.read', 'time_tracking.track',
      'pipelines.read', 'parties.read', 'parties.write', 'engagements.read', 'engagements.write',
      'deals.read', 'deals.write', 'work_items.read', 'work_items.write', 'quotes.read',
      'quotes.write', 'invoices.read', 'sla.read', 'targets.read', 'hiring.read',
      'employees.read', 'rules.read', 'assets.read', 'scores.read',
      'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit',
      'dispatch.read', 'dispatch.work', 'shipments.read', 'signatures.read',
      'contracts.read', 'contracts.write', 'controls.read', 'controls.collect',
      'controls.acknowledge', 'incidents.read', 'incidents.write'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.run_contract_renewals (
  as_of date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_today date := coalesce(run_contract_renewals.as_of, current_date);
  v_row "better_supabase"."contracts"%rowtype;
  v_renewed integer := 0;
  v_expired integer := 0;
begin
  for v_row in
    select * from "better_supabase"."contracts" x
    where x."status" = 'active' and x."ends_on" < v_today
    for update skip locked
  loop
    if v_row."auto_renew" then
      while v_row."ends_on" < v_today loop
        v_row."ends_on" := (v_row."ends_on" + make_interval(months => v_row."renewal_months"))::date;
        v_row."renewed_count" := v_row."renewed_count" + 1;
      end loop;
      update "better_supabase"."contracts" x set "ends_on" = v_row."ends_on", "renewed_count" = v_row."renewed_count", "updated_at" = now()
        where x."id" = v_row."id";
      perform "better_supabase"."contract_schedule_renewal"(v_row."id");
      perform "better_supabase".emit_event('contract.renewed', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'endsOn', v_row."ends_on", 'renewedCount', v_row."renewed_count"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.renewed',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'renewed contract ' || v_row."title" || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'endsOn', v_row."ends_on", 'renewedCount', v_row."renewed_count")
  );
      v_renewed := v_renewed + 1;
    else
      perform "better_supabase"."contract_apply_status"(v_row."id", 'expired');
      v_expired := v_expired + 1;
    end if;
  end loop;
  return jsonb_build_object('renewed', v_renewed, 'expired', v_expired);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.control_id is null then
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  perform "better_supabase".emit_event('control.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/controls');
  perform better_supabase.audit_event(
    event_type => 'control.saved',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'saved control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control_framework (
  tenant      uuid,
  key         text,
  name        text,
  version     text DEFAULT NULL::text,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_version (
  document_id uuid,
  state       text,
  label       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = save_document_version.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.maintain'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  return "better_supabase"."version_insert"(v_doc."tenant_id", 'document', v_doc."id"::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc."name"),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_evidence_task (
  control_id    uuid,
  title         text,
  interval_days integer,
  due_on        date    DEFAULT NULL::date,
  assignee_id   uuid    DEFAULT NULL::uuid,
  active        boolean DEFAULT true,
  task_id       uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_obligation (
  contract_id   uuid,
  title         text,
  due_on        date DEFAULT NULL::date,
  owner_id      uuid DEFAULT NULL::uuid,
  description   text DEFAULT NULL::text,
  obligation_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_contract "better_supabase"."contracts"%rowtype;
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_contract from "better_supabase"."contracts" x where x."id" = save_obligation.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_contract."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contract obligations' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if nullif(trim(save_obligation.title), '') is null then
    raise exception 'an obligation needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_obligation.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_contract."tenant_id" and m."user_id" = save_obligation.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_obligation.obligation_id is null then
    insert into "better_supabase"."contract_obligations" ("tenant_id", "contract_id", "title", "description", "due_on", "owner_id")
    values (v_contract."tenant_id", v_contract."id", trim(save_obligation.title), nullif(trim(save_obligation.description), ''), save_obligation.due_on, save_obligation.owner_id)
    returning * into v_row;
  else
    update "better_supabase"."contract_obligations" x set "title" = trim(save_obligation.title), "description" = nullif(trim(save_obligation.description), ''),
      "due_on" = save_obligation.due_on, "owner_id" = save_obligation.owner_id, "updated_at" = now()
      where x."id" = save_obligation.obligation_id and x."contract_id" = v_contract."id"
      returning * into v_row;
    if not found then
      raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
    end if;
  end if;
  perform "better_supabase".emit_event('obligation.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'obligation.saved',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'saved obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_policy (
  tenant                   uuid,
  key                      text,
  title                    text,
  owner_id                 uuid    DEFAULT NULL::uuid,
  requires_acknowledgement boolean DEFAULT true,
  policy_id                uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_policy.tenant, 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if save_policy.owner_id is not null and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = save_policy.tenant and m."user_id" = save_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'POLICY_INVALID';
  end if;
  if save_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_policy.tenant, save_policy.key, trim(save_policy.title), save_policy.owner_id, coalesce(save_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_policy.key, "title" = trim(save_policy.title), "owner_id" = save_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_policy.policy_id and x."tenant_id" = save_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_postmortem (
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
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = save_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to write postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(save_postmortem.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if save_postmortem.attrs ? 'actionItems' and jsonb_typeof(save_postmortem.attrs -> 'actionItems') is distinct from 'array' then
    raise exception 'actionItems must be an array' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incident_postmortems" ("tenant_id", "incident_id", "author_id")
  values (v_row."tenant_id", v_row."id", auth.uid())
  on conflict ("incident_id") do nothing;
  update "better_supabase"."incident_postmortems" x set
    "summary" = case when save_postmortem.attrs ? 'summary' then save_postmortem.attrs ->> 'summary' else x."summary" end,
    "impact" = case when save_postmortem.attrs ? 'impact' then save_postmortem.attrs ->> 'impact' else x."impact" end,
    "root_cause" = case when save_postmortem.attrs ? 'rootCause' then save_postmortem.attrs ->> 'rootCause' else x."root_cause" end,
    "resolution" = case when save_postmortem.attrs ? 'resolution' then save_postmortem.attrs ->> 'resolution' else x."resolution" end,
    "action_items" = case when save_postmortem.attrs ? 'actionItems' then save_postmortem.attrs -> 'actionItems' else x."action_items" end,
    "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actionItems', v_post."action_items", 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_status_component (
  tenant        uuid,
  name          text,
  description   text    DEFAULT NULL::text,
  group_name    text    DEFAULT NULL::text,
  is_public     boolean DEFAULT true,
  sort_position integer DEFAULT 0,
  component_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."status_components"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_status_component.tenant, 'incidents.manage'), false)) then
    raise exception 'not allowed to manage status components' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if nullif(trim(save_status_component.name), '') is null then
    raise exception 'a component needs a name' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if save_status_component.component_id is null then
    insert into "better_supabase"."status_components" ("tenant_id", "name", "description", "group_name", "public", "position")
    values (save_status_component.tenant, trim(save_status_component.name), save_status_component.description,
      nullif(trim(save_status_component.group_name), ''), coalesce(save_status_component.is_public, true), coalesce(save_status_component.sort_position, 0))
    returning * into v_row;
    insert into "better_supabase"."status_component_history" ("tenant_id", "component_id", "status")
    values (v_row."tenant_id", v_row."id", v_row."status");
  else
    update "better_supabase"."status_components" x set "name" = trim(save_status_component.name), "description" = save_status_component.description,
      "group_name" = nullif(trim(save_status_component.group_name), ''), "public" = coalesce(save_status_component.is_public, true),
      "position" = coalesce(save_status_component.sort_position, 0), "updated_at" = now()
      where x."id" = save_status_component.component_id and x."tenant_id" = save_status_component.tenant
      returning * into v_row;
    if not found then
      raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'group', v_row."group_name", 'public', v_row."public", 'status', v_row."status", 'position', v_row."position", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_status_page (
  tenant      uuid,
  slug        text,
  title       text,
  description text    DEFAULT NULL::text,
  published   boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."status_pages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_status_page.tenant, 'incidents.manage'), false)) then
    raise exception 'not allowed to manage the status page' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if save_status_page.slug is null or save_status_page.slug !~ '^[a-z0-9][a-z0-9-]{1,62}$' then
    raise exception 'the slug takes 2 to 63 lowercase letters, digits and dashes' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."status_pages" x where x."slug" = save_status_page.slug and x."tenant_id" <> save_status_page.tenant
  ) then
    raise exception 'another organization uses this slug' using errcode = '23505', hint = 'STATUS_PAGE_SLUG_TAKEN';
  end if;
  insert into "better_supabase"."status_pages" ("tenant_id", "slug", "title", "description", "published")
  values (save_status_page.tenant, save_status_page.slug, trim(save_status_page.title), save_status_page.description, coalesce(save_status_page.published, false))
  on conflict ("tenant_id") do update
    set "slug" = excluded."slug", "title" = excluded."title", "description" = excluded."description",
      "published" = excluded."published", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'slug', v_row."slug", 'title', v_row."title", 'description', v_row."description", 'published', v_row."published", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_contract_for_signature (
  contract_id uuid,
  signers     uuid[],
  sign_order  text   DEFAULT 'parallel'::text,
  message     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_version uuid;
  v_request uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contracts" x where x."id" = send_contract_for_signature.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.manage'), false)) then
    raise exception 'not allowed to send contracts for signature' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_review' then
    raise exception 'only a contract in review goes out for signature' using errcode = '55000', hint = 'CONTRACT_TRANSITION_INVALID';
  end if;
  v_version := ("better_supabase"."version_insert"(
    v_row."tenant_id", 'contract', v_row."id"::text,
    jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") - 'status' - 'updatedAt' - 'signatureRequestId' - 'renewedCount',
    null, 'Sent for signature', 'manual', true, auth.uid()
  ) ->> 'id')::uuid;
  v_request := ("better_supabase"."create_signature_request"(
    v_row."tenant_id", 'contract', v_row."id"::text,
    send_contract_for_signature.signers, v_version,
    coalesce(send_contract_for_signature.sign_order, 'parallel'), null,
    send_contract_for_signature.message
  ) ->> 'id')::uuid;
  update "better_supabase"."contracts" x set "signature_request_id" = v_request, "updated_at" = now()
    where x."id" = v_row."id";
  return "better_supabase"."contract_apply_status"(v_row."id", 'out_for_signature');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_contacts (
  deal     uuid,
  contacts jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not (case coalesce(v_item ->> 'type', 'person')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(v_item ->> 'type', 'person'), (v_item ->> 'id'), 'read')) then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_incident_impacts (
  incident_id uuid,
  impacts     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
begin
  select * into v_row from "better_supabase"."incidents" x where x."id" = set_incident_impacts.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to change incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  perform "better_supabase"."incident_apply_impacts"(v_row."id", set_incident_impacts.impacts);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_obligation_status (
  obligation_id uuid,
  status        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contract_obligations" x where x."id" = set_obligation_status.obligation_id for update;
  if not found then
    raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) or v_row."owner_id" = auth.uid()) then
    raise exception 'not allowed to change this obligation' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if set_obligation_status.status is null or set_obligation_status.status not in ('open', 'done', 'waived') then
    raise exception 'status must be open, done or waived' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  update "better_supabase"."contract_obligations" x set "status" = set_obligation_status.status,
    "completed_at" = case when set_obligation_status.status = 'open' then null else now() end,
    "completed_by" = case when set_obligation_status.status = 'open' then null else auth.uid() end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('obligation.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'obligation.status_changed',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'marked obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_time_rate (
  tenant         uuid,
  rate           bigint,
  currency       text,
  user_id        uuid   DEFAULT NULL::uuid,
  subject_type   text   DEFAULT NULL::text,
  subject_id     text   DEFAULT NULL::text,
  effective_from date   DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not (case set_time_rate.subject_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      else false
    end and "better_supabase"."can_subject"(set_time_rate.subject_type, set_time_rate.subject_id, 'read')) then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.shipments_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."shipments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_signature (
  request_id          uuid,
  method              text,
  typed_name          text DEFAULT NULL::text,
  image_attachment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "better_supabase"."signature_requests"%rowtype;
  v_row "better_supabase"."signatures"%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to sign' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    raise exception 'method must be drawn, typed or click' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    raise exception 'a typed signature needs the typed name' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    raise exception 'a drawn signature needs its image attachment' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "better_supabase"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.image_attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = sign_signature.image_attachment_id
      and a."organization_id" = v_req."tenant_id"
  ) then
    raise exception 'the signature image isn''t an attachment in this organization' using errcode = '22023', hint = 'SIGNATURE_IMAGE_NOT_FOUND';
  end if;
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  if v_current is distinct from v_req."content_hash" then
    raise exception 'the version to sign changed after the request was made' using errcode = '55000', hint = 'SIGNATURE_CONTENT_CHANGED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_sign"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using v_req."id", v_me, sign_signature.method;
    end if;
  end;
  insert into "better_supabase"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  perform "better_supabase".emit_event('signature.signed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.signed',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'signed ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method")
  );
  -- A signer who approves the linked request's current step decides it.
  if v_req."approval_request_id" is not null and "better_supabase"."approval_eligible"(v_req."approval_request_id") then
    perform "better_supabase"."decide_approval"(v_req."approval_request_id", 'approved', 'Signed electronically');
  end if;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    perform "better_supabase".emit_event('signature.completed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'versionId', v_req."version_id"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_sign"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'requestId', v_row."request_id", 'signer', v_row."signer", 'method', v_row."method", 'typedName', v_row."typed_name", 'imageAttachmentId', v_row."image_attachment_id", 'signedHash', v_row."signed_hash", 'ip', v_row."ip", 'userAgent', v_row."user_agent", 'signedAt', v_row."signed_at") || jsonb_build_object('requestStatus', v_req."status");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.signature_verification (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_req_hash text;
  v_current text;
  v_latest uuid;
  v_latest_hash text;
  v_items jsonb;
  v_signed boolean;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = signature_verification.request_id;
  if not found then
    return null;
  end if;
  v_req_hash := v_req."content_hash";
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  select x."id", x."content_hash" into v_latest, v_latest_hash
    from "better_supabase"."versions" x
    where x."subject_type" = v_req."subject_type" and x."subject_id" = v_req."subject_id"
    order by x."number" desc
    limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'signer', g."signer", 'valid', g."signed_hash" = encode(extensions.digest(g."request_id"::text || ':' || v_req_hash || ':' || g."signer"::text || ':' || g."method" || ':' || coalesce(g."typed_name", '') || ':' || coalesce(g."image_attachment_id"::text, '') || ':' || to_char(g."signed_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex')) order by g."signed_at"), '[]'::jsonb)
    into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  select coalesce(bool_and((i ->> 'valid')::boolean), true) into v_signed from jsonb_array_elements(v_items) i;
  return jsonb_build_object(
    'valid', v_current is not distinct from v_req_hash and v_signed,
    'contentMatches', v_current is not distinct from v_req_hash,
    'changedSince', v_latest_hash is distinct from v_req_hash,
    'latestVersionId', v_latest,
    'signatures', v_items
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_sla_clocks (
  subject_type text,
  subject_id   text,
  priority     text,
  trusted      boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case start_sla_clocks.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      else null::text
    end);
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or (case start_sla_clocks.subject_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(start_sla_clocks.subject_type, start_sla_clocks.subject_id, 'read'))) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_timer (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  billable      boolean DEFAULT false,
  rate          bigint  DEFAULT NULL::bigint,
  rate_currency text    DEFAULT NULL::text,
  note          text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.rate is null) <> (start_timer.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case subject_tags.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    else false
  end) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'comment' then
      return (select s."body"::text from "better_supabase"."comments" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'engagement' then
      return (select s."title"::text from "better_supabase"."engagements" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset' then
      return (select s."name"::text from "better_supabase"."assets" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset_location' then
      return (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lease' then
      return (select s."title"::text from "better_supabase"."lease_agreements" s where s."id" = (subject_title.subject_id)::uuid);
    when 'maintenance_request' then
      return (select s."title"::text from "better_supabase"."maintenance_requests" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_report' then
      return (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_line' then
      return (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (subject_title.subject_id)::uuid);
    when 'donation_fund' then
      return (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_order' then
      return (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'shipment' then
      return (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (subject_title.subject_id)::uuid);
    when 'contract' then
      return (select s."title"::text from "better_supabase"."contracts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'control' then
      return (select s."title"::text from "better_supabase"."controls" s where s."id" = (subject_title.subject_id)::uuid);
    when 'policy' then
      return (select s."title"::text from "better_supabase"."policies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'incident' then
      return (select s."title"::text from "better_supabase"."incidents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'comment', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."comments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'comment')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'engagement', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."engagements" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'engagement')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."lease_agreements" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'maintenance_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."maintenance_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'maintenance_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', null::text))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_types()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select '{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,asset,asset_location,lease,maintenance_request,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,document,customer,drive_node,application,project,task}'::text[]
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_form (
  form_id       uuid,
  answers       jsonb,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  submission_id uuid    DEFAULT NULL::uuid,
  draft         boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case submit_form.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    else false
  end) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case tag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'comment' then true
    when 'company' then true
    when 'person' then true
    when 'deal' then true
    when 'engagement' then true
    when 'work_item' then true
    when 'employee' then true
    when 'ledger_account' then true
    when 'product' then true
    when 'product_variant' then true
    when 'calendar_event' then true
    when 'asset' then true
    when 'asset_location' then true
    when 'lease' then true
    when 'maintenance_request' then true
    when 'expense_report' then true
    when 'expense_line' then true
    when 'donation_fund' then true
    when 'work_order' then true
    when 'shipment' then true
    when 'contract' then true
    when 'control' then true
    when 'policy' then true
    when 'incident' then true
    when 'document' then true
    when 'customer' then true
    when 'drive_node' then true
    when 'application' then true
    when 'project' then true
    when 'task' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  perform "better_supabase".emit_event('subject.tagged', jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id), 'subjects/' || tag.subject_type || '/' || tag.subject_id, (tag.tenant)::text, null, 'better-supabase/tags');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tags_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.comments' then array['comment'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    delete from "better_supabase"."taggings" x where x."subject_type" = v_type and x."subject_id" = v_drop and exists (select 1 from "better_supabase"."taggings" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."tag_id" is not distinct from x."tag_id");
    update "better_supabase"."taggings" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transition_contract (
  contract_id uuid,
  action      text,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_from text[];
  v_to text;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = transition_contract.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  case transition_contract.action
    when 'submit' then v_from := array['draft']; v_to := 'in_review';
    when 'return' then v_from := array['in_review']; v_to := 'draft';
    when 'activate' then v_from := array['in_review']; v_to := 'active';
    when 'recall' then v_from := array['out_for_signature']; v_to := 'in_review';
    when 'terminate' then v_from := array['draft', 'in_review', 'out_for_signature', 'active']; v_to := 'terminated';
    else
      raise exception 'action must be submit, return, activate, recall or terminate' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end case;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when transition_contract.action in ('submit', 'return') then 'contracts.write' else 'contracts.manage' end), false)) then
    raise exception 'not allowed to move this contract' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if not (v_row."status" = any (v_from)) then
    raise exception 'the contract can''t take this step from its status' using errcode = '55000', hint = 'CONTRACT_TRANSITION_INVALID';
  end if;
  if v_row."status" = 'out_for_signature' and v_row."signature_request_id" is not null then
    -- The signatures trigger moves a recalled contract back to review.
    perform "better_supabase"."cancel_signature_request"(v_row."signature_request_id");
    if transition_contract.action = 'recall' then
      return "better_supabase"."get_contract"(v_row."id");
    end if;
  end if;
  return "better_supabase"."contract_apply_status"(v_row."id", v_to, transition_contract.reason);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', unlink.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to unlink records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := unlink.target_type; v_source_id := unlink.target_id;
    v_target_type := unlink.source_type; v_target_id := unlink.source_id;
  else
    v_source_type := unlink.source_type; v_source_id := unlink.source_id;
    v_target_type := unlink.target_type; v_target_id := unlink.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case unlink.source_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end)
     or not (case unlink.target_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end) then
    raise exception 'not allowed to unlink these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."relations"
    where "tenant_id" = unlink.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id
    returning * into v_old;
  if v_old."id" is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', unlink.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (unlink.tenant)::text, null, 'better-supabase/relations');
  return jsonb_build_object('removed', true, 'data', v_old."data");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case untag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  perform "better_supabase".emit_event('subject.untagged', jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id), 'subjects/' || untag.subject_type || '/' || untag.subject_id, (untag.tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_contract (
  contract_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contracts" x where x."id" = update_contract.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contracts' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if jsonb_typeof(update_contract.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."status" not in ('draft', 'in_review', 'active') then
    raise exception 'this contract can no longer change' using errcode = '55000', hint = 'CONTRACT_LOCKED';
  end if;
  if v_row."status" = 'active' and exists (
    select 1 from jsonb_object_keys(update_contract.attrs) k
    where k not in ('description', 'ownerId', 'autoRenew', 'renewalMonths', 'noticeDays')
  ) then
    raise exception 'an active contract changes only its owner, description and renewal terms' using errcode = '55000', hint = 'CONTRACT_LOCKED';
  end if;
  v_owner := v_row."owner_id";
  v_row."title" := case when update_contract.attrs ? 'title' then (update_contract.attrs ->> 'title')::text else v_row."title" end;
  v_row."description" := case when update_contract.attrs ? 'description' then (update_contract.attrs ->> 'description')::text else v_row."description" end;
  v_row."counterparty_type" := case when update_contract.attrs ? 'counterpartyType' then (update_contract.attrs ->> 'counterpartyType')::text else v_row."counterparty_type" end;
  v_row."counterparty_id" := case when update_contract.attrs ? 'counterpartyId' then (update_contract.attrs ->> 'counterpartyId')::text else v_row."counterparty_id" end;
  v_row."owner_id" := case when update_contract.attrs ? 'ownerId' then (update_contract.attrs ->> 'ownerId')::uuid else v_row."owner_id" end;
  v_row."value" := case when update_contract.attrs ? 'value' then (update_contract.attrs ->> 'value')::bigint else v_row."value" end;
  v_row."currency" := case when update_contract.attrs ? 'currency' then (update_contract.attrs ->> 'currency')::text else v_row."currency" end;
  v_row."starts_on" := case when update_contract.attrs ? 'startsOn' then (update_contract.attrs ->> 'startsOn')::date else v_row."starts_on" end;
  v_row."ends_on" := case when update_contract.attrs ? 'endsOn' then (update_contract.attrs ->> 'endsOn')::date else v_row."ends_on" end;
  v_row."auto_renew" := case when update_contract.attrs ? 'autoRenew' then (update_contract.attrs ->> 'autoRenew')::boolean else v_row."auto_renew" end;
  v_row."renewal_months" := case when update_contract.attrs ? 'renewalMonths' then (update_contract.attrs ->> 'renewalMonths')::integer else v_row."renewal_months" end;
  v_row."notice_days" := case when update_contract.attrs ? 'noticeDays' then (update_contract.attrs ->> 'noticeDays')::integer else v_row."notice_days" end;
  v_row."title" := nullif(trim(v_row."title"), '');
  if v_row."title" is null then
    raise exception 'a contract needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."counterparty_type" is not null and not (case v_row."counterparty_type"
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."counterparty_type", v_row."counterparty_id", 'read')) then
    raise exception 'the counterparty is unknown or not in this organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."owner_id" is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."owner_id") then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  update "better_supabase"."contracts" x set
    "title" = v_row."title", "description" = v_row."description",
    "counterparty_type" = v_row."counterparty_type", "counterparty_id" = v_row."counterparty_id",
    "owner_id" = v_row."owner_id", "value" = v_row."value", "currency" = upper(v_row."currency"),
    "starts_on" = v_row."starts_on", "ends_on" = v_row."ends_on",
    "auto_renew" = coalesce(v_row."auto_renew", false), "renewal_months" = coalesce(v_row."renewal_months", 12),
    "notice_days" = coalesce(v_row."notice_days", 30), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_owner is distinct from v_row."owner_id" and v_row."owner_id" is not null then
    update "better_supabase"."reminders" x set "user_id" = v_row."owner_id"
      where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract'
        and x."subject_id" = v_row."id"::text and x."user_id" = v_owner
        and x."offset_minutes" = 20160;
  end if;
  perform "better_supabase"."contract_schedule_renewal"(v_row."id");
  perform "better_supabase".emit_event('contract.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.updated',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'updated contract' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_deals (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "better_supabase"."deals";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { dealId, field, value }' using errcode = '22023', hint = 'DEAL_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"((v_change -> 'value' ->> 'type'), (v_change -> 'value' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row."currency" then
          raise exception 'an amount must be in the deal''s currency' using errcode = '22023', hint = 'DEAL_CURRENCY_MISMATCH';
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_deal, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "better_supabase"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "better_supabase"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "better_supabase"."deals" x set "owner_user_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "better_supabase"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "better_supabase"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "better_supabase"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "better_supabase"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "better_supabase"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "better_supabase"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "better_supabase"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "better_supabase"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "better_supabase"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "better_supabase"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "better_supabase"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "better_supabase"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "better_supabase"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "better_supabase"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "better_supabase"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'DEAL_FIELD_UNKNOWN';
      end case;
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_deal, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."deals" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('deal.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'dealId')::uuid = v_row."id")), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_engagement (
  engagement uuid,
  attrs      jsonb,
  subjects   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := update_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_incident (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = update_incident.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to change incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_incident.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ? 'title' and nullif(trim(update_incident.attrs ->> 'title'), '') is null then
    raise exception 'an incident needs a title' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ? 'severity' and coalesce(update_incident.attrs ->> 'severity', '') not in ('sev1', 'sev2', 'sev3', 'sev4') then
    raise exception 'severity must be sev1, sev2, sev3 or sev4' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ->> 'commanderId' is not null
    and not exists (select 1 from "public"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = (update_incident.attrs ->> 'commanderId')::uuid) then
    raise exception 'the commander must be a member of the organization' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  update "better_supabase"."incidents" x set
    "title" = case when update_incident.attrs ? 'title' then trim(update_incident.attrs ->> 'title') else x."title" end,
    "description" = case when update_incident.attrs ? 'description' then update_incident.attrs ->> 'description' else x."description" end,
    "severity" = case when update_incident.attrs ? 'severity' then update_incident.attrs ->> 'severity' else x."severity" end,
    "public" = case when update_incident.attrs ? 'public' then coalesce((update_incident.attrs ->> 'public')::boolean, false) else x."public" end,
    "commander_id" = case when update_incident.attrs ? 'commanderId' then (update_incident.attrs ->> 'commanderId')::uuid else x."commander_id" end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_quote (
  quote uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'company' ->> 'type', 'company')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'company' ->> 'type', 'company'), (update_quote.attrs -> 'company' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person'), (update_quote.attrs -> 'contact' ->> 'id'), 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  perform "better_supabase".emit_event('quote.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_time_entry (
  entry_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if (v_row."rate" is null) <> (v_row."rate_currency" is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "rate_currency" = v_row."rate_currency",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."contract_obligations"
  ADD CONSTRAINT "contract_obligations_tenant_id_contract_id_fkey" FOREIGN KEY (tenant_id, contract_id) REFERENCES better_supabase.contracts(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."control_evidence"
  ADD CONSTRAINT "control_evidence_attachment_id_fkey" FOREIGN KEY (attachment_id) REFERENCES better_supabase.attachments(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."controls"
  ADD CONSTRAINT "controls_tenant_id_framework_id_fkey" FOREIGN KEY (tenant_id, framework_id) REFERENCES better_supabase.control_frameworks(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."control_evidence"
  ADD CONSTRAINT "control_evidence_tenant_id_control_id_fkey" FOREIGN KEY (tenant_id, control_id) REFERENCES better_supabase.controls(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."control_evidence"
  ADD CONSTRAINT "control_evidence_task_id_fkey" FOREIGN KEY (task_id) REFERENCES better_supabase.evidence_tasks(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."evidence_tasks"
  ADD CONSTRAINT "evidence_tasks_tenant_id_control_id_fkey" FOREIGN KEY (tenant_id, control_id) REFERENCES better_supabase.controls(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_impacts"
  ADD CONSTRAINT "incident_impacts_tenant_id_incident_id_fkey" FOREIGN KEY (tenant_id, incident_id) REFERENCES better_supabase.incidents(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_postmortems"
  ADD CONSTRAINT "incident_postmortems_tenant_id_incident_id_fkey" FOREIGN KEY (tenant_id, incident_id) REFERENCES better_supabase.incidents(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_updates"
  ADD CONSTRAINT "incident_updates_tenant_id_incident_id_fkey" FOREIGN KEY (tenant_id, incident_id) REFERENCES better_supabase.incidents(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."policies"
  ADD CONSTRAINT "policies_current_version_id_fkey" FOREIGN KEY (current_version_id) REFERENCES better_supabase.versions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."policy_acknowledgements"
  ADD CONSTRAINT "policy_acknowledgements_tenant_id_policy_id_fkey" FOREIGN KEY (tenant_id, policy_id) REFERENCES better_supabase.policies(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."policy_acknowledgements"
  ADD CONSTRAINT "policy_acknowledgements_version_id_fkey" FOREIGN KEY (version_id) REFERENCES better_supabase.versions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."contracts"
  ADD CONSTRAINT "contracts_signature_request_id_fkey" FOREIGN KEY (signature_request_id) REFERENCES better_supabase.signature_requests(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."signature_requests"
  ADD CONSTRAINT "signature_requests_version_id_fkey" FOREIGN KEY (version_id) REFERENCES better_supabase.versions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."signatures"
  ADD CONSTRAINT "signatures_request_id_fkey" FOREIGN KEY (request_id) REFERENCES better_supabase.signature_requests(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."incident_impacts"
  ADD CONSTRAINT "incident_impacts_tenant_id_component_id_fkey" FOREIGN KEY (tenant_id, component_id) REFERENCES better_supabase.status_components(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."status_component_history"
  ADD CONSTRAINT "status_component_history_tenant_id_component_id_fkey" FOREIGN KEY (tenant_id, component_id) REFERENCES better_supabase.status_components(tenant_id, id)
    ON DELETE CASCADE;

CREATE INDEX contract_obligations_due_idx ON better_supabase.contract_obligations USING btree (tenant_id, due_on)
  WHERE (status = 'open'::text);

CREATE INDEX contract_obligations_owner_idx ON better_supabase.contract_obligations USING btree (tenant_id, owner_id, due_on)
  WHERE (owner_id IS NOT NULL);

CREATE INDEX contract_obligations_parent_idx ON better_supabase.contract_obligations USING btree (tenant_id, contract_id, due_on);

CREATE INDEX contracts_counterparty_idx ON better_supabase.contracts USING btree (tenant_id, counterparty_type, counterparty_id)
  WHERE (counterparty_type IS NOT NULL);

CREATE INDEX contracts_owner_idx ON better_supabase.contracts USING btree (tenant_id, owner_id)
  WHERE (owner_id IS NOT NULL);

CREATE INDEX contracts_signature_idx ON better_supabase.contracts USING btree (signature_request_id)
  WHERE (signature_request_id IS NOT NULL);

CREATE INDEX contracts_status_idx ON better_supabase.contracts USING btree (tenant_id, status, ends_on);

CREATE INDEX control_evidence_attachment_idx ON better_supabase.control_evidence USING btree (attachment_id)
  WHERE (attachment_id IS NOT NULL);

CREATE INDEX control_evidence_parent_idx ON better_supabase.control_evidence USING btree (tenant_id, control_id, collected_at DESC);

CREATE INDEX control_evidence_request_idx ON better_supabase.control_evidence USING btree (task_id)
  WHERE (task_id IS NOT NULL);

CREATE INDEX controls_owner_idx ON better_supabase.controls USING btree (tenant_id, owner_id)
  WHERE (owner_id IS NOT NULL);

CREATE INDEX controls_tenant_idx ON better_supabase.controls USING btree (tenant_id, framework_id);

CREATE INDEX evidence_tasks_assignee_idx ON better_supabase.evidence_tasks USING btree (tenant_id, assignee_id, due_on)
  WHERE (assignee_id IS NOT NULL);

CREATE INDEX evidence_tasks_due_idx ON better_supabase.evidence_tasks USING btree (due_on)
  WHERE active;

CREATE INDEX evidence_tasks_parent_idx ON better_supabase.evidence_tasks USING btree (tenant_id, control_id);

CREATE INDEX incident_impacts_component_idx ON better_supabase.incident_impacts USING btree (tenant_id, component_id);

CREATE INDEX incident_impacts_parent_idx ON better_supabase.incident_impacts USING btree (tenant_id, incident_id);

CREATE INDEX incident_postmortems_tenant_idx ON better_supabase.incident_postmortems USING btree (tenant_id, incident_id);

CREATE INDEX incident_updates_parent_idx ON better_supabase.incident_updates USING btree (tenant_id, incident_id, created_at);

CREATE INDEX incidents_commander_idx ON better_supabase.incidents USING btree (tenant_id, commander_id)
  WHERE (commander_id IS NOT NULL);

CREATE INDEX incidents_open_idx ON better_supabase.incidents USING btree (tenant_id)
  WHERE (status <> 'resolved'::text);

CREATE INDEX incidents_tenant_idx ON better_supabase.incidents USING btree (tenant_id, started_at DESC);

CREATE INDEX policies_version_idx ON better_supabase.policies USING btree (current_version_id)
  WHERE (current_version_id IS NOT NULL);

CREATE INDEX policy_acknowledgements_parent_idx ON better_supabase.policy_acknowledgements USING btree (tenant_id, policy_id);

CREATE INDEX policy_acknowledgements_user_idx ON better_supabase.policy_acknowledgements USING btree (tenant_id, user_id);

CREATE INDEX policy_acknowledgements_version_idx ON better_supabase.policy_acknowledgements USING btree (version_id);

CREATE INDEX signature_requests_signers_idx ON better_supabase.signature_requests USING gin (signers);

CREATE INDEX signature_requests_subject_idx ON better_supabase.signature_requests USING btree (tenant_id, subject_type, subject_id);

CREATE INDEX signature_requests_version_idx ON better_supabase.signature_requests USING btree (version_id);

CREATE INDEX status_component_history_component_idx ON better_supabase.status_component_history USING btree (tenant_id, component_id, started_at);

CREATE UNIQUE INDEX status_component_history_open_idx ON better_supabase.status_component_history USING btree (component_id)
  WHERE (ended_at IS NULL);

CREATE INDEX status_components_tenant_idx ON better_supabase.status_components USING btree (tenant_id, "position");

CREATE TRIGGER bs_contracts_signature_settled
  AFTER UPDATE OF status ON better_supabase.signature_requests
  FOR EACH ROW
  WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text)))
  EXECUTE FUNCTION better_supabase.contract_signature_settled();

CREATE POLICY "activity_entries_read" ON "better_supabase"."activity_entries"
  FOR SELECT
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('activity.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR (subject_id IS NULL) OR (NOT
    (subject_type = ANY
    ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,asset,asset_location,lease,maintenance_request,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,document,customer,drive_node,application,project,task}'::text[]))) OR better_supabase.activity_subject_readable(subject_type, subject_id))));

CREATE POLICY "contract_obligations_read" ON "better_supabase"."contract_obligations"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with))));

CREATE POLICY "contracts_read" ON "better_supabase"."contracts"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with))));

CREATE POLICY "control_evidence_read" ON "better_supabase"."control_evidence"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)));

CREATE POLICY "control_frameworks_read" ON "better_supabase"."control_frameworks"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)));

CREATE POLICY "controls_read" ON "better_supabase"."controls"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)));

CREATE POLICY "evidence_tasks_read" ON "better_supabase"."evidence_tasks"
  FOR SELECT
  TO "authenticated"
  USING (((assignee_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with))));

CREATE POLICY "incident_impacts_read" ON "better_supabase"."incident_impacts"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "incident_postmortems_read" ON "better_supabase"."incident_postmortems"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "incident_updates_read" ON "better_supabase"."incident_updates"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "incidents_read" ON "better_supabase"."incidents"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "policies_read" ON "better_supabase"."policies"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('controls.acknowledge'::text) AS tenant_ids_with))));

CREATE POLICY "policy_acknowledgements_read" ON "better_supabase"."policy_acknowledgements"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with))));

CREATE POLICY "signature_requests_read" ON "better_supabase"."signature_requests"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('signatures.read'::text) AS tenant_ids_with)) OR (( SELECT auth.uid() AS uid) = ANY (signers))));

CREATE POLICY "signatures_read" ON "better_supabase"."signatures"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('signatures.read'::text) AS tenant_ids_with)) OR (signer = ( SELECT auth.uid() AS uid))));

CREATE POLICY "status_component_history_read" ON "better_supabase"."status_component_history"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "status_components_read" ON "better_supabase"."status_components"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

CREATE POLICY "status_pages_read" ON "better_supabase"."status_pages"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)));

COMMENT ON FUNCTION "better_supabase"."contracts_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

REVOKE ALL ON FUNCTION "api"."acknowledge_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."acknowledge_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."add_control_evidence"(uuid, uuid, text, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_control_evidence"(uuid, uuid, text, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."cancel_signature_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_signature_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."control_posture"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."control_posture"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_contract"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_contract"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decline_signature_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decline_signature_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_obligation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_obligation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_status_component"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_status_component"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_contract"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_contract"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_control"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_control"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_incident"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_incident"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_signature_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_signature_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_status_page"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_status_page"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_contracts"(uuid, text, text, text, uuid, date, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_contracts"(uuid, text, text, text, uuid, date, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_control_frameworks"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_control_frameworks"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_controls"(uuid, uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_controls"(uuid, uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_incidents"(uuid, text, text, uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_incidents"(uuid, text, text, uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_policies"(uuid, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_policies"(uuid, boolean, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_status_components"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_status_components"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notify_overdue_evidence_tasks"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notify_overdue_evidence_tasks"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."open_incident"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_incident"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."policy_acknowledgements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."policy_acknowledgements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_incident_update"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_incident_update"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."public_status_page"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."public_status_page"(text, integer) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."publish_policy"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."publish_policy"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."publish_postmortem"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."publish_postmortem"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_control_evidence"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_control_evidence"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."run_contract_renewals"(date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."run_contract_renewals"(date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_control_framework"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_control_framework"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_obligation"(uuid, text, date, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_obligation"(uuid, text, date, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_policy"(uuid, text, text, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_policy"(uuid, text, text, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_postmortem"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_postmortem"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_status_page"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_status_page"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."send_contract_for_signature"(uuid, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."send_contract_for_signature"(uuid, uuid[], text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_incident_impacts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_incident_impacts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_obligation_status"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_obligation_status"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sign_signature"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sign_signature"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."transition_contract"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."transition_contract"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_contract"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_contract"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_incident"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_incident"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."acknowledge_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."acknowledge_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_signature_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_signature_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."contract_apply_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."contract_apply_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."contract_schedule_renewal"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."contract_schedule_renewal"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."contract_signature_settled"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."contracts_subject_merge"(text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."control_posture"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."control_posture"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_contract"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_contract"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decline_signature_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decline_signature_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_obligation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_obligation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_status_component"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_status_component"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_contract"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_contract"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_control"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_control"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_incident"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_incident"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_signature_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_signature_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_status_page"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_status_page"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."incident_apply_impacts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."incident_apply_impacts"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."incident_refresh_components"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."incident_refresh_components"(uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_contracts"(uuid, text, text, text, uuid, date, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_contracts"(uuid, text, text, text, uuid, date, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_control_frameworks"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_control_frameworks"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_incidents"(uuid, text, text, uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_incidents"(uuid, text, text, uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_policies"(uuid, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_policies"(uuid, boolean, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_status_components"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_status_components"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notify_overdue_evidence_tasks"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notify_overdue_evidence_tasks"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_incident"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_incident"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."policy_acknowledgements"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."policy_acknowledgements"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_incident_update"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_incident_update"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."public_status_page"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."public_status_page"(text, integer) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."publish_policy"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."publish_policy"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."publish_postmortem"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."publish_postmortem"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_control_evidence"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_control_evidence"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."run_contract_renewals"(date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."run_contract_renewals"(date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_control_framework"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_control_framework"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_obligation"(uuid, text, date, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_obligation"(uuid, text, date, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_policy"(uuid, text, text, uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_policy"(uuid, text, text, uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_postmortem"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_postmortem"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_status_page"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_status_page"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."send_contract_for_signature"(uuid, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."send_contract_for_signature"(uuid, uuid[], text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_incident_impacts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_incident_impacts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_obligation_status"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_obligation_status"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sign_signature"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sign_signature"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."signature_verification"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."transition_contract"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transition_contract"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_contract"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_contract"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_incident"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_incident"(uuid, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."contract_obligations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."contract_obligations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."contracts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."contracts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."control_evidence" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."control_evidence" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."control_frameworks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."control_frameworks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."controls" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."controls" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."evidence_tasks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."evidence_tasks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incident_impacts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incident_impacts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incident_postmortems" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incident_postmortems" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incident_updates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incident_updates" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."incidents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incidents" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."policies" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."policies" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."policy_acknowledgements" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."policy_acknowledgements" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."signature_requests" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."signature_requests" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."signatures" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."signatures" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."status_component_history" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."status_component_history" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."status_components" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."status_components" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."status_pages" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."status_pages" TO "service_role";
