SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."discount_group_parties" (
  "tenant_id"  uuid                     NOT NULL,
  "group_id"   uuid                     NOT NULL,
  "party_id"   text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "discount_group_parties_party_id_check" CHECK (((length(party_id) >= 1) AND (length(party_id) <= 200))),
  CONSTRAINT "discount_group_parties_pkey" PRIMARY KEY (tenant_id, party_id)
);

ALTER TABLE "better_supabase"."discount_group_parties"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."discount_groups" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "kind"       text                     NOT NULL,
  "code"       text                     NOT NULL,
  "name"       text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "discount_groups_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 50))),
  CONSTRAINT "discount_groups_kind_check" CHECK ((kind = ANY (ARRAY['customer'::text, 'product'::text]))),
  CONSTRAINT "discount_groups_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "discount_groups_pkey" PRIMARY KEY (id),
  CONSTRAINT "discount_groups_tenant_id_kind_code_key" UNIQUE (tenant_id, kind, code)
);

ALTER TABLE "better_supabase"."discount_groups"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."discount_rules" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"         uuid                     NOT NULL,
  "customer_group_id" uuid,
  "product_group_id"  uuid,
  "valid_from"        date,
  "valid_to"          date,
  "min_quantity"      numeric(18,4)            NOT NULL DEFAULT 0,
  "discount_bps"      integer                  NOT NULL DEFAULT 0,
  "fixed_price"       bigint,
  "currency"          character(3),
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "discount_rules_check1" CHECK (((fixed_price IS NULL) = (currency IS NULL))),
  CONSTRAINT "discount_rules_check" CHECK (((valid_to IS NULL) OR (valid_from IS NULL) OR (valid_to >= valid_from))),
  CONSTRAINT "discount_rules_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "discount_rules_discount_bps_check" CHECK (((discount_bps >= 0) AND (discount_bps <= 10000))),
  CONSTRAINT "discount_rules_fixed_price_check" CHECK ((fixed_price >= 0)),
  CONSTRAINT "discount_rules_min_quantity_check" CHECK ((min_quantity >= (0)::numeric)),
  CONSTRAINT "discount_rules_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."discount_rules"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."intrastat_lines" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "period"           date                     NOT NULL,
  "flow"             text                     NOT NULL,
  "source"           text                     NOT NULL DEFAULT 'shipment'::text,
  "shipment_line_id" uuid,
  "variant_id"       uuid,
  "trade_code"       text,
  "country"          character(2),
  "net_mass_kg"      numeric(20,3),
  "quantity"         numeric(20,6),
  "value"            bigint,
  "currency"         character(3),
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "intrastat_lines_country_check" CHECK (((country IS NULL) OR (country ~ '^[A-Z]{2}$'::text))),
  CONSTRAINT "intrastat_lines_currency_check" CHECK (((currency IS NULL) OR (currency ~ '^[A-Z]{3}$'::text))),
  CONSTRAINT "intrastat_lines_flow_check" CHECK ((flow = ANY (ARRAY['arrival'::text, 'dispatch'::text]))),
  CONSTRAINT "intrastat_lines_net_mass_kg_check" CHECK (((net_mass_kg IS NULL) OR (net_mass_kg >= (0)::numeric))),
  CONSTRAINT "intrastat_lines_period_check" CHECK ((period = (date_trunc('month'::text, (period)::timestamp with time zone))::date)),
  CONSTRAINT "intrastat_lines_pkey" PRIMARY KEY (id),
  CONSTRAINT "intrastat_lines_quantity_check" CHECK (((quantity IS NULL) OR (quantity > (0)::numeric))),
  CONSTRAINT "intrastat_lines_shipment_line_id_key" UNIQUE (shipment_line_id),
  CONSTRAINT "intrastat_lines_source_check" CHECK ((source = ANY (ARRAY['shipment'::text, 'manual'::text]))),
  CONSTRAINT "intrastat_lines_trade_code_check" CHECK (((trade_code IS NULL) OR (trade_code ~ '^[0-9]{4,10}$'::text))),
  CONSTRAINT "intrastat_lines_value_check" CHECK (((value IS NULL) OR (value >= 0)))
);

ALTER TABLE "better_supabase"."intrastat_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."stock_count_lines" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "count_id"    uuid                     NOT NULL,
  "variant_id"  uuid                     NOT NULL,
  "bin_id"      uuid,
  "lot_id"      uuid,
  "serial"      text,
  "expected"    numeric(20,6)            NOT NULL DEFAULT 0,
  "counted"     numeric(20,6),
  "variance"    numeric(20,6)            GENERATED ALWAYS AS ((counted - expected)) STORED,
  "movement_id" uuid,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "stock_count_lines_counted_check" CHECK ((counted >= (0)::numeric)),
  CONSTRAINT "stock_count_lines_expected_check" CHECK ((expected >= (0)::numeric)),
  CONSTRAINT "stock_count_lines_pkey" PRIMARY KEY (id),
  CONSTRAINT "stock_count_lines_serial_check" CHECK (((length(serial) >= 1) AND (length(serial) <= 100)))
);

ALTER TABLE "better_supabase"."stock_count_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."stock_counts" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "location_id" uuid                     NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'open'::text,
  "note"        text,
  "posted_by"   uuid,
  "opened_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "posted_at"   timestamp with time zone,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "stock_counts_pkey" PRIMARY KEY (id),
  CONSTRAINT "stock_counts_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'posted'::text, 'cancelled'::text]))),
  "opened_by"   uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."stock_counts"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."product_variants"
  ADD COLUMN "discount_group_id" uuid;

