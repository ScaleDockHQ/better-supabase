SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.transfer_allocation (
  allocation    uuid,
  document_type text,
  document_id   text,
  line_id       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = transfer_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if transfer_allocation.document_type is null or transfer_allocation.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "document_type" = transfer_allocation.document_type, "document_id" = transfer_allocation.document_id,
    "line_id" = transfer_allocation.line_id, "updated_at" = now()
  where x."id" = v_row.id;
  perform "better_supabase".emit_event('allocation.transferred', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text, 'toDocumentType', transfer_allocation.document_type, 'toDocumentId', transfer_allocation.document_id), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$function$;
