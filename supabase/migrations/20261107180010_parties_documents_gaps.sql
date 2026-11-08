SET local check_function_bodies = off;

DROP INDEX "better_supabase"."invoices_tenant_id_direction_kind_number_key";

ALTER TABLE "better_supabase"."document_templates"
  DROP CONSTRAINT "document_templates_document_type_check";

ALTER TABLE "better_supabase"."rendered_documents"
  DROP CONSTRAINT "rendered_documents_document_type_check";

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "legal_name" text;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "registration_id" text;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "phone" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "mode" text NOT NULL DEFAULT 'external'::text;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "unit" text;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "discount_kind" text;

ALTER TABLE "better_supabase"."shipments"
  ADD COLUMN "direction" text NOT NULL DEFAULT 'outbound'::text;

ALTER TABLE "better_supabase"."quote_lines"
  ALTER COLUMN "periods" DROP NOT NULL;

CREATE OR REPLACE FUNCTION api.document_variables_purchase_order (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_purchase_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.seed_document_templates_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_document_templates_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_shipment_direction (
  shipment_id uuid,
  direction   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_shipment_direction"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_shipment (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_line record;
  v_part record;
  v_movement uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = cancel_shipment.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" not in ('draft', 'label_created') then
    raise exception 'only a draft or a shipment that hasn''t left gets cancelled' using errcode = '55000', hint = 'SHIPMENT_SHIPPED';
  end if;
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."location_id" as location, x."quantity" as quantity,
      x."detail" as detail, x."allocation_id" as allocation
    from "better_supabase"."shipment_lines" x
    where x."shipment_id" = v_ship."id" and x."direction" = 'outbound' and x."movement_id" is not null
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      if v_line.allocation is not null then
        v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."restore_allocation"(v_line.allocation, v_part.quantity, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      else
        perform "better_supabase"."move_stock"(v_ship."tenant_id", v_line.variant, v_line.location, v_part.quantity, 'return', 'shipment', v_ship."id"::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
      end if;
    end loop;
    update "better_supabase"."shipment_lines" x set "movement_id" = null, "moved_at" = null where x."id" = v_line.id;
  end loop;
  update "better_supabase"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  perform "better_supabase".emit_event('shipment.cancelled', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.cancelled',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'cancelled shipment',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'trackingNumber', v_ship."tracking_number")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
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
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
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
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
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
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods", "unit", "discount_kind")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods", x."unit", x."discount_kind" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
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
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (create_shipment.subject_id)::uuid)
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_quote (
  quote    uuid,
  decision text,
  note     text,
  by       text,
  selected jsonb DEFAULT NULL::jsonb,
  actor    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_template_contract (
  document_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_all constant jsonb := '{"invoice":{"version":1,"documentType":"invoice","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"credit_note":{"version":1,"documentType":"credit_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"},{"path":"document.originalNumber","type":"string"}]},"quote":{"version":1,"documentType":"quote","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.validUntil","type":"date"},{"path":"document.revision","type":"number"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"order":{"version":1,"documentType":"order","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"dunning_letter":{"version":1,"documentType":"dunning_letter","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"document.level","type":"number"},{"path":"document.textKey","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"delivery_note":{"version":1,"documentType":"delivery_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"statement":{"version":1,"documentType":"statement","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"purchase_order":{"version":1,"documentType":"purchase_order","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]}}'::jsonb;
begin
  if document_template_contract.document_type is null then
    return v_all;
  end if;
  if not v_all ? document_template_contract.document_type then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement, purchase_order' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return v_all -> document_template_contract.document_type;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  case document_variables.document_type
    when 'invoice' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, false);
    when 'credit_note' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, true);
    when 'quote' then return "better_supabase"."document_variables_quote"(document_variables.tenant, document_id);
    when 'order' then return "better_supabase"."document_variables_order"(document_variables.tenant, document_id);
    when 'delivery_note' then return "better_supabase"."document_variables_delivery_note"(document_variables.tenant, document_id);
    when 'purchase_order' then return "better_supabase"."document_variables_purchase_order"(document_variables.tenant, document_id);
    when 'dunning_letter' then return "better_supabase"."document_variables_dunning_letter"(document_variables.tenant, document_id);
    when 'statement' then return "better_supabase"."document_variables_statement"(document_variables.tenant, document_id);
    else
      raise exception 'unknown document type' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_purchase_order (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."purchase_orders"%rowtype;
  v_lines jsonb;
  v_subtotal bigint;
begin
  select * into v_row from "better_supabase"."purchase_orders" x
    where x."id" = document_variables_purchase_order.document_id and x."tenant_id" = document_variables_purchase_order.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', n.sku,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', trim_scale((n.quantity)::numeric)::text,
      'unitAmount', (n.unit_cost)::bigint::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', (n.amount)::bigint::text
    ) order by n.n), '[]'::jsonb), coalesce(sum(n.amount), 0)::bigint into v_lines, v_subtotal
  from (
    select row_number() over (order by cv."sku", x."id") as n,
      coalesce(cv."title", cv."sku") as description,
      cv."sku" as sku,
      x."quantity_ordered" as quantity,
      x."unit_cost" as unit_cost,
      round(x."quantity_ordered" * x."unit_cost")::bigint as amount
    from "better_supabase"."purchase_order_lines" x
    join "better_supabase"."product_variants" cv on cv."id" = x."variant_id"
    where x."purchase_order_id" = v_row."id"
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'purchase_order', 'number', 'PO-' || upper(substr(replace(v_row."id"::text, '-', ''), 1, 8)), 'title', null::text, 'status', v_row."status"::text, 'date', to_char(coalesce(v_row."placed_at", v_row."created_at") at time zone 'UTC', 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', v_row."note", 'reference', null::text),
    'entity', "better_supabase"."document_entity"(document_variables_purchase_order.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_purchase_order.tenant, case when v_row."supplier_type" = 'company' then v_row."supplier_id" end, case when v_row."supplier_type" = 'person' then v_row."supplier_id" end, null::jsonb, null::text, null::jsonb),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', v_subtotal::text, 'taxTotal', null::text, 'total', v_subtotal::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', null::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text),
    'shipping', jsonb_build_object('address', "better_supabase"."document_address"(v_row."ship_to"), 'carrier', null::text, 'trackingNumber', null::text)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_visible (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  case document_visible.document_type
    when 'invoice', 'credit_note' then
      return exists (select 1 from "better_supabase"."invoices" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'quote' then
      return exists (select 1 from "better_supabase"."quotes" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'order' then
      return exists (select 1 from "better_supabase"."orders" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'delivery_note' then
      return exists (select 1 from "better_supabase"."shipments" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'purchase_order' then
      return exists (select 1 from "better_supabase"."purchase_orders" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'dunning_letter' then
      return exists (select 1 from "better_supabase"."invoice_dunning_run_items" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    else
      return false;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.freeze_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', freeze_document.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if freeze_document.document_type is null or freeze_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement', 'purchase_order') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement, purchase_order' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return "better_supabase"."document_freeze"(freeze_document.tenant, freeze_document.document_type, freeze_document.document_id, freeze_document.language, freeze_document.template_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shipment (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = get_shipment.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shipments (
  tenant       uuid,
  status       text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  carrier      text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_shipments.tenant, 'shipments.read'), false)) then
    raise exception 'not allowed to read shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as item, x."created_at" as created, x."id" as id
      from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (list_shipments.status is null or x."status" = list_shipments.status)
        and (list_shipments.subject_type is null or (x."subject_type" = list_shipments.subject_type and x."subject_id" = list_shipments.subject_id))
        and (list_shipments.carrier is null or x."carrier" = list_shipments.carrier)
        and (list_shipments.before is null or x."created_at" < list_shipments.before)
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_shipments.page_size, 50), 1), 500)
    ) z
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_companies (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."companies";
  v_drop "better_supabase"."companies";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."companies" x where x."id" = merge_companies.keep for update;
  select * into v_drop from "better_supabase"."companies" x where x."id" = merge_companies.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "legal_name" = coalesce(x."legal_name", v_drop."legal_name"), "registration_id" = coalesce(x."registration_id", v_drop."registration_id"), "phone" = coalesce(x."phone", v_drop."phone"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  update "better_supabase"."companies" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_companies.keep;
  perform better_supabase.merge_subject_refs('better_supabase.companies', merge_companies.keep::text, merge_companies.drop::text);
  perform "better_supabase".emit_event('company.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop), 'companies/' || merge_companies.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.merged',
    category => 'data',
    target_type => 'company',
    record_id => merge_companies.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.portal_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and ((x."status" <> 'draft' and (((x."tenant_id")::text, ('quote')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or ((x."tenant_id")::text, (x."company_type")::text, (x."company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or ((x."tenant_id")::text, (x."contact_type")::text, (x."contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.viewed', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.public_quote (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.viewed', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.quote_from_deal (
  deal uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal "better_supabase"."deals";
  v_row "better_supabase"."quotes";
  v_contact record;
  v_lines jsonb;
begin
  select * into v_deal from "better_supabase"."deals" x where x."id" = quote_from_deal.deal;
  if v_deal."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_deal."tenant_id", 'quotes.write'), false)) then
    raise exception 'no such deal you can quote' using errcode = 'P0002', hint = 'QUOTE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."quotes" x
  where x."origin_type" = 'deal' and x."origin_id" = v_deal."id"::text
  order by x."created_at" limit 1;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  select x."contact_type" as type, x."contact_id" as id into v_contact
  from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal."id" order by x."is_primary" desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity", 'unitAmount', x."unit_amount"::text,
      'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
      'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
    ) order by x."position"), '[]'::jsonb) into v_lines
  from "better_supabase"."deal_lines" x where x."parent_id" = v_deal."id";
  if jsonb_array_length(v_lines) = 0 and v_deal."amount" > 0 then
    v_lines := jsonb_build_array(jsonb_build_object('description', v_deal."name", 'quantity', 1, 'unitAmount', v_deal."amount"::text));
  end if;
  return "better_supabase"."create_quote"(v_deal."tenant_id", jsonb_build_object(
    'title', v_deal."name", 'currency', v_deal."currency", 'ownerId', v_deal."owner_user_id",
    'company', case when v_deal."company_id" is null then null else jsonb_build_object('type', v_deal."company_type", 'id', v_deal."company_id") end,
    'contact', case when v_contact.id is null then null else jsonb_build_object('type', v_contact.type, 'id', v_contact.id) end,
    'origin', jsonb_build_object('type', 'deal', 'id', v_deal."id"::text)), v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_shipment_return (
  shipment_id uuid,
  lines       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_item jsonb;
  v_detail jsonb;
  v_movement uuid;
  v_quantity numeric := 0;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = receive_shipment_return.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" in ('draft', 'cancelled') then
    raise exception 'only a shipment that left takes returns' using errcode = '55000', hint = 'SHIPMENT_NOT_SHIPPED';
  end if;
  if jsonb_typeof(receive_shipment_return.lines) is distinct from 'array' or jsonb_array_length(receive_shipment_return.lines) > 500 or exists (
    select 1 from jsonb_array_elements(receive_shipment_return.lines) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' or coalesce(e ->> 'locationId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
      or (e ? 'detail' and jsonb_typeof(e -> 'detail') <> 'object') or coalesce(e ->> 'disposition', '') not in ('restock', 'hold', 'scrap')
  ) then
    raise exception 'each line needs a variantId, a locationId and a positive quantity and a disposition of restock, hold or scrap' using errcode = '22023', hint = 'SHIPMENT_LINES_INVALID';
  end if;
  if jsonb_array_length(receive_shipment_return.lines) = 0 then
    raise exception 'each line needs a variantId, a locationId and a positive quantity' using errcode = '22023', hint = 'SHIPMENT_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(receive_shipment_return.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = v_ship."tenant_id")
      or not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = (e ->> 'locationId')::uuid and x."tenant_id" = v_ship."tenant_id")
  ) then
    raise exception 'a line names a variant or location outside this organization' using errcode = 'P0002', hint = 'SHIPMENT_LINE_NOT_FOUND';
  end if;
  if exists (
    select 1 from (
      select (e ->> 'variantId')::uuid as variant, sum((e ->> 'quantity')::numeric) as quantity
      from jsonb_array_elements(receive_shipment_return.lines) e group by 1
    ) r
    where r.quantity > coalesce((select sum(case when x."direction" = 'outbound' then x."quantity" else -x."quantity" end)
      from "better_supabase"."shipment_lines" x where x."shipment_id" = v_ship."id" and x."variant_id" = r.variant
        and (x."direction" = 'return' or x."movement_id" is not null)), 0)
  ) then
    raise exception 'a variant comes back at most as often as the shipment carried it out' using errcode = '22023', hint = 'SHIPMENT_RETURN_EXCEEDS';
  end if;
  for v_item in select e from jsonb_array_elements(receive_shipment_return.lines) e
  loop
    v_detail := case when jsonb_typeof(v_item -> 'detail') = 'object' then v_item -> 'detail' end;
    if v_item ->> 'disposition' = 'hold' and not exists (
      select 1 from "better_supabase"."stock_bins" y
      where y."id"::text = v_detail ->> 'binId' and y."location_id" = (v_item ->> 'locationId')::uuid and y."hold"
    ) then
      raise exception 'a held return goes into a hold bin at its location: pass detail.binId' using errcode = '22023', hint = 'SHIPMENT_HOLD_BIN_REQUIRED';
    end if;
    v_movement := "better_supabase"."move_stock"(v_ship."tenant_id", (v_item ->> 'variantId')::uuid, (v_item ->> 'locationId')::uuid, (v_item ->> 'quantity')::numeric, 'return', 'shipment', v_ship."id"::text, null, v_detail);
    if v_item ->> 'disposition' = 'scrap' then
      v_movement := "better_supabase"."move_stock"(v_ship."tenant_id", (v_item ->> 'variantId')::uuid, (v_item ->> 'locationId')::uuid, -(v_item ->> 'quantity')::numeric, 'scrap', 'shipment', v_ship."id"::text, null, v_detail);
    end if;
    v_count := v_count + 1;
    insert into "better_supabase"."shipment_lines" ("tenant_id", "shipment_id", "position", "direction", "variant_id", "location_id", "quantity", "detail", "disposition", "movement_id", "moved_at")
    values (v_ship."tenant_id", v_ship."id", coalesce((select max(z."position") from "better_supabase"."shipment_lines" z where z."shipment_id" = v_ship."id"), 0) + 1, 'return', (v_item ->> 'variantId')::uuid, (v_item ->> 'locationId')::uuid,
      (v_item ->> 'quantity')::numeric, v_detail, v_item ->> 'disposition', v_movement, now());
    v_quantity := v_quantity + (v_item ->> 'quantity')::numeric;
  end loop;
  perform "better_supabase".emit_event('shipment.return_received', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'lines', v_count, 'quantity', v_quantity::text), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.return_received',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'received a shipment return',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'lines', v_count, 'quantity', v_quantity::text)
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_delivery_proof (
  shipment_id     uuid,
  delivered_to    text,
  proof_reference text DEFAULT NULL::text,
  attachment_id   uuid DEFAULT NULL::uuid
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
  select * into v_ship from "better_supabase"."shipments" x where x."id" = record_delivery_proof.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'delivered' then
    raise exception 'proof can only be recorded for a delivered shipment' using errcode = '55000', hint = 'SHIPMENT_NOT_DELIVERED';
  end if;
  if record_delivery_proof.delivered_to is null or length(btrim(record_delivery_proof.delivered_to)) not between 1 and 500 then
    raise exception 'delivered_to needs 1 to 500 characters' using errcode = '22023', hint = 'SHIPMENT_PROOF_INVALID';
  end if;
  if v_ship."proof_recorded_at" is not null then
    raise exception 'the proof of delivery is already recorded' using errcode = '55000', hint = 'SHIPMENT_PROOF_RECORDED';
  end if;
  update "better_supabase"."shipments" x set
      "delivered_to" = btrim(record_delivery_proof.delivered_to),
      "proof_reference" = record_delivery_proof.proof_reference,
      "proof_attachment_id" = record_delivery_proof.attachment_id,
      "proof_recorded_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  perform "better_supabase".emit_event('shipment.proof_recorded', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'deliveredTo', v_ship."delivered_to"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.proof_recorded',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'recorded proof of delivery',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'deliveredTo', v_ship."delivered_to")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_tracking_events (
  shipment_id uuid,
  events      jsonb,
  source      text  DEFAULT 'manual'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = record_tracking_events.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."tracking_number" is null then
    raise exception 'a shipment gets tracking events once it has a label' using errcode = '55000', hint = 'SHIPMENT_NOT_LABELED';
  end if;
  if record_tracking_events.source is null or record_tracking_events.source not in ('carrier', 'manual') then
    raise exception 'the source is carrier or manual' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  if jsonb_typeof(record_tracking_events.events) is distinct from 'array' or jsonb_array_length(record_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), record_tracking_events.source
      from jsonb_array_elements(record_tracking_events.events) i
      on conflict ("shipment_id", "external_id") do nothing
      returning 1
    )
    select count(*)::integer into v_count from inserted;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'each tracking event needs an id, a known status and an ISO 8601 occurredAt' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end;
  select t."status", t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    perform "better_supabase".emit_event('shipment.status_changed', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'from', v_from, 'to', v_ship."status", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.render_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text    DEFAULT NULL::text,
  fresh         boolean DEFAULT false,
  template_name text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."rendered_documents"%rowtype;
begin
  if render_document.document_type is null or render_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement', 'purchase_order') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement, purchase_order' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if not coalesce(render_document.fresh, false) then
    select * into v_row from "better_supabase"."rendered_documents" s
      where s."tenant_id" = render_document.tenant
        and s."document_type" = render_document.document_type
        and s."document_id" = render_document.document_id;
    if found then
      return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
    end if;
  end if;
  return "better_supabase"."document_render_live"(render_document.tenant, render_document.document_type, render_document.document_id, render_document.language, render_document.template_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revise_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
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
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('quote.revised', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_company (
  tenant  uuid,
  company uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_company.company;
  v_created boolean := save_company.company is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_company.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'customerTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditBlock' is not null and lower(trim(save_company.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'language' is not null and nullif(trim(save_company.attrs ->> 'language'), '') is not null and trim(save_company.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_company_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_company.tenant, save_company.company, save_company.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_company.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "legal_name", "registration_id", "phone", "lifecycle", "owner_user_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), nullif(trim(save_company.attrs ->> 'legalName'), ''), nullif(trim(save_company.attrs ->> 'registrationId'), ''), nullif(trim(save_company.attrs ->> 'phone'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(save_company.attrs ->> 'customerTermsId', '')::uuid, nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')), nullif(trim(save_company.attrs ->> 'language'), ''), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "legal_name" = case when save_company.attrs ? 'legalName' then nullif(trim(save_company.attrs ->> 'legalName'), '') else x."legal_name" end,
        "registration_id" = case when save_company.attrs ? 'registrationId' then nullif(trim(save_company.attrs ->> 'registrationId'), '') else x."registration_id" end,
        "phone" = case when save_company.attrs ? 'phone' then nullif(trim(save_company.attrs ->> 'phone'), '') else x."phone" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "customer_terms_id" = case when save_company.attrs ? 'customerTermsId' then nullif(save_company.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_company.attrs ? 'supplierTermsId' then nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_company.attrs ? 'creditBlock' then lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_company.attrs ? 'language' then nullif(trim(save_company.attrs ->> 'language'), '') else x."language" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_company.tenant, v_owner, 'company', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_company_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_template (
  tenant          uuid,
  document_type   text,
  body            text,
  language        text    DEFAULT NULL::text,
  name            text    DEFAULT 'default'::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active          boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_templates"%rowtype;
  v_language text := lower(nullif(btrim(save_document_template.language), ''));
  v_name text := coalesce(nullif(btrim(save_document_template.name), ''), 'default');
  v_active boolean := coalesce(save_document_template.active, true);
  v_changed boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_document_template.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if save_document_template.document_type is null or save_document_template.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement', 'purchase_order') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement, purchase_order' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if v_name !~ '^[a-z][a-z0-9_-]{0,63}$' then
    raise exception 'a template name is lower case letters, digits, _ and -, from a letter, up to 64 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.body is null or length(btrim(save_document_template.body)) = 0 or length(save_document_template.body) > 200000 then
    raise exception 'a template body is 1 to 200000 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.legal_entity_id is not null then
    perform "better_supabase"."legal_entity_of"(save_document_template.tenant, save_document_template.legal_entity_id);
  end if;
  perform "better_supabase"."assert_document_template"(save_document_template.document_type, save_document_template.body);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_template_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_template.tenant, save_document_template.document_type;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_templates:' || save_document_template.tenant::text, 0));
  select * into v_row from "better_supabase"."document_templates" t
    where t."tenant_id" = save_document_template.tenant
      and t."document_type" = save_document_template.document_type
      and t."name" = v_name
      and t."legal_entity_id" is not distinct from save_document_template.legal_entity_id
      and t."language" is not distinct from v_language;
  if found then
    v_changed := v_row."body" <> save_document_template.body;
    if not v_changed and v_row."active" = v_active then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_templates" t set
      "body" = save_document_template.body,
      "version" = t."version" + case when v_changed then 1 else 0 end,
      "active" = v_active,
      "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.updated',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'updated ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  else
    insert into "better_supabase"."document_templates" ("tenant_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
    values (save_document_template.tenant, save_document_template.legal_entity_id, save_document_template.document_type, v_language, v_name, save_document_template.body, v_active)
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.created', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.created',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'created ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_person (
  tenant uuid,
  person uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_person.person;
  v_created boolean := save_person.person is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_person.attrs ? 'mode' and coalesce(lower(trim(save_person.attrs ->> 'mode')), '') not in ('external', 'tenant') then
    raise exception 'a person is external or tenant' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if v_created and lower(trim(save_person.attrs ->> 'mode')) = 'tenant' and nullif(save_person.attrs ->> 'userId', '') is null then
    raise exception 'a tenant person needs a userId' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if save_person.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'customerTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditBlock' is not null and lower(trim(save_person.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'language' is not null and nullif(trim(save_person.attrs ->> 'language'), '') is not null and trim(save_person.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_person_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_person.tenant, save_person.person, save_person.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_person.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "mode", "lifecycle", "owner_user_id", "user_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), 'external'), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(save_person.attrs ->> 'customerTermsId', '')::uuid, nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')), nullif(trim(save_person.attrs ->> 'language'), ''), auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "mode" = case when save_person.attrs ? 'mode' then coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), x."mode") else x."mode" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "customer_terms_id" = case when save_person.attrs ? 'customerTermsId' then nullif(save_person.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_person.attrs ? 'supplierTermsId' then nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_person.attrs ? 'creditBlock' then lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_person.attrs ? 'language' then nullif(trim(save_person.attrs ->> 'language'), '') else x."language" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_person.tenant, v_owner, 'person', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_person_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
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
  perform "better_supabase"."seed_document_templates_defaults"(p_tenant, p_variants ->> 'document-templates', p_locale);
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
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested') or v_row."status" in ('rejected', 'withdrawn', 'expired')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "valid_until" = case when x."status" in ('rejected', 'withdrawn', 'expired') then greatest(x."valid_until", current_date + 30) else x."valid_until" end, "viewed_at" = case when x."status" in ('rejected', 'withdrawn', 'expired') then null else x."viewed_at" end, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  perform "better_supabase".emit_event('quote.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_quote_lines (
  parent uuid,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "unit", "discount_kind", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      coalesce(x.value ->> 'description', (select coalesce(v."title", (select p."title" from "better_supabase"."products" p where p."id" = v."product_id")) from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
      coalesce((x.value ->> 'quantity')::numeric, 1),
      coalesce((x.value ->> 'unitAmount')::bigint, (select ("better_supabase"."variant_price"(v."id", v_currency) ->> 'amount')::bigint from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      nullif(x.value ->> 'taxCodeId', '')::uuid,
      (x.value ->> 'unitCost')::bigint,
      coalesce((x.value ->> 'discountAmount')::bigint, 0),
      nullif(x.value ->> 'costSource', ''),
      nullif(x.value ->> 'locationId', '')::uuid,
      nullif(x.value ->> 'binId', '')::uuid,
      coalesce(nullif(x.value ->> 'billingParty', ''), 'customer'),
      nullif(x.value ->> 'billingPartyId', ''),
      nullif(x.value ->> 'billingAccountId', '')::uuid,
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      case when x.value ? 'periods' then (x.value ->> 'periods')::integer else 1 end,
      case when x.value ? 'unit' then nullif(trim(x.value ->> 'unit'), '') else better_supabase.column_default('"better_supabase"."quote_lines"', 'unit', (null::"better_supabase"."quote_lines")."unit") end,
      case when x.value ? 'discountKind' then nullif(x.value ->> 'discountKind', '') else better_supabase.column_default('"better_supabase"."quote_lines"', 'discount_kind', (null::"better_supabase"."quote_lines")."discount_kind") end,
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_shipment_direction (
  shipment_id uuid,
  direction   text
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
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_direction.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if set_shipment_direction.direction is null or set_shipment_direction.direction not in ('outbound', 'inbound') then
    raise exception 'a shipment is outbound or inbound' using errcode = '22023', hint = 'SHIPMENT_DIRECTION_INVALID';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft changes direction' using errcode = '55000', hint = 'SHIPMENT_SHIPPED';
  end if;
  update "better_supabase"."shipments" x set "direction" = set_shipment_direction.direction, "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_shipment_label (
  shipment_id     uuid,
  carrier         text,
  service         text,
  tracking_number text,
  label_id        text,
  label_cost      bigint,
  currency        text,
  label_format    text   DEFAULT 'pdf'::text,
  label_url       text   DEFAULT NULL::text,
  tracking_url    text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
  v_line record;
  v_part record;
  v_movement uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_label.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft shipment gets a label' using errcode = '55000', hint = 'SHIPMENT_NOT_DRAFT';
  end if;
  begin
    update "better_supabase"."shipments" x set
      "carrier" = set_shipment_label.carrier,
      "service" = set_shipment_label.service,
      "tracking_number" = set_shipment_label.tracking_number,
      "tracking_url" = set_shipment_label.tracking_url,
      "label_id" = set_shipment_label.label_id,
      "label_url" = set_shipment_label.label_url,
      "label_format" = coalesce(set_shipment_label.label_format, 'pdf'),
      "label_cost" = set_shipment_label.label_cost,
      "currency" = set_shipment_label.currency,
      "labeled_at" = now(),
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
  exception
    when unique_violation then
      raise exception 'another shipment has this carrier and tracking number' using errcode = '23505', hint = 'SHIPMENT_TRACKING_TAKEN';
    when check_violation or not_null_violation then
      raise exception 'a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency' using errcode = '22023', hint = 'SHIPMENT_LABEL_INVALID';
  end;
  if v_ship."carrier" is null or v_ship."service" is null or v_ship."tracking_number" is null or v_ship."label_id" is null or v_ship."label_cost" is null then
    raise exception 'a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency' using errcode = '22023', hint = 'SHIPMENT_LABEL_INVALID';
  end if;
  if not better_supabase.import_run() is not null then
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."location_id" as location, x."quantity" as quantity,
      x."detail" as detail, x."allocation_id" as allocation
    from "better_supabase"."shipment_lines" x
    where x."shipment_id" = v_ship."id" and x."direction" = 'outbound' and x."movement_id" is null
    order by x."position"
  loop
    if v_line.allocation is not null then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_movement := ("better_supabase"."fulfill_allocation"(v_line.allocation, v_line.quantity, v_line.detail) ->> 'movementId')::uuid;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    else
      v_movement := "better_supabase"."move_stock"(v_ship."tenant_id", v_line.variant, v_line.location, -v_line.quantity, 'sale', 'shipment', v_ship."id"::text, null, v_line.detail);
    end if;
    update "better_supabase"."shipment_lines" x set "movement_id" = v_movement, "moved_at" = now(),
      "detail" = jsonb_strip_nulls(coalesce(v_line.detail, '{}'::jsonb) || jsonb_build_object('parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."id" = v_line.id;
  end loop;
  end if;
  insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  perform "better_supabase".emit_event('shipment.labeled', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.labeled',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'bought shipping label',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number")
  );
  select t."status", t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    perform "better_supabase".emit_event('shipment.status_changed', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'from', v_from, 'to', v_ship."status", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_shipment_lines (
  shipment_id uuid,
  lines       jsonb
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
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_lines.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft shipment changes its lines' using errcode = '55000', hint = 'SHIPMENT_NOT_DRAFT';
  end if;
  if jsonb_typeof(set_shipment_lines.lines) is distinct from 'array' or jsonb_array_length(set_shipment_lines.lines) > 500 or exists (
    select 1 from jsonb_array_elements(set_shipment_lines.lines) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' or coalesce(e ->> 'locationId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
      or (e ? 'detail' and jsonb_typeof(e -> 'detail') <> 'object') or (e ? 'allocationId' and coalesce(e ->> 'allocationId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
  ) then
    raise exception 'each line needs a variantId, a locationId and a positive quantity' using errcode = '22023', hint = 'SHIPMENT_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(set_shipment_lines.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = v_ship."tenant_id")
      or not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = (e ->> 'locationId')::uuid and x."tenant_id" = v_ship."tenant_id")
  ) then
    raise exception 'a line names a variant or location outside this organization' using errcode = 'P0002', hint = 'SHIPMENT_LINE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(set_shipment_lines.lines) e
    where e ? 'allocationId' and not exists (
      select 1 from "better_supabase"."stock_allocations" y
      where y."id"::text = e ->> 'allocationId' and y."tenant_id" = v_ship."tenant_id"
        and y."variant_id" = (e ->> 'variantId')::uuid and y."location_id" = (e ->> 'locationId')::uuid and y."status" = 'open')
  ) then
    raise exception 'an allocation must be open and hold the line''s variant at its location' using errcode = '22023', hint = 'SHIPMENT_ALLOCATION_INVALID';
  end if;
  delete from "better_supabase"."shipment_lines" x where x."shipment_id" = v_ship."id" and x."direction" = 'outbound';
  insert into "better_supabase"."shipment_lines" ("tenant_id", "shipment_id", "position", "direction", "variant_id", "location_id", "quantity", "allocation_id", "detail")
  select v_ship."tenant_id", v_ship."id", coalesce((select max(z."position") from "better_supabase"."shipment_lines" z where z."shipment_id" = v_ship."id"), 0) + e.n, 'outbound', (e.l ->> 'variantId')::uuid, (e.l ->> 'locationId')::uuid,
    (e.l ->> 'quantity')::numeric, nullif(e.l ->> 'allocationId', '')::uuid, case when jsonb_typeof(e.l -> 'detail') = 'object' then e.l -> 'detail' end
  from jsonb_array_elements(set_shipment_lines.lines) with ordinality e(l, n);
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
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
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'company' ->> 'type', 'company'), (update_quote.attrs -> 'company' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
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
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('quote.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.withdraw_quote (
  quote  uuid,
  actor  jsonb DEFAULT NULL::jsonb,
  reason text  DEFAULT NULL::text
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
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('quote.withdrawn', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "bsb_companies_legal_name" CHECK (((length(legal_name) >= 1) AND (length(legal_name) <= 300)));

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "bsb_companies_registration_id" CHECK (((length(registration_id) >= 1) AND (length(registration_id) <= 100)));

ALTER TABLE "better_supabase"."document_templates"
  ADD CONSTRAINT "document_templates_document_type_check"
    CHECK
    ((document_type = ANY (ARRAY['invoice'::text, 'credit_note'::text, 'quote'::text, 'order'::text, 'dunning_letter'::text, 'delivery_note'::text, 'statement'::text,
    'purchase_order'::text])));

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "bsb_people_mode" CHECK (((mode = ANY (ARRAY['external'::text, 'tenant'::text])) AND ((mode = 'external'::text) OR (user_id IS NOT NULL))));

ALTER TABLE "better_supabase"."quote_lines"
  ADD CONSTRAINT "bsb_quote_lines_discount_kind" CHECK ((discount_kind = ANY (ARRAY['percentage'::text, 'fixed'::text])));

ALTER TABLE "better_supabase"."quote_lines"
  ADD CONSTRAINT "bsb_quote_lines_unit" CHECK (((length(unit) >= 1) AND (length(unit) <= 40)));

ALTER TABLE "better_supabase"."rendered_documents"
  ADD CONSTRAINT "rendered_documents_document_type_check"
    CHECK
    ((document_type = ANY (ARRAY['invoice'::text, 'credit_note'::text, 'quote'::text, 'order'::text, 'dunning_letter'::text, 'delivery_note'::text, 'statement'::text,
    'purchase_order'::text])));

ALTER TABLE "better_supabase"."shipments"
  ADD CONSTRAINT "bsb_shipments_direction" CHECK ((direction = ANY (ARRAY['outbound'::text, 'inbound'::text])));

CREATE UNIQUE INDEX invoices_tenant_id_direction_kind_identifier_key ON better_supabase.invoices
  USING btree (tenant_id, direction, kind, identifier, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));

REVOKE ALL ON FUNCTION "api"."document_variables_purchase_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_purchase_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."seed_document_templates_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_document_templates_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_shipment_direction"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_shipment_direction"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_purchase_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_purchase_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_document_templates_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_document_templates_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_shipment_direction"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_shipment_direction"(uuid, text) TO "authenticated", "service_role";
