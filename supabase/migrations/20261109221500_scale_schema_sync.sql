SET local check_function_bodies = off;

DROP TRIGGER "bsb_permission_overrides_bump_authz_versions" ON "better_supabase"."permission_overrides";

DROP INDEX "better_supabase"."notification_recipients_inbox_idx";

ALTER TABLE "better_supabase"."invoice_allocations"
  DROP CONSTRAINT "bsb_invoice_allocations_source_check";

ALTER TABLE "better_supabase"."purchase_order_lines"
  DROP CONSTRAINT "bsb_purchase_order_lines_check";

DROP FUNCTION "api"."drive_bin"(uuid, integer, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."app_my_organizations"();

DROP FUNCTION "better_supabase"."drive_bin"(uuid, integer, timestamp WITH time zone);

DROP FUNCTION "public"."my_organizations"();

CREATE TABLE "better_supabase"."asset_due_checks" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "asset_id"      uuid                     NOT NULL,
  "check_type"    text                     NOT NULL,
  "interval_days" integer                  NOT NULL,
  "last_done_at"  timestamp with time zone,
  "next_due_at"   timestamp with time zone,
  "result"        text,
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "asset_due_checks_pkey" PRIMARY KEY (id),
  CONSTRAINT "bsb_asset_due_checks_check_type_check" CHECK ((check_type ~ '^[a-z][a-z0-9_]{0,40}$'::text)),
  CONSTRAINT "bsb_asset_due_checks_interval_days_check" CHECK ((interval_days > 0))
);

ALTER TABLE "better_supabase"."asset_due_checks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."asset_identifiers" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "asset_id"   uuid                     NOT NULL,
  "type"       text                     NOT NULL,
  "value"      text                     NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "asset_identifiers_pkey" PRIMARY KEY (id)
);

CREATE TABLE "better_supabase"."asset_meter_readings" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "asset_id"   uuid                     NOT NULL,
  "unit"       text                     NOT NULL,
  "value"      numeric                  NOT NULL,
  "read_at"    timestamp with time zone NOT NULL,
  "reason"     text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "asset_meter_readings_pkey" PRIMARY KEY (id),
  CONSTRAINT "bsb_asset_meter_readings_unit_check" CHECK ((unit ~ '^[a-z][a-z0-9_]{0,40}$'::text))
);

CREATE TABLE "better_supabase"."import_refs" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "kind"       text                     NOT NULL,
  "key"        text                     NOT NULL,
  "payload"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "import_refs_key" UNIQUE (tenant_id, kind, key),
  CONSTRAINT "import_refs_pkey" PRIMARY KEY (id)
);

CREATE TABLE "better_supabase"."import_run_issues" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "run_id"      uuid                     NOT NULL,
  "tenant_id"   uuid                     NOT NULL,
  "source"      text                     NOT NULL,
  "entity"      text                     NOT NULL,
  "key"         text                     NOT NULL,
  "kind"        text                     NOT NULL,
  "code"        text                     NOT NULL,
  "message"     text                     NOT NULL,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "resolved_at" timestamp with time zone,
  CONSTRAINT "bsb_import_run_issues_kind" CHECK ((kind = ANY (ARRAY['conflict'::text, 'error'::text, 'warning'::text]))),
  CONSTRAINT "import_run_issues_pkey" PRIMARY KEY (id)
);

CREATE TABLE "better_supabase"."import_sources" (
  "id"              text   NOT NULL,
  "label_key"       text   NOT NULL,
  "description_key" text   NOT NULL,
  "file_types"      text[] NOT NULL DEFAULT '{}'::text[],
  "entities"        text[] NOT NULL DEFAULT '{}'::text[],
  "docs_link"       text,
  CONSTRAINT "import_sources_pkey" PRIMARY KEY (id)
);

CREATE TABLE "better_supabase"."invoice_open_items" (
  "tenant_id"     uuid   NOT NULL,
  "party_id"      text   NOT NULL,
  "side"          text   NOT NULL,
  "document_type" text   NOT NULL DEFAULT 'invoice'::text,
  "document_id"   uuid   NOT NULL,
  "currency"      text   NOT NULL,
  "due_on"        date,
  "issued_on"     date,
  "gross"         bigint NOT NULL,
  "balance"       bigint NOT NULL,
  CONSTRAINT "bsb_invoice_open_items_side_check" CHECK ((side = ANY (ARRAY['customer'::text, 'supplier'::text]))),
  CONSTRAINT "invoice_open_items_pkey" PRIMARY KEY (tenant_id, document_type, document_id)
);

