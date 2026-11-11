SET local check_function_bodies = off;

DROP FUNCTION "api"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text);

DROP FUNCTION "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text);

CREATE OR REPLACE FUNCTION api.cancel_purchase_order_quantity (
  purchase_order uuid,
  lines          jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_purchase_order_quantity"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_stock_allocation (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_stock_allocation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_purchase_order (
  tenant         uuid,
  purchase_order uuid,
  location       uuid,
  supplier_type  text,
  supplier_id    text,
  currency       text,
  expected_at    timestamp with time zone,
  lines          jsonb,
  note           text,
  number         text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_purchase_order"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.stock_allocation_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."stock_allocation_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_purchase_order (
  purchase_order uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_canceled" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.cancelled', jsonb_build_object('organizationId', v_row.tenant, 'id', cancel_purchase_order.purchase_order, 'locationId', v_row.location, 'status', 'cancelled', 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || cancel_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_purchase_order_quantity (
  purchase_order uuid,
  lines          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_received numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order_quantity.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(cancel_purchase_order_quantity.lines) is distinct from 'array' or jsonb_array_length(cancel_purchase_order_quantity.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(cancel_purchase_order_quantity.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(cancel_purchase_order_quantity.lines) e) <> jsonb_array_length(cancel_purchase_order_quantity.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant,
      y."quantity_ordered" - y."quantity_canceled" - y."quantity_received" as owed, (e ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(cancel_purchase_order_quantity.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = cancel_purchase_order_quantity.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.quantity > v_line.owed then
      raise exception 'a line would cancel more than it still owes' using errcode = '22023', hint = 'INVENTORY_OVER_CANCEL';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_canceled" = y."quantity_canceled" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_canceled" - y."quantity_received"), 0), coalesce(sum(y."quantity_received"), 0)
  into v_backordered, v_received from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = cancel_purchase_order_quantity.purchase_order;
  v_status := case when v_backordered > 0 then v_row.status when v_received > 0 then 'received' else 'cancelled' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = cancel_purchase_order_quantity.purchase_order;
  perform "better_supabase".emit_event('purchase_order.line_cancelled', jsonb_build_object('organizationId', v_row.tenant, 'id', cancel_purchase_order_quantity.purchase_order, 'locationId', v_row.location, 'status', v_status, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || cancel_purchase_order_quantity.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
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
  v_conflict_keys jsonb := '[]'::jsonb;
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
  if v_entity <> all (array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'stock_allocation', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[]) then
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
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
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
        when 'stock_allocation' then
          v_current := "better_supabase"."stock_allocation_updated_at"(v_rec."subject_id");
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
        if jsonb_array_length(v_conflict_keys) < 100 then
          v_conflict_keys := v_conflict_keys || to_jsonb(v_key);
        end if;
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
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
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
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
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

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_conflict_keys) > 0 then jsonb_build_object('conflictKeys', v_conflict_keys) else '{}'::jsonb end || case when jsonb_array_length(v_diff) > 0 then jsonb_build_object('diff', v_diff) else '{}'::jsonb end || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_entities()
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'stock_allocation', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[] $function$;

CREATE OR REPLACE FUNCTION better_supabase.import_stock_allocation (
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
  v_tenant uuid := (import_stock_allocation.item ->> 'tenant')::uuid;
  v_data jsonb := import_stock_allocation.item -> 'data';
  v_variant uuid;
  v_location uuid;
  v_quantity numeric;
  v_allocated numeric;
  v_fulfilled numeric;
  v_status text := coalesce(nullif(v_data ->> 'status', ''), 'open');
  v_row record;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_variant := nullif(v_data ->> 'variantId', '')::uuid;
    v_location := nullif(v_data ->> 'locationId', '')::uuid;
    v_quantity := (v_data ->> 'quantity')::numeric;
    v_allocated := coalesce((v_data ->> 'allocated')::numeric, 0);
    v_fulfilled := coalesce((v_data ->> 'fulfilled')::numeric, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'ids are uuids and quantity, allocated and fulfilled are numbers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_status not in ('open', 'fulfilled', 'released') then
    raise exception 'status is open, fulfilled or released' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_quantity is null or v_quantity <= 0 or v_allocated < 0 or v_fulfilled < 0 or v_allocated + v_fulfilled > v_quantity then
    raise exception 'quantity is above zero and allocated plus fulfilled isn''t more than the quantity' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'documentType', '') !~ '^[a-z][a-z0-9_]{0,62}$' or length(coalesce(v_data ->> 'documentId', '')) not between 1 and 200 then
    raise exception 'an allocation names its document type (lower case, with underscores) and its document id' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_variant is null then
    select y."id" into v_variant from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_data ->> 'sku';
  end if;
  if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" y where y."id" = v_variant and y."tenant_id" = v_tenant) then
    raise exception 'the allocation''s variant isn''t in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_location is null then
    select x."id" into v_location from "better_supabase"."inventory_locations" x where x."tenant_id" = v_tenant and x."code" = v_data ->> 'location';
  elsif not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = v_tenant) then
    v_location := null;
  end if;
  if v_location is null then
    raise exception 'the allocation''s location isn''t in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_status <> 'open' then
    v_allocated := 0;
  end if;
  if v_status = 'fulfilled' then
    v_fulfilled := v_quantity;
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, v_variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  if import_stock_allocation.subject_id is not null then
    select x."id" as id, x."variant_id" as variant, x."location_id" as location, x."allocated" as allocated,
      x."status" as status, x."updated_at" as updated_at
    into v_row from "better_supabase"."stock_allocations" x
    where x."id" = import_stock_allocation.subject_id::uuid and x."tenant_id" = v_tenant for update;
    if v_row.id is null then
      raise exception 'the stock allocation no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if v_row.status <> 'open' then
      return jsonb_build_object('subjectId', v_row.id::text, 'updatedAt', v_row.updated_at, 'warnings', jsonb_build_array(jsonb_build_object(
        'code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'a fulfilled or released stock allocation is kept as imported')));
    end if;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    update "better_supabase"."stock_allocations" x set "variant_id" = v_variant, "location_id" = v_location, "document_type" = v_data ->> 'documentType',
      "document_id" = v_data ->> 'documentId', "line_id" = nullif(v_data ->> 'lineId', ''), "quantity" = v_quantity,
      "allocated" = v_allocated, "fulfilled" = v_fulfilled, "status" = v_status, "updated_at" = now()
    where x."id" = v_row.id returning x."id", x."updated_at" into v_id, v_updated;
  else
    insert into "better_supabase"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id",
      "quantity", "allocated", "fulfilled", "status")
    values (v_tenant, v_variant, v_location, v_data ->> 'documentType', v_data ->> 'documentId', nullif(v_data ->> 'lineId', ''),
      v_quantity, v_allocated, v_fulfilled, v_status)
    returning x."id", x."updated_at" into v_id, v_updated;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + v_allocated, "updated_at" = now()
  where x."variant_id" = v_variant and x."location_id" = v_location;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_purchase_order (
  purchase_order uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.supplier_id is not null and exists (select 1 from (select p."supplier_status" from "better_supabase"."companies" p where p."id"::text = v_row.supplier_id and p."tenant_id" = v_row.tenant and p."merged_into" is null union all select p."supplier_status" from "better_supabase"."people" p where p."id"::text = v_row.supplier_id and p."tenant_id" = v_row.tenant and p."merged_into" is null) s(status) where s.status = 'blocked') then
    raise exception 'the supplier is blocked and can''t get a purchase order' using errcode = '55000', hint = 'PURCHASE_ORDER_SUPPLIER_BLOCKED';
  end if;
  select x."number" into v_number from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order;
  if v_number is null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row.tenant::text || ':inventory:purchase_order', 0));
    select (coalesce(max(case when y."number" ~ '^[0-9]{1,15}$' then y."number"::bigint end), 0) + 1)::text into v_number
    from "better_supabase"."purchase_orders" y where y."tenant_id" = v_row.tenant;
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "number" = v_number, "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.placed', jsonb_build_object('organizationId', v_row.tenant, 'id', place_purchase_order.purchase_order, 'locationId', v_row.location, 'status', 'ordered', 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || place_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
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
  set "subject_imported_updated_at" = coalesce((case x."entity" when 'organization_profile' then "better_supabase"."organization_profile_updated_at"(x."subject_id") when 'supplier_item' then "better_supabase"."supplier_item_updated_at"(x."subject_id") when 'product_identifier' then "better_supabase"."product_identifier_updated_at"(x."subject_id") when 'discount_group' then "better_supabase"."discount_group_updated_at"(x."subject_id") when 'discount_rule' then "better_supabase"."discount_rule_updated_at"(x."subject_id") when 'product' then "better_supabase"."product_updated_at"(x."subject_id") when 'product_category' then "better_supabase"."product_category_updated_at"(x."subject_id") when 'stock_count' then "better_supabase"."stock_count_updated_at"(x."subject_id") when 'stock_allocation' then "better_supabase"."stock_allocation_updated_at"(x."subject_id") when 'order' then "better_supabase"."order_updated_at"(x."subject_id") when 'payment_term' then "better_supabase"."payment_term_updated_at"(x."subject_id") when 'document_delivery_preference' then "better_supabase"."document_delivery_preference_updated_at"(x."subject_id") when 'party' then "better_supabase"."party_updated_at"(x."subject_id") when 'party_contact' then "better_supabase"."party_contact_updated_at"(x."subject_id") when 'contact_method' then "better_supabase"."contact_method_updated_at"(x."subject_id") when 'party_location' then "better_supabase"."party_location_updated_at"(x."subject_id") when 'party_bank_account' then "better_supabase"."party_bank_account_updated_at"(x."subject_id") when 'quote' then "better_supabase"."quote_updated_at"(x."subject_id") when 'invoice' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'credit_note' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'open_item' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'invoice_allocation' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'due_check' then "better_supabase"."due_check_updated_at"(x."subject_id") when 'asset' then "better_supabase"."asset_updated_at"(x."subject_id") when 'asset_identifier' then "better_supabase"."asset_identifier_updated_at"(x."subject_id") when 'tax_code' then "better_supabase"."tax_code_updated_at"(x."subject_id") when 'document_template' then "better_supabase"."document_template_updated_at"(x."subject_id") when 'document_text_block' then "better_supabase"."document_text_block_updated_at"(x."subject_id") when 'customer' then "public"."import_customer_updated_at"(x."subject_id") when 'customer_row' then "public"."import_customer_updated_at"(x."subject_id") else null end), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_purchase_order (
  purchase_order uuid,
  lines          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
  v_receipt uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  insert into "better_supabase"."inventory_receipts" ("tenant_id", "purchase_order_id", "location_id")
  values (v_row.tenant, receive_purchase_order.purchase_order, v_row.location)
  returning "id" into v_receipt;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" - y."quantity_canceled" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials', 'country', e -> 'country', 'netMassKg', e -> 'netMassKg')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
    insert into "better_supabase"."inventory_receipt_lines" ("tenant_id", "receipt_id", "purchase_order_line_id", "variant_id", "quantity", "unit_cost", "detail")
    values (v_row.tenant, v_receipt, v_line.id, v_line.variant, v_line.quantity, v_line.unit_cost, nullif(v_line.detail, '{}'::jsonb));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_canceled" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'status', v_status, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || receive_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  perform "better_supabase".emit_event('inventory_receipt.created', jsonb_build_object('organizationId', v_row.tenant, 'id', v_receipt, 'purchaseOrderId', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'inspectionId', null), 'inventory-receipts/' || v_receipt::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('status', v_status, 'backordered', v_backordered, 'receiptId', v_receipt);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_purchase_order (
  tenant         uuid,
  purchase_order uuid,
  location       uuid,
  supplier_type  text,
  supplier_id    text,
  currency       text,
  expected_at    timestamp with time zone,
  lines          jsonb,
  note           text,
  number         text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_purchase_order.purchase_order;
  v_number text := nullif(btrim(save_purchase_order.number), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.supplier_id is not null and exists (select 1 from (select p."supplier_status" from "better_supabase"."companies" p where p."id"::text = save_purchase_order.supplier_id and p."tenant_id" = save_purchase_order.tenant and p."merged_into" is null union all select p."supplier_status" from "better_supabase"."people" p where p."id"::text = save_purchase_order.supplier_id and p."tenant_id" = save_purchase_order.tenant and p."merged_into" is null) s(status) where s.status = 'blocked') then
    raise exception 'the supplier is blocked and can''t get a purchase order' using errcode = '55000', hint = 'PURCHASE_ORDER_SUPPLIER_BLOCKED';
  end if;
  if v_number is not null and length(v_number) > 50 then
    raise exception 'a purchase order number is up to 50 characters' using errcode = '22023', hint = 'INVENTORY_PURCHASE_ORDER_NUMBER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
        or (e ? 'taxRateBps' and coalesce(e ->> 'taxRateBps', '') !~ '^[0-9]{1,6}$')
        or (e ? 'taxRateBps' and coalesce(e ->> 'taxRateBps', '0') ~ '^[0-9]{1,6}$' and (e ->> 'taxRateBps')::integer > 100000)
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note", "number")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note, v_number)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "number" = coalesce(v_number, x."number"), "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost", "tax_rate_bps", "tax_code")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint, (e ->> 'taxRateBps')::integer, nullif(trim(e ->> 'taxCode'), '')
  from jsonb_array_elements(save_purchase_order.lines) e;
  delete from "better_supabase"."purchase_order_tax_lines" x where x."purchase_order_id" = v_id;
  insert into "better_supabase"."purchase_order_tax_lines" ("tenant_id", "purchase_order_id", "tax_code", "tax_rate_bps", "net", "tax", "gross")
  select save_purchase_order.tenant, v_id, g.code, g.rate, sum(g.net), sum(g.tax), sum(g.net + g.tax)
  from (
    select nullif(trim(e ->> 'taxCode'), '') as code, coalesce((e ->> 'taxRateBps')::integer, 0) as rate,
      round((e ->> 'quantity')::numeric * (e ->> 'unitCost')::bigint)::bigint as net,
      round((e ->> 'quantity')::numeric * (e ->> 'unitCost')::bigint * coalesce((e ->> 'taxRateBps')::integer, 0) / 10000.0)::bigint as tax
    from jsonb_array_elements(save_purchase_order.lines) e
  ) g
  where g.rate > 0
  group by g.code, g.rate;
  return jsonb_build_object('id', v_id, 'status', 'draft', 'number', (select x."number" from "better_supabase"."purchase_orders" x where x."id" = v_id));
exception when unique_violation then
  raise exception 'another purchase order has this number' using errcode = '23505', hint = 'INVENTORY_PURCHASE_ORDER_NUMBER_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stock_allocation_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."stock_allocations" x where x."id" = $1::uuid
$function$;

REVOKE ALL ON FUNCTION "api"."cancel_purchase_order_quantity"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_purchase_order_quantity"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_stock_allocation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_stock_allocation"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stock_allocation_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stock_allocation_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_purchase_order_quantity"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_purchase_order_quantity"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_stock_allocation"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_stock_allocation"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamp WITH time zone, jsonb, text, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stock_allocation_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stock_allocation_updated_at"(text) TO "service_role";
