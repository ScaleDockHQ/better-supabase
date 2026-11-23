SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."order_fulfillment_lines"
  DROP CONSTRAINT "bsb_order_fulfillment_lines_quantity_check";

ALTER TABLE "better_supabase"."order_lines"
  DROP CONSTRAINT "bsb_order_lines_check1";

ALTER TABLE "better_supabase"."order_lines"
  DROP CONSTRAINT "bsb_order_lines_check";

ALTER TABLE "better_supabase"."order_lines"
  DROP CONSTRAINT "bsb_order_lines_quantity_check";

ALTER TABLE "better_supabase"."order_return_lines"
  DROP CONSTRAINT "bsb_order_return_lines_quantity_check";

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "unit" text;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "description" text;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "line_type" text NOT NULL DEFAULT 'item'::text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "channel" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "source" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "external_id" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "invoicing_policy" text NOT NULL DEFAULT 'on_order'::text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "delivery_method" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "quote_id" uuid;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "order_discount" bigint NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "promotion_id" uuid;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "payment_required" boolean NOT NULL DEFAULT false;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "deposit_amount" bigint;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "party_type" text;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "party_id" text;

ALTER TABLE "better_supabase"."order_fulfillment_lines"
  ALTER COLUMN "quantity" DROP DEFAULT;

ALTER TABLE "better_supabase"."order_fulfillment_lines"
  ALTER COLUMN "quantity" TYPE numeric(18,0) USING "quantity"::numeric(18,0);

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_fulfilled" DROP DEFAULT;

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_fulfilled" TYPE numeric(18,0) USING "quantity_fulfilled"::numeric(18,0);

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_fulfilled" SET DEFAULT 0;

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_returned" DROP DEFAULT;

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_returned" TYPE numeric(18,0) USING "quantity_returned"::numeric(18,0);

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity_returned" SET DEFAULT 0;

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity" DROP DEFAULT;

ALTER TABLE "better_supabase"."order_lines"
  ALTER COLUMN "quantity" TYPE numeric(18,0) USING "quantity"::numeric(18,0);

ALTER TABLE "better_supabase"."order_return_lines"
  ALTER COLUMN "quantity" DROP DEFAULT;

ALTER TABLE "better_supabase"."order_return_lines"
  ALTER COLUMN "quantity" TYPE numeric(18,0) USING "quantity"::numeric(18,0);

