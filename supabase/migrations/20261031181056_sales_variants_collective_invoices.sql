SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."invoice_line_sources" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "invoice_id"     uuid                     NOT NULL,
  "position"       integer                  NOT NULL,
  "source"         text                     NOT NULL,
  "source_id"      uuid                     NOT NULL,
  "source_line_id" uuid,
  "order_line_id"  uuid,
  "quantity"       numeric(18,4)            NOT NULL,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invoice_line_sources_pkey" PRIMARY KEY (id),
  CONSTRAINT "invoice_line_sources_quantity_check" CHECK ((quantity > (0)::numeric)),
  CONSTRAINT "invoice_line_sources_source_check" CHECK ((source = ANY (ARRAY['order'::text, 'shipment'::text, 'time'::text])))
);

ALTER TABLE "better_supabase"."invoice_line_sources"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "variant_of" uuid;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "variant_label" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "is_selected" boolean NOT NULL DEFAULT true;

ALTER TABLE "better_supabase"."quotes"
  ADD COLUMN "variant_of" uuid;

ALTER TABLE "better_supabase"."quotes"
  ADD COLUMN "variant_label" text;

ALTER TABLE "better_supabase"."quotes"
  ADD COLUMN "is_selected" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION api.claim_time_for_invoice (
  tenant    uuid,
  invoice   uuid,
  entry_ids jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_time_for_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.create_quote_variant (
  quote uuid,
  label text,
  attrs jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_quote_variant"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.invoice_from_sources (
  tenant      uuid,
  party       jsonb,
  source_refs jsonb,
  options     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_from_sources"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_order_variants (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_order_variants"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_quote_variants (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_quote_variants"($1) $function$;

CREATE OR REPLACE FUNCTION api.select_order_variant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."select_order_variant"($1) $function$;

CREATE OR REPLACE FUNCTION api.select_quote_variant (
  quote   uuid,
  options jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."select_quote_variant"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_order_variant (
  id         uuid,
  variant_of uuid,
  label      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_order_variant"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.sources_ready_to_invoice (
  tenant uuid,
  party  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sources_ready_to_invoice"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.time_lines_for_invoice (
  tenant   uuid,
  scope    jsonb,
  group_by text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."time_lines_for_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_time_for_invoice (
  tenant    uuid,
  invoice   uuid,
  entry_ids jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claimed jsonb;
  v_expected integer := jsonb_array_length(claim_time_for_invoice.entry_ids);
begin
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || claim_time_for_invoice.tenant::text, 0));
  with claimed as (
    insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
    select u.id, claim_time_for_invoice.tenant, claim_time_for_invoice.invoice, u.rate, u.currency, round(u.seconds)::bigint
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = claim_time_for_invoice.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' is null or (x."subject_type" = jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' ->> 'type' and x."subject_id" = jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' ->> 'id'))
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'userId' is null or x."user_id" = (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'userId')::uuid)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'starts' is null or x."started_at" >= (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'starts')::timestamptz)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'ends' is null or x."started_at" < (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'ends')::timestamptz)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'entryIds')))) u
    where u.rate is not null
    returning "entry_id" as entry_id, "seconds" as seconds)
  select coalesce(jsonb_agg(jsonb_build_object('entryId', c.entry_id, 'seconds', c.seconds)), '[]'::jsonb) into v_claimed from claimed c;
  if jsonb_array_length(v_claimed) <> v_expected then
    raise exception 'some time entries were billed in the meantime' using errcode = '55000', hint = 'BILLABLE_TIME_STALE';
  end if;
  return v_claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote_variant (
  quote uuid,
  label text,
  attrs jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
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
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_from_quote (
  quote               uuid,
  deposit_bps         integer,
  deposit_amount      bigint  DEFAULT NULL::bigint,
  deposit_description text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_quote "better_supabase"."quotes";
  v_row "better_supabase"."invoices";
  v_lines jsonb;
  v_header jsonb := '{}'::jsonb;
begin
  select * into v_quote from "better_supabase"."quotes" x where x."id" = invoice_from_quote.quote;
  if v_quote."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'invoices.write'), false)) then
    raise exception 'no such quote you can invoice' using errcode = 'P0002', hint = 'INVOICE_ORIGIN_NOT_FOUND';
  end if;
  if v_quote."status" <> 'accepted' then
    raise exception 'only an accepted quote is invoiced' using errcode = '55000', hint = 'INVOICE_QUOTE_NOT_ACCEPTED';
  end if;
  if (v_quote."variant_of" is not null or exists (select 1 from "better_supabase"."quotes" s where s."variant_of" = v_quote."id"))
    and not v_quote."is_selected" then
    raise exception 'this quote is one of several variants; select a variant first' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTED';
  end if;
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    raise exception 'a deposit is between 0 and 100 percent' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is not null and invoice_from_quote.deposit_amount is not null then
    raise exception 'a deposit is a share (deposit_bps) or an amount (deposit_amount), not both' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_amount is not null and (invoice_from_quote.deposit_amount <= 0 or invoice_from_quote.deposit_amount > v_quote."total") then
    raise exception 'a deposit amount is positive and at most the quote''s total' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is null and invoice_from_quote.deposit_amount is null then
    select * into v_row from "better_supabase"."invoices" x
    where x."origin_type" = 'quote' and x."origin_id"::text = v_quote."id"::text
      and x."deposit_bps" is null and x."deposit_amount" is null and x."status" <> 'void' and x."kind" = 'invoice' and not (x."total" > 0 and x."credited_total" >= x."total")
    limit 1;
    if v_row."id" is not null then
      return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity" * coalesce(x."periods", 1), 'unitAmount', x."unit_amount"::text,
        'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
        'discountAmount', x."discount_amount", 'taxCodeId', x."tax_code_id", 'unitCost', x."unit_cost", 'costSource', x."cost_source", 'locationId', x."location_id", 'binId', x."bin_id", 'billingParty', x."billing_party", 'billingPartyId', x."billing_party_id", 'billingAccountId', x."billing_account_id",
        'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
      ) order by x."position"), '[]'::jsonb) into v_lines
    from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id" and (not x."optional" or x."selected");
    if not exists (select 1 from "better_supabase"."invoices" d where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total")) then
      v_header := jsonb_build_object('discountBps', v_quote."discount_bps", 'discountAmount', v_quote."discount_amount"::text);
    else
      select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Discount', 'quantity', 1, 'unitAmount', (-x."discount")::text,
          'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code") order by x."tax_rate_bps"), '[]'::jsonb)
        into v_lines
      from "better_supabase"."quote_tax_lines" x where x."parent_id" = v_quote."id" and x."discount" <> 0;
    end if;
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', replace(coalesce(nullif(trim(invoice_from_quote.deposit_description), ''), 'Deposit {identifier}'), '{identifier}', d."identifier"), 'quantity', 1, 'unitAmount', (-(case when d."prices_include_tax" = v_quote."prices_include_tax" then y.amount when d."prices_include_tax" then round(y.amount * 10000.0 / (10000 + y.rate))::bigint else round(y.amount * (10000 + y.rate) / 10000.0)::bigint end))::text,
        'taxRateBps', y.rate) order by d."identifier", y.rate), '[]'::jsonb)
      into v_lines
    from "better_supabase"."invoices" d
    cross join lateral (
      select dl."tax_rate_bps" as rate, sum(round(dl."quantity" * dl."unit_amount") - (round(round(dl."quantity" * dl."unit_amount") * dl."discount_bps" / 10000.0) + least(coalesce(dl."discount_amount", 0), greatest(round(dl."quantity" * dl."unit_amount") - round(round(dl."quantity" * dl."unit_amount") * dl."discount_bps" / 10000.0), 0))))::bigint as amount
      from "better_supabase"."invoice_lines" dl where dl."parent_id" = d."id" and true
      group by 1
    ) y
    where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total") and y.amount <> 0;
  elsif invoice_from_quote.deposit_amount is not null then
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', (case when v_quote."prices_include_tax" or v_quote."total" = 0 then invoice_from_quote.deposit_amount
        else round(invoice_from_quote.deposit_amount::numeric * v_quote."subtotal" / v_quote."total")::bigint end)::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', round(case when v_quote."prices_include_tax" then v_quote."total" else v_quote."subtotal" end::numeric * invoice_from_quote.deposit_bps / 10000)::bigint::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  end if;
  v_row := null;
  return "better_supabase"."create_invoice"(v_quote."tenant_id", jsonb_build_object(
    'title', v_quote."title", 'currency', v_quote."currency", 'depositBps', invoice_from_quote.deposit_bps, 'depositAmount', invoice_from_quote.deposit_amount::text, 'pricesIncludeTax', v_quote."prices_include_tax",
    'company', case when v_quote."company_id" is null then null else jsonb_build_object('type', v_quote."company_type", 'id', v_quote."company_id") end,
    'contact', case when v_quote."contact_id" is null then null else jsonb_build_object('type', v_quote."contact_type", 'id', v_quote."contact_id") end,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text)) || v_header, v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_from_sources (
  tenant      uuid,
  party       jsonb,
  source_refs jsonb,
  options     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_refs jsonb := invoice_from_sources.source_refs;
  v_options jsonb := coalesce(invoice_from_sources.options, '{}'::jsonb);
  v_cand jsonb := '[]'::jsonb;
  v_time jsonb;
  v_time_seen integer := 0;
  v_time_ids jsonb;
  v_claimed jsonb;
  v_ref jsonb;
  v_group record;
  v_group_rows jsonb;
  v_lines jsonb;
  v_attrs jsonb;
  v_company jsonb;
  v_invoice jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if better_supabase.import_run() is not null then
    raise exception 'sources are not invoiced in import mode; import the invoices instead' using errcode = '55000', hint = 'INVOICE_SOURCES_IMPORTING';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', invoice_from_sources.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(invoice_from_sources.party) is distinct from 'object' or nullif(trim(invoice_from_sources.party ->> 'type'), '') is null
    or nullif(trim(invoice_from_sources.party ->> 'id'), '') is null then
    raise exception 'party is { type, id }' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
  end if;
  if jsonb_typeof(v_refs) is distinct from 'array' or jsonb_array_length(v_refs) not between 1 and 200 then
    raise exception 'source_refs is a list of 1 to 200 sources' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
  end if;
  if jsonb_typeof(v_options) is distinct from 'object' then
    raise exception 'options is an object' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
  end if;
  for v_ref in select e.value from jsonb_array_elements(v_refs) e loop
    if jsonb_typeof(v_ref) is distinct from 'object' or (v_ref ->> 'type') is null or (v_ref ->> 'type') not in ('order', 'shipment', 'time') then
      raise exception 'each source is an object with a type of order, shipment or time' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
    end if;
    if (v_ref ->> 'type') = 'time' then
      null;
    elsif (v_ref ->> 'id') is null or (v_ref ->> 'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'an order or shipment source needs an id' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
    elsif (v_ref ->> 'type') = 'shipment' and false then
      raise exception 'this layout has no shipments with a subject to invoice' using errcode = '22023', hint = 'INVOICE_SOURCE_UNSUPPORTED';
    elsif v_ref -> 'lines' is not null and (jsonb_typeof(v_ref -> 'lines') is distinct from 'array' or (v_ref ->> 'type') <> 'order'
      or exists (select 1 from jsonb_array_elements(v_ref -> 'lines') w where jsonb_typeof(w) is distinct from 'object' or (w ->> 'id') is null
        or (w ->> 'quantity') is null or (w ->> 'quantity') !~ '^[0-9]{1,10}$' or (w ->> 'quantity')::numeric <= 0)) then
      raise exception 'lines is a list of { id, quantity } with a whole positive quantity, on an order source' using errcode = '22023', hint = 'INVOICE_SOURCE_INVALID';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('invoice_sources:' || invoice_from_sources.tenant::text, 0));
  for v_ref in select e.value from jsonb_array_elements(v_refs) e where e.value ->> 'type' in ('order', 'shipment') loop
    if (v_ref ->> 'type') = 'order' then
      if not exists (select 1 from "better_supabase"."orders" o where o."id" = (v_ref ->> 'id')::uuid and o."tenant_id" = invoice_from_sources.tenant) then
        raise exception 'no such order in this organization' using errcode = 'P0002', hint = 'INVOICE_SOURCE_NOT_FOUND';
      end if;
      if not exists (select 1 from "better_supabase"."orders" o where o."id" = (v_ref ->> 'id')::uuid and o."status" in ('confirmed', 'paid', 'fulfilled', 'completed') and o."invoiced_at" is null and o."is_selected") then
        raise exception 'an order is invoiced once it is confirmed or paid and wasn''t invoiced at checkout' using errcode = '55000', hint = 'INVOICE_SOURCE_NOT_READY';
      end if;
    else
      if not exists (select 1 from "better_supabase"."shipments" sh where sh."id" = (v_ref ->> 'id')::uuid and sh."tenant_id" = invoice_from_sources.tenant) then
        raise exception 'no such shipment in this organization' using errcode = 'P0002', hint = 'INVOICE_SOURCE_NOT_FOUND';
      end if;
      if not exists (select 1 from "better_supabase"."shipments" sh where sh."id" = (v_ref ->> 'id')::uuid
        and sh."status" = 'delivered' and sh."subject_type" = 'order') then
        raise exception 'a shipment is invoiced once it is delivered and belongs to an order' using errcode = '55000', hint = 'INVOICE_SOURCE_NOT_READY';
      end if;
      null;
    end if;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(c) order by c."sourceType", c.ref, c."sourceId", c.pos), '[]'::jsonb) into v_cand
  from (
  select r.source_type as "sourceType", r.source_id as "sourceId", r.source_line as "sourceLine", r.order_line as "orderLine",
    r.ref, r.pos, r.title || ' (' || r.ref || ')' as description, q.qty, r.avail, r.requested,
    r.unit_amount as "unitAmount",
    (round(r.discount::numeric * (r.done + q.qty) / r.order_quantity) - round(r.discount::numeric * r.done / r.order_quantity))::bigint as "discountAmount",
    case when n.net > 0 then round(r.tax * 10000.0 / n.net)::integer else 0 end as "taxRateBps",
    r.tax_code_id as "taxCodeId", r.variant, r.billing_party as "billingParty", r.billing_party_id as "billingPartyId",
    r.billing_account_id as "billingAccountId", r.unit_cost as "unitCost", r.currency, r.tax_inclusive as "taxInclusive", r.buyer
  from (
    select 'order'::text as source_type, o."id" as source_id, l."id" as source_line, l."id" as order_line,
      o."number"::text as ref, l."position" as pos, l."title" as title,
      greatest(case when l."requires_shipping" then l."quantity_fulfilled" else l."quantity" end - l."quantity_returned", 0)::numeric - d.done as avail,
      want.qty as requested, d.done, l."quantity"::numeric as order_quantity, l."unit_amount" as unit_amount,
      l."discount" as discount, l."total" as total, l."tax" as tax, o."tax_inclusive" as tax_inclusive,
      l."tax_code_id" as tax_code_id, l."variant_id" as variant,
      l."billing_party" as billing_party,
      l."billing_party_id" as billing_party_id,
      l."billing_account_id" as billing_account_id,
      l."unit_cost" as unit_cost,
      o."currency"::text as currency, o."buyer" as buyer
    from jsonb_array_elements(v_refs) r0(ref)
    join "better_supabase"."orders" o on r0.ref ->> 'type' = 'order' and o."id" = (r0.ref ->> 'id')::uuid and o."tenant_id" = invoice_from_sources.tenant and o."status" in ('confirmed', 'paid', 'fulfilled', 'completed') and o."invoiced_at" is null and o."is_selected"
    join "better_supabase"."order_lines" l on l."order_id" = o."id"
    left join lateral (select (w ->> 'quantity')::numeric as qty from jsonb_array_elements(r0.ref -> 'lines') w
      where (w ->> 'id')::uuid = l."id" limit 1) want on true
    cross join lateral (select coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
      where z."order_line_id" = l."id" and zi."status" <> 'void'), 0)::numeric as done) d
    where r0.ref -> 'lines' is null or want.qty is not null
    union all
    select 'shipment'::text, sh."id", sl."id", l."id",
      coalesce(sh."reference", sh."id"::text), l."position", l."title",
      least(sl."quantity"::numeric - coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
        where z."source" = 'shipment' and z."source_line_id" = sl."id" and zi."status" <> 'void'), 0),
        greatest(l."quantity" - l."quantity_returned", 0)::numeric - d.done),
      null::numeric, d.done, l."quantity"::numeric, l."unit_amount",
      l."discount", l."total", l."tax", o."tax_inclusive",
      l."tax_code_id", l."variant_id",
      l."billing_party",
      l."billing_party_id",
      l."billing_account_id",
      l."unit_cost",
      o."currency"::text, o."buyer"
    from jsonb_array_elements(v_refs) r0(ref)
    join "better_supabase"."shipments" sh on r0.ref ->> 'type' = 'shipment' and sh."id" = (r0.ref ->> 'id')::uuid and sh."tenant_id" = invoice_from_sources.tenant
      and sh."status" = 'delivered' and sh."subject_type" = 'order'
    join "better_supabase"."shipment_lines" sl on sl."shipment_id" = sh."id" and sl."direction" = 'outbound'
    join "better_supabase"."orders" o on o."id"::text = sh."subject_id" and o."tenant_id" = sh."tenant_id" and o."status" in ('confirmed', 'paid', 'fulfilled', 'completed') and o."invoiced_at" is null and o."is_selected"
    join lateral (select x.* from "better_supabase"."order_lines" x where x."order_id" = o."id" and x."variant_id" = sl."variant_id"
      order by x."position", x."id" limit 1) l on true
    left join lateral (select null::numeric as qty) want on true
    cross join lateral (select coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
      where z."order_line_id" = l."id" and zi."status" <> 'void'), 0)::numeric as done) d) r
  cross join lateral (select case when r.requested is null then r.avail else least(r.requested, r.avail) end as qty) q
  cross join lateral (select case when r.tax_inclusive then r.total - r.tax else r.total end as net) n
  where q.qty > 0 or r.avail <= 0 or r.requested is not null) c;
  for v_ref in select e.value from jsonb_array_elements(v_refs) e where e.value ->> 'type' = 'time' loop
    v_time := "better_supabase"."time_lines_for_invoice"(invoice_from_sources.tenant, coalesce(v_ref -> 'scope', '{}'::jsonb), coalesce(coalesce(v_ref -> 'scope', '{}'::jsonb) ->> 'groupBy', 'subject'));
    v_cand := v_cand || coalesce((select jsonb_agg(jsonb_build_object(
        'sourceType', 'time', 'sourceId', null, 'description', x.value ->> 'description', 'qty', (x.value ->> 'quantity')::numeric,
        'avail', (x.value ->> 'quantity')::numeric, 'unitAmount', (x.value ->> 'unitAmount')::bigint, 'discountAmount', 0, 'taxRateBps', 0,
        'billingParty', 'customer', 'currency', x.value ->> 'currency', 'taxInclusive', false, 'entryIds', x.value -> 'entryIds')
        order by x.ordinality) from jsonb_array_elements(v_time) with ordinality x(value, ordinality)), '[]'::jsonb);
    v_time_seen := v_time_seen + 1;
  end loop;
  if exists (select 1 from jsonb_array_elements(v_cand) e where e.value ->> 'requested' is not null
    and (e.value ->> 'requested')::numeric > (e.value ->> 'avail')::numeric and (e.value ->> 'avail')::numeric > 0) then
    raise exception 'a line is invoiced for more than is delivered and not yet invoiced' using errcode = '22023', hint = 'INVOICE_SOURCE_QUANTITY';
  end if;
  if exists (select 1 from jsonb_array_elements(v_cand) e where jsonb_typeof(e.value -> 'buyer') = 'object' and e.value -> 'buyer' ->> 'id' is not null
    and (e.value -> 'buyer' ->> 'id') is distinct from (invoice_from_sources.party ->> 'id')
    and (e.value ->> 'qty')::numeric > 0) then
    raise exception 'an order was placed by another buyer than the party' using errcode = '22023', hint = 'INVOICE_SOURCE_PARTY';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', r.value ->> 'type', 'id', r.value ->> 'id', 'reason', 'invoiced')), '[]'::jsonb) into v_skipped
  from jsonb_array_elements(v_refs) r
  where r.value ->> 'type' in ('order', 'shipment') and not exists (
    select 1 from jsonb_array_elements(v_cand) e where e.value ->> 'sourceId' = r.value ->> 'id' and (e.value ->> 'qty')::numeric > 0);
  for v_group in
    select distinct e.value ->> 'billingParty' as billing_party, e.value ->> 'billingPartyId' as billing_party_id,
      e.value ->> 'currency' as currency, (e.value ->> 'taxInclusive')::boolean as tax_inclusive
    from jsonb_array_elements(v_cand) e where (e.value ->> 'qty')::numeric > 0
    order by 1, 2 nulls first, 3, 4
  loop
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'description', e.value ->> 'description', 'quantity', (e.value ->> 'qty')::numeric,
        'unitAmount', (e.value ->> 'unitAmount'), 'discountAmount', (e.value ->> 'discountAmount'),
        'taxRateBps', (e.value ->> 'taxRateBps')::integer, 'taxCodeId', e.value ->> 'taxCodeId',
        'billingParty', e.value ->> 'billingParty', 'billingPartyId', e.value ->> 'billingPartyId',
        'billingAccountId', e.value ->> 'billingAccountId', 'unitCost', e.value ->> 'unitCost',
        'product', case when e.value ->> 'variant' is null then null else jsonb_build_object('type', 'product_variant', 'id', e.value ->> 'variant') end)) order by e.ordinality), jsonb_agg(e.value order by e.ordinality),
      coalesce(jsonb_agg(e.value -> 'entryIds') filter (where e.value ->> 'sourceType' = 'time'), '[]'::jsonb)
      into v_lines, v_group_rows, v_time_ids
    from jsonb_array_elements(v_cand) with ordinality e(value, ordinality)
    where (e.value ->> 'qty')::numeric > 0 and e.value ->> 'billingParty' = v_group.billing_party
      and e.value ->> 'billingPartyId' is not distinct from v_group.billing_party_id
      and e.value ->> 'currency' = v_group.currency and (e.value ->> 'taxInclusive')::boolean = v_group.tax_inclusive;
    select coalesce(jsonb_agg(z.id), '[]'::jsonb) into v_time_ids from (
      select distinct x.value as id from jsonb_array_elements(v_time_ids) g, jsonb_array_elements(g.value) x(value)) z;
    v_company := case when v_group.billing_party <> 'customer' and v_group.billing_party_id is not null
      then jsonb_build_object('type', invoice_from_sources.party ->> 'type', 'id', v_group.billing_party_id)
      else jsonb_build_object('type', invoice_from_sources.party ->> 'type', 'id', invoice_from_sources.party ->> 'id') end;
    v_attrs := (coalesce(v_options -> 'attrs', '{}'::jsonb) - 'origin' - 'currency' - 'company' - 'pricesIncludeTax')
      || jsonb_build_object('company', v_company, 'currency', v_group.currency,
        'title', coalesce(nullif(trim(v_options ->> 'title'), ''), nullif(trim(v_options -> 'attrs' ->> 'title'), ''), 'Delivered goods and services'))
      || case when v_group.tax_inclusive then jsonb_build_object('pricesIncludeTax', true) else '{}'::jsonb end;
    v_invoice := "better_supabase"."create_invoice"(invoice_from_sources.tenant, v_attrs, v_lines);
    insert into "better_supabase"."invoice_line_sources" ("tenant_id", "invoice_id", "position", "source", "source_id", "source_line_id", "order_line_id", "quantity")
    select invoice_from_sources.tenant, (v_invoice ->> 'id')::uuid, g.ordinality, g.value ->> 'sourceType', (g.value ->> 'sourceId')::uuid, (g.value ->> 'sourceLine')::uuid, (g.value ->> 'orderLine')::uuid, (g.value ->> 'qty')::numeric
    from jsonb_array_elements(v_group_rows) with ordinality g(value, ordinality)
    where g.value ->> 'sourceType' <> 'time';
    if jsonb_array_length(v_time_ids) > 0 then
      v_claimed := "better_supabase"."claim_time_for_invoice"(invoice_from_sources.tenant, (v_invoice ->> 'id')::uuid, v_time_ids);
      insert into "better_supabase"."invoice_line_sources" ("tenant_id", "invoice_id", "position", "source", "source_id", "quantity")
      select invoice_from_sources.tenant, (v_invoice ->> 'id')::uuid, g.ordinality, 'time', (x.value)::uuid,
        greatest(round(((c.value ->> 'seconds')::numeric) / 3600.0, 4), 0.0001)
      from jsonb_array_elements(v_group_rows) with ordinality g(value, ordinality)
      cross join lateral jsonb_array_elements_text(coalesce(g.value -> 'entryIds', '[]'::jsonb)) x(value)
      join jsonb_array_elements(v_claimed) c(value) on c.value ->> 'entryId' = x.value
      where g.value ->> 'sourceType' = 'time';
    end if;
    v_invoices := v_invoices || jsonb_build_array(v_invoice);
  end loop;
  return jsonb_build_object('invoices', v_invoices, 'skipped', v_skipped);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_order_variants (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
begin
  select * into v_order from "better_supabase"."orders" x where x."id" = list_order_variants.id;
  if not found then
    raise exception 'no such order' using errcode = 'P0002', hint = 'ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'orders.read'), false)) then
    raise exception 'not allowed to read these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'variantOf', x."variant_of", 'variantLabel', x."variant_label", 'isSelected', x."is_selected", 'total', x."total"::text, 'currency', x."currency") order by x."placed_at", x."id"), '[]'::jsonb)
    from "better_supabase"."orders" x where coalesce(x."variant_of", x."id") = coalesce(v_order."variant_of", v_order."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_quote_variants (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_from_quote (
  quote uuid,
  attrs jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_quote record;
  v_lines jsonb;
  v_attrs jsonb := coalesce(order_from_quote.attrs, '{}'::jsonb);
begin
  select * into v_quote from "better_supabase"."quotes" x where x."id" = order_from_quote.quote;
  if v_quote."id" is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'orders.manage'), false)) then
    raise exception 'no such quote you can order' using errcode = 'P0002', hint = 'ORDERS_QUOTE_NOT_FOUND';
  end if;
  if v_quote."status" <> 'accepted' then
    raise exception 'only an accepted quote becomes an order' using errcode = '55000', hint = 'ORDERS_QUOTE_NOT_ACCEPTED';
  end if;
  if (v_quote."variant_of" is not null or exists (select 1 from "better_supabase"."quotes" s where s."variant_of" = v_quote."id"))
    and not v_quote."is_selected" then
    raise exception 'this quote is one of several variants; select a variant first' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTED';
  end if;
  if exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id" and (not x."optional" or x."selected")
    and x."quantity" <> trunc(x."quantity")) then
    raise exception 'an order line is a whole quantity; the quote has a fractional one' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'variantId', cv."id", 'productId', cp."id", 'sku', coalesce(cv."sku", ''), 'title', x."description",
      'quantity', x."quantity"::integer, 'unitAmount', x."unit_amount"::text,
      'subtotal', s.subtotal::text, 'discount', s.discount::text,
      'tax', (case when v_quote."prices_include_tax" then (s.subtotal - s.discount) - round((s.subtotal - s.discount) * 10000.0 / (10000 + s.rate))
        else round((s.subtotal - s.discount) * s.rate / 10000.0) end)::bigint::text,
      'total', (s.subtotal - s.discount)::text,
      'requiresShipping', coalesce(cp."kind" = 'physical', false)) order by x."position"), '[]'::jsonb)
  into v_lines
  from "better_supabase"."quote_lines" x
  cross join lateral (select round(x."quantity" * x."unit_amount")::bigint as subtotal,
    round(round(x."quantity" * x."unit_amount") * x."discount_bps" / 10000.0)::bigint as discount,
    x."tax_rate_bps" as rate) s
  left join "better_supabase"."product_variants" cv on x."product_type"::text = 'product_variant' and x."product_id" ~* '^[0-9a-f-]{36}$' and cv."id" = x."product_id"::uuid and cv."tenant_id" = v_quote."tenant_id"
  left join "better_supabase"."products" cp on cp."id" = cv."product_id"
  where x."parent_id" = v_quote."id" and (not x."optional" or x."selected") and x."quantity" > 0;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'the quote has no lines to order' using errcode = '55000', hint = 'ORDERS_LINES_INVALID';
  end if;
  return "better_supabase"."order_from_document"(v_quote."tenant_id", v_attrs || jsonb_build_object(
    'currency', v_quote."currency", 'taxInclusive', v_quote."prices_include_tax",
    'subtotal', v_quote."list_total"::text, 'discountTotal', v_quote."discount_total"::text, 'shippingTotal', '0',
    'taxTotal', v_quote."tax_total"::text, 'total', v_quote."total"::text,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text)),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.select_order_variant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."orders" x where x."id" = select_order_variant.id;
  if not found then
    raise exception 'no such order' using errcode = 'P0002', hint = 'ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if coalesce(v_order."variant_of", v_order."id") = v_order."id" and not exists (
    select 1 from "better_supabase"."orders" s where s."variant_of" = v_order."id") then
    raise exception 'this order has no variants' using errcode = '22023', hint = 'ORDER_VARIANT_INVALID';
  end if;
  if v_order."status" in ('cancelled', 'refunded') then
    raise exception 'a cancelled or refunded order can''t be selected' using errcode = '55000', hint = 'ORDER_VARIANT_NOT_SELECTABLE';
  end if;
  perform 1 from "better_supabase"."orders" x where coalesce(x."variant_of", x."id") = coalesce(v_order."variant_of", v_order."id") order by x."id" for update;
  update "better_supabase"."orders" x set "is_selected" = (x."id" = v_order."id")
  where coalesce(x."variant_of", x."id") = coalesce(v_order."variant_of", v_order."id");
  return jsonb_build_object('order', (select jsonb_build_object('id', x."id", 'number', x."number", 'variantOf', x."variant_of", 'variantLabel', x."variant_label", 'isSelected', x."is_selected", 'total', x."total"::text, 'currency', x."currency") from "better_supabase"."orders" x where x."id" = v_order."id"),
    'variants', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'variantOf', x."variant_of", 'variantLabel', x."variant_label", 'isSelected', x."is_selected", 'total', x."total"::text, 'currency', x."currency") order by x."placed_at", x."id"), '[]'::jsonb)
      from "better_supabase"."orders" x where coalesce(x."variant_of", x."id") = coalesce(v_order."variant_of", v_order."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.select_quote_variant (
  quote   uuid,
  options jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('order', 'invoice') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward = 'order' then
    v_order := "better_supabase"."order_from_quote"(v_row."id", select_quote_variant.options -> 'attrs');
  end if;
  if v_forward = 'invoice' then
    v_invoice := "better_supabase"."invoice_from_quote"(v_row."id", (select_quote_variant.options ->> 'depositBps')::integer);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_order_variant (
  id         uuid,
  variant_of uuid,
  label      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_root record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."orders" x where x."id" = set_order_variant.id for update;
  if not found then
    raise exception 'no such order' using errcode = 'P0002', hint = 'ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if set_order_variant.variant_of is null then
    update "better_supabase"."orders" x set "variant_of" = null, "variant_label" = null, "is_selected" = true
    where x."id" = v_order."id";
  else
    select * into v_root from "better_supabase"."orders" x where x."id" = set_order_variant.variant_of for update;
    if not found or v_root."tenant_id" <> v_order."tenant_id" then
      raise exception 'no such order to group with' using errcode = 'P0002', hint = 'ORDER_NOT_FOUND';
    end if;
    if v_root."variant_of" is not null or v_root."id" = v_order."id" or exists (
      select 1 from "better_supabase"."orders" s where s."variant_of" = v_order."id") then
      raise exception 'group with the first order of a group, and not an order that has variants itself' using errcode = '22023', hint = 'ORDER_VARIANT_INVALID';
    end if;
    if v_root."currency" <> v_order."currency" then
      raise exception 'variants share one currency' using errcode = '22023', hint = 'ORDER_VARIANT_INVALID';
    end if;
    update "better_supabase"."orders" x set "variant_of" = v_root."id",
      "variant_label" = coalesce(nullif(trim(set_order_variant.label), ''), x."variant_label"),
      "is_selected" = false
    where x."id" = v_order."id";
    update "better_supabase"."orders" x set "variant_label" = coalesce(nullif(x."variant_label", ''), 'Original')
    where x."id" = v_root."id";
  end if;
  return (select jsonb_build_object('id', x."id", 'number', x."number", 'variantOf', x."variant_of", 'variantLabel', x."variant_label", 'isSelected', x."is_selected", 'total', x."total"::text, 'currency', x."currency") from "better_supabase"."orders" x where x."id" = v_order."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sources_ready_to_invoice (
  tenant uuid,
  party  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', sources_ready_to_invoice.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('type', g."sourceType", 'id', g."sourceId", 'reference', g.ref, 'currency', g.currency,
      'lines', g.lines, 'quantity', g.quantity::text, 'amount', g.amount::text) order by g."sourceType", g.ref, g."sourceId")
    from (select c."sourceType", c."sourceId", min(c.ref) as ref, min(c.currency) as currency, count(*) as lines, sum(c.qty) as quantity,
        sum(round(c.qty * c."unitAmount") - c."discountAmount")::bigint as amount
      from (
  select r.source_type as "sourceType", r.source_id as "sourceId", r.source_line as "sourceLine", r.order_line as "orderLine",
    r.ref, r.pos, r.title || ' (' || r.ref || ')' as description, q.qty, r.avail, r.requested,
    r.unit_amount as "unitAmount",
    (round(r.discount::numeric * (r.done + q.qty) / r.order_quantity) - round(r.discount::numeric * r.done / r.order_quantity))::bigint as "discountAmount",
    case when n.net > 0 then round(r.tax * 10000.0 / n.net)::integer else 0 end as "taxRateBps",
    r.tax_code_id as "taxCodeId", r.variant, r.billing_party as "billingParty", r.billing_party_id as "billingPartyId",
    r.billing_account_id as "billingAccountId", r.unit_cost as "unitCost", r.currency, r.tax_inclusive as "taxInclusive", r.buyer
  from (
    select 'order'::text as source_type, o."id" as source_id, l."id" as source_line, l."id" as order_line,
      o."number"::text as ref, l."position" as pos, l."title" as title,
      greatest(case when l."requires_shipping" then l."quantity_fulfilled" else l."quantity" end - l."quantity_returned", 0)::numeric - d.done as avail,
      want.qty as requested, d.done, l."quantity"::numeric as order_quantity, l."unit_amount" as unit_amount,
      l."discount" as discount, l."total" as total, l."tax" as tax, o."tax_inclusive" as tax_inclusive,
      l."tax_code_id" as tax_code_id, l."variant_id" as variant,
      l."billing_party" as billing_party,
      l."billing_party_id" as billing_party_id,
      l."billing_account_id" as billing_account_id,
      l."unit_cost" as unit_cost,
      o."currency"::text as currency, o."buyer" as buyer
    from "better_supabase"."orders" o
    join "better_supabase"."order_lines" l on l."order_id" = o."id"
    left join lateral (select null::numeric as qty) want on true
    cross join lateral (select coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
      where z."order_line_id" = l."id" and zi."status" <> 'void'), 0)::numeric as done) d
    where o."tenant_id" = sources_ready_to_invoice.tenant and o."status" in ('confirmed', 'paid', 'fulfilled', 'completed') and o."invoiced_at" is null and o."is_selected"
      and (sources_ready_to_invoice.party is null or (o."buyer" @> sources_ready_to_invoice.party))
    union all
    select 'shipment'::text, sh."id", sl."id", l."id",
      coalesce(sh."reference", sh."id"::text), l."position", l."title",
      least(sl."quantity"::numeric - coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
        where z."source" = 'shipment' and z."source_line_id" = sl."id" and zi."status" <> 'void'), 0),
        greatest(l."quantity" - l."quantity_returned", 0)::numeric - d.done),
      null::numeric, d.done, l."quantity"::numeric, l."unit_amount",
      l."discount", l."total", l."tax", o."tax_inclusive",
      l."tax_code_id", l."variant_id",
      l."billing_party",
      l."billing_party_id",
      l."billing_account_id",
      l."unit_cost",
      o."currency"::text, o."buyer"
    from "better_supabase"."shipments" sh
    join "better_supabase"."shipment_lines" sl on sl."shipment_id" = sh."id" and sl."direction" = 'outbound'
    join "better_supabase"."orders" o on o."id"::text = sh."subject_id" and o."tenant_id" = sh."tenant_id" and o."status" in ('confirmed', 'paid', 'fulfilled', 'completed') and o."invoiced_at" is null and o."is_selected"
    join lateral (select x.* from "better_supabase"."order_lines" x where x."order_id" = o."id" and x."variant_id" = sl."variant_id"
      order by x."position", x."id" limit 1) l on true
    left join lateral (select null::numeric as qty) want on true
    cross join lateral (select coalesce((select sum(z."quantity") from "better_supabase"."invoice_line_sources" z join "better_supabase"."invoices" zi on zi."id" = z."invoice_id"
      where z."order_line_id" = l."id" and zi."status" <> 'void'), 0)::numeric as done) d
    where sh."tenant_id" = sources_ready_to_invoice.tenant and sh."subject_type" = 'order'
      and sh."status" = 'delivered'
      and (sources_ready_to_invoice.party is null or (o."buyer" @> sources_ready_to_invoice.party))) r
  cross join lateral (select case when r.requested is null then r.avail else least(r.requested, r.avail) end as qty) q
  cross join lateral (select case when r.tax_inclusive then r.total - r.tax else r.total end as net) n
  where q.qty > 0 or r.avail <= 0 or r.requested is not null) c where c.qty > 0
      group by c."sourceType", c."sourceId") g), '[]'::jsonb)
    || coalesce((select jsonb_agg(jsonb_build_object('type', 'time', 'id', null, 'reference', x.value ->> 'description', 'currency', x.value ->> 'currency',
        'lines', 1, 'quantity', x.value ->> 'quantity', 'amount', round((x.value ->> 'quantity')::numeric * (x.value ->> 'unitAmount')::numeric)::bigint::text,
        'entryIds', x.value -> 'entryIds') order by x.ordinality)
      from jsonb_array_elements("better_supabase"."time_lines_for_invoice"(sources_ready_to_invoice.tenant, case when sources_ready_to_invoice.party is null then null else jsonb_build_object('subject', sources_ready_to_invoice.party) end, 'subject')) with ordinality x(value, ordinality)), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.time_lines_for_invoice (
  tenant   uuid,
  scope    jsonb,
  group_by text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope jsonb := coalesce(time_lines_for_invoice.scope, '{}'::jsonb);
  v_group text := coalesce(time_lines_for_invoice.group_by, 'subject');
begin
  if v_group not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity::text, 'unitAmount', l.rate::text,
      'currency', l.currency, 'entryIds', l.entry_ids) order by l.first_at)
    from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when v_group = 'entry' then min(u.user_id::text) end as user_text,
      case when v_group = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when v_group = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = time_lines_for_invoice.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when v_group in ('member', 'entry') then u.user_id end,
      case when v_group = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l), '[]'::jsonb);