CREATE OR REPLACE FUNCTION api.cancel_stock_count (
  count uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_stock_count"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_discount_group (
  "group" uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_discount_group"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_discount_rule (
  rule uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_discount_rule"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_intrastat_line (
  line uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_intrastat_line"($1) $function$;

CREATE OR REPLACE FUNCTION api.discount_group_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."discount_group_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.discount_rule_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."discount_rule_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_discount_group (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_discount_group"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_discount_rule (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_discount_rule"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_stock_count (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_stock_count"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.open_stock_count (
  tenant   uuid,
  location uuid,
  attrs    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_stock_count"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.post_stock_count (
  count uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_stock_count"($1) $function$;

CREATE OR REPLACE FUNCTION api.prepare_intrastat (
  tenant uuid,
  period date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."prepare_intrastat"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_count_line (
  count uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_count_line"($1, $2) $function$;

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
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_line_discount"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.save_discount_group (
  tenant  uuid,
  "group" uuid,
  kind    text,
  code    text,
  name    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_discount_group"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_discount_rule (
  tenant uuid,
  rule   uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_discount_rule"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_intrastat_line (
  tenant uuid,
  line   uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_intrastat_line"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_party_discount_group (
  tenant  uuid,
  party   text,
  "group" uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_party_discount_group"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_variant_discount_group (
  variant uuid,
  "group" uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_variant_discount_group"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.stock_count_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stock_count_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_stock_count (
  count uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."status" into v_tenant, v_status from "better_supabase"."stock_counts" x where x."id" = cancel_stock_count.count for update;
  if v_tenant is null then
    raise exception 'stock count not found' using errcode = 'P0002', hint = 'INVENTORY_COUNT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_status = 'cancelled' then
    return false;
  end if;
  if v_status <> 'open' then
    raise exception 'a posted count can''t be cancelled' using errcode = '22023', hint = 'INVENTORY_COUNT_CLOSED';
  end if;
  update "better_supabase"."stock_counts" x set "status" = 'cancelled', "updated_at" = now() where x."id" = cancel_stock_count.count;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.count_expected (
  variant  uuid,
  location uuid,
  bin      uuid,
  lot      uuid,
  serial   text
)
  RETURNS numeric
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when $5 is not null then
      (select count(*) from "better_supabase"."stock_serials" y where y."variant_id" = $1 and y."serial" = $5 and y."location_id" = $2 and y."status" = 'in_stock')::numeric
    when $3 is null and $4 is null then
      coalesce((select x."on_hand" from "better_supabase"."stock_levels" x where x."variant_id" = $1 and x."location_id" = $2), 0)
        - coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y where y."variant_id" = $1 and y."location_id" = $2), 0)
    else
      coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y where y."variant_id" = $1 and y."location_id" = $2
        and y."bin_id" is not distinct from $3 and y."lot_id" is not distinct from $4), 0)
  end
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
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_discount_group (
  "group" uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."discount_groups" x where x."id" = delete_discount_group."group";
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."discount_rules" y where y."customer_group_id" = delete_discount_group."group" or y."product_group_id" = delete_discount_group."group") then
    raise exception 'a rule of the matrix still uses this group' using errcode = '23503', hint = 'CATALOG_DISCOUNT_GROUP_IN_USE';
  end if;
  delete from "better_supabase"."discount_groups" x where x."id" = delete_discount_group."group";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_discount_rule (
  rule uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."discount_rules" x where x."id" = delete_discount_rule.rule;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."discount_rules" x where x."id" = delete_discount_rule.rule;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_intrastat_line (
  line uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."intrastat_lines" x where x."id" = delete_intrastat_line.line and x."source" = 'manual';
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'shipments.manage'), false)) then
    raise exception 'not allowed to manage shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."intrastat_lines" x where x."id" = delete_intrastat_line.line;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.discount_group_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."discount_groups" x where x."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.discount_rule_check (
  tenant uuid,
  attrs  jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_customer uuid;
  v_product uuid;