CREATE OR REPLACE FUNCTION api.page_orders (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_orders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_fulfillment (
  order_id        uuid,
  lines           jsonb DEFAULT NULL::jsonb,
  location        uuid  DEFAULT NULL::uuid,
  carrier         text  DEFAULT NULL::text,
  tracking_number text  DEFAULT NULL::text,
  tracking_url    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_item record;
  v_requested jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = create_fulfillment.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status::text not in ('paid', 'confirmed') then
    raise exception 'only a paid or confirmed order can be fulfilled' using errcode = '55000', hint = 'ORDERS_NOT_PAID';
  end if;
  if exists (select 1 from "better_supabase"."orders" x where x."id" = v_order.id and x."payment_required"
    and x."paid_total" < coalesce(x."deposit_amount", x."total")) then
    raise exception 'the order ships once its deposit, or its total without one, is paid' using errcode = '55000', hint = 'ORDERS_PAYMENT_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_fulfillment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  v_requested := coalesce(create_fulfillment.lines, (
    select jsonb_agg(jsonb_build_object('lineId', l."id", 'quantity', l."quantity" - l."quantity_fulfilled") order by l."position")
    from "better_supabase"."order_lines" l where l."order_id" = v_order.id and l."quantity" > l."quantity_fulfilled"));
  if v_requested is null or jsonb_typeof(v_requested) <> 'array' or jsonb_array_length(v_requested) = 0 then
    raise exception 'no lines left to fulfill' using errcode = '55000', hint = 'ORDERS_NOTHING_TO_FULFILL';
  end if;
  insert into "better_supabase"."order_fulfillments" ("tenant_id", "order_id", "location_id", "carrier", "tracking_number", "tracking_url")
  values (v_order.tenant, v_order.id,
    coalesce(create_fulfillment.location, (select l."location_id" from "better_supabase"."order_lines" l where l."order_id" = v_order.id and l."location_id" is not null order by l."position" limit 1)),
    create_fulfillment.carrier, create_fulfillment.tracking_number, create_fulfillment.tracking_url)
  returning "id" into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, case when (case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,12}$' then (e ->> 'quantity')::numeric > 0 else false end) then (e ->> 'quantity')::numeric end as quantity,
      case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end as detail
    from jsonb_array_elements(v_requested) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    update "better_supabase"."order_lines" x set "quantity_fulfilled" = x."quantity_fulfilled" + v_item.quantity
    where x."id" = v_item.line and x."order_id" = v_order.id and x."quantity_fulfilled" + v_item.quantity <= x."quantity";
    if not found then
      raise exception 'a line isn''t on this order or has less left to fulfill' using errcode = '22023', hint = 'ORDERS_FULFILLMENT_INVALID';
    end if;
    insert into "better_supabase"."order_fulfillment_lines" as x ("tenant_id", "fulfillment_id", "order_line_id", "quantity", "detail")
    values (v_order.tenant, v_id, v_item.line, v_item.quantity, v_item.detail)
    on conflict ("fulfillment_id", "order_line_id") do update set "quantity" = x."quantity" + excluded."quantity",
      "detail" = coalesce(excluded."detail", x."detail");
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_fulfillment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'pending');
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
        select v_tenant, v_id, e.n::integer, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, coalesce(e.l ->> 'sku', ''), e.l ->> 'title', (e.l ->> 'quantity')::numeric, (e.l ->> 'unitAmount')::bigint, coalesce((e.l ->> 'subtotal')::bigint, round((e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::numeric)::bigint), coalesce((e.l ->> 'discount')::bigint, 0), coalesce((e.l ->> 'tax')::bigint, 0), coalesce((e.l ->> 'total')::bigint, round((e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::numeric)::bigint - coalesce((e.l ->> 'discount')::bigint, 0)), coalesce((e.l ->> 'requiresShipping')::boolean, false), nullif(e.l ->> 'locationId', '')::uuid, nullif(e.l ->> 'taxCodeId', '')::uuid, (e.l ->> 'unitCost')::bigint, nullif(e.l ->> 'costSource', ''), nullif(e.l ->> 'binId', '')::uuid, coalesce(nullif(e.l ->> 'billingParty', ''), 'customer'), nullif(e.l ->> 'billingPartyId', ''), nullif(e.l ->> 'billingAccountId', '')::uuid
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
    where coalesce(l.value ->> 'title', '') = '' or not (case when coalesce(l.value ->> 'quantity', '') ~ '^[0-9]{1,12}$' then (l.value ->> 'quantity')::numeric > 0 else false end) or coalesce(l.value ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
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

  select coalesce(sum(round((l.value ->> 'unitAmount')::bigint * (l.value ->> 'quantity')::numeric)::bigint), 0),
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
  select v_tenant, v_id, e.n::integer, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, coalesce(e.l ->> 'sku', ''), e.l ->> 'title', (e.l ->> 'quantity')::numeric, (e.l ->> 'unitAmount')::bigint, coalesce((e.l ->> 'subtotal')::bigint, round((e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::numeric)::bigint), coalesce((e.l ->> 'discount')::bigint, 0), coalesce((e.l ->> 'tax')::bigint, 0), coalesce((e.l ->> 'total')::bigint, round((e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::numeric)::bigint - coalesce((e.l ->> 'discount')::bigint, 0)), coalesce((e.l ->> 'requiresShipping')::boolean, false), nullif(e.l ->> 'locationId', '')::uuid, nullif(e.l ->> 'taxCodeId', '')::uuid, (e.l ->> 'unitCost')::bigint, nullif(e.l ->> 'costSource', ''), nullif(e.l ->> 'binId', '')::uuid, coalesce(nullif(e.l ->> 'billingParty', ''), 'customer'), nullif(e.l ->> 'billingPartyId', ''), nullif(e.l ->> 'billingAccountId', '')::uuid
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

CREATE OR REPLACE FUNCTION better_supabase.order_from_document (
  p_tenant   uuid,
  p_attrs    jsonb,
  p_lines    jsonb,
  p_location uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_line record;
  v_allocation jsonb;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_claims text;
begin
  if p_attrs -> 'origin' is not null then
    select x."id" into v_id from "better_supabase"."orders" x
    where x."tenant_id" = p_tenant and x."origin_type" = p_attrs #>> '{origin,type}' and x."origin_id" = p_attrs #>> '{origin,id}'
      and x."status" <> 'cancelled'
    limit 1;
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if nullif(p_attrs ->> 'externalId', '') is not null then
    select x."id" into v_id from "better_supabase"."orders" x
    where x."tenant_id" = p_tenant and x."source" = p_attrs ->> 'source' and x."external_id" = p_attrs ->> 'externalId';
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = p_tenant;
  v_number := v_seq::text;
  end if;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "customer_id", "email", "status", "currency",
    "subtotal", "discount_total", "shipping_total", "tax_total", "total", "tax_inclusive",
    "shipping_address", "billing_address", "origin_type", "origin_id", "channel", "source", "external_id", "invoicing_policy", "delivery_method", "quote_id", "order_discount", "promotion_id", "payment_required", "deposit_amount", "party_type", "party_id")
  values (p_tenant, v_number, v_seq, nullif(p_attrs ->> 'customerId', '')::uuid, p_attrs ->> 'email', case when coalesce((p_attrs ->> 'draft')::boolean, false) then 'draft' else 'confirmed' end, p_attrs ->> 'currency',
    (p_attrs ->> 'subtotal')::bigint, (p_attrs ->> 'discountTotal')::bigint, (p_attrs ->> 'shippingTotal')::bigint,
    (p_attrs ->> 'taxTotal')::bigint, (p_attrs ->> 'total')::bigint, coalesce((p_attrs ->> 'taxInclusive')::boolean, false),
    p_attrs -> 'shippingAddress', p_attrs -> 'billingAddress', p_attrs #>> '{origin,type}', p_attrs #>> '{origin,id}', nullif(p_attrs ->> 'channel', ''), nullif(p_attrs ->> 'source', ''), nullif(p_attrs ->> 'externalId', ''), coalesce(nullif(p_attrs ->> 'invoicingPolicy', ''), 'on_order'), nullif(p_attrs ->> 'deliveryMethod', ''), nullif(p_attrs ->> 'quoteId', '')::uuid, coalesce((p_attrs ->> 'orderDiscount')::bigint, 0), nullif(p_attrs ->> 'promotionId', '')::uuid, coalesce((p_attrs ->> 'paymentRequired')::boolean, false), nullif(p_attrs ->> 'deposit', '')::bigint, nullif(p_attrs #>> '{party,type}', ''), nullif(p_attrs #>> '{party,id}', ''))
  returning "id" into v_id;
  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title",
    "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping", "unit", "description", "line_type")
  select p_tenant, v_id, e.n, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::numeric, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    (e.l ->> 'tax')::bigint, (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean, nullif(e.l ->> 'unit', ''), nullif(e.l ->> 'description', ''), coalesce(nullif(e.l ->> 'lineType', ''), 'item')
  from jsonb_array_elements(p_lines) with ordinality as e(l, n);
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id;
  if not coalesce((p_attrs ->> 'draft')::boolean, false) then
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."quantity" as quantity, cv."allow_backorder" as backorder
    from "better_supabase"."order_lines" x join "better_supabase"."product_variants" cv on cv."id" = x."variant_id"
    where x."order_id" = v_order.id and cv."track_inventory"
    order by x."position"
  loop
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_allocation := "better_supabase"."allocate_stock"(v_order.tenant, v_line.variant, p_location, v_line.quantity::numeric, 'order', v_order.id::text, v_line.id::text, v_line.backorder);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    update "better_supabase"."order_lines" x set "location_id" = (v_allocation ->> 'locationId')::uuid,
      "backordered" = (v_allocation ->> 'backordered')::numeric > 0
    where x."id" = v_line.id;
  end loop;
  end if;
  if coalesce((p_attrs ->> 'draft')::boolean, false) then
    perform "better_supabase".emit_event('order.drafted', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id)), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  else
    perform "better_supabase".emit_event('order.placed', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'subtotal', (p_attrs ->> 'subtotal'), 'discountTotal', (p_attrs ->> 'discountTotal'), 'shippingTotal', (p_attrs ->> 'shippingTotal'), 'taxTotal', (p_attrs ->> 'taxTotal'), 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id)), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  end if;
  return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', true);
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
  v_order_discount bigint;
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
  if (v_attrs ? 'orderDiscount' and coalesce(v_attrs ->> 'orderDiscount', '') !~ '^[0-9]{1,18}$') or (v_attrs ? 'deposit' and coalesce(v_attrs ->> 'deposit', '') !~ '^[0-9]{1,18}$') then
    raise exception 'amounts are minor units of zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  if nullif(v_attrs ->> 'externalId', '') is not null and nullif(v_attrs ->> 'source', '') is null then
    raise exception 'attrs.externalId needs attrs.source, the system the id comes from' using errcode = '22023', hint = 'ORDERS_SOURCE_REQUIRED';
  end if;
  if v_attrs -> 'party' is not null and (nullif(v_attrs #>> '{party,type}', '') is null or nullif(v_attrs #>> '{party,id}', '') is null) then
    raise exception 'attrs.party is { type, id }' using errcode = '22023', hint = 'ORDERS_PARTY_INVALID';
  end if;
  v_order_discount := coalesce(case when coalesce(v_attrs ->> 'orderDiscount', '') ~ '^[0-9]{1,18}$' then (v_attrs ->> 'orderDiscount')::bigint end, 0);
  for v_item in
    select e as raw, nullif(e ->> 'variantId', '')::uuid as variant, e ->> 'quantity' as quantity,
      cv."id" as found, cv."tenant_id" as variant_tenant, cv."sku" as sku, concat_ws(' / ', cp."title", nullif(cv."title", '')) as title, cp."id" as product, cp."kind" as kind
    from jsonb_array_elements(order_from_lines.lines) e
    left join "better_supabase"."product_variants" cv on cv."id" = nullif(e ->> 'variantId', '')::uuid
    left join "better_supabase"."products" cp on cp."id" = cv."product_id"
  loop
    if not (case when coalesce(v_item.quantity, '') ~ '^[0-9]{1,12}$' then (v_item.quantity)::numeric > 0 else false end) then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    if coalesce(v_item.raw ->> 'lineType', 'item') not in ('item', 'service', 'fee') then
      raise exception 'a line''s lineType is one of item, service, fee' using errcode = '22023', hint = 'ORDERS_LINES_INVALID';
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
      case when v_rule is not null and not v_item.raw ? 'discount' then round(round(v_unit * v_item.quantity::numeric)::bigint * (v_rule ->> 'discountBps')::integer / 10000.0)::bigint end, 0);
    if v_disc > round(v_unit * v_item.quantity::numeric)::bigint then
      raise exception 'a line''s discount is more than its subtotal' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'variantId', v_item.variant, 'productId', v_item.product,
      'sku', coalesce(v_item.raw ->> 'sku', v_item.sku, ''), 'title', coalesce(nullif(v_item.raw ->> 'title', ''), v_item.title),
      'quantity', v_item.quantity, 'unitAmount', v_unit::text, 'subtotal', (round(v_unit * v_item.quantity::numeric)::bigint)::text,
      'discount', v_disc::text, 'tax', coalesce(case when coalesce(v_item.raw ->> 'tax', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'tax')::bigint end, 0)::text,
      'total', (round(v_unit * v_item.quantity::numeric)::bigint - v_disc)::text,
      'requiresShipping', case when v_item.variant is null then coalesce((v_item.raw ->> 'requiresShipping')::boolean, false) else v_item.kind = 'physical' end)
      || jsonb_strip_nulls(jsonb_build_object('unit', v_item.raw -> 'unit', 'description', v_item.raw -> 'description',
        'lineType', v_item.raw -> 'lineType', 'fields', v_item.raw -> 'fields')));
    v_subtotal := v_subtotal + round(v_unit * v_item.quantity::numeric)::bigint;
    v_discount := v_discount + v_disc;
    v_tax := v_tax + coalesce(case when coalesce(v_item.raw ->> 'tax', '') ~ '^[0-9]{1,18}$' then (v_item.raw ->> 'tax')::bigint end, 0);
  end loop;
  if v_order_discount > v_subtotal - v_discount then
    raise exception 'attrs.orderDiscount is more than the lines'' net subtotal' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  v_discount := v_discount + v_order_discount;
  return "better_supabase"."order_from_document"(order_from_lines.tenant, v_attrs || jsonb_build_object(
    'subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'shippingTotal', v_shipping::text, 'taxTotal', v_tax::text,
    'total', (v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end)::text),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
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
  if (v_attrs ? 'orderDiscount' and coalesce(v_attrs ->> 'orderDiscount', '') !~ '^[0-9]{1,18}$') or (v_attrs ? 'deposit' and coalesce(v_attrs ->> 'deposit', '') !~ '^[0-9]{1,18}$') then
    raise exception 'amounts are minor units of zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  if nullif(v_attrs ->> 'externalId', '') is not null and nullif(v_attrs ->> 'source', '') is null then
    raise exception 'attrs.externalId needs attrs.source, the system the id comes from' using errcode = '22023', hint = 'ORDERS_SOURCE_REQUIRED';
  end if;
  if v_attrs -> 'party' is not null and (nullif(v_attrs #>> '{party,type}', '') is null or nullif(v_attrs #>> '{party,id}', '') is null) then
    raise exception 'attrs.party is { type, id }' using errcode = '22023', hint = 'ORDERS_PARTY_INVALID';
  end if;
  if v_attrs ? 'orderDiscount' then
    raise exception 'an order from a quote takes the quote''s discounts, not attrs.orderDiscount' using errcode = '22023', hint = 'ORDERS_FIELD_UNSUPPORTED';
  end if;
  if (v_quote."variant_of" is not null or exists (select 1 from "better_supabase"."quotes" s where s."variant_of" = v_quote."id"))
    and not v_quote."is_selected" then
    raise exception 'this quote is one of several variants; select a variant first' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTED';
  end if;
  if exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id" and (not x."optional" or x."selected")
    and x."quantity" <> round(x."quantity", 0)) then
    raise exception 'an order line has at most 0 decimals (options.quantityScale); the quote has a line with more' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'variantId', cv."id", 'productId', cp."id", 'sku', coalesce(cv."sku", ''), 'title', x."description",
      'quantity', x."quantity", 'unitAmount', x."unit_amount"::text,
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
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text), 'quoteId', v_quote."id"),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_json (
  p_order uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'cartId', x."cart_id",
    'customerId', x."customer_id", 'email', x."email", 'status', x."status", 'currency', x."currency",
    'subtotal', x."subtotal"::text, 'discountTotal', x."discount_total"::text,
    'shippingTotal', x."shipping_total"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'paidTotal', x."paid_total"::text, 'refundedTotal', x."refunded_total"::text, 'taxInclusive', x."tax_inclusive",
    'shippingAddress', x."shipping_address", 'billingAddress', x."billing_address", 'shipping', x."shipping",
    'promotions', x."promotions", 'tax', x."tax", 'taxTransaction', x."tax_transaction",
    'invoiceNumber', x."invoice_number", 'invoicedAt', x."invoiced_at", 'placedAt', x."placed_at",
    'paidAt', x."paid_at", 'fulfilledAt', x."fulfilled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason",
    'heldAt', x."held_at", 'holdReason', x."hold_reason",
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l."id", 'variantId', l."variant_id", 'productId', l."product_id", 'sku', l."sku",
        'title', l."title", 'quantity', l."quantity", 'unitAmount', l."unit_amount"::text,
        'subtotal', l."subtotal"::text, 'discount', l."discount"::text, 'tax', l."tax"::text,
        'total', l."total"::text, 'requiresShipping', l."requires_shipping", 'locationId', l."location_id",
        'reservationId', l."reservation_id", 'fulfilled', l."quantity_fulfilled", 'returned', l."quantity_returned",
        'backordered', l."backordered", 'unit', l."unit", 'description', l."description", 'lineType', l."line_type") order by l."position")
      from "better_supabase"."order_lines" l where l."order_id" = x."id"), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'provider', y."provider", 'reference', y."reference", 'status', y."status",
        'amount', y."amount"::text, 'captured', y."captured"::text, 'refunded', y."refunded"::text,
        'createdAt', y."created_at") order by y."created_at")
      from "better_supabase"."order_payments" y where y."order_id" = x."id"), '[]'::jsonb),
    'fulfillments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'status', y."status", 'locationId', y."location_id", 'carrier', y."carrier",
        'trackingNumber', y."tracking_number", 'trackingUrl', y."tracking_url", 'createdAt', y."created_at",
        'shippedAt', y."shipped_at", 'deliveredAt', y."delivered_at",
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z."order_line_id", 'quantity', z."quantity"))
          from "better_supabase"."order_fulfillment_lines" z where z."fulfillment_id" = y."id"), '[]'::jsonb)) order by y."created_at")
      from "better_supabase"."order_fulfillments" y where y."order_id" = x."id"), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'status', y."status", 'reason', y."reason", 'createdAt', y."created_at",
        'receivedAt', y."received_at",
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z."order_line_id", 'quantity', z."quantity"))
          from "better_supabase"."order_return_lines" z where z."return_id" = y."id"), '[]'::jsonb)) order by y."created_at")
      from "better_supabase"."order_returns" y where y."order_id" = x."id"), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'paymentId', y."payment_id", 'returnId', y."return_id", 'amount', y."amount"::text,
        'status', y."status", 'reason', y."reason", 'providerReference', y."provider_reference",
        'createdAt', y."created_at", 'completedAt', y."completed_at") order by y."created_at")
      from "better_supabase"."order_refunds" y where y."order_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text)
  from "better_supabase"."orders" x where x."id" = p_order
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_orders (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_orders.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency', 'channel') then
      raise exception 'facet is one of status, currency, channel' using errcode = '22023', hint = 'ORDERS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'currency' then (x."currency")::text when 'channel' then (x."channel")::text end) as v
      from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
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
      select 1 from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('placedAt', 'number', 'total') then
    raise exception 'sort is one of placedAt, number, total' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."placed_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."placed_at" >= (v_after ->> 0)::timestamptz and ((x."placed_at" > (v_after ->> 0)::timestamptz) or (x."placed_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."placed_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."placed_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."placed_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."placed_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'placedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."placed_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."placed_at" >= (v_after ->> 0)::timestamptz and ((x."placed_at" > (v_after ->> 0)::timestamptz) or (x."placed_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."placed_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'placedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."placed_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."placed_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."placed_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."sequence" >= (v_after ->> 0)::bigint and ((x."sequence" > (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" < (v_after ->> 1)::uuid))))
      order by x."sequence" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."sequence", x."id") < ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."total")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."total" >= (v_after ->> 0)::bigint and ((x."total" > (v_after ->> 0)::bigint) or (x."total" = (v_after ->> 0)::bigint and x."id" < (v_after ->> 1)::uuid))))
      order by x."total" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ORDERS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'number', x."number", 'status', x."status",
      'customerId', x."customer_id", 'currency', x."currency", 'total', x."total"::text,
      'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") || jsonb_build_object('party', case when x."party_id" is not null then jsonb_build_object('type', x."party_type", 'id', x."party_id") end, 'channel', x."channel", 'source', x."source", 'externalId', x."external_id", 'invoicingPolicy', x."invoicing_policy", 'deliveryMethod', x."delivery_method", 'quoteId', x."quote_id", 'orderDiscount', x."order_discount"::text, 'promotionId', x."promotion_id", 'paymentRequired', x."payment_required", 'deposit', x."deposit_amount"::text) as j, jsonb_build_array((x."total")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
        and (v_after is null or (x."total", x."id") < ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."total" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."orders" x
      where x."tenant_id" = page_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or x."customer_id" = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::uuid[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or (x."party_id")::text = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or (x."channel")::text = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (x."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."placed_at" >= (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."placed_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or x."number" ilike v_search or x."email" ilike v_search or x."external_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_return (
  order_id uuid,
  lines    jsonb,
  reason   text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_item record;
  v_id uuid;
  v_open integer;
  v_units integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = request_return.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(v_order.customer = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to return this order' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status not in ('paid', 'fulfilled', 'completed') then
    raise exception 'only a paid order can be returned' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  if request_return.lines is null or jsonb_typeof(request_return.lines) <> 'array' or jsonb_array_length(request_return.lines) = 0 then
    raise exception 'lines is a non-empty array of {lineId, quantity}' using errcode = '22023', hint = 'ORDERS_RETURN_INVALID';
  end if;
  insert into "better_supabase"."order_returns" ("tenant_id", "order_id", "reason")
  values (v_order.tenant, v_order.id, request_return.reason)
  returning "id" into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, case when (case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,12}$' then (e ->> 'quantity')::numeric > 0 else false end) then (e ->> 'quantity')::numeric end as quantity from jsonb_array_elements(request_return.lines) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    select coalesce(sum(y."quantity"), 0) into v_open
    from "better_supabase"."order_return_lines" y join "better_supabase"."order_returns" z on z."id" = y."return_id"
    where y."order_line_id" = v_item.line and z."status" = 'requested';
    if not exists (select 1 from "better_supabase"."order_lines" l where l."id" = v_item.line and l."order_id" = v_order.id
      and l."quantity_fulfilled" - l."quantity_returned" - v_open >= v_item.quantity) then
      raise exception 'a line isn''t on this order or has fewer fulfilled units left to return' using errcode = '22023', hint = 'ORDERS_RETURN_INVALID';
    end if;
    insert into "better_supabase"."order_return_lines" as x ("tenant_id", "return_id", "order_line_id", "quantity")
    values (v_order.tenant, v_id, v_item.line, v_item.quantity)
    on conflict ("return_id", "order_line_id") do update set "quantity" = x."quantity" + excluded."quantity";
    v_units := v_units + v_item.quantity;
  end loop;
  perform "better_supabase".emit_event('return.requested', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_id, 'orderId', v_order.id, 'number', v_order.number, 'quantity', v_units::text, 'reason', request_return.reason), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'requested', 'quantity', v_units);
end;
$function$;

ALTER TABLE "better_supabase"."order_fulfillment_lines"
  ADD CONSTRAINT "bsb_order_fulfillment_lines_quantity_check" CHECK ((quantity > (0)::numeric));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_check1" CHECK (((quantity_returned >= (0)::numeric) AND (quantity_returned <= quantity)));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_check" CHECK (((quantity_fulfilled >= (0)::numeric) AND (quantity_fulfilled <= quantity)));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_description_check" CHECK ((length(description) <= 4000));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_line_type_check" CHECK ((line_type = ANY (ARRAY['item'::text, 'service'::text, 'fee'::text])));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_quantity_check" CHECK ((quantity > (0)::numeric));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "bsb_order_lines_unit_check" CHECK (((length(unit) >= 1) AND (length(unit) <= 32)));

ALTER TABLE "better_supabase"."order_return_lines"
  ADD CONSTRAINT "bsb_order_return_lines_quantity_check" CHECK ((quantity > (0)::numeric));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_channel_check" CHECK ((channel ~ '^[a-z][a-z0-9_]{0,62}$'::text));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_delivery_method_check" CHECK ((delivery_method ~ '^[a-z][a-z0-9_]{0,62}$'::text));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_deposit_amount_check" CHECK ((deposit_amount >= 0));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 200)));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_external_source_check" CHECK (((external_id IS NULL) OR (source IS NOT NULL)));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_invoicing_policy_check" CHECK ((invoicing_policy = ANY (ARRAY['on_order'::text, 'on_delivery'::text])));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_order_discount_check" CHECK ((order_discount >= 0));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_party_id_check" CHECK (((length(party_id) >= 1) AND (length(party_id) <= 200)));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_party_pair_check" CHECK (((party_type IS NULL) = (party_id IS NULL)));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_party_type_check" CHECK ((party_type ~ '^[a-z][a-z0-9_]{0,62}$'::text));

ALTER TABLE "better_supabase"."orders"
  ADD CONSTRAINT "bsb_orders_source_check" CHECK ((source ~ '^[a-z][a-z0-9_]{0,62}$'::text));

CREATE INDEX orders_channel_idx ON better_supabase.orders USING btree (tenant_id, channel, placed_at);

CREATE UNIQUE INDEX orders_external_idx ON better_supabase.orders USING btree (tenant_id, source, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX orders_party_idx ON better_supabase.orders USING btree (tenant_id, party_type, party_id)
  WHERE (party_id IS NOT NULL);

CREATE INDEX orders_quote_idx ON better_supabase.orders USING btree (quote_id)
  WHERE (quote_id IS NOT NULL);

REVOKE ALL ON FUNCTION "api"."page_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_orders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_orders"(uuid, jsonb) TO "authenticated", "service_role";