end;
$function$;

ALTER TABLE "better_supabase"."invoice_line_sources"
  ADD CONSTRAINT "invoice_line_sources_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES better_supabase.invoices(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "orders_variant_label_check" CHECK ((length(variant_label) <= 200));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "orders_variant_of_fkey" FOREIGN KEY (variant_of) REFERENCES better_supabase.orders(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."quotes"
  ADD CONSTRAINT "quotes_variant_label_check" CHECK (((length(variant_label) >= 1) AND (length(variant_label) <= 100)));

CREATE INDEX invoice_line_sources_invoice_idx ON better_supabase.invoice_line_sources USING btree (invoice_id);

CREATE INDEX invoice_line_sources_line_idx ON better_supabase.invoice_line_sources USING btree (source, source_line_id)
  WHERE (source_line_id IS NOT NULL);

CREATE INDEX invoice_line_sources_order_line_idx ON better_supabase.invoice_line_sources USING btree (order_line_id)
  WHERE (order_line_id IS NOT NULL);

CREATE INDEX invoice_line_sources_source_idx ON better_supabase.invoice_line_sources USING btree (tenant_id, source, source_id);

CREATE INDEX orders_variant_idx ON better_supabase.orders USING btree (variant_of)
  WHERE (variant_of IS NOT NULL);