ALTER TABLE "better_supabase"."invoice_open_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."maintenance_request_material_lines" (
  "id"                     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"              uuid                     NOT NULL,
  "maintenance_request_id" uuid                     NOT NULL,
  "variant_id"             uuid,
  "quantity"               numeric(12,3)            NOT NULL,
  "unit"                   text,
  "rank"                   text                     COLLATE pg_catalog."C" NOT NULL,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_maintenance_request_material_lines_quantity_check" CHECK ((quantity >= (0)::numeric)),
  CONSTRAINT "bsb_maintenance_request_material_lines_rank_check" CHECK ((rank ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'::text)),
  CONSTRAINT "bsb_maintenance_request_material_lines_unit_check" CHECK (((char_length(unit) >= 1) AND (char_length(unit) <= 30))),
  CONSTRAINT "maintenance_request_material_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."maintenance_request_material_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."maintenance_request_specification_lines" (
  "id"                     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"              uuid                     NOT NULL,
  "maintenance_request_id" uuid                     NOT NULL,
  "description"            text                     NOT NULL,
  "quantity"               numeric(12,3),
  "unit"                   text,
  "estimate"               numeric(10,2),
  "rank"                   text                     COLLATE pg_catalog."C" NOT NULL,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_maintenance_request_specification_lines_description_check" CHECK (((char_length(description) >= 1) AND (char_length(description) <= 500))),
  CONSTRAINT "bsb_maintenance_request_specification_lines_estimate_check" CHECK ((estimate >= (0)::numeric)),
  CONSTRAINT "bsb_maintenance_request_specification_lines_quantity_check" CHECK ((quantity >= (0)::numeric)),
  CONSTRAINT "bsb_maintenance_request_specification_lines_rank_check" CHECK ((rank ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'::text)),
  CONSTRAINT "bsb_maintenance_request_specification_lines_unit_check" CHECK (((char_length(unit) >= 1) AND (char_length(unit) <= 30))),
  CONSTRAINT "maintenance_request_specification_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."maintenance_request_specification_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."organization_payment_accounts" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "iban"       text                     NOT NULL,
  "bic"        text,
  "holder"     text,
  "label"      text,
  "is_primary" boolean                  NOT NULL DEFAULT false,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "organization_payment_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "organization_payment_accounts_tenant_id_iban_key" UNIQUE (tenant_id, iban)
);

ALTER TABLE "better_supabase"."organization_payment_accounts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."organization_profiles" (
  "tenant_id"       uuid                     NOT NULL,
  "vat_id"          text,
  "registration_id" text,
  "default_rate"    numeric,
  "currency"        text,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "organization_profiles_pkey" PRIMARY KEY (tenant_id)
);

ALTER TABLE "better_supabase"."organization_profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."party_bank_accounts" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "party_id"   uuid                     NOT NULL,
  "iban"       text                     NOT NULL,
  "bic"        text,
  "holder"     text,
  "is_primary" boolean                  NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "party_bank_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "party_bank_accounts_tenant_id_iban_key" UNIQUE (tenant_id, iban)
);

ALTER TABLE "better_supabase"."party_bank_accounts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."party_channels" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "party_id"   uuid                     NOT NULL,
  "party_kind" text                     NOT NULL,
  "channel"    text                     NOT NULL,
  "label"      text,
  "address"    text                     NOT NULL,
  "is_primary" boolean                  NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_party_channels_channel_check" CHECK ((channel = ANY (ARRAY['email'::text, 'phone'::text, 'mobile'::text, 'fax'::text, 'whatsapp'::text]))),
  CONSTRAINT "bsb_party_channels_party_kind_check" CHECK ((party_kind = ANY (ARRAY['person'::text, 'company'::text]))),
  CONSTRAINT "party_channels_pkey" PRIMARY KEY (id),
  CONSTRAINT "party_channels_tenant_id_party_id_channel_address_key" UNIQUE (tenant_id, party_id, channel, address)
);

ALTER TABLE "better_supabase"."party_channels"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."party_locations" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "party_id"    uuid                     NOT NULL,
  "kind"        text                     NOT NULL DEFAULT 'other'::text,
  "line1"       text,
  "line2"       text,
  "postal_code" text,
  "city"        text,
  "country"     text,
  "latitude"    double precision,
  "longitude"   double precision,
  "is_primary"  boolean                  NOT NULL DEFAULT false,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "party_locations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."party_locations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."work_item_material_lines" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "work_item_id" uuid                     NOT NULL,
  "variant_id"   uuid,
  "quantity"     numeric(12,3)            NOT NULL,
  "unit"         text,
  "rank"         text                     COLLATE pg_catalog."C" NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_work_item_material_lines_quantity_check" CHECK ((quantity >= (0)::numeric)),
  CONSTRAINT "bsb_work_item_material_lines_rank_check" CHECK ((rank ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'::text)),
  CONSTRAINT "bsb_work_item_material_lines_unit_check" CHECK (((char_length(unit) >= 1) AND (char_length(unit) <= 30))),
  CONSTRAINT "work_item_material_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."work_item_material_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."work_item_specification_lines" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "work_item_id" uuid                     NOT NULL,
  "description"  text                     NOT NULL,
  "quantity"     numeric(12,3),
  "unit"         text,
  "estimate"     numeric(10,2),
  "rank"         text                     COLLATE pg_catalog."C" NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_work_item_specification_lines_description_check" CHECK (((char_length(description) >= 1) AND (char_length(description) <= 500))),
  CONSTRAINT "bsb_work_item_specification_lines_estimate_check" CHECK ((estimate >= (0)::numeric)),
  CONSTRAINT "bsb_work_item_specification_lines_quantity_check" CHECK ((quantity >= (0)::numeric)),
  CONSTRAINT "bsb_work_item_specification_lines_rank_check" CHECK ((rank ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'::text)),
  CONSTRAINT "bsb_work_item_specification_lines_unit_check" CHECK (((char_length(unit) >= 1) AND (char_length(unit) <= 30))),
  CONSTRAINT "work_item_specification_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."work_item_specification_lines"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "make" text;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "model" text;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "model_year" integer;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "ownership" text;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "product_id" uuid;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "billing_email" text;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "bill_to_id" uuid;

ALTER TABLE "better_supabase"."import_records"
  ADD COLUMN "source_updated_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."import_records"
  ADD COLUMN "owned_hash" text;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "diff" jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "plan" jsonb;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "outcome" text;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "lease_until" timestamp WITH time zone;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "heartbeat_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."invoices"
  ADD COLUMN "supplied_on" date;

ALTER TABLE "better_supabase"."ledger_entries"
  ADD COLUMN "effective_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD COLUMN "estimated_minutes" integer;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "given_name" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "last_name" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "initials" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "infix" text;

ALTER TABLE "better_supabase"."products"
  ADD COLUMN "manufacturer" text;

ALTER TABLE "better_supabase"."products"
  ADD COLUMN "model" text;

ALTER TABLE "better_supabase"."products"
  ADD COLUMN "tax_code" text;

ALTER TABLE "better_supabase"."purchase_order_lines"
  ADD COLUMN "quantity_canceled" numeric(20,6) NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."purchase_order_lines"
  ADD COLUMN "tax_code" text;

ALTER TABLE "better_supabase"."purchase_orders"
  ADD COLUMN "exchange_rate" numeric;

ALTER TABLE "better_supabase"."purchase_orders"
  ADD COLUMN "number" text;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "estimated_minutes" integer;

CREATE OR REPLACE FUNCTION api.allocate_existing (
  tenant       uuid,
  invoice      uuid,
  reference    text,
  amount       bigint,
  party        text,
  allocated_on date   DEFAULT CURRENT_DATE,
  ledger_entry uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."allocate_existing"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.asset_identifier_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."asset_identifier_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.asset_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."asset_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.bootstrap_permissions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."bootstrap_permissions"() $function$;

CREATE OR REPLACE FUNCTION api.contact_method_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."contact_method_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_bin"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.due_check_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_check_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.ensure_import_periods (
  tenant           uuid,
  entry_date       date,
  start_month      integer,
  close_historical boolean
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ensure_import_periods"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.heartbeat_import_run (
  run     uuid,
  seconds integer DEFAULT 30
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."heartbeat_import_run"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_allocation (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_allocation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_asset (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_asset"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_asset_identifier (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_asset_identifier"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_contact_method (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_contact_method"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_due_check (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_due_check"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_ensure_ref (
  tenant   uuid,
  kind     text,
  key      text,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_ensure_ref"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.import_entities()
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_entities"() $function$;

CREATE OR REPLACE FUNCTION api.import_integrity (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_integrity"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_meter_reading (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_meter_reading"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_organization_profile (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_organization_profile"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_party (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_party_bank_account (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party_bank_account"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_party_contact (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party_contact"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_party_discount_group (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party_discount_group"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_party_location (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party_location"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_product (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_product"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_product_category (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_product_category"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.inventory_levels (
  tenant      uuid,
  variant_ids uuid[] DEFAULT NULL::uuid[],
  location_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inventory_levels"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.inventory_status_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inventory_status_counts"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_import_diff (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_diff"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_import_issues (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_issues"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_import_source_runs (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_source_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_import_sources()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_sources"() $function$;

CREATE OR REPLACE FUNCTION api.list_inventory_movements (
  tenant        uuid,
  variant       uuid    DEFAULT NULL::uuid,
  location      uuid    DEFAULT NULL::uuid,
  bin           uuid    DEFAULT NULL::uuid,
  lot           uuid    DEFAULT NULL::uuid,
  document_type text    DEFAULT NULL::text,
  document_id   text    DEFAULT NULL::text,
  row_limit     integer DEFAULT 50,
  row_offset    integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_inventory_movements"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_materials (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_materials"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_specification (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_specification"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_materials (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_materials"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_specification (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_specification"($1) $function$;

CREATE OR REPLACE FUNCTION api.open_items_page (
  tenant    uuid,
  side      text    DEFAULT NULL::text,
  party_id  text    DEFAULT NULL::text,
  "limit"   integer DEFAULT 50,
  "offset"  integer DEFAULT 0,
  count_cap integer DEFAULT 10000
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_items_page"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.organization_profile_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_profile_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.party_bank_account_id (
  tenant uuid,
  item   jsonb
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."party_bank_account_id"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.party_bank_account_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."party_bank_account_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.party_contact_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."party_contact_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.party_location_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."party_location_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.party_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."party_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.product_category_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_category_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.product_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.rebase_import_records (
  tenant   uuid,
  source   text,
  entities text[] DEFAULT NULL::text[],
  keys     text[] DEFAULT NULL::text[]
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rebase_import_records"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.rebuild_open_items (
  tenant uuid
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rebuild_open_items"($1) $function$;

CREATE OR REPLACE FUNCTION api.register_import_source (
  id              text,
  label_key       text,
  description_key text,
  file_types      text[],
  entities        text[],
  docs_link       text   DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."register_import_source"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.resolve_import_conflict (
  tenant uuid,
  source text,
  entity text,
  key    text,
  action text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_import_conflict"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_maintenance_request_material_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_maintenance_request_material_line"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_maintenance_request_specification_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_maintenance_request_specification_line"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_work_item_material_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_work_item_material_line"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_work_item_specification_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_work_item_specification_line"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.allocate_existing (
  tenant       uuid,
  invoice      uuid,
  reference    text,
  amount       bigint,
  party        text,
  allocated_on date   DEFAULT CURRENT_DATE,
  ledger_entry uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_reference text := nullif(btrim(allocate_existing.reference), '');
  v_party text := nullif(btrim(allocate_existing.party), '');
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', allocate_existing.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to record payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if v_reference is null or v_party is null or coalesce(allocate_existing.amount, 0) <= 0 then
    raise exception 'an imported allocation needs a reference, a party and a positive amount' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  select * into v_row from "better_supabase"."invoices" x
  where x."id" = allocate_existing.invoice and x."tenant_id" = allocate_existing.tenant
  for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select b."id" into v_id from "better_supabase"."invoice_allocations" b
  where b."tenant_id" = allocate_existing.tenant and b."reference" = v_reference and b."invoice_id" = v_row."id";
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'invoiceId', v_row."id", 'reference', v_reference, 'created', false);
  end if;
  insert into "better_supabase"."invoice_allocations" ("tenant_id", "reference", "party_id", "invoice_id", "source", "amount", "payment_id", "allocated_on")
  values (allocate_existing.tenant, v_reference, v_party, v_row."id", 'import', allocate_existing.amount, allocate_existing.ledger_entry, coalesce(allocate_existing.allocated_on, current_date))
  returning "id" into v_id;
  update "better_supabase"."invoices" x set
    "paid_total" = x."paid_total" + allocate_existing.amount,
    "paid_at" = coalesce(x."paid_at", allocate_existing.allocated_on::timestamptz),
    "status" = case
      when x."paid_total" + allocate_existing.amount >= x."total" then 'paid'
      else 'partially_paid'
    end
  where x."id" = v_row."id";
  return jsonb_build_object('id', v_id, 'invoiceId', v_row."id", 'reference', v_reference, 'created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_my_organizations (
  page_size          integer                  DEFAULT 50,
  after_last_used_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  after_name         text                     DEFAULT NULL::text,
  after_id           uuid                     DEFAULT NULL::uuid
)
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
  select o.id, o.name, o.slug, r.key, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join better_supabase.roles r on r.id = m.role
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
    and (
      after_id is null
      or (
        coalesce(m.last_used_at, '-infinity'::timestamptz),
        o.name,
        o.id
      ) < (
        coalesce(after_last_used_at, '-infinity'::timestamptz),
        after_name,
        after_id
      )
    )
  order by m.last_used_at desc nulls last, o.name, o.id
  limit least(greatest(coalesce(page_size, 50), 1), 200);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.asset_identifier_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase".asset_identifiers x where x."id"::text = asset_identifier_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.asset_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."assets" x where x."id"::text = asset_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bootstrap_permissions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with keys as (
    select coalesce(array_agg(distinct key order by key), '{}'::text[]) as keys
    from better_supabase.member_organization_ids(null) as tenant(id),
      lateral unnest(better_supabase.member_permissions(auth.uid(), tenant.id)) as key
    where auth.uid() is not null
  )
  select case
    when auth.uid() is null then jsonb_build_object(
      'apiVersion', 1, 'form', 'compact', 'keys', '[]'::jsonb, 'tenants', '{}'::jsonb
    )
    else jsonb_build_object(
      'apiVersion', 1,
      'form', 'compact',
      'keys', to_jsonb(keys.keys),
      'tenants', coalesce((
        select jsonb_object_agg(
          tenant.id::text,
          better_supabase.permission_bitset(
            keys.keys,
            better_supabase.member_permissions(auth.uid(), tenant.id)
          )
        )
        from better_supabase.member_organization_ids(null) as tenant(id)
      ), '{}'::jsonb)
    )
  end
  from keys
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_deal_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select parent from (
      select n."parent_id" as parent from new_rows n
      join old_rows o on o."id" = n."id"
      where n."quantity" is distinct from o."quantity"
        or n."unit_amount" is distinct from o."unit_amount"
      union
      select n."parent_id" from new_rows n
      where not exists (select 1 from old_rows o where o."id" = n."id")
      union
      select o."parent_id" from old_rows o
      where not exists (select 1 from new_rows n where n."id" = o."id")
    ) changed order by 1'
  end loop
    perform "better_supabase"."set_deal_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_invoice_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select parent from (
      select n."parent_id" as parent from new_rows n
      join old_rows o on o."id" = n."id"
      where n."quantity" is distinct from o."quantity"
        or n."unit_amount" is distinct from o."unit_amount"
      union
      select n."parent_id" from new_rows n
      where not exists (select 1 from old_rows o where o."id" = n."id")
      union
      select o."parent_id" from old_rows o
      where not exists (select 1 from new_rows n where n."id" = o."id")
    ) changed order by 1'
  end loop
    perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_quote_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select parent from (
      select n."parent_id" as parent from new_rows n
      join old_rows o on o."id" = n."id"
      where n."quantity" is distinct from o."quantity"
        or n."unit_amount" is distinct from o."unit_amount"
        or n."selected" is distinct from o."selected"
        or n."optional" is distinct from o."optional"
      union
      select n."parent_id" from new_rows n
      where not exists (select 1 from old_rows o where o."id" = n."id")
      union
      select o."parent_id" from old_rows o
      where not exists (select 1 from new_rows n where n."id" = o."id")
    ) changed order by 1'
  end loop
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_change_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
  v_version uuid;
  v_number integer;
  v_graph jsonb;
begin
  if tg_op = 'INSERT' then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    v_graph := "better_supabase"."lifecycle_graph"(v_version);
    if new."status" is null then
      new."status" := v_graph ->> 'initial';
    end if;
    if new."status" is null or not ((v_graph -> 'order') ? new."status"::text) then
      raise exception 'that status is not a stage of the machine''s workflow' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    v_op := nullif(current_setting('better_supabase.lifecycle_op', true), '')::jsonb;
    if v_op is not null and v_op ->> 'machine' = 'change_request' and v_op ->> 'id' = new."id"::text then
      case v_op ->> 'op'
        when 'pause' then
          if (v_op ->> 'until') is not null and (v_op ->> 'until')::timestamptz <= now() then
            raise exception 'a pause must end in the future' using errcode = '22023', hint = 'STATE_PAUSE_INVALID';
          end if;
          insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "paused_at", "pause_expires_at", "pause_reason", "paused_by")
          values (new."organization_id", 'change_request', new."id"::text, 1, now(), (v_op ->> 'until')::timestamptz, nullif(v_op ->> 'reason', ''), auth.uid())
          on conflict ("subject_type", "subject_id") do update set
            "paused_at" = excluded."paused_at",
            "pause_expires_at" = excluded."pause_expires_at",
            "pause_reason" = excluded."pause_reason",
            "paused_by" = excluded."paused_by",
            "updated_at" = now();
          perform set_config('better_supabase.lifecycle_changed', '1', true);
          perform "better_supabase".emit_event('status.paused', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'until', v_op ->> 'until', 'reason', nullif(v_op ->> 'reason', '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
        when 'resume' then
          update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by" = null, "updated_at" = now()
          where "subject_type" = 'change_request' and "subject_id" = new."id"::text and "paused_at" is not null;
          if found then
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        when 'flag' then
          v_flag := v_op ->> 'flag';
          if v_flag is null or not (v_flag = any ('{}'::text[])) then
            raise exception 'the machine has no such flag' using errcode = '22023', hint = 'STATE_FLAG_UNKNOWN';
          end if;
          select coalesce("flags", '{}') into v_flags from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text for update;
          v_flags := coalesce(v_flags, '{}');
          if coalesce((v_op ->> 'enabled')::boolean, false) is distinct from (v_flag = any (v_flags)) then
            v_flags := case when coalesce((v_op ->> 'enabled')::boolean, false)
              then v_flags || v_flag else array_remove(v_flags, v_flag) end;
            insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "flags")
            values (new."organization_id", 'change_request', new."id"::text, 1, v_flags)
            on conflict ("subject_type", "subject_id") do update set
              "flags" = excluded."flags",
              "updated_at" = now();
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.flagged', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'flag', v_flag, 'enabled', coalesce((v_op ->> 'enabled')::boolean, false)), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        else
          raise exception 'unknown lifecycle change' using errcode = '22023', hint = 'STATE_LIFECYCLE_INVALID';
      end case;
    end if;
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  select "workflow_version_id" into v_version from "better_supabase"."subject_lifecycles"
  where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if v_version is null then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
  end if;
  v_graph := "better_supabase"."lifecycle_graph"(v_version);
  if not coalesce((v_graph -> 'transitions' -> old."status"::text) ? new."status"::text, false) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  select "pause_expires_at", "paused_at" is not null into v_until, v_paused from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if coalesce(v_paused, false) then
    if v_until is null or v_until > now() then
      raise exception 'the record is paused; resume it first' using errcode = '55000', hint = 'STATE_PAUSED';
    end if;
    update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by" = null, "updated_at" = now()
    where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
    perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."organization_id", 'change_request', new."id"::text, old."status"::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_drive_node()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."document_status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, null::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."document_status" is not distinct from old."document_status" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if new."document_status" is null or not (old."document_status" is null and new."document_status"::text = 'draft') and not (case old."document_status"::text when 'draft' then new."document_status"::text = any ('{in_review}'::text[]) when 'in_review' then new."document_status"::text = any ('{draft,effective}'::text[]) when 'effective' then new."document_status"::text = any ('{obsolete}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old."document_status"::text when 'in_review' then new."document_status"::text = any ('{effective}'::text[]) else false end)
    and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    and not exists (
      select 1 from "better_supabase"."approval_requests" a
      where a."id"::text = nullif(current_setting('better_supabase.approval', true), '')
        and a."status" = 'approved'
        and a."subject_type" = 'drive_node'
        and a."subject_id" = new."id"::text
    ) then
    raise exception 'that status change needs an approved request' using errcode = '42501', hint = 'STATE_APPROVAL_REQUIRED';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, old."document_status"::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', new."id"::text, 'from', old."document_status"::text, 'to', new."document_status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/drive_node/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."state" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, null::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_deleted_platform_roles()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(select "user_id" from changed));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_deleted_role_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (select "role_id" from changed)
  ));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_inserted_platform_roles()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(select "user_id" from changed));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_inserted_role_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (select "role_id" from changed)
  ));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_override_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where (m."organization_id", m."role") in (
      select "tenant_id", "role_id" from changed
    )
  ));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_updated_role_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m."user_id"
    from "public"."memberships" m
    where m."role" in (
      select "role_id" from changed
      union
      select "role_id" from previous
    )
  ));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.contact_method_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."party_channels" x where x."id"::text = contact_method_updated_at.subject_id
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
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'tenant_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'tenant_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_bin.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', b.item_id, 'batchId', b.batch_id, 'count', b.n, 'trashedBy', b.trashed_by, 'trashedAt', b.trashed_at, 'purgeAfter', b.purge_at, 'node', b.node) order by b.trashed_at desc, b.item_id), '[]'::jsonb)
    from (
      select i."id" as item_id, i."batch_id" as batch_id, i."trashed_by" as trashed_by, i."trashed_at" as trashed_at, i."purge_at" as purge_at,
        (select count(*) from "better_supabase"."trash_items" c where c."batch_id" = i."batch_id")::integer as n,
        "better_supabase"."drive_node_json"(x) as node
      from "better_supabase"."trash_items" i
      join "better_supabase"."drive_nodes" x on x."id"::text = i."subject_id"
      where i."tenant_id" = drive_bin.tenant and i."subject_type" = 'drive_node' and i."depth" = 0
        and (
          drive_bin.before is null
          or (i."trashed_at", i."id") < (
            drive_bin.before,
            coalesce(drive_bin.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)
          )
        )
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor'))
      order by i."trashed_at" desc, i."id"
      limit least(greatest(coalesce(drive_bin.page_size, 50), 1), 200)
    ) b
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.due_check_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase".asset_due_checks x where x."id"::text = due_check_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_import_periods (
  tenant           uuid,
  entry_date       date,
  start_month      integer,
  close_historical boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_month integer := least(greatest(coalesce(ensure_import_periods.start_month, 1), 1), 12);
  v_year integer := extract(year from ensure_import_periods.entry_date)::integer;
  v_start date;
  v_index integer;
begin
  if extract(month from ensure_import_periods.entry_date) < v_month then
    v_year := v_year - 1;
  end if;
  v_start := make_date(v_year, v_month, 1);
  if not exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = ensure_import_periods.tenant and y."fiscal_year" = v_year) then
    for v_index in 0..11 loop
      insert into "better_supabase"."accounting_periods" ("tenant_id", "fiscal_year", "number", "starts_on", "ends_on")
      values (ensure_import_periods.tenant, v_year, v_index + 1, (v_start + make_interval(months => v_index))::date,
        ((v_start + make_interval(months => v_index + 1)) - 1)::date);
    end loop;
  end if;
  if ensure_import_periods.close_historical then
    update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now()
    where y."tenant_id" = ensure_import_periods.tenant and y."fiscal_year" < v_year and y."status" = 'open';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_seal (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select case when field_seal.value is null then null
    when left(field_seal.value, 5) = 'bsf1:' then field_seal.value
    else 'bsf1:' || translate(encode(extensions.pgp_sym_encrypt(field_seal.value, field_seal.key, 'cipher-algo=aes256, s2k-mode=1'), 'base64'), E'\n', '')
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fill_asset_due_check()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if new."last_done_at" is not null then
    new."next_due_at" := new."last_done_at" + make_interval(days => new."interval_days");
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  return v_counts;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_import_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_many (
  tenant uuid,
  ids    uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'transactionId', e."transaction_id",
    'accountId', e."account_id",
    'amount', e."amount"::text,
    'unit', e."unit",
    'effectiveAt', e."effective_at"
  ) order by e."effective_at", e."id"), '[]'::jsonb)
  from "better_supabase"."ledger_entries" e
  where e."tenant_id" = get_many.tenant and e."id" = any (get_many.ids)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_asset_meter_reading()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_previous numeric;
begin
  select r."value" into v_previous
  from "better_supabase".asset_meter_readings r
  where r."tenant_id" = new."tenant_id" and r."asset_id" = new."asset_id" and r."unit" = new."unit"
    and r."read_at" < new."read_at"
  order by r."read_at" desc
  limit 1;
  if v_previous is not null and new."value" < v_previous and new."reason" is null then
    raise exception 'a meter reading is below the previous one and has no reason' using errcode = '23514', hint = 'ASSET_METER_DECREASE_REASON';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.heartbeat_import_run (
  run     uuid,
  seconds integer DEFAULT 30
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hook_plan (
  event jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_user uuid := nullif(event ->> 'user_id', '')::uuid;
begin
  if coalesce(v_claims ->> 'client_id', '') <> '' then
    return 'slim';
  end if;

  -- A refresh whose permission claim was built for another tenant than
  -- app_metadata.tenant_id must read again. reuse would keep the old keys.
  if coalesce(v_claims -> 'app_metadata' ->> 'tenant_id', '') <> ''
    and jsonb_typeof(v_claims -> 'permissions') = 'object'
    and v_claims -> 'permissions' <> '{}'::jsonb
    and not (v_claims -> 'permissions' ? (v_claims -> 'app_metadata' ->> 'tenant_id'))
  then
    return 'full';
  end if;

  if event ->> 'authentication_method' = 'token_refresh'
    and jsonb_typeof(v_claims -> 'authz_ver') = 'number'
    and jsonb_typeof(v_claims -> 'memberships') = 'array'
    and coalesce(v_claims ->> 'permissions_truncated', 'false') <> 'true'
    and coalesce(v_claims ->> 'team_ids_truncated', 'false') <> 'true'
    and (v_claims ->> 'authz_ver')::bigint = better_supabase.authz_version(v_user)
  then
    return 'reuse';
  end if;

  return 'full';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_entry (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_entry.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_entry.item -> 'data';
  v_journal uuid;
  v_lines jsonb;
  v_debit numeric;
  v_credit numeric;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_entry.item -> 'data') is distinct from 'object' then
    raise exception 'an entry item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_journal := coalesce(nullif(v_data ->> 'journalId', '')::uuid,
      (select y."id" from "better_supabase"."accounting_journals" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'journalCode'));
    select jsonb_agg((e.value - 'accountCode') || jsonb_build_object('accountId', coalesce(nullif(e.value ->> 'accountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = e.value ->> 'accountCode'))) order by e.ordinality),
      coalesce(sum((coalesce(nullif(e.value ->> 'debit', ''), '0'))::numeric), 0),
      coalesce(sum((coalesce(nullif(e.value ->> 'credit', ''), '0'))::numeric), 0)
    into v_lines, v_debit, v_credit
    from jsonb_array_elements(v_data -> 'lines') with ordinality e;
  exception
    when invalid_text_representation then
      raise exception 'an entry''s ids are uuids and its amounts integers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_journal is null then
    raise exception 'the journal isn''t a journal of the organization; import journals first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) e where e.value ->> 'accountId' is null) then
    raise exception 'a line''s account isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_debit <> v_credit then
    raise exception 'the lines don''t balance: debits and credits differ' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform "better_supabase"."ensure_import_periods"(v_tenant, (v_data ->> 'entryDate')::date,
    coalesce((import_accounting_entry.item -> 'options' -> 'fiscalYear' ->> 'startMonth')::integer, 1),
    coalesce((import_accounting_entry.item -> 'options' ->> 'closeHistorical')::boolean, false));
  v_row := "better_supabase"."save_accounting_entry"(v_journal, (v_data ->> 'entryDate')::date, v_lines, nullif(v_data ->> 'memo', ''), nullif(v_data ->> 'reference', ''),
    null, null, import_accounting_entry.subject_id::uuid);
  if coalesce((v_data ->> 'post')::boolean, true) then
    v_row := "better_supabase"."post_accounting_entry"((v_row ->> 'id')::uuid);
  end if;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_allocation (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_allocation.item ->> 'tenant')::uuid;
  v_data jsonb := import_allocation.item -> 'data';
  v_invoice uuid := coalesce(nullif(v_data ->> 'invoiceId', ''), nullif(import_allocation.item -> 'resolved' ->> 'invoice', ''), import_allocation.subject_id)::uuid;
  v_result jsonb;
begin
  v_result := "better_supabase"."allocate_existing"(
    v_tenant,
    v_invoice,
    coalesce(nullif(v_data ->> 'reference', ''), import_allocation.item ->> 'key'),
    (v_data ->> 'amount')::bigint,
    v_data ->> 'party',
    nullif(v_data ->> 'allocatedOn', '')::date,
    nullif(v_data ->> 'ledgerEntryId', '')::uuid
  );
  return jsonb_build_object('subjectId', v_result ->> 'id', 'updatedAt', now(), 'warnings', '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
  v_pending jsonb[] := '{}';
  v_calls jsonb[] := '{}';
  v_pending_keys text[] := '{}';
  v_raw jsonb;
  v_results jsonb[];
  v_p jsonb;
  v_i integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := coalesce((
    select jsonb_object_agg(wanted.field || chr(31) || wanted.key, found."subject_id")
    from (
      select ref.field, ref.entity, item.value -> 'refs' ->> ref.field as key
      from jsonb_array_elements(v_items) item(value)
      cross join (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
      where ref.target = v_entity
    ) wanted
    join "better_supabase"."import_records" found
      on found."tenant_id" = v_run."tenant_id"
      and found."source" = v_run."source"
      and found."entity" = wanted.entity
      and found."external_key" = wanted.key
    where wanted.key is not null
  ), '{}'::jsonb);

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    if v_scope || chr(31) || v_key = any (v_pending_keys) then
      if cardinality(v_pending) > 0 then
          begin
            case v_entity
          when 'customer' then
            v_subject_type := 'customer';
            v_raw := "public"."import_customer_batch"(v_run_id, to_jsonb(v_calls));
            else
              v_raw := null;
            end case;
            if jsonb_typeof(v_raw) is distinct from 'array' or jsonb_array_length(v_raw) <> cardinality(v_pending) then
              raise exception 'a batch target returns one result per item' using errcode = '22023';
            end if;
            v_results := array(select e.value from jsonb_array_elements(v_raw) e);
          exception when others then
            v_results := null;
          end;
          for v_i in 1 .. cardinality(v_pending) loop
            v_p := v_pending[v_i];
            v_key := v_p ->> 'key';
            v_scope := v_p ->> 'scope';
            v_hash := v_p ->> 'hash';
            v_found := (v_p ->> 'found')::boolean;
            v_subject_id := v_p ->> 'subjectId';
            begin
              if v_results is null then
                v_call := v_calls[v_i];
                case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;
              else
                v_out := v_results[v_i];
                if jsonb_typeof(v_out) = 'object' and v_out ? 'error' then
                  raise exception '%', coalesce(v_out -> 'error' ->> 'message', 'the import target refused the item')
                    using hint = coalesce(v_out -> 'error' ->> 'code', 'IMPORT_ITEM_INVALID');
                end if;
              end if;
              v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
            exception when others then
              get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
            end;
          end loop;
          v_pending := '{}';
          v_calls := '{}';
          v_pending_keys := '{}';
        end if;
    end if;

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        case v_entity
        when 'party_bank_account' then
          v_natural := "better_supabase"."party_bank_account_id"(v_run."tenant_id", v_item);
          else null;
        end case;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        case v_entity
        when 'organization_profile' then
          v_current := "better_supabase"."organization_profile_updated_at"(v_rec."subject_id");
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'product' then
          v_current := "better_supabase"."product_updated_at"(v_rec."subject_id");
        when 'product_category' then
          v_current := "better_supabase"."product_category_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'party' then
          v_current := "better_supabase"."party_updated_at"(v_rec."subject_id");
        when 'party_contact' then
          v_current := "better_supabase"."party_contact_updated_at"(v_rec."subject_id");
        when 'contact_method' then
          v_current := "better_supabase"."contact_method_updated_at"(v_rec."subject_id");
        when 'party_location' then
          v_current := "better_supabase"."party_location_updated_at"(v_rec."subject_id");
        when 'party_bank_account' then
          v_current := "better_supabase"."party_bank_account_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'open_item' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'invoice_allocation' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'due_check' then
          v_current := "better_supabase"."due_check_updated_at"(v_rec."subject_id");
        when 'asset' then
          v_current := "better_supabase"."asset_updated_at"(v_rec."subject_id");
        when 'asset_identifier' then
          v_current := "better_supabase"."asset_identifier_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
        when 'customer_row' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        v_resolved := coalesce((
    select jsonb_object_agg(ref.field, v_ref_map ->> (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field))
  ), '{}'::jsonb);
  v_warnings := v_warnings || coalesce((
    select jsonb_agg(jsonb_build_object(
      'entity', v_entity,
      'key', v_item -> 'refs' ->> ref.field,
      'code', 'IMPORT_REF_MISSING',
      'message', 'missing ref ' || ref.field
    ))
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and not (v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
  ), '[]'::jsonb);
  v_call := v_call || jsonb_build_object('resolved', v_resolved);
        if v_entity = any (array['customer']::text[]) then
            v_pending := v_pending || jsonb_build_object('subjectId', v_subject_id, 'found', v_found, 'key', v_key, 'scope', v_scope, 'hash', v_hash);
            v_calls := v_calls || v_call;
            v_pending_keys := v_pending_keys || (v_scope || chr(31) || v_key);
          else
            case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

            v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
          end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  if cardinality(v_pending) > 0 then
          begin
            case v_entity
          when 'customer' then
            v_subject_type := 'customer';
            v_raw := "public"."import_customer_batch"(v_run_id, to_jsonb(v_calls));
            else
              v_raw := null;
            end case;
            if jsonb_typeof(v_raw) is distinct from 'array' or jsonb_array_length(v_raw) <> cardinality(v_pending) then
              raise exception 'a batch target returns one result per item' using errcode = '22023';
            end if;
            v_results := array(select e.value from jsonb_array_elements(v_raw) e);
          exception when others then
            v_results := null;
          end;
          for v_i in 1 .. cardinality(v_pending) loop
            v_p := v_pending[v_i];
            v_key := v_p ->> 'key';
            v_scope := v_p ->> 'scope';
            v_hash := v_p ->> 'hash';
            v_found := (v_p ->> 'found')::boolean;
            v_subject_id := v_p ->> 'subjectId';
            begin
              if v_results is null then
                v_call := v_calls[v_i];
                case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;
              else
                v_out := v_results[v_i];
                if jsonb_typeof(v_out) = 'object' and v_out ? 'error' then
                  raise exception '%', coalesce(v_out -> 'error' ->> 'message', 'the import target refused the item')
                    using hint = coalesce(v_out -> 'error' ->> 'code', 'IMPORT_ITEM_INVALID');
                end if;
              end if;
              v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
            exception when others then
              get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
            end;
          end loop;
          v_pending := '{}';
          v_calls := '{}';
          v_pending_keys := '{}';
        end if;

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_asset (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_asset.item -> 'data';
  v_tenant uuid := (import_asset.item ->> 'tenant')::uuid;
  v_id uuid := nullif(import_asset.subject_id, '')::uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or nullif(btrim(v_data ->> 'name'), '') is null then
    raise exception 'an asset needs a name' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."assets" ("tenant_id", "kind", "name", "make", "model", "ownership")
    values (v_tenant, coalesce(nullif(v_data ->> 'kind', ''), 'asset'), btrim(v_data ->> 'name'), nullif(btrim(v_data ->> 'make'), ''), nullif(btrim(v_data ->> 'model'), ''), nullif(v_data ->> 'ownership', ''))
    returning "id", "updated_at" into v_id, v_updated;
  else
    update "better_supabase"."assets" x set "name" = btrim(v_data ->> 'name'), "make" = coalesce(nullif(btrim(v_data ->> 'make'), ''), x."make"), "model" = coalesce(nullif(btrim(v_data ->> 'model'), ''), x."model"), "ownership" = coalesce(nullif(v_data ->> 'ownership', ''), x."ownership"), "updated_at" = now()
    where x."id" = v_id and x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_asset_identifier (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_asset_identifier.item -> 'data';
  v_asset uuid := nullif(coalesce(import_asset_identifier.item -> 'resolved' ->> 'asset', v_data ->> 'assetId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
begin
  if v_asset is null or nullif(btrim(v_data ->> 'type'), '') is null or nullif(btrim(v_data ->> 'value'), '') is null then
    raise exception 'an identifier needs an asset, a type and a value' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase".asset_identifiers ("tenant_id", "asset_id", "type", "value")
  values ((import_asset_identifier.item ->> 'tenant')::uuid, v_asset, btrim(v_data ->> 'type'), btrim(v_data ->> 'value'))
  on conflict ("tenant_id", "type", "value") do update set "asset_id" = excluded."asset_id", "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_clear_issues (
  run    uuid,
  entity text,
  key    text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_contact_method (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_contact_method.item -> 'data';
  v_party uuid := nullif(coalesce(import_contact_method.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_kind text := coalesce(nullif(v_data ->> 'partyKind', ''), 'person');
  v_channel text := nullif(v_data ->> 'channel', '');
  v_address text := nullif(btrim(v_data ->> 'address'), '');
  v_id uuid;
  v_updated timestamptz;
begin
  if v_channel in ('email') then
    v_address := nullif(lower(v_address), '');
  elsif v_channel in ('phone', 'mobile', 'fax', 'whatsapp') then
    v_address := nullif(better_supabase.normalize_phone(v_address, v_data ->> 'region'), '');
  end if;
  if v_party is null or v_kind not in ('person', 'company') or v_channel not in ('email', 'phone', 'mobile', 'fax', 'whatsapp') or v_address is null then
    raise exception 'a contact method needs a party, a channel and an address' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_channels" x
  where x."tenant_id" = (import_contact_method.item ->> 'tenant')::uuid
    and x."party_id" = v_party and x."channel" = v_channel and x."address" = v_address
    and x."label" is not distinct from nullif(btrim(v_data ->> 'label'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false);
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_channels" ("tenant_id", "party_id", "party_kind", "channel", "label", "address", "is_primary")
  values ((import_contact_method.item ->> 'tenant')::uuid, v_party, v_kind, v_channel, nullif(btrim(v_data ->> 'label'), ''), v_address, coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "party_id", "channel", "address") do update
    set "label" = excluded."label", "is_primary" = excluded."is_primary", "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_due_check (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_due_check.item ->> 'tenant')::uuid;
  v_data jsonb := import_due_check.item -> 'data';
  v_asset uuid;
  v_days integer;
  v_done timestamptz;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_asset := nullif(v_data ->> 'assetId', '')::uuid;
    v_days := (v_data ->> 'intervalDays')::integer;
    v_done := nullif(v_data ->> 'lastDoneAt', '')::timestamptz;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'assetId is a uuid, intervalDays is a whole number and lastDoneAt is a timestamp' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_asset is null or nullif(v_data ->> 'checkType', '') is null or v_days is null or v_days < 1 then
    raise exception 'a due check needs an assetId, a checkType and an intervalDays of 1 or more' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."assets" a where a."id" = v_asset and a."tenant_id" = v_tenant) then
    raise exception 'the asset is not in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase".asset_due_checks ("tenant_id", "asset_id", "check_type", "interval_days", "last_done_at", "result")
  values (v_tenant, v_asset, v_data ->> 'checkType', v_days, v_done, nullif(v_data ->> 'result', ''))
  on conflict ("tenant_id", "asset_id", "check_type") do update set
    "interval_days" = excluded."interval_days",
    "last_done_at" = coalesce(excluded."last_done_at", "better_supabase".asset_due_checks."last_done_at"),
    "result" = coalesce(excluded."result", "better_supabase".asset_due_checks."result")
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_ensure_ref (
  tenant   uuid,
  kind     text,
  key      text,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_entities()
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[] $function$;

CREATE OR REPLACE FUNCTION better_supabase.import_integrity (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
    union all
    select 'unbalanced_ledger', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select e."transaction_id"::text as sample from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where y."tenant_id" = import_integrity.tenant
      group by e."transaction_id"
      having sum(e."amount") <> 0
    ) q
    union all
    select 'negative_invoice', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "total" < 0 and "kind"::text is distinct from 'credit_note'
    union all
    select 'issued_without_number', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "status"::text in ('issued', 'partially_paid', 'paid') and nullif("identifier"::text, '') is null
    union all
    select 'archived_without_date', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."companies" where "tenant_id" = import_integrity.tenant and "lifecycle"::text = 'archived' and "archived_at" is null
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_invoice_document (
  item       jsonb,
  subject_id text,
  v_credit   boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_invoice_document.item ->> 'tenant')::uuid;
  v_data jsonb := import_invoice_document.item -> 'data';
  v_status text := case when v_credit then 'issued' else coalesce(v_data ->> 'status', 'issued') end;
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_issued_on date;
  v_due_on date;
  v_original uuid;
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."invoices";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_invoice_document.subject_id is not null then
    select * into v_row from "better_supabase"."invoices" x where x."id" = import_invoice_document.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the invoice no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if coalesce(v_data ->> 'update', 'keep') is distinct from 'apply' then
      return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source document changed after it was imported; an imported document is kept as imported, so void or credit it and import the correction as a new document')));
    end if;
    v_id := v_row."id";
    update "better_supabase"."invoices" x set
      "status" = case when v_row."status"::text in ('void', 'paid') and coalesce((v_data ->> 'repost')::boolean, false) = false then v_row."status" else coalesce(nullif(v_data ->> 'status', ''), v_row."status"::text) end,
      "title" = coalesce(nullif(v_data ->> 'title', ''), x."title"),
      "currency" = coalesce(nullif(v_data ->> 'currency', ''), x."currency"),
      "terms_days" = coalesce((v_data ->> 'termsDays')::integer, x."terms_days"),
      "issued_on" = coalesce(nullif(v_data ->> 'issuedOn', '')::date, x."issued_on"),
      "due_on" = coalesce(nullif(v_data ->> 'dueOn', '')::date, x."due_on"),
      "company_id" = coalesce(nullif(v_data ->> 'companyId', ''), x."company_id"),
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
    if coalesce((v_data ->> 'repost')::boolean, false) or v_row."status"::text not in ('void', 'paid') then
      if (select count(*) from "better_supabase"."invoice_lines" l where l."parent_id" = v_id) = jsonb_array_length(coalesce(v_data -> 'lines', '[]'::jsonb)) then
        update "better_supabase"."invoice_lines" l set
          "description" = coalesce(nullif(e.l ->> 'title', ''), nullif(e.l ->> 'description', ''), l."description"),
          "tax_rate_bps" = coalesce((e.l ->> 'taxRateBps')::integer, l."tax_rate_bps"),
          "tax_code" = coalesce(nullif(e.l ->> 'taxCode', ''), l."tax_code")
        from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n)
        where l."parent_id" = v_id and l."position" = e.n::integer;
      elsif jsonb_typeof(v_data -> 'lines') = 'array' then
        perform "better_supabase"."set_invoice_lines"(v_id, v_data -> 'lines');
      end if;
    end if;
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
  end if;
  if not v_credit and coalesce((v_data -> 'totals' ->> 'total')::bigint, 0) < 0 then
    if coalesce(nullif(v_data ->> 'originalId', ''), nullif(import_invoice_document.item -> 'resolved' ->> 'original', '')) is not null then
      v_credit := true;
    else
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_CREDIT_WITHOUT_ORIGINAL', 'message', 'a negative total has no original invoice, so it stays an invoice'));
    end if;
  end if;

  if v_status not in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible') then
    raise exception 'status is draft, issued, partially_paid, paid, void or uncollectible' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a document needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_status <> 'draft' and v_number is null then
    raise exception 'an issued document needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_issued_on := coalesce(nullif(v_data ->> 'issuedOn', '')::date, nullif(v_data ->> 'suppliedOn', '')::date);
    v_due_on := nullif(v_data ->> 'dueOn', '')::date;
  exception when others then
    raise exception 'issuedOn and dueOn are dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_status <> 'draft' and v_issued_on is null then
    raise exception 'an issued document needs its issue date' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  if coalesce(v_data ->> 'onTaken', 'fail') not in ('fail', 'next_free') then
    raise exception 'onTaken is fail or next_free' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ->> 'onTaken' = 'next_free' and v_number is not null and exists (select 1 from "better_supabase"."invoices" x where x."tenant_id" = v_tenant and x."identifier" = v_number) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_NUMBER_REASSIGNED', 'message', 'number ' || v_number || ' was taken; the next free number was issued'));
    v_number := null;
  end if;

  if v_credit then
    v_original := coalesce(
      nullif(v_data ->> 'originalId', '')::uuid,
      nullif(import_invoice_document.item -> 'resolved' ->> 'original', '')::uuid,
      (select x."id" from "better_supabase"."invoices" x where x."tenant_id" = v_tenant and x."identifier" = v_data ->> 'original' limit 1)
    );
    if v_original is null and coalesce(v_data ->> 'settlement', 'payments') = 'row' then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_CREDIT_WITHOUT_ORIGINAL', 'message', 'a credit note has no original invoice, so no posting was made'));
      v_credit := false;
    elsif v_original is null then
      raise exception 'a credit note names the invoice it credits (originalId or original)' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if v_credit then
    v_made := "better_supabase"."credit_invoice"(v_original, v_data -> 'lines', nullif(v_data ->> 'note', ''), v_number, v_issued_on);
    v_id := (v_made ->> 'id')::uuid;
  else
    v_made := "better_supabase"."create_invoice"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'title', coalesce(nullif(v_data ->> 'title', ''), replace('Invoice {number}', '{number}', coalesce(v_number, 'draft'))),
      'currency', v_data -> 'currency',
      'termsDays', v_data -> 'termsDays',
      'note', v_data -> 'note',
      'company', v_data -> 'company',
      'contact', v_data -> 'contact',
      'origin', v_data -> 'origin',
      'direction', v_data -> 'direction',
      'pricesIncludeTax', v_data -> 'pricesIncludeTax',
      'discountBps', v_data -> 'discountBps',
      'discountAmount', v_data -> 'discountAmount')), v_data -> 'lines');
    v_id := (v_made ->> 'id')::uuid;
  end if;
  update "better_supabase"."invoices" x set legal_entity_id = case when v_credit then x.legal_entity_id else nullif(v_data ->> 'legalEntityId', '')::uuid end,
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' else x."buyer" end,
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, x."created_at")
  where x."id" = v_id;
  update "better_supabase"."invoices" x set "supplied_on" = coalesce(nullif(v_data ->> 'suppliedOn', '')::date, v_issued_on)
  where x."id" = v_id;
  update "better_supabase"."invoice_lines" l set "product_type" = 'product'
  where l."parent_id" = v_id and l."product_id" is not null and l."product_type" is distinct from 'product';
  if v_status <> 'draft' and not v_credit then
    perform "better_supabase"."issue_invoice"(v_id, v_issued_on, v_due_on, null, v_number);
  end if;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(y."tax_code", '') || ':' || y."tax_rate_bps"::text as key, sum(y."net") as net, sum(y."tax") as tax
        from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id;
    insert into "better_supabase"."invoice_tax_lines" ("tenant_id", "invoice_id", "tax_rate_bps", "tax_code", "tax_code_id", "net", "tax", "gross", "discount", "show_tax")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), nullif(g.value ->> 'taxCodeId', '')::uuid,
      (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint),
      coalesce((g.value ->> 'discount')::bigint, 0), coalesce((g.value ->> 'showTax')::boolean, true)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."invoices" x set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
  end if;
  if coalesce(v_data ->> 'settlement', 'payments') = 'row' then
    update "better_supabase"."invoices" x set
      "paid_total" = coalesce((v_data -> 'settlement' ->> 'paidCents')::bigint, x."paid_total"),
      "paid_at" = coalesce((v_data -> 'settlement' ->> 'paidOn')::timestamptz, x."paid_at"),
      "status" = case v_data -> 'settlement' ->> 'state'
        when 'paid' then 'paid'
        when 'partially_paid' then 'partially_paid'
        when 'open' then 'issued'
        else x."status"
      end
    where x."id" = v_id;
  elsif jsonb_typeof(v_data -> 'payments') = 'array' and jsonb_array_length(v_data -> 'payments') > 0 then
    if v_credit or v_status = 'draft' then
      raise exception 'only an issued invoice takes payments' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    for v_pay in select p.value from jsonb_array_elements(v_data -> 'payments') p loop
      v_index := v_index + 1;
      perform "better_supabase"."record_invoice_payment"(
        v_id, (v_pay ->> 'amount')::bigint, upper(coalesce(v_pay ->> 'currency', v_row."currency")),
        (v_pay ->> 'paidAt')::timestamptz, coalesce(nullif(v_pay ->> 'method', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_invoice_document.item ->> 'key' || ':payment:' || v_index::text),
        nullif(v_pay ->> 'note', ''), null, null);
    end loop;
    update "better_supabase"."invoices" x set "paid_at" = (select max((p.value ->> 'paidAt')::timestamptz) from jsonb_array_elements(v_data -> 'payments') p)
    where x."id" = v_id and x."paid_at" is not null and jsonb_typeof(v_data -> 'payments') = 'array';
  end if;
  if nullif(v_data ->> 'paymentTermCode', '') is not null then
    update "better_supabase"."invoices" x set "payment_terms_id" = (
      select z."id" from "better_supabase"."payment_terms" z
      where z."tenant_id" = v_tenant and z."code" = v_data ->> 'paymentTermCode'
      limit 1
    )
    where x."id" = v_id;
  end if;
  update "better_supabase"."invoice_lines" l set "tax_code" = (
    select c."code" from "better_supabase"."tax_codes" c
    join "better_supabase"."tax_rates" r on r."tax_code_id" = c."id"
    where c."tenant_id" = v_tenant and r."rate_bps" = l."tax_rate_bps"
    group by c."code"
    having count(*) = 1
  )
  where l."parent_id" = v_id and l."tax_code" is null;
  if exists (
    select 1 from "better_supabase"."invoice_lines" l
    where l."parent_id" = v_id and l."tax_code" is null and l."tax_rate_bps" is not null
      and (
        select count(distinct c."id") from "better_supabase"."tax_codes" c
        join "better_supabase"."tax_rates" r on r."tax_code_id" = c."id"
        where c."tenant_id" = v_tenant and r."rate_bps" = l."tax_rate_bps"
      ) > 1
  ) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_CODE_AMBIGUOUS', 'message', 'a tax rate matches more than one tax code'));
  end if;
  if v_status = 'void' then
    perform "better_supabase"."void_invoice"(v_id, coalesce(nullif(v_data ->> 'voidReason', ''), 'imported as void'));
  elsif v_status = 'uncollectible' then
    perform "better_supabase"."write_off_invoice"(v_id, nullif(v_data ->> 'writeOffReason', ''));
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
  if v_status in ('partially_paid', 'paid') and v_row."status"::text <> v_status then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_STATUS_MISMATCH', 'message', 'the payments give the status ' || v_row."status"::text || ', not ' || v_status, 'status', v_row."status"::text));
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_meter_reading (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_meter_reading.item ->> 'tenant')::uuid;
  v_data jsonb := import_meter_reading.item -> 'data';
  v_asset uuid;
  v_value numeric;
  v_at timestamptz;
  v_previous numeric;
  v_reason text;
  v_id uuid;
  v_warning boolean := false;
begin
  begin
    v_asset := nullif(v_data ->> 'assetId', '')::uuid;
    v_value := (v_data ->> 'value')::numeric;
    v_at := coalesce((v_data ->> 'readAt')::timestamptz, (v_data ->> 'orderBy')::timestamptz, now());
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'assetId is a uuid and value is a number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_asset is null or v_value is null or nullif(v_data ->> 'unit', '') is null then
    raise exception 'a meter reading needs an assetId, a unit and a value' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."assets" a where a."id" = v_asset and a."tenant_id" = v_tenant) then
    raise exception 'the asset is not in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."value" into v_previous from "better_supabase".asset_meter_readings r
  where r."tenant_id" = v_tenant and r."asset_id" = v_asset and r."unit" = v_data ->> 'unit' and r."read_at" < v_at
  order by r."read_at" desc limit 1;
  v_reason := nullif(v_data ->> 'reason', '');
  if v_previous is not null and v_value < v_previous then
    v_reason := coalesce(v_reason, 'import');
    v_warning := true;
  end if;
  if import_meter_reading.subject_id is null then
    insert into "better_supabase".asset_meter_readings ("tenant_id", "asset_id", "unit", "value", "read_at", "reason")
    values (v_tenant, v_asset, v_data ->> 'unit', v_value, v_at, v_reason)
    returning "id" into v_id;
  else
    update "better_supabase".asset_meter_readings r set "value" = v_value, "read_at" = v_at, "reason" = v_reason
    where r."id" = import_meter_reading.subject_id::uuid and r."tenant_id" = v_tenant
    returning r."id" into v_id;
    if v_id is null then
      raise exception 'the meter reading no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object(
    'subjectId', v_id::text,
    'updatedAt', now(),
    'warnings', case when v_warning then jsonb_build_array(jsonb_build_object(
      'code', 'IMPORT_SERIES_DECREASE',
      'message', 'the reading is below the previous one and was stored with reason import'
    )) else '[]'::jsonb end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_note_issue (
  run     uuid,
  entity  text,
  key     text,
  kind    text,
  code    text,
  message text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_note_warnings (
  run      uuid,
  entity   text,
  warnings jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_warning jsonb;
begin
  if jsonb_typeof(import_note_warnings.warnings) is distinct from 'array' then
    return;
  end if;
  for v_warning in select value from jsonb_array_elements(import_note_warnings.warnings) loop
    perform "better_supabase"."import_note_issue"(
      import_note_warnings.run,
      import_note_warnings.entity,
      coalesce(v_warning ->> 'key', ''),
      'warning',
      coalesce(v_warning ->> 'code', 'IMPORT_WARNING'),
      coalesce(v_warning ->> 'message', '')
    );
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_order (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_order.item ->> 'tenant')::uuid;
  v_data jsonb := import_order.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_seq bigint;
  v_id uuid;
  v_inclusive boolean := coalesce((v_data ->> 'taxInclusive')::boolean, false);
  v_subtotal bigint;
  v_discount bigint;
  v_tax bigint;
  v_shipping bigint;
  v_total bigint;
  v_paid bigint := 0;
  v_paid_at timestamptz;
  v_given jsonb := v_data -> 'totals';
  v_warnings jsonb := '[]'::jsonb;
  v_updated timestamptz;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_order.subject_id is not null then
    select x."updated_at" into v_updated from "better_supabase"."orders" x where x."id" = import_order.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the order no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if coalesce(v_data ->> 'update', 'keep') is distinct from 'apply' then
      return jsonb_build_object('subjectId', import_order.subject_id, 'updatedAt', v_updated, 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source order changed after it was imported; an imported order is kept as imported')));
    end if;
    v_id := import_order.subject_id::uuid;
    update "better_supabase"."orders" x set
      "status" = case when x."status"::text in ('cancelled', 'paid') and coalesce((v_data ->> 'repost')::boolean, false) = false then x."status" else coalesce(nullif(v_data ->> 'status', ''), x."status"::text) end,
      "customer_id" = coalesce(nullif(v_data ->> 'customerId', '')::uuid, x."customer_id"),
      "currency" = coalesce(nullif(upper(v_data ->> 'currency'), ''), x."currency"),
      "placed_at" = coalesce(nullif(v_data ->> 'placedAt', '')::timestamptz, x."placed_at"),
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'taxTotal')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
    if coalesce((v_data ->> 'repost')::boolean, false) or (select x."status"::text from "better_supabase"."orders" x where x."id" = v_id) not in ('cancelled', 'paid') then
      if (select count(*) from "better_supabase"."order_lines" l where l."order_id" = v_id) = jsonb_array_length(coalesce(v_data -> 'lines', '[]'::jsonb)) then
        update "better_supabase"."order_lines" l set
          "title" = coalesce(nullif(e.l ->> 'title', ''), l."title"),
          "tax" = coalesce((e.l ->> 'tax')::bigint, l."tax")
        from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n)
        where l."order_id" = v_id and l."position" = e.n::integer;
      elsif jsonb_typeof(v_data -> 'lines') = 'array' then
        delete from "better_supabase"."order_lines" l where l."order_id" = v_id;
        insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title", "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping", "location_id", "tax_code_id", "unit_cost", "cost_source", "bin_id", "billing_party", "billing_party_id", "billing_account_id")
        select v_tenant, v_id, e.n::integer, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, coalesce(e.l ->> 'sku', ''), e.l ->> 'title', (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, coalesce((e.l ->> 'subtotal')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint), coalesce((e.l ->> 'discount')::bigint, 0), coalesce((e.l ->> 'tax')::bigint, 0), coalesce((e.l ->> 'total')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint - coalesce((e.l ->> 'discount')::bigint, 0)), coalesce((e.l ->> 'requiresShipping')::boolean, false), nullif(e.l ->> 'locationId', '')::uuid, nullif(e.l ->> 'taxCodeId', '')::uuid, (e.l ->> 'unitCost')::bigint, nullif(e.l ->> 'costSource', ''), nullif(e.l ->> 'binId', '')::uuid, coalesce(nullif(e.l ->> 'billingParty', ''), 'customer'), nullif(e.l ->> 'billingPartyId', ''), nullif(e.l ->> 'billingAccountId', '')::uuid
        from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n);
      end if;
    end if;
    select x."updated_at" into v_updated from "better_supabase"."orders" x where x."id" = v_id;
    return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated, 'warnings', v_warnings);
  end if;
  if v_number is null then
    raise exception 'an order needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'currency', '') !~ '^[A-Za-z]{3}$' then
    raise exception 'currency is an ISO 4217 code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'an order needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where coalesce(l.value ->> 'title', '') = '' or coalesce(l.value ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$' or coalesce(l.value ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
  ) then
    raise exception 'a line needs a title, a whole quantity above zero and a unitAmount' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where l.value ->> 'billingParty' is not null and l.value ->> 'billingParty' not in ('customer', 'internal', 'own_warranty', 'supplier_warranty', 'cost_account')
      or l.value ->> 'costSource' is not null and l.value ->> 'costSource' not in ('catalog', 'average', 'manual', 'imported')
  ) then
    raise exception 'a line''s billingParty or costSource is not a known value' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  select coalesce(sum((l.value ->> 'unitAmount')::bigint * (l.value ->> 'quantity')::bigint), 0),
    coalesce(sum(coalesce((l.value ->> 'discount')::bigint, 0)), 0),
    coalesce(sum(coalesce((l.value ->> 'tax')::bigint, 0)), 0)
  into v_subtotal, v_discount, v_tax
  from jsonb_array_elements(v_data -> 'lines') l;
  v_shipping := coalesce((v_given ->> 'shippingTotal')::bigint, 0);
  v_total := v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end;
  if jsonb_typeof(v_given) = 'object' then
    if coalesce((v_given ->> 'subtotal')::bigint, v_subtotal) <> v_subtotal
      or coalesce((v_given ->> 'discountTotal')::bigint, v_discount) <> v_discount
      or coalesce((v_given ->> 'taxTotal')::bigint, v_tax) <> v_tax
      or coalesce((v_given ->> 'total')::bigint, v_total) <> v_total then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'taxTotal', v_tax::text, 'total', v_total::text),
        'given', v_given));
    end if;
    v_subtotal := coalesce((v_given ->> 'subtotal')::bigint, v_subtotal);
    v_discount := coalesce((v_given ->> 'discountTotal')::bigint, v_discount);
    v_tax := coalesce((v_given ->> 'taxTotal')::bigint, v_tax);
    v_total := coalesce((v_given ->> 'total')::bigint, v_total);
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' then
    select coalesce(sum((p.value ->> 'amount')::bigint), 0), max((p.value ->> 'paidAt')::timestamptz)
    into v_paid, v_paid_at from jsonb_array_elements(v_data -> 'payments') p;
  end if;

  if nullif(btrim(v_data ->> 'number'), '') is not null then
    perform set_config('better_supabase.fixed_number', 'order' || chr(31) || btrim(v_data ->> 'number'), true);
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_tenant;
  v_number := v_seq::text;
  end if;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "customer_id", "email", "status", "currency", "subtotal", "discount_total", "shipping_total", "tax_total", "total", "paid_total", "tax_inclusive", "shipping_address", "billing_address", "tax", "invoice_number", "invoice_sequence", "invoiced_at", "placed_at", "paid_at", "fulfilled_at", "completed_at", "cancelled_at", "cancel_reason", "buyer", legal_entity_id)
  values (v_tenant, v_number, v_seq, nullif(v_data ->> 'customerId', '')::uuid, v_data ->> 'email', coalesce(v_data ->> 'status', 'confirmed'), upper(v_data ->> 'currency'), v_subtotal, v_discount, v_shipping, v_tax, v_total, v_paid, v_inclusive, v_data -> 'shippingAddress', v_data -> 'billingAddress', v_data -> 'taxLines', nullif(v_data ->> 'invoiceNumber', ''), substring(nullif(v_data ->> 'invoiceNumber', '') from '([0-9]+)$')::bigint, nullif(v_data ->> 'invoicedAt', '')::timestamptz, coalesce(nullif(v_data ->> 'placedAt', '')::timestamptz, now()), coalesce(nullif(v_data ->> 'paidAt', '')::timestamptz, v_paid_at), nullif(v_data ->> 'fulfilledAt', '')::timestamptz, nullif(v_data ->> 'completedAt', '')::timestamptz, nullif(v_data ->> 'cancelledAt', '')::timestamptz, nullif(v_data ->> 'cancelReason', ''), case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end, nullif(v_data ->> 'legalEntityId', '')::uuid)
  returning "id", "updated_at" into v_id, v_updated;

  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title", "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping", "location_id", "tax_code_id", "unit_cost", "cost_source", "bin_id", "billing_party", "billing_party_id", "billing_account_id")
  select v_tenant, v_id, e.n::integer, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, coalesce(e.l ->> 'sku', ''), e.l ->> 'title', (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, coalesce((e.l ->> 'subtotal')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint), coalesce((e.l ->> 'discount')::bigint, 0), coalesce((e.l ->> 'tax')::bigint, 0), coalesce((e.l ->> 'total')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint - coalesce((e.l ->> 'discount')::bigint, 0)), coalesce((e.l ->> 'requiresShipping')::boolean, false), nullif(e.l ->> 'locationId', '')::uuid, nullif(e.l ->> 'taxCodeId', '')::uuid, (e.l ->> 'unitCost')::bigint, nullif(e.l ->> 'costSource', ''), nullif(e.l ->> 'binId', '')::uuid, coalesce(nullif(e.l ->> 'billingParty', ''), 'customer'), nullif(e.l ->> 'billingPartyId', ''), nullif(e.l ->> 'billingAccountId', '')::uuid
  from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n);

  if jsonb_typeof(v_data -> 'payments') = 'array' then
    for v_pay in select e.value from jsonb_array_elements(v_data -> 'payments') e loop
      v_index := v_index + 1;
      insert into "better_supabase"."order_payments" ("tenant_id", "order_id", "provider", "reference", "status", "currency", "amount", "captured", "refunded", "created_at", "updated_at")
      values (v_tenant, v_id, coalesce(nullif(v_pay ->> 'provider', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_order.item ->> 'key' || ':payment:' || v_index::text),
        'succeeded', upper(v_data ->> 'currency'), (v_pay ->> 'amount')::bigint, (v_pay ->> 'amount')::bigint, 0,
        coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()), coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()));
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_organization_profile (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_organization_profile.item -> 'data';
  v_tenant uuid := (import_organization_profile.item ->> 'tenant')::uuid;
  v_vat text := nullif(upper(btrim(v_data ->> 'vatId')), '');
  v_warnings jsonb := '[]'::jsonb;
  v_account jsonb;
  v_iban text;
  v_primary boolean;
  v_id uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'an organization profile needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_vat ~ '^[A-Z]{2}$' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_VAT_PREFIX', 'message', 'a VAT number that is only a country prefix was skipped'));
    v_vat := null;
  end if;
  insert into "better_supabase"."organization_profiles" ("tenant_id") values (v_tenant) on conflict ("tenant_id") do nothing;
  if exists (
    select 1 from "better_supabase"."organization_profiles" x
    where x."tenant_id" = v_tenant
      and (v_vat is null or x."vat_id" is not distinct from v_vat)
      and (v_data ->> 'registrationId' is null or x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), ''))
      and (v_data ->> 'defaultRate' is null or x."default_rate" is not distinct from (v_data ->> 'defaultRate')::numeric)
      and (v_data ->> 'currency' is null or x."currency" is not distinct from nullif(btrim(v_data ->> 'currency'), ''))
  ) then
    v_updated := (select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id" = v_tenant);
  else
    update "better_supabase"."organization_profiles" x set
      "vat_id" = coalesce(v_vat, x."vat_id"),
      "registration_id" = coalesce(nullif(btrim(v_data ->> 'registrationId'), ''), x."registration_id"),
      "default_rate" = coalesce((v_data ->> 'defaultRate')::numeric, x."default_rate"),
      "currency" = coalesce(nullif(btrim(v_data ->> 'currency'), ''), x."currency"),
      "updated_at" = now()
    where x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if jsonb_typeof(v_data -> 'accounts') = 'array' then
    for v_account in select value from jsonb_array_elements(v_data -> 'accounts') loop
      v_iban := upper(regexp_replace(coalesce(v_account ->> 'iban', ''), '\s', '', 'g'));
      if not better_supabase.validate_iban(v_iban) then
        raise exception 'a payment account needs a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
      v_primary := case when v_account ? 'isPrimary' then (v_account ->> 'isPrimary')::boolean else null end;
      select x."id" into v_id from "better_supabase"."organization_payment_accounts" x
      where x."tenant_id" = v_tenant and x."iban" = v_iban
        and x."bic" is not distinct from coalesce(nullif(upper(btrim(v_account ->> 'bic')), ''), x."bic")
        and x."holder" is not distinct from coalesce(nullif(btrim(v_account ->> 'holder'), ''), x."holder")
        and x."label" is not distinct from coalesce(nullif(btrim(v_account ->> 'label'), ''), x."label")
        and (v_primary is null or x."is_primary" = v_primary);
      if v_id is null then
        if v_primary is true then
          update "better_supabase"."organization_payment_accounts" x set "is_primary" = false where x."tenant_id" = v_tenant and x."iban" <> v_iban;
        end if;
        insert into "better_supabase"."organization_payment_accounts" ("tenant_id", "iban", "bic", "holder", "label", "is_primary")
        values (v_tenant, v_iban, nullif(upper(btrim(v_account ->> 'bic')), ''), nullif(btrim(v_account ->> 'holder'), ''),
          nullif(btrim(v_account ->> 'label'), ''), coalesce(v_primary, false))
        on conflict ("tenant_id", "iban") do update set
          "bic" = coalesce(excluded."bic", "better_supabase"."organization_payment_accounts"."bic"),
          "holder" = coalesce(excluded."holder", "better_supabase"."organization_payment_accounts"."holder"),
          "label" = coalesce(excluded."label", "better_supabase"."organization_payment_accounts"."label"),
          "is_primary" = case when v_primary is true then true else "better_supabase"."organization_payment_accounts"."is_primary" end,
          "updated_at" = now();
      end if;
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_tenant, 'updatedAt', coalesce(v_updated, now()), 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_party.item -> 'data';
  v_tenant uuid := (import_party.item ->> 'tenant')::uuid;
  v_display text := nullif(btrim(v_data ->> 'displayName'), '');
  v_legal text := nullif(btrim(v_data ->> 'legalName'), '');
  v_person text := nullif(btrim(concat_ws(' ', v_data ->> 'givenName', v_data ->> 'infix', v_data ->> 'lastName')), '');
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_name text := coalesce(v_display, v_legal, v_person, v_number);
  v_kind text := coalesce(nullif(v_data ->> 'kind', ''), 'auto');
  v_warnings jsonb := '[]'::jsonb;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or v_name is null then
    raise exception 'a party needs a display name, a legal name, a person name or a number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_display is null then
    v_warnings := jsonb_build_array(jsonb_build_object('code', 'IMPORT_NAME_FALLBACK', 'message', 'the party name came from a fallback'));
  end if;
  if v_kind = 'auto' then
    v_kind := case when v_name ~* '\m(b\.?v\.?|n\.?v\.?|gmbh|ltd\.?|llc|inc\.?|bvba|vof|stichting|holding)\M' then 'company' else 'person' end;
  end if;
  if v_kind = 'company' then
    if import_party.subject_id is not null then
      select x."id", x."updated_at", x."name" is not distinct from v_name and x."legal_name" is not distinct from coalesce(v_legal, v_name) and x."vat_id" is not distinct from nullif(btrim(v_data ->> 'vatId'), '') and x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), '') and x."phone" is not distinct from better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region') and x."billing_email" is not distinct from nullif(lower(btrim(v_data ->> 'billingEmail')), '') and x."bill_to_id" is not distinct from nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid and x."lifecycle" is not distinct from coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]) and x."language" is not distinct from nullif(btrim(v_data ->> 'language'), '') and x."roles" is not distinct from case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end and x."customer_terms_id" is not distinct from (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')) and x."archived_at" is not distinct from nullif(v_data ->> 'archivedAt', '')::timestamptz into v_id, v_updated, v_same
      from "better_supabase"."companies" x
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update "better_supabase"."companies" x set "name" = v_name, "legal_name" = coalesce(v_legal, v_name), "vat_id" = nullif(btrim(v_data ->> 'vatId'), ''), "registration_id" = nullif(btrim(v_data ->> 'registrationId'), ''), "phone" = better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), "billing_email" = nullif(lower(btrim(v_data ->> 'billingEmail')), ''), "bill_to_id" = nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid, "lifecycle" = coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]), "language" = nullif(btrim(v_data ->> 'language'), ''), "roles" = case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, "customer_terms_id" = (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')), "archived_at" = nullif(v_data ->> 'archivedAt', '')::timestamptz, "updated_at" = now()
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    end if;
    if v_id is null then
      insert into "better_supabase"."companies" ("tenant_id", "name", "legal_name", "vat_id", "registration_id", "phone", "billing_email", "bill_to_id", "lifecycle", "language", "roles", "customer_terms_id", "archived_at")
      values (v_tenant, v_name, coalesce(v_legal, v_name), nullif(btrim(v_data ->> 'vatId'), ''), nullif(btrim(v_data ->> 'registrationId'), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), nullif(lower(btrim(v_data ->> 'billingEmail')), ''), nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid, coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')), nullif(v_data ->> 'archivedAt', '')::timestamptz)
      returning "id", "updated_at" into v_id, v_updated;
    end if;
  elsif v_kind = 'person' then
    if import_party.subject_id is not null then
      select x."id", x."updated_at", x."name" is not distinct from v_name and x."given_name" is not distinct from nullif(btrim(v_data ->> 'givenName'), '') and x."last_name" is not distinct from nullif(btrim(v_data ->> 'lastName'), '') and x."initials" is not distinct from nullif(btrim(v_data ->> 'initials'), '') and x."infix" is not distinct from nullif(btrim(v_data ->> 'infix'), '') and x."email" is not distinct from nullif(lower(btrim(v_data ->> 'email')), '') and x."phone" is not distinct from better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region') and x."lifecycle" is not distinct from coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]) and x."language" is not distinct from nullif(btrim(v_data ->> 'language'), '') and x."roles" is not distinct from case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end and x."archived_at" is not distinct from nullif(v_data ->> 'archivedAt', '')::timestamptz into v_id, v_updated, v_same
      from "better_supabase"."people" x
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update "better_supabase"."people" x set "name" = v_name, "given_name" = nullif(btrim(v_data ->> 'givenName'), ''), "last_name" = nullif(btrim(v_data ->> 'lastName'), ''), "initials" = nullif(btrim(v_data ->> 'initials'), ''), "infix" = nullif(btrim(v_data ->> 'infix'), ''), "email" = nullif(lower(btrim(v_data ->> 'email')), ''), "phone" = better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), "lifecycle" = coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), "language" = nullif(btrim(v_data ->> 'language'), ''), "roles" = case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, "archived_at" = nullif(v_data ->> 'archivedAt', '')::timestamptz, "updated_at" = now()
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    end if;
    if v_id is null then
      insert into "better_supabase"."people" ("tenant_id", "name", "given_name", "last_name", "initials", "infix", "email", "phone", "lifecycle", "language", "roles", "archived_at")
      values (v_tenant, v_name, nullif(btrim(v_data ->> 'givenName'), ''), nullif(btrim(v_data ->> 'lastName'), ''), nullif(btrim(v_data ->> 'initials'), ''), nullif(btrim(v_data ->> 'infix'), ''), nullif(lower(btrim(v_data ->> 'email')), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, nullif(v_data ->> 'archivedAt', '')::timestamptz)
      returning "id", "updated_at" into v_id, v_updated;
    end if;
  else
    raise exception 'kind is person, company or auto' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_bank_account (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_party_bank_account.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_bank_account.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_iban text := upper(regexp_replace(coalesce(v_data ->> 'iban', ''), '\s', '', 'g'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_party is null or not better_supabase.validate_iban(v_iban) then
    raise exception 'a bank account needs a party and a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_bank_accounts" x
  where x."tenant_id" = (import_party_bank_account.item ->> 'tenant')::uuid and x."iban" = v_iban
    and x."bic" is not distinct from nullif(upper(btrim(v_data ->> 'bic')), '')
    and x."holder" is not distinct from nullif(btrim(v_data ->> 'holder'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, x."is_primary");
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_bank_accounts" ("tenant_id", "party_id", "iban", "bic", "holder", "is_primary")
  values ((import_party_bank_account.item ->> 'tenant')::uuid, v_party, v_iban,
    nullif(upper(btrim(v_data ->> 'bic')), ''), nullif(btrim(v_data ->> 'holder'), ''), coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "iban") do update
    set "bic" = excluded."bic", "holder" = excluded."holder",
      "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, "better_supabase"."party_bank_accounts"."is_primary"),
      "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_contact (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_party_contact.item -> 'data';
  v_company uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'company', v_data ->> 'companyId'), '')::uuid;
  v_person uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'person', v_data ->> 'personId'), '')::uuid;
  v_primary boolean := coalesce((v_data ->> 'isPrimary')::boolean, false);
begin
  if v_company is null or v_person is null then
    raise exception 'a party contact needs a company and a person' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."company_people" x
    where x."company_id" = v_company and x."person_id" = v_person
      and x."is_primary" is not distinct from v_primary
      and x."role" is not distinct from nullif(btrim(v_data ->> 'role'), '')
  ) then
    return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt',
      (select x."created_at" from "better_supabase"."company_people" x where x."company_id" = v_company and x."person_id" = v_person));
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "is_primary", "role")
  values ((import_party_contact.item ->> 'tenant')::uuid, v_company, v_person, v_primary, nullif(btrim(v_data ->> 'role'), ''))
  on conflict ("company_id", "person_id") do update
    set "is_primary" = excluded."is_primary", "role" = nullif(btrim(v_data ->> 'role'), '');
  return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt', now());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_discount_group (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_party_discount_group.item ->> 'tenant')::uuid;
  v_data jsonb := import_party_discount_group.item -> 'data';
  v_party text := btrim(coalesce(nullif(v_data ->> 'party', ''), import_party_discount_group.subject_id));
  v_group uuid := nullif(v_data ->> 'groupId', '')::uuid;
  v_code text := nullif(btrim(v_data ->> 'groupCode'), '');
begin
  if v_party is null or length(v_party) not between 1 and 200 then
    raise exception 'a party discount group names the party' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_group is null and v_code is not null then
    select x."id" into v_group
    from "better_supabase"."discount_groups" x
    where x."tenant_id" = v_tenant and x."kind" = 'customer' and x."code" = v_code;
  end if;
  if v_group is null and v_code is not null then
    raise exception 'no customer discount group has this code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform "better_supabase"."set_party_discount_group"(v_tenant, v_party, v_group);
  return jsonb_build_object(
    'subjectId', v_party,
    'updatedAt', (select x."created_at" from "better_supabase"."discount_group_parties" x where x."tenant_id" = v_tenant and x."party_id" = v_party)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_location (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_party_location.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_location.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if v_party is null then
    raise exception 'a location needs a party' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_party_location.subject_id is not null then
    select x."id", x."updated_at", x."party_id" is not distinct from v_party and x."kind" is not distinct from coalesce(nullif(v_data ->> 'kind', ''), 'other') and x."line1" is not distinct from nullif(btrim(v_data ->> 'line1'), '') and x."line2" is not distinct from nullif(btrim(v_data ->> 'line2'), '') and x."postal_code" is not distinct from nullif(btrim(v_data ->> 'postalCode'), '') and x."city" is not distinct from nullif(btrim(v_data ->> 'city'), '') and x."country" is not distinct from nullif(btrim(v_data ->> 'country'), '') and x."latitude" is not distinct from nullif(v_data ->> 'latitude', '')::double precision and x."longitude" is not distinct from nullif(v_data ->> 'longitude', '')::double precision and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false) into v_id, v_updated, v_same
    from "better_supabase"."party_locations" x
    where x."id" = import_party_location.subject_id::uuid and x."tenant_id" = (import_party_location.item ->> 'tenant')::uuid;
    if v_id is not null and v_same then
      return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
    end if;
    update "better_supabase"."party_locations" x set "party_id" = v_party, "kind" = coalesce(nullif(v_data ->> 'kind', ''), 'other'), "line1" = nullif(btrim(v_data ->> 'line1'), ''), "line2" = nullif(btrim(v_data ->> 'line2'), ''), "postal_code" = nullif(btrim(v_data ->> 'postalCode'), ''), "city" = nullif(btrim(v_data ->> 'city'), ''), "country" = nullif(btrim(v_data ->> 'country'), ''), "latitude" = nullif(v_data ->> 'latitude', '')::double precision, "longitude" = nullif(v_data ->> 'longitude', '')::double precision, "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, false), "updated_at" = now()
    where x."id" = import_party_location.subject_id::uuid
    returning x."id", x."updated_at" into v_id, v_updated;
  end if;
  if v_id is null then
    insert into "better_supabase"."party_locations" ("tenant_id", "party_id", "kind", "line1", "line2", "postal_code", "city", "country", "latitude", "longitude", "is_primary")
    values ((import_party_location.item ->> 'tenant')::uuid, v_party, coalesce(nullif(v_data ->> 'kind', ''), 'other'), nullif(btrim(v_data ->> 'line1'), ''), nullif(btrim(v_data ->> 'line2'), ''), nullif(btrim(v_data ->> 'postalCode'), ''), nullif(btrim(v_data ->> 'city'), ''), nullif(btrim(v_data ->> 'country'), ''), nullif(v_data ->> 'latitude', '')::double precision, nullif(v_data ->> 'longitude', '')::double precision, coalesce((v_data ->> 'isPrimary')::boolean, false))
    returning "id", "updated_at" into v_id, v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_product (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_product.item -> 'data';
  v_tenant uuid := (import_product.item ->> 'tenant')::uuid;
  v_raw text := coalesce(v_data ->> 'name', v_data ->> 'title', '');
  v_name text;
  v_slug text;
  v_sku text := nullif(btrim(v_data ->> 'sku'), '');
  v_price bigint;
  v_id uuid := nullif(import_product.subject_id, '')::uuid;
  v_updated timestamptz;
  v_fallback boolean := coalesce((import_product.item -> 'options' ->> 'priceFallback')::boolean, false);
begin
  if length(regexp_replace(v_raw, '[[:cntrl:][:space:]]', '', 'g')) * 2 < length(regexp_replace(coalesce(v_raw, ''), '[[:space:]]', '', 'g')) then
    raise exception 'a product name is mostly control characters' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_name := btrim(regexp_replace(regexp_replace(v_raw, '[[:cntrl:]]', '', 'g'), U&'[\+00E000-\+00F8FF]', '', 'g'));
  if v_name is null or length(v_name) = 0 then
    raise exception 'a product needs a name' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_price := coalesce(
    nullif(v_data ->> 'price', '')::bigint,
    nullif(v_data ->> 'listPrice', '')::bigint,
    case when v_fallback then round(nullif(v_data ->> 'lastPurchasePrice', '')::numeric * coalesce(nullif(v_data ->> 'markup', '')::numeric, 1))::bigint end);
  v_slug := trim(both '-' from lower(regexp_replace(coalesce(nullif(v_data ->> 'slug', ''), v_name), '[^a-zA-Z0-9]+', '-', 'g')));
  if v_id is not null and exists (
    select 1 from "better_supabase"."products" x
    where x."id" = v_id and x."tenant_id" = v_tenant and x."title" is not distinct from v_name
      and x."slug" is not distinct from v_slug
      and x."price" is not distinct from coalesce(v_price, x."price")
  ) and (v_sku is null or exists (
    select 1 from "better_supabase"."product_variants" y where y."product_id" = v_id and y."sku" is not distinct from v_sku
  )) then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', (select x."updated_at" from "better_supabase"."products" x where x."id" = v_id));
  end if;
  if v_sku is not null and exists (
    select 1 from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_sku and y."product_id" is distinct from v_id
  ) then
    raise exception 'a sku is already used by another product' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."products" x where x."tenant_id" = v_tenant and x."slug" = v_slug and x."id" is distinct from v_id) then
    v_slug := left(v_slug, 40) || '-' || left(coalesce(import_product.item ->> 'key', 'item'), 8);
  end if;
  if v_id is null then
    insert into "better_supabase"."products" ("tenant_id", "title", "slug", "price", "manufacturer", "model", "tax_code")
    values (v_tenant, v_name, v_slug, v_price, nullif(btrim(v_data ->> 'manufacturer'), ''), nullif(btrim(v_data ->> 'model'), ''), nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), ''))
    returning "id", "updated_at" into v_id, v_updated;
  else
    update "better_supabase"."products" x set "title" = v_name, "slug" = v_slug, "updated_at" = now(), "price" = coalesce(v_price, x."price"), "manufacturer" = coalesce(nullif(btrim(v_data ->> 'manufacturer'), ''), x."manufacturer"), "model" = coalesce(nullif(btrim(v_data ->> 'model'), ''), x."model"), "tax_code" = coalesce(nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), ''), x."tax_code")
    where x."id" = v_id and x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" y where y."product_id" = v_id) then
    insert into "better_supabase"."product_variants" ("tenant_id", "product_id", "sku", "barcode", "price")
    values (v_tenant, v_id, coalesce(v_sku, v_slug), nullif(btrim(v_data ->> 'ean'), ''), v_price);
  elsif v_sku is not null then
    update "better_supabase"."product_variants" y set "sku" = v_sku, "barcode" = coalesce(nullif(btrim(v_data ->> 'ean'), ''), y."barcode"), "price" = coalesce(v_price, y."price")
    where y."id" = (select y2."id" from "better_supabase"."product_variants" y2 where y2."product_id" = v_id order by y2."created_at" limit 1);
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_product_category (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_product_category.item -> 'data';
  v_product uuid := nullif(coalesce(import_product_category.item -> 'resolved' ->> 'product', v_data ->> 'productId'), '')::uuid;
  v_category uuid := nullif(coalesce(import_product_category.item -> 'resolved' ->> 'category', v_data ->> 'categoryId'), '')::uuid;
begin
  if v_category is null and nullif(btrim(v_data ->> 'name'), '') is not null then
    select x."id" into v_category from "better_supabase"."catalog_categories" x
    where x."tenant_id" = (import_product_category.item ->> 'tenant')::uuid and x."name" = btrim(v_data ->> 'name');
  end if;
  if v_product is null or v_category is null then
    raise exception 'a product category needs a product and a category' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."product_categories" ("tenant_id", "product_id", "category_id")
  values ((import_product_category.item ->> 'tenant')::uuid, v_product, v_category)
  on conflict do nothing;
  return jsonb_build_object('subjectId', v_product::text || ':' || v_category::text, 'updatedAt', now());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_quote (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if coalesce(v_data ->> 'update', 'keep') is distinct from 'apply' then
      return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
    end if;
    v_id := v_row."id";
    update "better_supabase"."quotes" y set
      "status" = coalesce(v_data ->> 'status', 'draft'),
      "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
      "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
      "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
      "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
      "decided_by" = nullif(v_data ->> 'decidedBy', ''),
      "decision_note" = nullif(v_data ->> 'decisionNote', ''),
      "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
      legal_entity_id = nullif(v_data ->> 'legalEntityId', '')::uuid,
      "updated_at" = now(),
      "title" = coalesce(nullif(v_data ->> 'title', ''), y."title"),
      "currency" = coalesce(nullif(v_data ->> 'currency', ''), y."currency"),
      "valid_until" = coalesce(nullif(v_data ->> 'validUntil', '')::date, y."valid_until"),
      "company_id" = coalesce(nullif(v_data ->> 'companyId', ''), y."company_id")
    where y."id" = v_id;
    if (select count(*) from "better_supabase"."quote_lines" l where l."parent_id" = v_id) = jsonb_array_length(coalesce(v_data -> 'lines', '[]'::jsonb)) then
      update "better_supabase"."quote_lines" l set
        "description" = coalesce(nullif(e.l ->> 'title', ''), nullif(e.l ->> 'description', ''), l."description"),
        "tax_rate_bps" = coalesce((e.l ->> 'taxRateBps')::integer, l."tax_rate_bps"),
        "tax_code" = coalesce(nullif(e.l ->> 'taxCode', ''), l."tax_code")
      from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n)
      where l."parent_id" = v_id and l."position" = e.n::integer;
    elsif jsonb_typeof(v_data -> 'lines') = 'array' then
      perform "better_supabase"."set_quote_lines"(v_id, v_data -> 'lines');
    end if;
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'onTaken', 'fail') not in ('fail', 'next_free') then
    raise exception 'onTaken is fail or next_free' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ->> 'onTaken' = 'next_free' and exists (select 1 from "better_supabase"."quotes" y where y."tenant_id" = v_tenant and y."identifier" = v_number) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_NUMBER_REASSIGNED', 'message', 'number ' || v_number || ' was taken; the next free number was issued'));
    v_number := null;
  end if;
  if v_number is not null then
    perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  end if;
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), replace('Quote {number}', '{number}', coalesce(v_number, ''))),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    legal_entity_id = nullif(v_data ->> 'legalEntityId', '')::uuid,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_upsert_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);
  perform set_config('better_supabase.search_deferred', 'on', true);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
    perform "better_supabase"."search_refresh_dirty"();
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inventory_levels (
  tenant      uuid,
  variant_ids uuid[] DEFAULT NULL::uuid[],
  location_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'variantId', y."variant_id",
    'locationId', y."location_id",
    'onHand', y."on_hand"::text,
    'allocated', y."reserved"::text,
    'available', y."available"::text,
    'incoming', y."incoming"::text,
    'reorderPoint', y."reorder_point"::text,
    'status', case
      when y."available" <= 0 then 'out'
      when y."reorder_point" is not null and y."available" <= y."reorder_point" then 'low'
      else 'in_stock'
    end
  )), '[]'::jsonb)
  from "better_supabase"."stock_levels" y
  where y."tenant_id" = inventory_levels.tenant
    and (inventory_levels.variant_ids is null or y."variant_id" = any (inventory_levels.variant_ids))
    and (inventory_levels.location_id is null or y."location_id" = inventory_levels.location_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inventory_status_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'inStock', count(*) filter (where y."available" > 0 and (y."reorder_point" is null or y."available" > y."reorder_point")),
    'low', count(*) filter (where y."reorder_point" is not null and y."available" <= y."reorder_point" and y."available" > 0),
    'out', count(*) filter (where y."available" <= 0)
  )
  from "better_supabase"."stock_levels" y
  where y."tenant_id" = inventory_status_counts.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_post (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb,
  reverses        uuid                     DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit", "effective_at")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit", v_row."effective_at"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  perform "better_supabase".emit_event('ledger_transaction.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_diff (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_counts jsonb;
  v_diff jsonb;
  v_rows jsonb;
begin
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(d.value), '[]'::jsonb) into v_rows from (
    select value from jsonb_array_elements(coalesce(v_diff, '[]'::jsonb)) value
    where list_import_diff.entity is null or value ->> 'entity' = list_import_diff.entity
    offset greatest(coalesce(list_import_diff.row_offset, 0), 0)
    limit least(greatest(coalesce(list_import_diff.row_limit, 50), 1), 200)
  ) d;
  return jsonb_build_object(
    'counts', case when list_import_diff.entity is null then v_counts else coalesce(v_counts -> list_import_diff.entity, '{}'::jsonb) end,
    'rows', v_rows
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_issues (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
    where i."run_id" = list_import_issues.run
      and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
    order by i."created_at", i."id"
    limit least(greatest(coalesce(list_import_issues.row_limit, 50), 1), 200)
    offset greatest(coalesce(list_import_issues.row_offset, 0), 0)
  ) t;
  return jsonb_build_object(
    'rows', v_rows,
    'total', least(v_total, 10000),
    'capped', v_total > 10000
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_runs (
  tenant    uuid,
  source    text    DEFAULT NULL::text,
  status    text    DEFAULT NULL::text,
  row_limit integer DEFAULT 50
)
  RETURNS SETOF jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_source_runs (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_sources()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s."id", 'labelKey', s."label_key", 'descriptionKey', s."description_key",
    'fileTypes', s."file_types", 'entities', s."entities", 'docsLink', s."docs_link"
  ) order by s."id"), '[]'::jsonb)
  from "better_supabase".import_sources s
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inventory_movements (
  tenant        uuid,
  variant       uuid    DEFAULT NULL::uuid,
  location      uuid    DEFAULT NULL::uuid,
  bin           uuid    DEFAULT NULL::uuid,
  lot           uuid    DEFAULT NULL::uuid,
  document_type text    DEFAULT NULL::text,
  document_id   text    DEFAULT NULL::text,
  row_limit     integer DEFAULT 50,
  row_offset    integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'kind', x."kind",
    'variantId', x."metadata" ->> 'variantId',
    'locationId', x."metadata" ->> 'locationId',
    'binId', x."metadata" ->> 'binId',
    'lotId', x."metadata" ->> 'lotId',
    'quantity', x."metadata" ->> 'quantity',
    'documentType', x."reference_type",
    'documentId', x."reference_id",
    'effectiveAt', x."effective_at"
  )), '[]'::jsonb)
  from (
    select *
    from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = list_inventory_movements.tenant
      and y."kind" like 'stock.%'
      and (list_inventory_movements.variant is null or y."metadata" ->> 'variantId' = list_inventory_movements.variant::text)
      and (list_inventory_movements.location is null or y."metadata" ->> 'locationId' = list_inventory_movements.location::text)
      and (list_inventory_movements.bin is null or y."metadata" ->> 'binId' = list_inventory_movements.bin::text)
      and (list_inventory_movements.lot is null or y."metadata" ->> 'lotId' = list_inventory_movements.lot::text)
      and (list_inventory_movements.document_type is null or y."reference_type" = list_inventory_movements.document_type)
      and (list_inventory_movements.document_id is null or y."reference_id" = list_inventory_movements.document_id)
    order by y."effective_at" desc, y."id"
    limit least(greatest(coalesce(list_inventory_movements.row_limit, 50), 0), 200)
    offset greatest(coalesce(list_inventory_movements.row_offset, 0), 0)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_request_materials (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."maintenance_request_id", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."maintenance_requests" x
  join "better_supabase"."maintenance_request_material_lines" y on y."maintenance_request_id" = x."id"
  where x."id" = list_maintenance_request_materials.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_request_specification (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."maintenance_request_id", 'description', y."description", 'quantity', y."quantity", 'unit', y."unit", 'estimate', y."estimate", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."maintenance_requests" x
  join "better_supabase"."maintenance_request_specification_lines" y on y."maintenance_request_id" = x."id"
  where x."id" = list_maintenance_request_specification.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_work_item_materials (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."work_item_id", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."work_item_material_lines" y on y."work_item_id" = x."id"
  where x."id" = list_work_item_materials.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_work_item_specification (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."work_item_id", 'description', y."description", 'quantity', y."quantity", 'unit', y."unit", 'estimate', y."estimate", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."work_item_specification_lines" y on y."work_item_id" = x."id"
  where x."id" = list_work_item_specification.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_stock (
  tenant         uuid,
  variant        uuid,
  location       uuid,
  quantity       numeric,
  reason         text,
  reference_type text    DEFAULT NULL::text,
  reference_id   text    DEFAULT NULL::text,
  note           text    DEFAULT NULL::text,
  detail         jsonb   DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in', 'consumption', 'production') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason in ('receipt', 'production') then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason in ('receipt', 'production')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out', 'consumption')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out', 'consumption')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' when 'consumption' then 'stock:production' when 'production' then 'stock:production' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' when 'consumption' then 'Production' when 'production' then 'Production' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' when 'consumption' then 'stock_value:production' when 'production' then 'stock_value:production' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' when 'consumption' then 'Work in progress' when 'production' then 'Work in progress' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_bin, 'lotId', v_lot, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_value <> 0 then
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('stock_movement', v_id::text);
  end if;
  end if;
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out', 'consumption')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', move_stock.tenant, 'subjectType', 'product_variant', 'subjectId', move_stock.variant::text, 'variantId', move_stock.variant, 'locationId', move_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || move_stock.variant::text || '/' || move_stock.location::text, (move_stock.tenant)::text, null, 'better-supabase/inventory');
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_for_party (
  tenant   uuid,
  party_id text DEFAULT NULL::text,
  as_of    date DEFAULT NULL::date,
  side     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_as_of date := coalesce(open_items_for_party.as_of, current_date);
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', open_items_for_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if open_items_for_party.side is not null and open_items_for_party.side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_OPEN_ITEMS_INVALID';
  end if;
  
  if v_as_of = current_date then
    return coalesce((
      select jsonb_agg(s.item order by s.ord_side, s.ord_party, s.ord_due nulls last, s.ord_document)
      from (
        select jsonb_build_object(
            'side', e."side", 'partyId', e."party_id", 'documentType', e."document_type", 'documentId', e."document_id",
            'currency', e."currency", 'issuedOn', e."issued_on", 'dueOn', e."due_on",
            'amount', e."gross"::text, 'balance', e."balance"::text,
            'daysOverdue', case when e."due_on" is null then 0 else v_as_of - e."due_on" end,
            'bucket', case when e."due_on" is null or v_as_of - e."due_on" <= 0 then 'current'
              when v_as_of - e."due_on" <= 30 then 'days1To30' when v_as_of - e."due_on" <= 60 then 'days31To60'
              when v_as_of - e."due_on" <= 90 then 'days61To90' else 'over90' end) as item,
          e."side" as ord_side, e."party_id" as ord_party, e."due_on" as ord_due, e."document_id" as ord_document
        from "better_supabase"."invoice_open_items" e
        where e."tenant_id" = open_items_for_party.tenant
          and e."balance" <> 0
          and (open_items_for_party.party_id is null or e."party_id" = open_items_for_party.party_id)
          and (open_items_for_party.side is null or e."side" = open_items_for_party.side)
        union all
        
        select jsonb_build_object(
            'side', 'customer', 'partyId', a."holder_id", 'documentType', 'unallocated_payment', 'documentId', a."id",
            'currency', a."unit"::text, 'issuedOn', null, 'dueOn', null,
            'amount', (-c.amount)::text, 'balance', (-c.amount)::text,
            'daysOverdue', 0, 'bucket', 'unallocated') as item,
          'customer'::text as ord_side, a."holder_id" as ord_party, null::date as ord_due, a."id" as ord_document
        from "better_supabase"."ledger_accounts" a
        cross join lateral (
          select coalesce(-sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
          join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
          where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= v_as_of
        ) c
        where a."tenant_id" = open_items_for_party.tenant and a."managed_by" = 'invoices'
          and a."holder_type" = 'invoice_party'
          and (open_items_for_party.party_id is null or a."holder_id" = open_items_for_party.party_id)
          and (open_items_for_party.side is null or open_items_for_party.side = 'customer')
          and c.amount > 0
      ) s
    ), '[]'::jsonb);
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'side', e.side, 'partyId', e.party, 'documentType', e.document_type, 'documentId', e.id,
        'identifier', e.identifier, 'currency', e.currency, 'issuedOn', e.issued_on, 'dueOn', e.due_on,
        'amount', e.gross::text, 'balance', e.balance::text, 'daysOverdue', e.days,
        'bucket', case when e.document_type = 'unallocated_payment' then 'unallocated'
          when e.days <= 0 then 'current' when e.days <= 30 then 'days1To30' when e.days <= 60 then 'days31To60'
          when e.days <= 90 then 'days61To90' else 'over90' end,
        'discountDueOn', e.discount_due_on, 'discountAmount', e.discount_amount::text,
        'legalEntityId', e.entity, 'approvalStatus', e.approval)
      order by e.side, e.party, e.due_on nulls last, e.id)
    from (
      select d.*, case when d.due_on is null then 0 else v_as_of - d.due_on end as days
      from (
        select 'invoice'::text as document_type, x."id" as id, case when x."direction" = 'purchase' then 'supplier' else 'customer' end as side, coalesce(x."company_id"::text, x."contact_id"::text) as party,
          x."identifier"::text as identifier, x."currency"::text as currency, x."issued_on" as issued_on, x."due_on" as due_on,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint as gross,
          case when open_items_for_party.as_of is null or open_items_for_party.as_of = current_date
            then (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
            else (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - (select coalesce(-sum(e."amount"), 0)::bigint from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text
        and (y."effective_at" at time zone 'UTC')::date <= v_as_of))::bigint
          end as balance,
          x."discount_due_on" as discount_due_on,
          coalesce(x."discount_amount_early", 0)::bigint as discount_amount,
          x.legal_entity_id as entity,
          case when x."direction" = 'purchase' then "better_supabase"."invoice_approval_state"(x."id") ->> 'status' end as approval
        from "better_supabase"."invoices" x
        where x."tenant_id" = open_items_for_party.tenant
          and x."kind" = 'invoice'
          and x."status" in ('issued', 'partially_paid', 'paid')
          and x."issued_on" <= v_as_of
          and (open_items_for_party.party_id is null or (x."company_id"::text = open_items_for_party.party_id or x."contact_id"::text = open_items_for_party.party_id))
        union all
        select 'unallocated_payment'::text, a."id", 'customer'::text, a."holder_id", null::text, a."unit"::text,
          null::date, null::date, (-c.amount)::bigint, (-c.amount)::bigint, null::date, 0::bigint, null::uuid, null::text
        from "better_supabase"."ledger_accounts" a
        cross join lateral (
          select coalesce(-sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
          join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
          where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= v_as_of
        ) c
        where a."tenant_id" = open_items_for_party.tenant and a."managed_by" = 'invoices'
          and a."holder_type" = 'invoice_party'
          and (open_items_for_party.party_id is null or a."holder_id" = open_items_for_party.party_id)
          and c.amount > 0
      ) d
      where d.balance <> 0
    ) e
    where open_items_for_party.side is null or e.side = open_items_for_party.side
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_page (
  tenant    uuid,
  side      text    DEFAULT NULL::text,
  party_id  text    DEFAULT NULL::text,
  "limit"   integer DEFAULT 50,
  "offset"  integer DEFAULT 0,
  count_cap integer DEFAULT 10000
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_total integer;
  v_rows jsonb;
begin
  if (select auth.role()) is distinct from 'service_role' and not coalesce(better_supabase.can('tenant', open_items_page.tenant, 'invoices.read'), false) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase"."invoice_open_items" e
  where e."tenant_id" = open_items_page.tenant
    and e."balance" <> 0
    and (open_items_page.party_id is null or e."party_id" = open_items_page.party_id)
    and (open_items_page.side is null or e."side" = open_items_page.side);
  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb) into v_rows from (
    select e."side" as side, e."party_id" as "partyId", e."document_type" as "documentType",
      e."document_id" as "documentId", e."currency" as currency, e."due_on" as "dueOn",
      e."issued_on" as "issuedOn", e."gross"::text as amount, e."balance"::text as balance
    from "better_supabase"."invoice_open_items" e
    where e."tenant_id" = open_items_page.tenant
      and e."balance" <> 0
      and (open_items_page.party_id is null or e."party_id" = open_items_page.party_id)
      and (open_items_page.side is null or e."side" = open_items_page.side)
    order by e."due_on" nulls last, e."document_id"
    limit least(greatest(coalesce(open_items_page."limit", 50), 1), 200)
    offset greatest(coalesce(open_items_page."offset", 0), 0)
  ) p;
  return jsonb_build_object('rows', v_rows, 'total', least(v_total, coalesce(open_items_page.count_cap, 10000)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_profile_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id"::text = organization_profile_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.party_bank_account_id (
  tenant uuid,
  item   jsonb
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."id"::text from "better_supabase"."party_bank_accounts" x
  where x."tenant_id" = party_bank_account_id.tenant
    and x."iban" = upper(regexp_replace(coalesce(party_bank_account_id.item -> 'data' ->> 'iban', ''), '\s', '', 'g'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.party_bank_account_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."party_bank_accounts" x where x."id"::text = party_bank_account_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.party_contact_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."created_at" from "better_supabase"."company_people" x
  where x."company_id"::text = split_part(party_contact_updated_at.subject_id, ':', 1)
    and x."person_id"::text = split_part(party_contact_updated_at.subject_id, ':', 2)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.party_location_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."party_locations" x where x."id"::text = party_location_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.party_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select x."updated_at" from "better_supabase"."companies" x where x."id"::text = party_updated_at.subject_id),
    (select x."updated_at" from "better_supabase"."people" x where x."id"::text = party_updated_at.subject_id))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_bitset (
  all_keys text[],
  held     text[]
)
  RETURNS text
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.product_category_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select now()
$function$;

CREATE OR REPLACE FUNCTION better_supabase.product_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."products" x where x."id"::text = product_updated_at.subject_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebase_import_records (
  tenant   uuid,
  source   text,
  entities text[] DEFAULT NULL::text[],
  keys     text[] DEFAULT NULL::text[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((case x."entity" when 'organization_profile' then "better_supabase"."organization_profile_updated_at"(x."subject_id") when 'supplier_item' then "better_supabase"."supplier_item_updated_at"(x."subject_id") when 'product_identifier' then "better_supabase"."product_identifier_updated_at"(x."subject_id") when 'discount_group' then "better_supabase"."discount_group_updated_at"(x."subject_id") when 'discount_rule' then "better_supabase"."discount_rule_updated_at"(x."subject_id") when 'product' then "better_supabase"."product_updated_at"(x."subject_id") when 'product_category' then "better_supabase"."product_category_updated_at"(x."subject_id") when 'stock_count' then "better_supabase"."stock_count_updated_at"(x."subject_id") when 'order' then "better_supabase"."order_updated_at"(x."subject_id") when 'payment_term' then "better_supabase"."payment_term_updated_at"(x."subject_id") when 'document_delivery_preference' then "better_supabase"."document_delivery_preference_updated_at"(x."subject_id") when 'party' then "better_supabase"."party_updated_at"(x."subject_id") when 'party_contact' then "better_supabase"."party_contact_updated_at"(x."subject_id") when 'contact_method' then "better_supabase"."contact_method_updated_at"(x."subject_id") when 'party_location' then "better_supabase"."party_location_updated_at"(x."subject_id") when 'party_bank_account' then "better_supabase"."party_bank_account_updated_at"(x."subject_id") when 'quote' then "better_supabase"."quote_updated_at"(x."subject_id") when 'invoice' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'credit_note' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'open_item' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'invoice_allocation' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'due_check' then "better_supabase"."due_check_updated_at"(x."subject_id") when 'asset' then "better_supabase"."asset_updated_at"(x."subject_id") when 'asset_identifier' then "better_supabase"."asset_identifier_updated_at"(x."subject_id") when 'tax_code' then "better_supabase"."tax_code_updated_at"(x."subject_id") when 'document_template' then "better_supabase"."document_template_updated_at"(x."subject_id") when 'document_text_block' then "better_supabase"."document_text_block_updated_at"(x."subject_id") when 'customer' then "public"."import_customer_updated_at"(x."subject_id") when 'customer_row' then "public"."import_customer_updated_at"(x."subject_id") else null end), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebuild_open_items (
  tenant uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.role()) is distinct from 'service_role' and not coalesce(better_supabase.can('tenant', rebuild_open_items.tenant, 'invoices.read'), false) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  delete from "better_supabase"."invoice_open_items" x where x."tenant_id" = rebuild_open_items.tenant and x."document_type" = 'invoice';
  insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
  select x."tenant_id", coalesce(x."company_id"::text, x."contact_id"::text), case when x."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', x."id", x."currency"::text,
    x."due_on", x."issued_on", (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint, (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
  from "better_supabase"."invoices" x
  where x."tenant_id" = rebuild_open_items.tenant
    and x."kind" = 'invoice'
    and x."status"::text in ('issued', 'partially_paid', 'paid')
    and x."issued_on" <= current_date
    and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <> 0
    and coalesce(x."company_id"::text, x."contact_id"::text) is not null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_open_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_balance bigint;
begin
  v_balance := (new."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = new."id"), 0) - new."credited_total" - new."paid_total");
  delete from "better_supabase"."invoice_open_items" x
  where x."document_id" = new."id" and x."document_type" = 'invoice';
  if new."status"::text in ('issued', 'partially_paid', 'paid') and v_balance <> 0 and new."issued_on" <= current_date and coalesce(new."company_id"::text, new."contact_id"::text) is not null then
    insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
    values (new."tenant_id", coalesce(new."company_id"::text, new."contact_id"::text), case when new."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', new."id", new."currency"::text,
      new."due_on", new."issued_on", (new."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = new."id"), 0) - new."credited_total")::bigint, v_balance);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_import_source (
  id              text,
  label_key       text,
  description_key text,
  file_types      text[],
  entities        text[],
  docs_link       text   DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
  values (register_import_source.id, register_import_source.label_key, register_import_source.description_key,
    coalesce(register_import_source.file_types, '{}'), coalesce(register_import_source.entities, '{}'), register_import_source.docs_link)
  on conflict ("id") do update set
    "label_key" = excluded."label_key",
    "description_key" = excluded."description_key",
    "file_types" = excluded."file_types",
    "entities" = excluded."entities",
    "docs_link" = excluded."docs_link";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_import_conflict (
  tenant uuid,
  source text,
  entity text,
  key    text,
  action text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = resolve_import_conflict.tenant
    and i."source" = resolve_import_conflict.source
    and i."entity" = resolve_import_conflict.entity
    and i."key" = resolve_import_conflict.key
    and i."kind" = 'conflict'
    and i."resolved_at" is null;
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('action', resolve_import_conflict.action, 'resolved', v_resolved);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_maintenance_request_material_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_requests";
  v_id uuid := save_maintenance_request_material_line.line_id;
  v_last text;
  v_line "better_supabase"."maintenance_request_material_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_maintenance_request_material_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x
  where x."id" = save_maintenance_request_material_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."maintenance_request_material_lines" y where y."maintenance_request_id" = v_row."id";
    insert into "better_supabase"."maintenance_request_material_lines" ("tenant_id", "maintenance_request_id", "variant_id", "quantity", "unit", "rank")
    values (v_row."tenant_id", v_row."id", nullif(save_maintenance_request_material_line.attrs ->> 'variantId', '')::uuid, nullif(save_maintenance_request_material_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_maintenance_request_material_line.attrs ->> 'unit'), ''), coalesce(nullif(save_maintenance_request_material_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."maintenance_request_material_lines" y set "variant_id" = coalesce(nullif(save_maintenance_request_material_line.attrs ->> 'variantId', '')::uuid, "variant_id"), "quantity" = coalesce(nullif(save_maintenance_request_material_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_maintenance_request_material_line.attrs ? 'unit' then nullif(btrim(save_maintenance_request_material_line.attrs ->> 'unit'), '') else "unit" end, "rank" = coalesce(nullif(save_maintenance_request_material_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."maintenance_request_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."maintenance_request_id", 'rank', v_line."rank");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_maintenance_request_specification_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_requests";
  v_id uuid := save_maintenance_request_specification_line.line_id;
  v_last text;
  v_line "better_supabase"."maintenance_request_specification_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_maintenance_request_specification_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x
  where x."id" = save_maintenance_request_specification_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."maintenance_request_specification_lines" y where y."maintenance_request_id" = v_row."id";
    insert into "better_supabase"."maintenance_request_specification_lines" ("tenant_id", "maintenance_request_id", "description", "quantity", "unit", "estimate", "rank")
    values (v_row."tenant_id", v_row."id", nullif(btrim(save_maintenance_request_specification_line.attrs ->> 'description'), ''), nullif(save_maintenance_request_specification_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_maintenance_request_specification_line.attrs ->> 'unit'), ''), nullif(save_maintenance_request_specification_line.attrs ->> 'estimate', '')::numeric, coalesce(nullif(save_maintenance_request_specification_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."maintenance_request_specification_lines" y set "description" = coalesce(nullif(btrim(save_maintenance_request_specification_line.attrs ->> 'description'), ''), "description"), "quantity" = coalesce(nullif(save_maintenance_request_specification_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_maintenance_request_specification_line.attrs ? 'unit' then nullif(btrim(save_maintenance_request_specification_line.attrs ->> 'unit'), '') else "unit" end, "estimate" = case when save_maintenance_request_specification_line.attrs ? 'estimate' then nullif(save_maintenance_request_specification_line.attrs ->> 'estimate', '')::numeric else "estimate" end, "rank" = coalesce(nullif(save_maintenance_request_specification_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."maintenance_request_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."maintenance_request_id", 'rank', v_line."rank");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_item_material_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_material_line.line_id;
  v_last text;
  v_line "better_supabase"."work_item_material_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_work_item_material_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x
  where x."id" = save_work_item_material_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."work_item_material_lines" y where y."work_item_id" = v_row."id";
    insert into "better_supabase"."work_item_material_lines" ("tenant_id", "work_item_id", "variant_id", "quantity", "unit", "rank")
    values (v_row."tenant_id", v_row."id", nullif(save_work_item_material_line.attrs ->> 'variantId', '')::uuid, nullif(save_work_item_material_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_work_item_material_line.attrs ->> 'unit'), ''), coalesce(nullif(save_work_item_material_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."work_item_material_lines" y set "variant_id" = coalesce(nullif(save_work_item_material_line.attrs ->> 'variantId', '')::uuid, "variant_id"), "quantity" = coalesce(nullif(save_work_item_material_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_work_item_material_line.attrs ? 'unit' then nullif(btrim(save_work_item_material_line.attrs ->> 'unit'), '') else "unit" end, "rank" = coalesce(nullif(save_work_item_material_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."work_item_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."work_item_id", 'rank', v_line."rank");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_item_specification_line (
  task    uuid,
  line_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_specification_line.line_id;
  v_last text;
  v_line "better_supabase"."work_item_specification_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_work_item_specification_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x
  where x."id" = save_work_item_specification_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."work_item_specification_lines" y where y."work_item_id" = v_row."id";
    insert into "better_supabase"."work_item_specification_lines" ("tenant_id", "work_item_id", "description", "quantity", "unit", "estimate", "rank")
    values (v_row."tenant_id", v_row."id", nullif(btrim(save_work_item_specification_line.attrs ->> 'description'), ''), nullif(save_work_item_specification_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_work_item_specification_line.attrs ->> 'unit'), ''), nullif(save_work_item_specification_line.attrs ->> 'estimate', '')::numeric, coalesce(nullif(save_work_item_specification_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."work_item_specification_lines" y set "description" = coalesce(nullif(btrim(save_work_item_specification_line.attrs ->> 'description'), ''), "description"), "quantity" = coalesce(nullif(save_work_item_specification_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_work_item_specification_line.attrs ? 'unit' then nullif(btrim(save_work_item_specification_line.attrs ->> 'unit'), '') else "unit" end, "estimate" = case when save_work_item_specification_line.attrs ? 'estimate' then nullif(save_work_item_specification_line.attrs ->> 'estimate', '')::numeric else "estimate" end, "rank" = coalesce(nullif(save_work_item_specification_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."work_item_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."work_item_id", 'rank', v_line."rank");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_document_templates_defaults (
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
  if p_locale = any (array['en']) then
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "key", "language", "body")
    select p_tenant, 'letterhead', 'en', '{{entity.name}} · Company no. {{entity.cocNumber}} · VAT {{entity.vatNumber}} · IBAN {{entity.iban}}'
    where not exists (select 1 from "better_supabase"."document_text_blocks" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'letterhead' and x."language" is not distinct from 'en');
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "key", "language", "body")
    select p_tenant, 'letterhead', 'nl', '{{entity.name}} · KvK {{entity.cocNumber}} · BTW {{entity.vatNumber}} · IBAN {{entity.iban}}'
    where not exists (select 1 from "better_supabase"."document_text_blocks" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'letterhead' and x."language" is not distinct from 'nl');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "key", "language", "body")
    select p_tenant, 'letterhead', 'de', '{{entity.name}} · Handelsregister {{entity.cocNumber}} · USt-IdNr. {{entity.vatNumber}} · IBAN {{entity.iban}}'
    where not exists (select 1 from "better_supabase"."document_text_blocks" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'letterhead' and x."language" is not distinct from 'de');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "key", "language", "body")
    select p_tenant, 'letterhead', 'fr', '{{entity.name}} · RCS {{entity.cocNumber}} · TVA {{entity.vatNumber}} · IBAN {{entity.iban}}'
    where not exists (select 1 from "better_supabase"."document_text_blocks" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'letterhead' and x."language" is not distinct from 'fr');
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_tax_defaults (
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
  if p_locale = any (array['en']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'STD', 'Standard VAT', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'STD');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'RED', 'Reduced VAT', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'RED');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'ZERO', 'Zero rate', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'ZERO');
  end if;
  if p_locale = any (array['en']) then
  
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL21', 'BTW hoog 21%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL21');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL9', 'BTW laag 9%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL9');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL0', 'BTW 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL0');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NLVRIJ', 'Vrijgesteld van BTW', 'exempt'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NLVRIJ');
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL21' limit 1), 2100
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL21' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL9' limit 1), 900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL9' limit 1));
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE19', 'Umsatzsteuer 19%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE19');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE7', 'Umsatzsteuer 7%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE7');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE0', 'Umsatzsteuer 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE0');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE19' limit 1), 1900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE19' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE7' limit 1), 700
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE7' limit 1));
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR20', 'TVA 20%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR20');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR10', 'TVA 10%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR10');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR55', 'TVA 5,5%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR55');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR0', 'TVA 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR0');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR20' limit 1), 2000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR20' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR10' limit 1), 1000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR10' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR55' limit 1), 550
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR55' limit 1));
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_import_run (
  tenant  uuid,
  source  text,
  options jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_organizations (
  page_size          integer                  DEFAULT 50,
  after_last_used_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  after_name         text                     DEFAULT NULL::text,
  after_id           uuid                     DEFAULT NULL::uuid
)
  RETURNS TABLE (
    id           uuid,
    name         text,
    slug         text,
    role         text,
    plan         text,
    last_used_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select *
  from better_supabase.app_my_organizations(
    page_size,
    after_last_used_at,
    after_name,
    after_id
  )
$function$;

REVOKE ALL ON FUNCTION "public"."my_organizations"(integer, timestamp WITH time zone, text, uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION rbac.bump_override_authz_versions()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m.user_id
    from public.memberships m
    where (m.organization_id, m.role) in (
      select tenant_id, role_id from changed
    )
  ));

  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION rbac.bump_platform_role_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select user_id from changed
  ));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION rbac.bump_role_permission_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.bump_authz_versions(array(
    select m.user_id
    from public.memberships m
    where m.role in (select role_id from changed)
  ));
  return null;
end;
$function$;

ALTER TABLE "better_supabase"."asset_due_checks"
  ADD CONSTRAINT "asset_due_checks_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES better_supabase.assets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."asset_identifiers"
  ADD CONSTRAINT "asset_identifiers_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES better_supabase.assets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."asset_meter_readings"
  ADD CONSTRAINT "asset_meter_readings_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES better_supabase.assets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "bsb_assets_ownership_check"
    CHECK (((ownership IS NULL) OR (ownership = ANY (ARRAY['customer'::text, 'stock'::text, 'trade_in'::text, 'loan'::text, 'rental'::text]))));

ALTER TABLE "better_supabase"."invoice_allocations"
  ADD CONSTRAINT "bsb_invoice_allocations_source_check" CHECK ((source = ANY (ARRAY['payment'::text, 'credit'::text, 'import'::text])));

ALTER TABLE "better_supabase"."invoice_open_items"
  ADD CONSTRAINT "invoice_open_items_document_id_fkey" FOREIGN KEY (document_id) REFERENCES better_supabase.invoices(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."maintenance_request_material_lines"
  ADD CONSTRAINT "maintenance_request_material_lines_maintenance_request_id_fkey" FOREIGN KEY (maintenance_request_id) REFERENCES better_supabase.maintenance_requests(id)
    ON DELETE CASCADE;

ALTER TABLE "better_supabase"."maintenance_request_material_lines"
  ADD CONSTRAINT "maintenance_request_material_lines_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."maintenance_request_specification_lines"
  ADD CONSTRAINT "maintenance_request_specification_l_maintenance_request_id_fkey" FOREIGN KEY (maintenance_request_id) REFERENCES better_supabase.maintenance_requests(id)
    ON DELETE CASCADE;

ALTER TABLE "better_supabase"."maintenance_requests"
  ADD CONSTRAINT "bsb_maintenance_requests_estimated_minutes_check" CHECK ((estimated_minutes >= 0));

ALTER TABLE "better_supabase"."purchase_order_lines"
  ADD CONSTRAINT "bsb_purchase_order_lines_check1" CHECK (((quantity_canceled >= (0)::numeric) AND (quantity_canceled <= quantity_ordered)));

ALTER TABLE "better_supabase"."purchase_order_lines"
  ADD CONSTRAINT "bsb_purchase_order_lines_check" CHECK (((quantity_received >= (0)::numeric) AND (quantity_received <= (quantity_ordered - quantity_canceled))));

ALTER TABLE "better_supabase"."purchase_orders"
  ADD CONSTRAINT "bsb_purchase_orders_exchange_rate_check" CHECK (((exchange_rate IS NULL) OR (exchange_rate > (0)::numeric)));

ALTER TABLE "better_supabase"."work_item_material_lines"
  ADD CONSTRAINT "work_item_material_lines_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."work_item_material_lines"
  ADD CONSTRAINT "work_item_material_lines_work_item_id_fkey" FOREIGN KEY (work_item_id) REFERENCES better_supabase.work_items(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."work_item_specification_lines"
  ADD CONSTRAINT "work_item_specification_lines_work_item_id_fkey" FOREIGN KEY (work_item_id) REFERENCES better_supabase.work_items(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."work_items"
  ADD CONSTRAINT "bsb_work_items_estimated_minutes_check" CHECK ((estimated_minutes >= 0));

CREATE INDEX asset_due_checks_due_idx ON better_supabase.asset_due_checks USING btree (tenant_id, next_due_at)
  WHERE (next_due_at IS NOT NULL);

CREATE UNIQUE INDEX asset_due_checks_key ON better_supabase.asset_due_checks USING btree (tenant_id, asset_id, check_type);

CREATE UNIQUE INDEX asset_identifiers_key ON better_supabase.asset_identifiers USING btree (tenant_id, TYPE, VALUE);

CREATE INDEX asset_meter_readings_series_idx ON better_supabase.asset_meter_readings USING btree (tenant_id, asset_id, unit, read_at);

CREATE INDEX bsb_maintenance_request_material_lines_item_idx ON better_supabase.maintenance_request_material_lines USING btree (maintenance_request_id, rank);

CREATE INDEX bsb_maintenance_request_specification_lines_item_idx ON better_supabase.maintenance_request_specification_lines USING btree (maintenance_request_id, rank);

CREATE INDEX bsb_work_item_material_lines_item_idx ON better_supabase.work_item_material_lines USING btree (work_item_id, rank);

CREATE INDEX bsb_work_item_specification_lines_item_idx ON better_supabase.work_item_specification_lines USING btree (work_item_id, rank);

CREATE INDEX cases_created_idx ON better_supabase.cases USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX import_run_issues_open_idx ON better_supabase.import_run_issues USING btree (tenant_id, source, entity, key)
  WHERE (resolved_at IS NULL);

CREATE INDEX import_run_issues_run_idx ON better_supabase.import_run_issues USING btree (run_id, entity);

CREATE INDEX invoice_open_items_due_idx ON better_supabase.invoice_open_items USING btree (tenant_id, due_on);

CREATE INDEX invoice_open_items_party_idx ON better_supabase.invoice_open_items USING btree (tenant_id, party_id, side);

CREATE INDEX ledger_entries_tenant_idx ON better_supabase.ledger_entries USING btree (tenant_id, effective_at DESC);

CREATE INDEX notification_recipients_inbox_idx ON better_supabase.notification_recipients USING btree (user_id, created_at DESC, id DESC)
  WHERE (dismissed_at IS NULL);

CREATE UNIQUE INDEX organization_payment_accounts_primary_idx ON better_supabase.organization_payment_accounts USING btree (tenant_id)
  WHERE is_primary;

CREATE UNIQUE INDEX party_bank_accounts_primary_idx ON better_supabase.party_bank_accounts USING btree (tenant_id, party_id)
  WHERE is_primary;

CREATE UNIQUE INDEX party_locations_primary_idx ON better_supabase.party_locations USING btree (tenant_id, party_id)
  WHERE is_primary;

CREATE UNIQUE INDEX purchase_orders_number_idx ON better_supabase.purchase_orders USING btree (tenant_id, number)
  WHERE (number IS NOT NULL);

CREATE TRIGGER bsb_asset_due_checks_fill
  BEFORE INSERT OR UPDATE OF last_done_at, interval_days ON better_supabase.asset_due_checks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.fill_asset_due_check();

CREATE TRIGGER bsb_asset_meter_readings_series
  BEFORE INSERT ON better_supabase.asset_meter_readings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_asset_meter_reading();

CREATE TRIGGER invoice_open_items_refresh
  AFTER INSERT OR UPDATE OF status, paid_total, total, credited_total, due_on, issued_on ON better_supabase.invoices
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.refresh_open_item();

CREATE TRIGGER bsb_bump_override_members_delete
  AFTER DELETE ON better_supabase.permission_overrides REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_override_members();

CREATE TRIGGER bsb_bump_override_members_insert
  AFTER INSERT ON better_supabase.permission_overrides REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_override_members();

CREATE TRIGGER bsb_bump_override_members_update
  AFTER UPDATE ON better_supabase.permission_overrides REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_override_members();

CREATE TRIGGER bsb_permission_overrides_bump_delete
  AFTER DELETE ON better_supabase.permission_overrides REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_override_authz_versions();

CREATE TRIGGER bsb_permission_overrides_bump_insert
  AFTER INSERT ON better_supabase.permission_overrides REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_override_authz_versions();

CREATE TRIGGER bsb_permission_overrides_bump_update
  AFTER UPDATE ON better_supabase.permission_overrides REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_override_authz_versions();

CREATE TRIGGER bsb_bump_deleted_platform_roles
  AFTER DELETE ON better_supabase.platform_roles REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_deleted_platform_roles();

CREATE TRIGGER bsb_bump_inserted_platform_roles
  AFTER INSERT ON better_supabase.platform_roles REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_inserted_platform_roles();

CREATE TRIGGER bsb_platform_roles_bump_delete
  AFTER DELETE ON better_supabase.platform_roles REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_platform_role_members();

CREATE TRIGGER bsb_platform_roles_bump_insert
  AFTER INSERT ON better_supabase.platform_roles REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_platform_role_members();

CREATE TRIGGER bsb_bump_deleted_role_members
  AFTER DELETE ON better_supabase.role_permissions REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_deleted_role_members();

CREATE TRIGGER bsb_bump_inserted_role_members
  AFTER INSERT ON better_supabase.role_permissions REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_inserted_role_members();

CREATE TRIGGER bsb_bump_updated_role_members
  AFTER UPDATE ON better_supabase.role_permissions REFERENCING OLD TABLE AS previous NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bump_updated_role_members();

CREATE TRIGGER bsb_role_permissions_bump_delete
  AFTER DELETE ON better_supabase.role_permissions REFERENCING OLD TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_role_permission_members();

CREATE TRIGGER bsb_role_permissions_bump_insert
  AFTER INSERT ON better_supabase.role_permissions REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT
  EXECUTE FUNCTION rbac.bump_role_permission_members();

CREATE POLICY "bsb_asset_due_checks_read" ON "better_supabase"."asset_due_checks"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_invoice_open_items_read" ON "better_supabase"."invoice_open_items"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."invoice_open_items"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."invoice_open_items"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."invoice_open_items"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."invoice_open_items"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_maintenance_request_material_lines_read" ON "better_supabase"."maintenance_request_material_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('facilities.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."maintenance_request_material_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."maintenance_request_material_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."maintenance_request_material_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('facilities.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."maintenance_request_material_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_maintenance_request_specification_lines_read" ON "better_supabase"."maintenance_request_specification_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('facilities.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."maintenance_request_specification_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."maintenance_request_specification_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."maintenance_request_specification_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('facilities.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."maintenance_request_specification_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_organization_payment_accounts_read" ON "better_supabase"."organization_payment_accounts"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_organization_profiles_read" ON "better_supabase"."organization_profiles"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_party_bank_accounts_read" ON "better_supabase"."party_bank_accounts"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."party_bank_accounts"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."party_bank_accounts"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."party_bank_accounts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."party_bank_accounts"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_party_channels_read" ON "better_supabase"."party_channels"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."party_channels"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."party_channels"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."party_channels"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."party_channels"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_party_locations_read" ON "better_supabase"."party_locations"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."party_locations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."party_locations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."party_locations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."party_locations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."work_item_material_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."work_item_material_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."work_item_material_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS
    tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."work_item_material_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_work_item_material_lines_read" ON "better_supabase"."work_item_material_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."work_item_specification_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."work_item_specification_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."work_item_specification_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS
    tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."work_item_specification_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_work_item_specification_lines_read" ON "better_supabase"."work_item_specification_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."allocate_existing"(uuid, uuid, text, bigint, text, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."allocate_existing"(uuid, uuid, text, bigint, text, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."asset_identifier_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."asset_identifier_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."asset_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."asset_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."bootstrap_permissions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bootstrap_permissions"() TO "authenticated";

REVOKE ALL ON FUNCTION "api"."contact_method_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."contact_method_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."drive_bin"(uuid, integer, timestamp WITH time zone, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_bin"(uuid, integer, timestamp WITH time zone, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."due_check_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."due_check_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ensure_import_periods"(uuid, date, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ensure_import_periods"(uuid, date, integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."heartbeat_import_run"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."heartbeat_import_run"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_allocation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_allocation"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_asset"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_asset"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_asset_identifier"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_asset_identifier"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_contact_method"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_contact_method"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_due_check"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_due_check"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_ensure_ref"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_ensure_ref"(uuid, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_entities"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_entities"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_integrity"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_integrity"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_meter_reading"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_meter_reading"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_organization_profile"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_organization_profile"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_party"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_party_bank_account"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party_bank_account"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_party_contact"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party_contact"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_party_discount_group"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party_discount_group"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_party_location"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party_location"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_product"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_product"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_product_category"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_product_category"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."inventory_levels"(uuid, uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inventory_levels"(uuid, uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."inventory_status_counts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inventory_status_counts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_diff"(uuid, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_diff"(uuid, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_issues"(uuid, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_issues"(uuid, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_source_runs"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_source_runs"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_sources"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_sources"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_inventory_movements"(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_inventory_movements"(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_maintenance_request_materials"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_maintenance_request_materials"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_maintenance_request_specification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_maintenance_request_specification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_work_item_materials"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_work_item_materials"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_work_item_specification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_work_item_specification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_items_page"(uuid, text, text, integer, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_items_page"(uuid, text, text, integer, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."organization_profile_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."organization_profile_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."party_bank_account_id"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."party_bank_account_id"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."party_bank_account_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."party_bank_account_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."party_contact_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."party_contact_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."party_location_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."party_location_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."party_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."party_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."product_category_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."product_category_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."product_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."product_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."rebase_import_records"(uuid, text, text[], text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rebase_import_records"(uuid, text, text[], text[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."rebuild_open_items"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rebuild_open_items"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."register_import_source"(text, text, text, text[], text[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."register_import_source"(text, text, text, text[], text[], text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_import_conflict"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_import_conflict"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_maintenance_request_material_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_maintenance_request_material_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_maintenance_request_specification_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_maintenance_request_specification_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_work_item_material_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_work_item_material_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_work_item_specification_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_work_item_specification_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."allocate_existing"(uuid, uuid, text, bigint, text, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allocate_existing"(uuid, uuid, text, bigint, text, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."app_my_organizations"(integer, timestamp WITH time zone, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_my_organizations"(integer, timestamp WITH time zone, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."asset_identifier_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."asset_identifier_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."asset_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."asset_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bootstrap_permissions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bootstrap_permissions"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."bump_deleted_platform_roles"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_deleted_role_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_inserted_platform_roles"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_inserted_role_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_override_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_updated_role_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."contact_method_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."contact_method_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_bin"(uuid, integer, timestamp WITH time zone, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_bin"(uuid, integer, timestamp WITH time zone, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."due_check_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."due_check_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ensure_import_periods"(uuid, date, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ensure_import_periods"(uuid, date, integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fill_asset_due_check"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."get_many"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_many"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."guard_asset_meter_reading"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."heartbeat_import_run"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."heartbeat_import_run"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_allocation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_allocation"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_asset"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_asset"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_asset_identifier"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_asset_identifier"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_contact_method"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_contact_method"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_due_check"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_due_check"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_entities"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_entities"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_integrity"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_integrity"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_meter_reading"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_meter_reading"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_organization_profile"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_organization_profile"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party_bank_account"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party_bank_account"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party_contact"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party_contact"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party_discount_group"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party_discount_group"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party_location"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party_location"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_product"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_product"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_product_category"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_product_category"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inventory_levels"(uuid, uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inventory_levels"(uuid, uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inventory_status_counts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inventory_status_counts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_diff"(uuid, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_diff"(uuid, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_issues"(uuid, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_issues"(uuid, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_source_runs"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_source_runs"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_sources"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_sources"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_inventory_movements"(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_inventory_movements"(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_maintenance_request_materials"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_maintenance_request_materials"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_maintenance_request_specification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_maintenance_request_specification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_work_item_materials"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_work_item_materials"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_work_item_specification"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_work_item_specification"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_items_page"(uuid, text, text, integer, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_items_page"(uuid, text, text, integer, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_profile_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_profile_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."party_bank_account_id"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."party_bank_account_id"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."party_bank_account_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."party_bank_account_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."party_contact_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."party_contact_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."party_location_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."party_location_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."party_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."party_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_bitset"(text[], text[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."product_category_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."product_category_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."product_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."product_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rebuild_open_items"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rebuild_open_items"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_import_source"(text, text, text, text[], text[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_import_source"(text, text, text, text[], text[], text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_maintenance_request_material_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_maintenance_request_material_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_maintenance_request_specification_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_maintenance_request_specification_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_work_item_material_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_work_item_material_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_work_item_specification_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_work_item_specification_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"(integer, timestamp WITH time zone, text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_organizations"(integer, timestamp WITH time zone, text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"(integer, timestamp WITH time zone, text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"(integer, timestamp WITH time zone, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "rbac"."bump_platform_role_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "rbac"."bump_role_permission_members"() FROM PUBLIC;

GRANT SELECT ON TABLE "better_supabase"."asset_due_checks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."asset_due_checks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."invoice_open_items" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invoice_open_items" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_request_material_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."maintenance_request_material_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_request_specification_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."maintenance_request_specification_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."organization_payment_accounts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."organization_payment_accounts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."organization_profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."organization_profiles" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."party_bank_accounts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."party_bank_accounts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."party_channels" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."party_channels" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."party_locations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."party_locations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."work_item_material_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."work_item_material_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."work_item_specification_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."work_item_specification_lines" TO "service_role";

