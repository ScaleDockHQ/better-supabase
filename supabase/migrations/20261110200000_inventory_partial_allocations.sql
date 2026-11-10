SET local check_function_bodies = off;

DROP FUNCTION "api"."release_allocation"(uuid);

DROP FUNCTION "api"."transfer_allocation"(uuid, text, text, text);

DROP FUNCTION "better_supabase"."release_allocation"(uuid);

DROP FUNCTION "better_supabase"."transfer_allocation"(uuid, text, text, text);

CREATE OR REPLACE FUNCTION api.release_allocation (
  allocation uuid,
  quantity   numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_allocation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.transfer_allocation (
  allocation    uuid,
  document_type text,
  document_id   text,
  line_id       text    DEFAULT NULL::text,
  quantity      numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."transfer_allocation"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.release_allocation (
  allocation uuid,
  quantity   numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row record;
  v_left numeric;
  v_backorder numeric;
  v_held numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = release_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  v_left := v_row.quantity - v_row.fulfilled;
  if release_allocation.quantity is not null
    and (release_allocation.quantity <= 0 or release_allocation.quantity > v_left) then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if release_allocation.quantity is null or release_allocation.quantity = v_left then
    v_held := v_row.allocated;
    if v_held > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
  else
    v_backorder := v_left - v_row.allocated;
    v_held := greatest(release_allocation.quantity - v_backorder, 0);
    if v_held > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_held,
      "quantity" = x."quantity" - release_allocation.quantity, "updated_at" = now()
    where x."id" = v_row.id;
  end if;
  perform "better_supabase".emit_event('allocation.released', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text, 'released', coalesce(release_allocation.quantity, v_left)::text), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  if v_held > 0 then
    perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
  end if;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transfer_allocation (
  allocation    uuid,
  document_type text,
  document_id   text,
  line_id       text    DEFAULT NULL::text,
  quantity      numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row record;
  v_left numeric;
  v_held numeric;
  v_new uuid;
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
  v_left := v_row.quantity - v_row.fulfilled;
  if transfer_allocation.quantity is not null
    and (transfer_allocation.quantity <= 0 or transfer_allocation.quantity > v_left) then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if transfer_allocation.quantity is null or transfer_allocation.quantity = v_left then
    update "better_supabase"."stock_allocations" x set "document_type" = transfer_allocation.document_type, "document_id" = transfer_allocation.document_id,
      "line_id" = transfer_allocation.line_id, "updated_at" = now()
    where x."id" = v_row.id;
    v_new := v_row.id;
  else
    v_held := least(transfer_allocation.quantity, v_row.allocated);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_held,
      "quantity" = x."quantity" - transfer_allocation.quantity, "updated_at" = now()
    where x."id" = v_row.id;
    insert into "better_supabase"."stock_allocations" ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
    values (v_row.tenant, v_row.variant, v_row.location, transfer_allocation.document_type, transfer_allocation.document_id,
      transfer_allocation.line_id, transfer_allocation.quantity, v_held)
    returning "id" into v_new;
  end if;
  perform "better_supabase".emit_event('allocation.transferred', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text, 'toDocumentType', transfer_allocation.document_type, 'toDocumentId', transfer_allocation.document_id, 'transferred', coalesce(transfer_allocation.quantity, v_left)::text), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_new);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."release_allocation"(uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_allocation"(uuid, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."transfer_allocation"(uuid, text, text, text, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."transfer_allocation"(uuid, text, text, text, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_allocation"(uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_allocation"(uuid, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."transfer_allocation"(uuid, text, text, text, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transfer_allocation"(uuid, text, text, text, numeric) TO "authenticated", "service_role";