CREATE INDEX quotes_variant_idx ON better_supabase.quotes USING btree (variant_of)
  WHERE (variant_of IS NOT NULL);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."invoice_line_sources"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."invoice_line_sources"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."invoice_line_sources"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."invoice_line_sources"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "invoice_line_sources_read" ON "better_supabase"."invoice_line_sources"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."claim_time_for_invoice"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_time_for_invoice"(uuid, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_quote_variant"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_quote_variant"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."invoice_from_sources"(uuid, jsonb, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invoice_from_sources"(uuid, jsonb, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_order_variants"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_order_variants"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_quote_variants"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_quote_variants"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."select_order_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."select_order_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."select_quote_variant"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."select_quote_variant"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_order_variant"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_order_variant"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sources_ready_to_invoice"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sources_ready_to_invoice"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."time_lines_for_invoice"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."time_lines_for_invoice"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_time_for_invoice"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_time_for_invoice"(uuid, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_quote_variant"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_quote_variant"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invoice_from_sources"(uuid, jsonb, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invoice_from_sources"(uuid, jsonb, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_order_variants"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_order_variants"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_quote_variants"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_quote_variants"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."select_order_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."select_order_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."select_quote_variant"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."select_quote_variant"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_order_variant"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_order_variant"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sources_ready_to_invoice"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sources_ready_to_invoice"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."time_lines_for_invoice"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."time_lines_for_invoice"(uuid, jsonb, text) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."invoice_line_sources" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invoice_line_sources" TO "service_role";
