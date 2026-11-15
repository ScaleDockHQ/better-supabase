SET local check_function_bodies = off;

DROP FUNCTION "api"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid);

DROP FUNCTION "better_supabase"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid);

ALTER TABLE "better_supabase"."bookings"
  ADD COLUMN "archived_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."invoices"
  ADD COLUMN "archived_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."shipments"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_booking"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_invoice"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_risk (
  risk_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_risk"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_shipment (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_shipment"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_bookings (
  tenant           uuid,
  range_start      timestamp with time zone,
  range_end        timestamp with time zone,
  resource         uuid                     DEFAULT NULL::uuid,
  include_archived boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bookings"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.restore_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_booking"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_invoice"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_risk (
  risk_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_risk"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_shipment (
  shipment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_shipment"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = archive_booking.booking for update;
  if not found or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_booking."archived_at" is not null then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  if v_booking."status" <> 'cancelled' and upper(v_booking."during") > now() then
    raise exception 'only a cancelled booking or one that has ended is archived' using errcode = '55000', hint = 'BOOKING_ACTIVE';
  end if;
  update "better_supabase"."bookings" bk set "archived_at" = now(), "updated_at" = now()
  where bk."id" = v_booking."id" returning * into v_booking;
  perform "better_supabase".emit_event('booking.archived', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = archive_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can archive' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return true;
  end if;
  update "better_supabase"."invoices" x set "archived_at" = now(), "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_risk (
  risk_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = archive_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false))) then
    raise exception 'not allowed to archive risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."risks" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('risk.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.archived',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'risk archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_shipment (
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = archive_shipment.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."archived_at" is not null then
    return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
  end if;
  if v_ship."status" not in ('delivered', 'returned', 'cancelled') then
    raise exception 'only a delivered, returned or cancelled shipment is archived' using errcode = '55000', hint = 'SHIPMENT_ACTIVE';
  end if;
  update "better_supabase"."shipments" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  perform "better_supabase".emit_event('shipment.archived', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.archived',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'archived shipment',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.change_booking (
  booking      uuid,
  to_status    text,
  reason       text,
  access_token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    if v_booking."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_booking."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    perform "better_supabase".emit_event('booking.cancelled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
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
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (create_shipment.subject_id)::uuid)
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
      when 'warranty_claim' then (select s."tenant_id"::text from "better_supabase"."warranty_claims" s where s."id" = (create_shipment.subject_id)::uuid)
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
      when 'advisory' then (select s."tenant_id"::text from "better_supabase"."advisories" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'advisory_product' then (select s."tenant_id"::text from "better_supabase"."advisory_products" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'vulnerability' then (select s."tenant_id"::text from "better_supabase"."vulnerabilities" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'organization' then (select s."id"::text from "public"."organizations" s where s."id" = (create_shipment.subject_id)::uuid)
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_booking_series (
  series_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', sr."id", 'organizationId', sr."tenant_id"::text, 'serviceId', sr."service_id", 'resourceId', sr."resource_id", 'rule', sr."rule", 'startsAt', sr."starts_at", 'tz', sr."tz", 'customerName', sr."customer_name", 'customerEmail', sr."customer_email", 'customerUserId', sr."customer_id", 'status', sr."status", 'endsAt', sr."ends_at", 'createdAt', sr."created_at") || jsonb_build_object('bookings', coalesce((
    select jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") order by lower(bk."during"))
    from "better_supabase"."bookings" bk where bk."series_id" = sr."id"
  ), '[]'::jsonb))
  from "better_supabase"."booking_series" sr
  where sr."id" = get_booking_series.series_id
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
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
      and x."deposit_bps" is null and x."deposit_amount" is null and x."status" <> 'void' and x."kind" = 'invoice' and x."archived_at" is null and not (x."total" > 0 and x."credited_total" >= x."total")
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
    if not exists (select 1 from "better_supabase"."invoices" d where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and d."archived_at" is null and not (d."total" > 0 and d."credited_total" >= d."total")) then
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
    where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and d."archived_at" is null and not (d."total" > 0 and d."credited_total" >= d."total") and y.amount <> 0;
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

CREATE OR REPLACE FUNCTION better_supabase.list_bookings (
  tenant           uuid,
  range_start      timestamp with time zone,
  range_end        timestamp with time zone,
  resource         uuid                     DEFAULT NULL::uuid,
  include_archived boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
    and (list_bookings.include_archived or bk."archived_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_bookings_for_customer (
  tenant    uuid,
  customer  text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.item order by z.starts desc, z.id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as item, lower(bk."during") as starts, bk."id" as id
    from "better_supabase"."bookings" bk
    where bk."tenant_id" = list_bookings_for_customer.tenant
      and bk."customer_id"::text = list_bookings_for_customer.customer
      and bk."archived_at" is null
    order by lower(bk."during") desc, bk."id" desc
    limit least(greatest(coalesce(list_bookings_for_customer.page_size, 50), 1), 200)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shipments (
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
  v_filters jsonb := coalesce(list_shipments.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 500);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_shipments.tenant, 'shipments.read'), false)) then
    raise exception 'not allowed to read shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'carrier') then
      raise exception 'facet is one of status, carrier' using errcode = '22023', hint = 'SHIPMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'carrier' then (x."carrier")::text end) as v
      from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'deliveredAt') then
    raise exception 'sort is one of createdAt, deliveredAt' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."delivered_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."delivered_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_booking (
  booking   uuid,
  starts_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."bookings"%rowtype;
  v_booking "better_supabase"."bookings"%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from "better_supabase"."bookings" bk where bk."id" = move_booking.booking for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_old."status" = 'cancelled' then
    raise exception 'a cancelled booking can''t move' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  v_booking := v_old;
  if lower(v_old."during") = move_booking.starts_at then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  v_length := upper(v_old."during") - lower(v_old."during");
  v_before := lower(v_old."during") - lower(v_old."blocked");
  v_after := upper(v_old."blocked") - upper(v_old."during");
  update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'bs:moving'
  where bk."id" = v_old."id";
  if not exists (
    select 1 from "better_supabase"."booking_slots"(v_old."service_id", move_booking.starts_at, move_booking.starts_at + v_length, null, v_old."resource_id") t
    where t.starts_at = move_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs where rs."id" = v_old."resource_id";
  for v_seat in 1..v_capacity loop
    begin
      update "better_supabase"."bookings" bk set "status" = v_old."status", "hold_expires_at" = v_old."hold_expires_at", "cancelled_at" = null, "cancel_reason" = null,
        "seat" = v_seat,
        "during" = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        "blocked" = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        "updated_at" = now()
      where bk."id" = v_old."id"
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_booking."status" = 'confirmed' then
    if v_old."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_old."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
  end if;
  perform "better_supabase".emit_event('booking.rescheduled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_booking (
  service       uuid,
  resource      uuid,
  starts_at     timestamp with time zone,
  customer      jsonb,
  confirm       boolean,
  customer_user uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  perform "better_supabase".emit_event('booking.reserved', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  if v_status = 'confirmed' then
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  if v_status = 'hold' then
    perform "better_supabase"."enqueue_job"(queue => 'bookings.expire-holds', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at") || jsonb_build_object('accessToken', v_token);
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
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
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = restore_booking.booking for update;
  if not found or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_booking."archived_at" is null then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  update "better_supabase"."bookings" bk set "archived_at" = null, "updated_at" = now()
  where bk."id" = v_booking."id" returning * into v_booking;
  perform "better_supabase".emit_event('booking.restored', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = restore_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can restore' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return true;
  end if;
  update "better_supabase"."invoices" x set "archived_at" = null, "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_risk (
  risk_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = restore_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false))) then
    raise exception 'not allowed to restore risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."risks" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('risk.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.restored',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'risk restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_shipment (
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = restore_shipment.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."archived_at" is null then
    return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
  end if;
  update "better_supabase"."shipments" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  perform "better_supabase".emit_event('shipment.restored', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.restored',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'restored shipment',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_risk"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_risk"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_shipment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_shipment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_risk"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_risk"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_shipment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_shipment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_risk"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_risk"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_shipment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_shipment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_bookings"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_risk"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_risk"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_shipment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_shipment"(uuid) TO "authenticated", "service_role";