begin
  begin
    v_customer := nullif(discount_rule_check.attrs ->> 'customerGroupId', '')::uuid;
    v_product := nullif(discount_rule_check.attrs ->> 'productGroupId', '')::uuid;
    perform (discount_rule_check.attrs ->> 'validFrom')::date, (discount_rule_check.attrs ->> 'validTo')::date;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'group ids are uuids and dates are YYYY-MM-DD' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end;
  if v_customer is not null and not exists (select 1 from "better_supabase"."discount_groups" y where y."id" = v_customer and y."tenant_id" = discount_rule_check.tenant and y."kind" = 'customer') then
    raise exception 'customerGroupId isn''t a customer group of this organization' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_GROUP_NOT_FOUND';
  end if;
  if v_product is not null and not exists (select 1 from "better_supabase"."discount_groups" y where y."id" = v_product and y."tenant_id" = discount_rule_check.tenant and y."kind" = 'product') then
    raise exception 'productGroupId isn''t a product group of this organization' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_GROUP_NOT_FOUND';
  end if;
  if coalesce(discount_rule_check.attrs ->> 'discountBps', '0') !~ '^[0-9]{1,5}$' or coalesce(discount_rule_check.attrs ->> 'discountBps', '0')::integer > 10000 then
    raise exception 'discountBps is a whole number from 0 to 10000' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end if;
  if coalesce(discount_rule_check.attrs ->> 'minQuantity', '0') !~ '^[0-9]{1,14}([.][0-9]{1,4})?$' then
    raise exception 'minQuantity is zero or more' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end if;
  if (discount_rule_check.attrs ->> 'fixedPrice') is not null and discount_rule_check.attrs ->> 'fixedPrice' !~ '^[0-9]{1,18}$' then
    raise exception 'fixedPrice is a whole number of minor units' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end if;
  if ((discount_rule_check.attrs ->> 'fixedPrice') is null) <> ((discount_rule_check.attrs ->> 'currency') is null)
    or ((discount_rule_check.attrs ->> 'currency') is not null and (discount_rule_check.attrs ->> 'currency') !~ '^[A-Z]{3}$') then
    raise exception 'a fixed price comes with its ISO 4217 currency, and neither without the other' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end if;
  if (discount_rule_check.attrs ->> 'validFrom') is not null and (discount_rule_check.attrs ->> 'validTo') is not null
    and (discount_rule_check.attrs ->> 'validTo')::date < (discount_rule_check.attrs ->> 'validFrom')::date then
    raise exception 'validTo is on or after validFrom' using errcode = '22023', hint = 'CATALOG_DISCOUNT_RULE_INVALID';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.discount_rule_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."discount_rules" x where x."id" = $1::uuid
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'quote', 'invoice', 'credit_note', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
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
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_discount_group (
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
  v_tenant uuid := (import_discount_group.item ->> 'tenant')::uuid;
  v_data jsonb := import_discount_group.item -> 'data';
  v_kind text := v_data ->> 'kind';
  v_code text := btrim(v_data ->> 'code');
  v_name text := btrim(coalesce(v_data ->> 'name', v_data ->> 'code'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_kind is null or v_kind not in ('customer', 'product') or v_code is null or length(v_code) not between 1 and 50 or length(v_name) not between 1 and 200 then
    raise exception 'a discount group needs a kind (customer or product), a code and a name' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ? 'parties' and (v_kind <> 'customer' or jsonb_typeof(v_data -> 'parties') <> 'array') then
    raise exception 'parties is a list on a customer group' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_discount_group.subject_id is null then
    insert into "better_supabase"."discount_groups" as x ("tenant_id", "kind", "code", "name")
    values (v_tenant, v_kind, v_code, v_name)
    on conflict ("tenant_id", "kind", "code") do update set "name" = excluded."name", "updated_at" = now()
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    begin
      update "better_supabase"."discount_groups" x set "kind" = v_kind, "code" = v_code, "name" = v_name, "updated_at" = now()
      where x."id" = import_discount_group.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    exception when unique_violation then
      raise exception 'another group of this kind has this code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
    if v_id is null then
      raise exception 'the discount group no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if v_data ? 'parties' then
    delete from "better_supabase"."discount_group_parties" x where x."group_id" = v_id and x."party_id" not in (select jsonb_array_elements_text(v_data -> 'parties'));
    insert into "better_supabase"."discount_group_parties" as x ("tenant_id", "group_id", "party_id")
    select v_tenant, v_id, btrim(p) from jsonb_array_elements_text(v_data -> 'parties') p where length(btrim(p)) between 1 and 200
    on conflict ("tenant_id", "party_id") do update set "group_id" = excluded."group_id";
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_discount_rule (
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
  v_tenant uuid := (import_discount_rule.item ->> 'tenant')::uuid;
  v_data jsonb := import_discount_rule.item -> 'data';
  v_customer_id uuid;
  v_product_id uuid;
  v_customer_code text := nullif(btrim(v_data ->> 'customerGroup'), '');
  v_product_code text := nullif(btrim(v_data ->> 'productGroup'), '');
  v_customer uuid;
  v_product uuid;
  v_attrs jsonb;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_customer_id := nullif(v_data ->> 'customerGroupId', '')::uuid;
    v_product_id := nullif(v_data ->> 'productGroupId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'group ids are uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  v_customer := (select y."id" from "better_supabase"."discount_groups" y
      where y."tenant_id" = v_tenant and y."kind" = 'customer'
        and ((v_customer_id is not null and y."id" = v_customer_id) or (v_customer_id is null and v_customer_code is not null and y."code" = v_customer_code)));
  v_product := (select y."id" from "better_supabase"."discount_groups" y
      where y."tenant_id" = v_tenant and y."kind" = 'product'
        and ((v_product_id is not null and y."id" = v_product_id) or (v_product_id is null and v_product_code is not null and y."code" = v_product_code)));
  if (v_customer_id is not null or v_customer_code is not null) and v_customer is null then
    raise exception 'the customer group isn''t in this organization; import the groups first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if (v_product_id is not null or v_product_code is not null) and v_product is null then
    raise exception 'the product group isn''t in this organization; import the groups first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_attrs := jsonb_strip_nulls(jsonb_build_object('customerGroupId', v_customer, 'productGroupId', v_product, 'validFrom', v_data -> 'validFrom', 'validTo', v_data -> 'validTo',
    'minQuantity', v_data -> 'minQuantity', 'discountBps', v_data -> 'discountBps', 'fixedPrice', v_data -> 'fixedPrice', 'currency', v_data -> 'currency'));
  begin
    perform "better_supabase"."discount_rule_check"(v_tenant, v_attrs);
  exception when sqlstate '22023' or sqlstate 'P0002' then
    raise exception 'the rule isn''t valid: check the groups, dates, discountBps, minQuantity and fixed price' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if import_discount_rule.subject_id is null then
    insert into "better_supabase"."discount_rules" as x ("tenant_id", "customer_group_id", "product_group_id", "valid_from", "valid_to", "min_quantity", "discount_bps", "fixed_price", "currency")
    values (v_tenant, v_customer, v_product, (v_attrs ->> 'validFrom')::date, (v_attrs ->> 'validTo')::date, coalesce((v_attrs ->> 'minQuantity')::numeric, 0),
      coalesce((v_attrs ->> 'discountBps')::integer, 0), (v_attrs ->> 'fixedPrice')::bigint, v_attrs ->> 'currency')
    on conflict ("tenant_id", coalesce("customer_group_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("product_group_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("valid_from", date '0001-01-01'), "min_quantity") do update set
      "valid_to" = excluded."valid_to", "discount_bps" = excluded."discount_bps", "fixed_price" = excluded."fixed_price",
      "currency" = excluded."currency", "updated_at" = now()
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    begin
      update "better_supabase"."discount_rules" x set "customer_group_id" = v_customer, "product_group_id" = v_product, "valid_from" = (v_attrs ->> 'validFrom')::date, "valid_to" = (v_attrs ->> 'validTo')::date,
        "min_quantity" = coalesce((v_attrs ->> 'minQuantity')::numeric, 0), "discount_bps" = coalesce((v_attrs ->> 'discountBps')::integer, 0),
        "fixed_price" = (v_attrs ->> 'fixedPrice')::bigint, "currency" = v_attrs ->> 'currency', "updated_at" = now()
      where x."id" = import_discount_rule.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    exception when unique_violation then
      raise exception 'another rule has the same groups, start date and minimum quantity' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
    if v_id is null then
      raise exception 'the discount rule no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_stock_count (
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
  v_tenant uuid := (import_stock_count.item ->> 'tenant')::uuid;
  v_data jsonb := import_stock_count.item -> 'data';
  v_location uuid;
  v_id uuid;
  v_status text;
  v_updated timestamptz;
  v_entry jsonb;
  v_variant uuid;
  v_bin uuid;
  v_lot uuid;
  v_serial text;
  v_counted numeric;
  v_expected numeric;
begin
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' then
    raise exception 'a stock count needs a list of lines' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_location := nullif(v_data ->> 'locationId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId is a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_location is null then
    select x."id" into v_location from "better_supabase"."inventory_locations" x where x."tenant_id" = v_tenant and x."code" = v_data ->> 'location';
  elsif not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = v_tenant) then
    v_location := null;
  end if;
  if v_location is null then
    raise exception 'the count''s location isn''t in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_stock_count.subject_id is null then
    insert into "better_supabase"."stock_counts" as x ("tenant_id", "location_id", "note")
    values (v_tenant, v_location, nullif(btrim(v_data ->> 'note'), ''))
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    select x."id", x."status" into v_id, v_status from "better_supabase"."stock_counts" x
    where x."id" = import_stock_count.subject_id::uuid and x."tenant_id" = v_tenant for update;
    if v_id is null then
      raise exception 'the stock count no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if v_status <> 'open' then
      raise exception 'a posted or cancelled count can''t be imported again' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    update "better_supabase"."stock_counts" x set "location_id" = v_location, "note" = nullif(btrim(v_data ->> 'note'), ''), "updated_at" = now()
    where x."id" = v_id returning x."updated_at" into v_updated;
    delete from "better_supabase"."stock_count_lines" y where y."count_id" = v_id and y."movement_id" is null;
  end if;
  for v_entry in select e from jsonb_array_elements(v_data -> 'lines') e loop
    begin
      v_variant := nullif(v_entry ->> 'variantId', '')::uuid;
      v_bin := nullif(v_entry ->> 'binId', '')::uuid;
      v_lot := nullif(v_entry ->> 'lotId', '')::uuid;
      v_counted := (v_entry ->> 'counted')::numeric;
      v_expected := (v_entry ->> 'expected')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'ids are uuids and counted and expected are numbers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
    if v_variant is null then
      select y."id" into v_variant from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_entry ->> 'sku';
    end if;
    if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" y where y."id" = v_variant and y."tenant_id" = v_tenant) then
      raise exception 'a line''s variant isn''t in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if v_bin is null and nullif(v_entry ->> 'bin', '') is not null then
      select y."id" into v_bin from "better_supabase"."stock_bins" y where y."tenant_id" = v_tenant and y."location_id" = v_location and y."code" = v_entry ->> 'bin';
      if v_bin is null then
        raise exception 'a line''s bin isn''t at the location' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
    end if;
    if v_lot is null and nullif(v_entry ->> 'lot', '') is not null then
      select y."id" into v_lot from "better_supabase"."stock_lots" y where y."tenant_id" = v_tenant and y."variant_id" = v_variant and y."code" = v_entry ->> 'lot';
      if v_lot is null then
        raise exception 'a line''s lot isn''t a lot of its variant' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
    end if;
    v_serial := nullif(btrim(v_entry ->> 'serial'), '');
    if v_counted is null or v_counted < 0 or (v_serial is not null and (v_counted not in (0, 1) or v_bin is not null or v_lot is not null)) then
      raise exception 'a line needs a counted quantity of zero or more, and a serial is counted 0 or 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    insert into "better_supabase"."stock_count_lines" as x ("tenant_id", "count_id", "variant_id", "bin_id", "lot_id", "serial", "expected", "counted")
    values (v_tenant, v_id, v_variant, v_bin, v_lot, v_serial,
      coalesce(v_expected, "better_supabase"."count_expected"(v_variant, v_location, v_bin, v_lot, v_serial)), v_counted)
    on conflict ("count_id", "variant_id", coalesce("bin_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("lot_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("serial", '')) do update
      set "counted" = excluded."counted", "expected" = excluded."expected", "updated_at" = now();
  end loop;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_stock_count (
  tenant   uuid,
  location uuid,
  attrs    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_attrs jsonb := coalesce(open_stock_count.attrs, '{}'::jsonb);
  v_variants uuid[];
  v_id uuid;
  v_lines integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', open_stock_count.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = open_stock_count.location and x."tenant_id" = open_stock_count.tenant) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  begin
    if jsonb_typeof(v_attrs -> 'variantIds') = 'array' then
      v_variants := array(select jsonb_array_elements_text(v_attrs -> 'variantIds'))::uuid[];
    end if;
  exception when invalid_text_representation then
    raise exception 'variantIds is a list of uuids' using errcode = '22023', hint = 'INVENTORY_COUNT_INVALID';
  end;
  insert into "better_supabase"."stock_counts" as x ("tenant_id", "location_id", "note")
  values (open_stock_count.tenant, open_stock_count.location, nullif(btrim(v_attrs ->> 'note'), ''))
  returning x."id" into v_id;
  insert into "better_supabase"."stock_count_lines" ("tenant_id", "count_id", "variant_id", "bin_id", "lot_id", "serial", "expected")
  select open_stock_count.tenant, v_id, p.variant, p.bin, p.lot, p.serial, p.expected
  from (
    select y."variant_id" as variant, y."bin_id" as bin, y."lot_id" as lot, null::text as serial, y."on_hand" as expected
    from "better_supabase"."stock_buckets" y
    where y."location_id" = open_stock_count.location and y."tenant_id" = open_stock_count.tenant and y."on_hand" > 0
      and not exists (select 1 from "better_supabase"."stock_items" q where q."variant_id" = y."variant_id" and q."tracking" = 'serial')
    union all
    select x."variant_id", null, null, null,
      x."on_hand" - coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y where y."variant_id" = x."variant_id" and y."location_id" = x."location_id"), 0)
    from "better_supabase"."stock_levels" x
    where x."location_id" = open_stock_count.location and x."tenant_id" = open_stock_count.tenant
      and not exists (select 1 from "better_supabase"."stock_items" q where q."variant_id" = x."variant_id" and q."tracking" = 'serial')
    union all
    select z."variant_id", z."bin_id", z."lot_id", z."serial", 1
    from "better_supabase"."stock_serials" z
    where z."location_id" = open_stock_count.location and z."tenant_id" = open_stock_count.tenant and z."status" = 'in_stock'
  ) p
  where (v_variants is null or p.variant = any (v_variants)) and p.expected > 0
  on conflict do nothing;
  get diagnostics v_lines = row_count;
  return jsonb_build_object('id', v_id, 'lines', v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_from_lines (
  tenant uuid,
  lines  jsonb,
  attrs  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_attrs jsonb := coalesce(order_from_lines.attrs, '{}'::jsonb);
  v_currency text := v_attrs ->> 'currency';
  v_inclusive boolean := coalesce((v_attrs ->> 'taxInclusive')::boolean, false);
  v_shipping bigint := coalesce(case when coalesce(v_attrs ->> 'shippingTotal', '') ~ '^[0-9]{1,18}$' then (v_attrs ->> 'shippingTotal')::bigint end, 0);
  v_item record;
  v_lines jsonb := '[]';
  v_unit bigint;
  v_rule jsonb;
  v_disc bigint;
  v_subtotal bigint := 0;
  v_discount bigint := 0;
  v_tax bigint := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', order_from_lines.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'attrs.currency is an ISO 4217 code' using errcode = '22023', hint = 'ORDERS_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(order_from_lines.lines) is distinct from 'array' or jsonb_array_length(order_from_lines.lines) = 0 then
    raise exception 'lines is a non-empty list' using errcode = '22023', hint = 'ORDERS_LINES_INVALID';
  end if;
  if (v_attrs ? 'shippingTotal' and case when coalesce(v_attrs ->> 'shippingTotal', '') ~ '^[0-9]{1,18}$' then (v_attrs ->> 'shippingTotal')::bigint end is null) then
    raise exception 'amounts are minor units of zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  for v_item in
    select e as raw, nullif(e ->> 'variantId', '')::uuid as variant, e ->> 'quantity' as quantity,
      cv."id" as found, cv."tenant_id" as variant_tenant, cv."sku" as sku, concat_ws(' / ', cp."title", nullif(cv."title", '')) as title, cp."id" as product, cp."kind" as kind
    from jsonb_array_elements(order_from_lines.lines) e
    left join "better_supabase"."product_variants" cv on cv."id" = nullif(e ->> 'variantId', '')::uuid
    left join "better_supabase"."products" cp on cp."id" = cv."product_id"
  loop
    if coalesce(v_item.quantity, '') !~ '^[1-9][0-9]{0,8}$' then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    if v_item.variant is not null and (v_item.found is null or v_item.variant_tenant <> order_from_lines.tenant) then
      raise exception 'a line''s variant isn''t in this organization' using errcode = 'P0002', hint = 'ORDERS_VARIANT_NOT_FOUND';
    end if;
    if v_item.variant is null and coalesce(v_item.raw ->> 'title', '') = '' then
      raise exception 'a line without a variant needs a title' using errcode = '22023', hint = 'ORDERS_LINES_INVALID';
    end if;
    if (v_item.raw ? 'unitAmount' and case when coalesce(v_item.raw ->> 'unitAmount', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'unitAmount')::bigint end is null)
      or (v_item.raw ? 'discount' and case when coalesce(v_item.raw ->> 'discount', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'discount')::bigint end is null)
      or (v_item.raw ? 'tax' and case when coalesce(v_item.raw ->> 'tax', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'tax')::bigint end is null) then
      raise exception 'amounts are minor units of zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
    end if;
    v_rule := null;
    
    v_unit := coalesce(case when coalesce(v_item.raw ->> 'unitAmount', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'unitAmount')::bigint end, (v_rule ->> 'fixedPrice')::bigint,
      case when v_item.variant is not null then ("better_supabase"."variant_price"(v_item.variant, v_currency, null, null) ->> 'amount')::bigint end);
    if v_unit is null then
      raise exception 'a line has no unitAmount and its variant no price in this currency' using errcode = '22023', hint = 'ORDERS_LINE_UNPRICED';
    end if;
    v_disc := coalesce(case when coalesce(v_item.raw ->> 'discount', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'discount')::bigint end,
      case when v_rule is not null and not v_item.raw ? 'discount' then round(v_unit * v_item.quantity::bigint * (v_rule ->> 'discountBps')::integer / 10000.0)::bigint end, 0);
    if v_disc > v_unit * v_item.quantity::bigint then
      raise exception 'a line''s discount is more than its subtotal' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'variantId', v_item.variant, 'productId', v_item.product,
      'sku', coalesce(v_item.raw ->> 'sku', v_item.sku, ''), 'title', coalesce(nullif(v_item.raw ->> 'title', ''), v_item.title),
      'quantity', v_item.quantity, 'unitAmount', v_unit::text, 'subtotal', (v_unit * v_item.quantity::bigint)::text,
      'discount', v_disc::text, 'tax', coalesce(case when coalesce(v_item.raw ->> 'tax', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'tax')::bigint end, 0)::text,
      'total', (v_unit * v_item.quantity::bigint - v_disc)::text,
      'requiresShipping', case when v_item.variant is null then coalesce((v_item.raw ->> 'requiresShipping')::boolean, false) else v_item.kind = 'physical' end));
    v_subtotal := v_subtotal + v_unit * v_item.quantity::bigint;
    v_discount := v_discount + v_disc;
    v_tax := v_tax + coalesce(case when coalesce(v_item.raw ->> 'tax', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'tax')::bigint end, 0);
  end loop;
  return "better_supabase"."order_from_document"(order_from_lines.tenant, v_attrs || jsonb_build_object(
    'subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'shippingTotal', v_shipping::text, 'taxTotal', v_tax::text,
    'total', (v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end)::text),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_stock_count (
  count uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count record;
  v_line record;
  v_movement uuid;
  v_moves integer := 0;
  v_total numeric := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status, x."note" as note into v_count
  from "better_supabase"."stock_counts" x where x."id" = post_stock_count.count for update;
  if not found then
    raise exception 'stock count not found' using errcode = 'P0002', hint = 'INVENTORY_COUNT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_count.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_count.status = 'posted' then
    return jsonb_build_object('posted', false, 'movements', (select count(*) from "better_supabase"."stock_count_lines" y where y."count_id" = post_stock_count.count and y."movement_id" is not null), 'variance', null);
  end if;
  if v_count.status <> 'open' then
    raise exception 'a cancelled count can''t be posted' using errcode = '22023', hint = 'INVENTORY_COUNT_CLOSED';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."bin_id" as bin, y."lot_id" as lot, y."serial" as serial, y."variance" as variance
    from "better_supabase"."stock_count_lines" y
    where y."count_id" = post_stock_count.count and y."variance" is not null and y."variance" <> 0 and y."movement_id" is null
    order by y."variant_id", y."id"
  loop
    insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
    values (v_count.tenant, v_line.variant, v_count.location)
    on conflict ("variant_id", "location_id") do nothing;
    v_movement := "better_supabase"."move_stock"(v_count.tenant, v_line.variant, v_count.location, v_line.variance, 'count', 'stock_count', post_stock_count.count::text, coalesce(v_count.note, 'Stock count'), jsonb_strip_nulls(jsonb_build_object('binId', v_line.bin, 'lotId', v_line.lot, 'serials', case when v_line.serial is not null then jsonb_build_array(v_line.serial) end)));
    update "better_supabase"."stock_count_lines" y set "movement_id" = v_movement, "updated_at" = now() where y."id" = v_line.id;
    v_moves := v_moves + 1;
    v_total := v_total + abs(v_line.variance);
  end loop;
  update "better_supabase"."stock_counts" x set "status" = 'posted', "posted_at" = now(), "posted_by" = auth.uid(), "updated_at" = now() where x."id" = post_stock_count.count;
  return jsonb_build_object('posted', true, 'movements', v_moves, 'variance', v_total::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prepare_intrastat (
  tenant uuid,
  period date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_start date := date_trunc('month', prepare_intrastat.period)::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', prepare_intrastat.tenant, 'shipments.manage'), false)) then
    raise exception 'not allowed to manage shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  if prepare_intrastat.period is null then
    raise exception 'name the month to prepare' using errcode = '22023', hint = 'SHIPMENT_INTRASTAT_INVALID';
  end if;
  delete from "better_supabase"."intrastat_lines" x where x."tenant_id" = prepare_intrastat.tenant and x."period" = v_start and x."source" = 'shipment';
  insert into "better_supabase"."intrastat_lines" ("tenant_id", "period", "flow", "source", "shipment_line_id", "variant_id", "trade_code", "country", "net_mass_kg", "quantity", "value", "currency")
  select s.tenant, v_start, s.flow, 'shipment', s.line, s.variant, s.trade_code, s.partner, s.net_mass, s.quantity, s.value, s.currency
  from (
    select sl."tenant_id" as tenant, sl."id" as line, sl."variant_id" as variant, sl."quantity" as quantity,
      case when sl."direction" = 'return' then 'arrival' else 'dispatch' end as flow,
      upper(sh."to_address" ->> 'country') as partner,
      upper(sh."from_address" ->> 'country') as own,
      cv."trade_code" as trade_code,
      coalesce(nullif(sl."detail" ->> 'netMassKg', '')::numeric, case when cv."weight_grams" is not null then round(cv."weight_grams"::numeric * sl."quantity" / 1000, 3) end) as net_mass,
      coalesce(nullif(sl."detail" ->> 'currency', ''), sh."currency") as currency,
      coalesce(nullif(sl."detail" ->> 'value', '')::bigint, (select round(("better_supabase"."variant_price"(sl."variant_id", coalesce(nullif(sl."detail" ->> 'currency', ''), sh."currency"), null, null) ->> 'amount')::numeric * sl."quantity")::bigint
        where coalesce(nullif(sl."detail" ->> 'currency', ''), sh."currency") is not null)) as value
    from "better_supabase"."shipment_lines" sl
    join "better_supabase"."shipments" sh on sh."id" = sl."shipment_id"
    left join "better_supabase"."product_variants" cv on cv."id" = sl."variant_id"
    where sl."tenant_id" = prepare_intrastat.tenant and sl."moved_at" is not null and sh."cancelled_at" is null
      and sl."moved_at" >= v_start::timestamptz and sl."moved_at" < (v_start + interval '1 month')::timestamptz
  ) s
  where s.partner = any (array['AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE']) and s.partner is distinct from s.own;
  return jsonb_build_object(
    'period', v_start,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'period', x."period", 'flow', x."flow", 'source', x."source",
      'shipmentLineId', x."shipment_line_id", 'variantId', x."variant_id", 'tradeCode', x."trade_code", 'country', x."country",
      'netMassKg', x."net_mass_kg"::text, 'quantity', x."quantity"::text, 'value', x."value"::text, 'currency', x."currency") order by x."flow", x."trade_code" nulls first, x."created_at", x."id"), '[]'::jsonb) from "better_supabase"."intrastat_lines" x
      where x."tenant_id" = prepare_intrastat.tenant and x."period" = v_start),
    'exceptions', (select coalesce(jsonb_agg(jsonb_build_object('lineId', e.id, 'shipmentLineId', e.shipment_line, 'variantId', e.variant, 'code', e.code) order by e.code, e.id), '[]'::jsonb)
      from (
        select x."id" as id, x."shipment_line_id" as shipment_line, x."variant_id" as variant, c.code
        from "better_supabase"."intrastat_lines" x
        cross join lateral (values
          ('INTRASTAT_TRADE_CODE_MISSING', x."trade_code" is null),
          ('INTRASTAT_COUNTRY_MISSING', x."country" is null),
          ('INTRASTAT_NET_MASS_MISSING', x."net_mass_kg" is null or x."net_mass_kg" = 0),
          ('INTRASTAT_VALUE_MISSING', x."value" is null)
        ) c (code, failed)
        where x."tenant_id" = prepare_intrastat.tenant and x."period" = v_start and c.failed
      ) e)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_count_line (
  count uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_attrs jsonb := coalesce(record_count_line.attrs, '{}'::jsonb);
  v_count record;
  v_variant uuid;
  v_bin uuid;
  v_lot uuid;
  v_serial text := nullif(btrim(v_attrs ->> 'serial'), '');
  v_counted numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status into v_count
  from "better_supabase"."stock_counts" x where x."id" = record_count_line.count for update;
  if not found then
    raise exception 'stock count not found' using errcode = 'P0002', hint = 'INVENTORY_COUNT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_count.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_count.status <> 'open' then
    raise exception 'a posted or cancelled count takes no more lines' using errcode = '22023', hint = 'INVENTORY_COUNT_CLOSED';
  end if;
  begin
    v_variant := (v_attrs ->> 'variantId')::uuid;
    v_bin := nullif(v_attrs ->> 'binId', '')::uuid;
    v_lot := nullif(v_attrs ->> 'lotId', '')::uuid;
    v_counted := (v_attrs ->> 'counted')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'variantId, binId and lotId are uuids and counted is a number' using errcode = '22023', hint = 'INVENTORY_COUNT_INVALID';
  end;
  if v_variant is null or v_counted is null or v_counted < 0 then
    raise exception 'a line needs a variantId and a counted quantity of zero or more' using errcode = '22023', hint = 'INVENTORY_COUNT_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = v_variant and cv."tenant_id" = v_count.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."stock_items" q where q."variant_id" = v_variant and q."tracking" = 'serial') and (v_serial is null or v_counted not in (0, 1)) then
    raise exception 'a serial-tracked variant is counted per serial number, 0 or 1' using errcode = '22023', hint = 'INVENTORY_COUNT_INVALID';
  end if;
  if v_serial is not null and (v_counted not in (0, 1) or v_bin is not null or v_lot is not null) then
    raise exception 'a serial number is counted 0 or 1, without a bin or lot' using errcode = '22023', hint = 'INVENTORY_COUNT_INVALID';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" b where b."id" = v_bin and b."location_id" = v_count.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" b where b."id" = v_lot and b."variant_id" = v_variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_count_lines" as x ("tenant_id", "count_id", "variant_id", "bin_id", "lot_id", "serial", "expected", "counted")
  values (v_count.tenant, record_count_line.count, v_variant, v_bin, v_lot, v_serial,
    "better_supabase"."count_expected"(v_variant, v_count.location, v_bin, v_lot, v_serial), v_counted)
  on conflict ("count_id", "variant_id", coalesce("bin_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("lot_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("serial", '')) do update
    set "counted" = excluded."counted", "updated_at" = now()
  returning x."id", x."expected", x."counted", x."variance" into v_row;
  update "better_supabase"."stock_counts" x set "updated_at" = now() where x."id" = record_count_line.count;
  return jsonb_build_object('id', v_row."id", 'expected', v_row."expected"::text, 'counted', v_row."counted"::text, 'variance', v_row."variance"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_line_discount (
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
  AS $function$
  with scope as (
    select (select x."group_id" from "better_supabase"."discount_group_parties" x where x."tenant_id" = $1 and x."party_id" = $2) as customer_group,
      (select y."discount_group_id" from "better_supabase"."product_variants" y where y."id" = $3 and y."tenant_id" = $1) as item_group
  ),
  matched as (
    select r."id" as id, r."discount_bps" as discount_bps, r."fixed_price" as fixed_price, r."currency" as currency
    from "better_supabase"."discount_rules" r cross join scope s
    where r."tenant_id" = $1
      and (r."customer_group_id" is null or r."customer_group_id" = s.customer_group)
      and (r."product_group_id" is null or r."product_group_id" = s.item_group)
      and (r."valid_from" is null or r."valid_from" <= coalesce($5, current_date))
      and (r."valid_to" is null or r."valid_to" >= coalesce($5, current_date))
      and r."min_quantity" <= coalesce($4, 1)
      and (r."fixed_price" is null or $6 is null or r."currency" = upper($6))
    order by (case when r."customer_group_id" is not null then 2 else 0 end) + (case when r."product_group_id" is not null then 1 else 0 end) desc,
      r."min_quantity" desc, r."valid_from" desc nulls last, r."created_at", r."id"
    limit 1
  )
  select coalesce((select jsonb_build_object('discountBps', m.discount_bps, 'fixedPrice', m.fixed_price::text, 'currency', m.currency, 'ruleId', m.id) from matched m),
    jsonb_build_object('discountBps', 0, 'fixedPrice', null, 'currency', null, 'ruleId', null))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_discount_group (
  tenant  uuid,
  "group" uuid,
  kind    text,
  code    text,
  name    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_created boolean := save_discount_group."group" is null;
  v_code text := btrim(save_discount_group.code);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_discount_group.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if save_discount_group.kind is null or save_discount_group.kind not in ('customer', 'product') then
    raise exception 'the kind is customer or product' using errcode = '22023', hint = 'CATALOG_DISCOUNT_GROUP_INVALID';
  end if;
  if v_code is null or length(v_code) not between 1 and 50 or length(btrim(coalesce(save_discount_group.name, ''))) not between 1 and 200 then
    raise exception 'a group needs a code of up to 50 and a name of up to 200 characters' using errcode = '22023', hint = 'CATALOG_DISCOUNT_GROUP_INVALID';
  end if;
  begin
    if v_created then
      insert into "better_supabase"."discount_groups" as x ("tenant_id", "kind", "code", "name")
      values (save_discount_group.tenant, save_discount_group.kind, v_code, btrim(save_discount_group.name))
      returning x."id" into v_id;
    else
      update "better_supabase"."discount_groups" x set "code" = v_code, "name" = btrim(save_discount_group.name), "updated_at" = now()
      where x."id" = save_discount_group."group" and x."tenant_id" = save_discount_group.tenant and x."kind" = save_discount_group.kind
      returning x."id" into v_id;
      if v_id is null then
        raise exception 'discount group not found' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_GROUP_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'a group of this kind already has this code' using errcode = '23505', hint = 'CATALOG_DISCOUNT_GROUP_EXISTS';
  end;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_discount_rule (
  tenant uuid,
  rule   uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_attrs jsonb := coalesce(save_discount_rule.attrs, '{}'::jsonb);
  v_id uuid;
  v_created boolean := true;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_discount_rule.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  perform "better_supabase"."discount_rule_check"(save_discount_rule.tenant, v_attrs);
  if save_discount_rule.rule is not null then
    update "better_supabase"."discount_rules" x set
      "customer_group_id" = nullif(v_attrs ->> 'customerGroupId', '')::uuid, "product_group_id" = nullif(v_attrs ->> 'productGroupId', '')::uuid,
      "valid_from" = (v_attrs ->> 'validFrom')::date, "valid_to" = (v_attrs ->> 'validTo')::date,
      "min_quantity" = coalesce((v_attrs ->> 'minQuantity')::numeric, 0), "discount_bps" = coalesce((v_attrs ->> 'discountBps')::integer, 0),
      "fixed_price" = (v_attrs ->> 'fixedPrice')::bigint, "currency" = v_attrs ->> 'currency', "updated_at" = now()
    where x."id" = save_discount_rule.rule and x."tenant_id" = save_discount_rule.tenant
    returning x."id" into v_id;
    if v_id is null then
      raise exception 'discount rule not found' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_RULE_NOT_FOUND';
    end if;
    return jsonb_build_object('id', v_id, 'created', false);
  end if;
  insert into "better_supabase"."discount_rules" as x ("tenant_id", "customer_group_id", "product_group_id", "valid_from", "valid_to", "min_quantity", "discount_bps", "fixed_price", "currency")
  values (save_discount_rule.tenant, nullif(v_attrs ->> 'customerGroupId', '')::uuid, nullif(v_attrs ->> 'productGroupId', '')::uuid,
    (v_attrs ->> 'validFrom')::date, (v_attrs ->> 'validTo')::date, coalesce((v_attrs ->> 'minQuantity')::numeric, 0),
    coalesce((v_attrs ->> 'discountBps')::integer, 0), (v_attrs ->> 'fixedPrice')::bigint, v_attrs ->> 'currency')
  on conflict ("tenant_id", coalesce("customer_group_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("product_group_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("valid_from", date '0001-01-01'), "min_quantity") do update set
    "valid_to" = excluded."valid_to", "discount_bps" = excluded."discount_bps", "fixed_price" = excluded."fixed_price",
    "currency" = excluded."currency", "updated_at" = now()
  returning x."id", (xmax = 0) into v_id, v_created;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_intrastat_line (
  tenant uuid,
  line   uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_attrs jsonb := coalesce(save_intrastat_line.attrs, '{}'::jsonb);
  v_period date;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_intrastat_line.tenant, 'shipments.manage'), false)) then
    raise exception 'not allowed to manage shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  begin
    v_period := date_trunc('month', (v_attrs ->> 'period')::date)::date;
    perform (v_attrs ->> 'netMassKg')::numeric, (v_attrs ->> 'quantity')::numeric, (v_attrs ->> 'value')::bigint, (v_attrs ->> 'variantId')::uuid;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'period is a date and the amounts and variantId are numbers and a uuid' using errcode = '22023', hint = 'SHIPMENT_INTRASTAT_INVALID';
  end;
  if v_period is null or v_attrs ->> 'flow' is null or v_attrs ->> 'flow' not in ('arrival', 'dispatch')
    or coalesce(v_attrs ->> 'country', '') !~ '^[A-Z]{2}$' or not (v_attrs ->> 'country') = any (array['AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE']) then
    raise exception 'a line needs a period, a flow (arrival or dispatch) and the country of a member state' using errcode = '22023', hint = 'SHIPMENT_INTRASTAT_INVALID';
  end if;
  if (v_attrs ->> 'variantId') is not null and not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (v_attrs ->> 'variantId')::uuid and cv."tenant_id" = save_intrastat_line.tenant) then
    raise exception 'the variant isn''t in this organization' using errcode = 'P0002', hint = 'SHIPMENT_INTRASTAT_INVALID';
  end if;
  if save_intrastat_line.line is null then
    insert into "better_supabase"."intrastat_lines" as x ("tenant_id", "period", "flow", "source", "variant_id", "trade_code", "country", "net_mass_kg", "quantity", "value", "currency")
    values (save_intrastat_line.tenant, v_period, v_attrs ->> 'flow', 'manual', nullif(v_attrs ->> 'variantId', '')::uuid, nullif(v_attrs ->> 'tradeCode', ''), v_attrs ->> 'country',
      (v_attrs ->> 'netMassKg')::numeric, (v_attrs ->> 'quantity')::numeric, (v_attrs ->> 'value')::bigint, nullif(v_attrs ->> 'currency', ''))
    returning x."id" into v_id;
    return jsonb_build_object('id', v_id, 'created', true);
  end if;
  update "better_supabase"."intrastat_lines" x set "period" = v_period, "flow" = v_attrs ->> 'flow', "variant_id" = nullif(v_attrs ->> 'variantId', '')::uuid, "trade_code" = nullif(v_attrs ->> 'tradeCode', ''),
    "country" = v_attrs ->> 'country', "net_mass_kg" = (v_attrs ->> 'netMassKg')::numeric, "quantity" = (v_attrs ->> 'quantity')::numeric,
    "value" = (v_attrs ->> 'value')::bigint, "currency" = nullif(v_attrs ->> 'currency', ''), "updated_at" = now()
  where x."id" = save_intrastat_line.line and x."tenant_id" = save_intrastat_line.tenant and x."source" = 'manual'
  returning x."id" into v_id;
  if v_id is null then
    raise exception 'a manual Intrastat line of this organization wasn''t found' using errcode = 'P0002', hint = 'SHIPMENT_INTRASTAT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_id, 'created', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_party_discount_group (
  tenant  uuid,
  party   text,
  "group" uuid
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_party_discount_group.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if set_party_discount_group.party is null or length(btrim(set_party_discount_group.party)) not between 1 and 200 then
    raise exception 'name the party by its id' using errcode = '22023', hint = 'CATALOG_DISCOUNT_PARTY_INVALID';
  end if;
  if set_party_discount_group."group" is null then
    delete from "better_supabase"."discount_group_parties" x where x."tenant_id" = set_party_discount_group.tenant and x."party_id" = btrim(set_party_discount_group.party);
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."discount_groups" y where y."id" = set_party_discount_group."group" and y."tenant_id" = set_party_discount_group.tenant and y."kind" = 'customer') then
    raise exception 'a party takes a customer group of its organization' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_GROUP_NOT_FOUND';
  end if;
  insert into "better_supabase"."discount_group_parties" as x ("tenant_id", "group_id", "party_id")
  values (set_party_discount_group.tenant, set_party_discount_group."group", btrim(set_party_discount_group.party))
  on conflict ("tenant_id", "party_id") do update set "group_id" = excluded."group_id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_variant_discount_group (
  variant uuid,
  "group" uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = set_variant_discount_group.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if set_variant_discount_group."group" is not null and not exists (
    select 1 from "better_supabase"."discount_groups" y where y."id" = set_variant_discount_group."group" and y."tenant_id" = v_tenant and y."kind" = 'product') then
    raise exception 'a variant takes a product group of its organization' using errcode = 'P0002', hint = 'CATALOG_DISCOUNT_GROUP_NOT_FOUND';
  end if;
  update "better_supabase"."product_variants" x set "discount_group_id" = set_variant_discount_group."group", "updated_at" = now() where x."id" = set_variant_discount_group.variant;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stock_count_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."stock_counts" x where x."id" = $1::uuid
$function$;

ALTER TABLE "better_supabase"."discount_group_parties"
  ADD CONSTRAINT "discount_group_parties_group_id_fkey" FOREIGN KEY (group_id) REFERENCES better_supabase.discount_groups(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."discount_rules"
  ADD CONSTRAINT "discount_rules_customer_group_id_fkey" FOREIGN KEY (customer_group_id) REFERENCES better_supabase.discount_groups(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."discount_rules"
  ADD CONSTRAINT "discount_rules_product_group_id_fkey" FOREIGN KEY (product_group_id) REFERENCES better_supabase.discount_groups(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD CONSTRAINT "intrastat_lines_shipment_line_id_fkey" FOREIGN KEY (shipment_line_id) REFERENCES better_supabase.shipment_lines(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD CONSTRAINT "intrastat_lines_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."product_variants"
  ADD CONSTRAINT "product_variants_discount_group_id_fkey" FOREIGN KEY (discount_group_id) REFERENCES better_supabase.discount_groups(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."stock_count_lines"
  ADD CONSTRAINT "stock_count_lines_bin_id_fkey" FOREIGN KEY (bin_id) REFERENCES better_supabase.stock_bins(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."stock_count_lines"
  ADD CONSTRAINT "stock_count_lines_lot_id_fkey" FOREIGN KEY (lot_id) REFERENCES better_supabase.stock_lots(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."stock_count_lines"
  ADD CONSTRAINT "stock_count_lines_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_counts"
  ADD CONSTRAINT "stock_counts_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_count_lines"
  ADD CONSTRAINT "stock_count_lines_count_id_fkey" FOREIGN KEY (count_id) REFERENCES better_supabase.stock_counts(id) ON DELETE CASCADE;

CREATE INDEX discount_group_parties_group_idx ON better_supabase.discount_group_parties USING btree (group_id);

CREATE INDEX discount_rules_customer_group_idx ON better_supabase.discount_rules USING btree (customer_group_id)
  WHERE (customer_group_id IS NOT NULL);

CREATE UNIQUE INDEX discount_rules_key ON better_supabase.discount_rules
  USING btree
  (tenant_id, COALESCE(customer_group_id, '00000000-0000-4000-8000-000000000000'::uuid), COALESCE(product_group_id, '00000000-0000-4000-8000-000000000000'::uuid),
  COALESCE(valid_from, '0001-01-01'::date), min_quantity);

CREATE INDEX discount_rules_product_group_idx ON better_supabase.discount_rules USING btree (product_group_id)
  WHERE (product_group_id IS NOT NULL);

CREATE INDEX intrastat_lines_period_idx ON better_supabase.intrastat_lines USING btree (tenant_id, period);

CREATE INDEX intrastat_lines_variant_idx ON better_supabase.intrastat_lines USING btree (variant_id)
  WHERE (variant_id IS NOT NULL);

CREATE INDEX product_variants_discount_group_idx ON better_supabase.product_variants USING btree (discount_group_id)
  WHERE (discount_group_id IS NOT NULL);

CREATE INDEX stock_count_lines_bin_idx ON better_supabase.stock_count_lines USING btree (bin_id)
  WHERE (bin_id IS NOT NULL);

CREATE UNIQUE INDEX stock_count_lines_key ON better_supabase.stock_count_lines
  USING btree
  (count_id, variant_id, COALESCE(bin_id, '00000000-0000-4000-8000-000000000000'::uuid), COALESCE(lot_id, '00000000-0000-4000-8000-000000000000'::uuid), COALESCE(serial, ''::text));

CREATE INDEX stock_count_lines_lot_idx ON better_supabase.stock_count_lines USING btree (lot_id)
  WHERE (lot_id IS NOT NULL);

CREATE INDEX stock_count_lines_variant_idx ON better_supabase.stock_count_lines USING btree (variant_id);

CREATE INDEX stock_counts_location_idx ON better_supabase.stock_counts USING btree (location_id);

CREATE INDEX stock_counts_status_idx ON better_supabase.stock_counts USING btree (tenant_id, status);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."discount_group_parties"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."discount_group_parties"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."discount_group_parties"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."discount_group_parties"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "discount_group_parties_read" ON "better_supabase"."discount_group_parties"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."discount_groups"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."discount_groups"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."discount_groups"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."discount_groups"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "discount_groups_read" ON "better_supabase"."discount_groups"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."discount_rules"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."discount_rules"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."discount_rules"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."discount_rules"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "discount_rules_read" ON "better_supabase"."discount_rules"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."intrastat_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."intrastat_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."intrastat_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."intrastat_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "intrastat_lines_read" ON "better_supabase"."intrastat_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."stock_count_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."stock_count_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."stock_count_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."stock_count_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "stock_count_lines_read" ON "better_supabase"."stock_count_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."stock_counts"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."stock_counts"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."stock_counts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."stock_counts"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "stock_counts_read" ON "better_supabase"."stock_counts"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."cancel_stock_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_stock_count"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_discount_group"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_discount_group"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_discount_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_discount_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_intrastat_line"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_intrastat_line"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."discount_group_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."discount_group_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."discount_rule_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."discount_rule_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_discount_group"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_discount_group"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_discount_rule"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_discount_rule"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_stock_count"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_stock_count"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."open_stock_count"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_stock_count"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_stock_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_stock_count"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."prepare_intrastat"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."prepare_intrastat"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_count_line"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_count_line"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_line_discount"(uuid, text, uuid, numeric, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_line_discount"(uuid, text, uuid, numeric, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_discount_group"(uuid, uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_discount_group"(uuid, uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_discount_rule"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_discount_rule"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_intrastat_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_intrastat_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_party_discount_group"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_party_discount_group"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_variant_discount_group"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_variant_discount_group"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stock_count_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stock_count_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_stock_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_stock_count"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."count_expected"(uuid, uuid, uuid, uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."delete_discount_group"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_discount_group"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_discount_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_discount_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_intrastat_line"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_intrastat_line"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."discount_group_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."discount_group_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."discount_rule_check"(uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."discount_rule_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."discount_rule_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_discount_group"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_discount_group"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_discount_rule"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_discount_rule"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_stock_count"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_stock_count"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_stock_count"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_stock_count"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_stock_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_stock_count"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."prepare_intrastat"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."prepare_intrastat"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_count_line"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_count_line"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_line_discount"(uuid, text, uuid, numeric, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_line_discount"(uuid, text, uuid, numeric, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_discount_group"(uuid, uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_discount_group"(uuid, uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_discount_rule"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_discount_rule"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_intrastat_line"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_intrastat_line"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_party_discount_group"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_party_discount_group"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_variant_discount_group"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_variant_discount_group"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stock_count_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stock_count_updated_at"(text) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."discount_group_parties" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."discount_group_parties" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."discount_groups" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."discount_groups" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."discount_rules" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."discount_rules" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."intrastat_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."intrastat_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."stock_count_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."stock_count_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."stock_counts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."stock_counts" TO "service_role";
