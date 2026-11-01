SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."intrastat_lines"
  DROP CONSTRAINT "intrastat_lines_source_check";

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD COLUMN "receipt_line_id" uuid;

CREATE OR REPLACE FUNCTION api.legal_entities_disable_check (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."legal_entities_disable_check"($1) $function$;

CREATE OR REPLACE FUNCTION api.recompute_invoice_totals (
  tenant      uuid,
  invoice_ids uuid[]  DEFAULT NULL::uuid[],
  dry_run     boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."recompute_invoice_totals"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_invoices_entity_numbers()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_default uuid;
begin
  select e."id" into v_default from "better_supabase"."legal_entities" e where e."tenant_id" = new."tenant_id" and e."is_default";
  if new.legal_entity_id is not null and new.legal_entity_id is distinct from v_default then
    return new;
  end if;
  if new."number" is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || 'invoices' || ':' || new."tenant_id"::text || ':number:' || new."number"::text, 0));
    if exists (
      select 1 from "better_supabase"."invoices" x
      where x."tenant_id" = new."tenant_id" and x."number" = new."number" and x."id" <> new."id" and x."direction" is not distinct from new."direction" and x."kind" is not distinct from new."kind"
        and (x.legal_entity_id is null or x.legal_entity_id = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', 'invoices', 'number', new."number"
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;
  if new."identifier" is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || 'invoices' || ':' || new."tenant_id"::text || ':identifier:' || new."identifier"::text, 0));
    if exists (
      select 1 from "better_supabase"."invoices" x
      where x."tenant_id" = new."tenant_id" and x."identifier" = new."identifier" and x."id" <> new."id" and x."direction" is not distinct from new."direction" and x."kind" is not distinct from new."kind"
        and (x.legal_entity_id is null or x.legal_entity_id = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', 'invoices', 'identifier', new."identifier"
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_orders_entity_numbers()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_default uuid;
begin
  select e."id" into v_default from "better_supabase"."legal_entities" e where e."tenant_id" = new."tenant_id" and e."is_default";
  if new.legal_entity_id is not null and new.legal_entity_id is distinct from v_default then
    return new;
  end if;
  if new."number" is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || 'orders' || ':' || new."tenant_id"::text || ':number:' || new."number"::text, 0));
    if exists (
      select 1 from "better_supabase"."orders" x
      where x."tenant_id" = new."tenant_id" and x."number" = new."number" and x."id" <> new."id"
        and (x.legal_entity_id is null or x.legal_entity_id = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', 'orders', 'number', new."number"
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;
  if new."invoice_number" is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || 'orders' || ':' || new."tenant_id"::text || ':invoiceNumber:' || new."invoice_number"::text, 0));
    if exists (
      select 1 from "better_supabase"."orders" x
      where x."tenant_id" = new."tenant_id" and x."invoice_number" = new."invoice_number" and x."id" <> new."id"
        and (x.legal_entity_id is null or x.legal_entity_id = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', 'orders', 'invoiceNumber', new."invoice_number"
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_quotes_entity_numbers()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_default uuid;
begin
  select e."id" into v_default from "better_supabase"."legal_entities" e where e."tenant_id" = new."tenant_id" and e."is_default";
  if new.legal_entity_id is not null and new.legal_entity_id is distinct from v_default then
    return new;
  end if;
  if new."number" is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || 'quotes' || ':' || new."tenant_id"::text || ':number:' || new."number"::text, 0));
    if exists (
      select 1 from "better_supabase"."quotes" x
      where x."tenant_id" = new."tenant_id" and x."number" = new."number" and x."id" <> new."id" and x."revision" is not distinct from new."revision"
        and (x.legal_entity_id is null or x.legal_entity_id = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', 'quotes', 'number', new."number"
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.legal_entities_disable_check (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_collisions jsonb;
  v_defaults jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', legal_entities_disable_check.tenant, 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  v_collisions := coalesce((select jsonb_agg(jsonb_build_object('kind', q.kind, 'column', q."column", 'value', q.value, 'documents', q.documents, 'legalEntityIds', q.entities) order by q.kind, q."column", q.value) from (
    select 'invoices' as kind, 'number' as "column", x."number"::text as value,
      count(*) as documents, jsonb_agg(distinct coalesce(x.legal_entity_id, (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))) as entities
    from "better_supabase"."invoices" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
    group by x."number", x."direction", x."kind"
    having count(*) > 1
    union all
    select 'invoices' as kind, 'identifier' as "column", x."identifier"::text as value,
      count(*) as documents, jsonb_agg(distinct coalesce(x.legal_entity_id, (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))) as entities
    from "better_supabase"."invoices" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."identifier" is not null
    group by x."identifier", x."direction", x."kind"
    having count(*) > 1
    union all
    select 'quotes' as kind, 'number' as "column", x."number"::text as value,
      count(*) as documents, jsonb_agg(distinct coalesce(x.legal_entity_id, (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))) as entities
    from "better_supabase"."quotes" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
    group by x."number", x."revision"
    having count(*) > 1
    union all
    select 'orders' as kind, 'number' as "column", x."number"::text as value,
      count(*) as documents, jsonb_agg(distinct coalesce(x.legal_entity_id, (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))) as entities
    from "better_supabase"."orders" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
    group by x."number"
    having count(*) > 1
    union all
    select 'orders' as kind, 'invoiceNumber' as "column", x."invoice_number"::text as value,
      count(*) as documents, jsonb_agg(distinct coalesce(x.legal_entity_id, (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))) as entities
    from "better_supabase"."orders" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."invoice_number" is not null
    group by x."invoice_number"
    having count(*) > 1
  ) q), '[]'::jsonb);
  v_defaults := coalesce((select jsonb_agg(jsonb_build_object('kind', q.kind, 'column', q."column", 'value', q.value, 'documents', q.documents) order by q.kind, q."column", q.value) from (
    select 'invoices' as kind, 'number' as "column", x."number"::text as value, count(*) as documents
    from "better_supabase"."invoices" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
      and (x.legal_entity_id is null or x.legal_entity_id = (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))
    group by x."number", x."direction", x."kind"
    having count(*) > 1
    union all
    select 'invoices' as kind, 'identifier' as "column", x."identifier"::text as value, count(*) as documents
    from "better_supabase"."invoices" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."identifier" is not null
      and (x.legal_entity_id is null or x.legal_entity_id = (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))
    group by x."identifier", x."direction", x."kind"
    having count(*) > 1
    union all
    select 'quotes' as kind, 'number' as "column", x."number"::text as value, count(*) as documents
    from "better_supabase"."quotes" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
      and (x.legal_entity_id is null or x.legal_entity_id = (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))
    group by x."number", x."revision"
    having count(*) > 1
    union all
    select 'orders' as kind, 'number' as "column", x."number"::text as value, count(*) as documents
    from "better_supabase"."orders" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."number" is not null
      and (x.legal_entity_id is null or x.legal_entity_id = (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))
    group by x."number"
    having count(*) > 1
    union all
    select 'orders' as kind, 'invoiceNumber' as "column", x."invoice_number"::text as value, count(*) as documents
    from "better_supabase"."orders" x
    where x."tenant_id" = legal_entities_disable_check.tenant and x."invoice_number" is not null
      and (x.legal_entity_id is null or x.legal_entity_id = (select d."id" from "better_supabase"."legal_entities" d where d."tenant_id" = x."tenant_id" and d."is_default"))
    group by x."invoice_number"
    having count(*) > 1
  ) q), '[]'::jsonb);
  return jsonb_build_object('ok', jsonb_array_length(v_collisions) = 0, 'collisions', v_collisions, 'defaultCollisions', v_defaults);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.legal_entity_default_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_number text;
begin
  select x."number"::text into v_number
  from "better_supabase"."invoices" x
  where x."tenant_id" = new."tenant_id" and x."number" is not null
    and (x.legal_entity_id is null or x.legal_entity_id = new."id")
  group by x."number", x."direction", x."kind" having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', 'invoices', v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;
  select x."identifier"::text into v_number
  from "better_supabase"."invoices" x
  where x."tenant_id" = new."tenant_id" and x."identifier" is not null
    and (x.legal_entity_id is null or x.legal_entity_id = new."id")
  group by x."identifier", x."direction", x."kind" having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', 'invoices', v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;
  select x."number"::text into v_number
  from "better_supabase"."quotes" x
  where x."tenant_id" = new."tenant_id" and x."number" is not null
    and (x.legal_entity_id is null or x.legal_entity_id = new."id")
  group by x."number", x."revision" having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', 'quotes', v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;
  select x."number"::text into v_number
  from "better_supabase"."orders" x
  where x."tenant_id" = new."tenant_id" and x."number" is not null
    and (x.legal_entity_id is null or x.legal_entity_id = new."id")
  group by x."number" having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', 'orders', v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;
  select x."invoice_number"::text into v_number
  from "better_supabase"."orders" x
  where x."tenant_id" = new."tenant_id" and x."invoice_number" is not null
    and (x.legal_entity_id is null or x.legal_entity_id = new."id")
  group by x."invoice_number" having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', 'orders', v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;
  return new;
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
  v_superseded jsonb := '[]'::jsonb;
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
  delete from "better_supabase"."intrastat_lines" x where x."tenant_id" = prepare_intrastat.tenant and x."period" = v_start and x."source" in ('shipment', 'receipt');
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
  with cand as (
    select rl."tenant_id" as tenant, rl."id" as line, rl."variant_id" as variant, rl."quantity" as quantity,
      cv."trade_code" as trade_code, r.country,
      coalesce(nullif(rl."detail" ->> 'netMassKg', '')::numeric, case when cv."weight_grams" is not null then round(cv."weight_grams"::numeric * rl."quantity" / 1000, 3) end) as net_mass,
      o."currency" as currency,
      coalesce(nullif(rl."detail" ->> 'value', '')::bigint, round(rl."quantity" * rl."unit_cost")::bigint) as value,
      (select m."id" from "better_supabase"."intrastat_lines" m
        where m."tenant_id" = rl."tenant_id" and m."period" = v_start and m."flow" = 'arrival' and m."source" = 'manual'
          and m."variant_id" = rl."variant_id" and m."country" = r.country
        order by m."created_at", m."id" limit 1) as manual_line
    from "better_supabase"."inventory_receipt_lines" rl
    join "better_supabase"."inventory_receipts" rc on rc."id" = rl."receipt_id"
    join "better_supabase"."purchase_orders" o on o."id" = rc."purchase_order_id"
    left join "better_supabase"."product_variants" cv on cv."id" = rl."variant_id"
    cross join lateral (select upper(coalesce(nullif(rl."detail" ->> 'country', ''), nullif(rl."detail" ->> 'supplierCountry', ''), nullif(rl."detail" ->> 'countryOfOrigin', ''))) as country) r
    where rl."tenant_id" = prepare_intrastat.tenant
      and rc."received_at" >= v_start::timestamptz and rc."received_at" < (v_start + interval '1 month')::timestamptz
      and r.country = any (array['AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE'])
  ), added as (
    insert into "better_supabase"."intrastat_lines" ("tenant_id", "period", "flow", "source", "receipt_line_id", "variant_id", "trade_code", "country", "net_mass_kg", "quantity", "value", "currency")
    select c.tenant, v_start, 'arrival', 'receipt', c.line, c.variant, c.trade_code, c.country, c.net_mass, c.quantity, c.value, c.currency
    from cand c where c.manual_line is null
  )
  select coalesce(jsonb_agg(jsonb_build_object('manualLineId', c.manual_line, 'receiptLineId', c.line) order by c.line) filter (where c.manual_line is not null), '[]'::jsonb)
  into v_superseded from cand c;
  return jsonb_build_object(
    'period', v_start,
    'superseded', v_superseded,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'period', x."period", 'flow', x."flow", 'source', x."source",
      'shipmentLineId', x."shipment_line_id", 'receiptLineId', x."receipt_line_id", 'supersedes', coalesce((select jsonb_agg(e -> 'receiptLineId' order by e ->> 'receiptLineId') from jsonb_array_elements(v_superseded) e where e ->> 'manualLineId' = x."id"::text), '[]'::jsonb), 'variantId', x."variant_id", 'tradeCode', x."trade_code", 'country', x."country",
      'netMassKg', x."net_mass_kg"::text, 'quantity', x."quantity"::text, 'value', x."value"::text, 'currency', x."currency") order by x."flow", x."trade_code" nulls first, x."created_at", x."id"), '[]'::jsonb) from "better_supabase"."intrastat_lines" x
      where x."tenant_id" = prepare_intrastat.tenant and x."period" = v_start),
    'exceptions', (select coalesce(jsonb_agg(jsonb_build_object('lineId', e.id, 'shipmentLineId', e.shipment_line, 'receiptLineId', e.receipt_line, 'variantId', e.variant, 'code', e.code) order by e.code, e.id), '[]'::jsonb)
      from (
        select x."id" as id, x."shipment_line_id" as shipment_line, x."receipt_line_id" as receipt_line, x."variant_id" as variant, c.code
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
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
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
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'status', v_status, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || receive_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  perform "better_supabase".emit_event('inventory_receipt.created', jsonb_build_object('organizationId', v_row.tenant, 'id', v_receipt, 'purchaseOrderId', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'inspectionId', null), 'inventory-receipts/' || v_receipt::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('status', v_status, 'backordered', v_backordered, 'receiptId', v_receipt);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recompute_invoice_totals (
  tenant      uuid,
  invoice_ids uuid[]  DEFAULT NULL::uuid[],
  dry_run     boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_old jsonb;
  v_new jsonb;
  v_balance bigint;
  v_balance_after bigint;
  v_entry uuid;
  v_entry_number text;
  v_period text;
  v_detail jsonb;
  v_ledger jsonb;
  v_items jsonb := '[]'::jsonb;
  v_checked integer := 0;
  v_changed integer := 0;
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', recompute_invoice_totals.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  for v_row in
    select * from "better_supabase"."invoices" x
    where x."tenant_id" = recompute_invoice_totals.tenant
      and x."status" not in ('draft', 'void')
      and (recompute_invoice_totals.invoice_ids is null or x."id" = any (recompute_invoice_totals.invoice_ids))
    order by x."created_at", x."id"
    for update
  loop
    v_checked := v_checked + 1;
    v_old := jsonb_build_object('listTotal', v_row."list_total"::text, 'discountTotal', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text);
    v_balance := (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total");
    begin
      perform "better_supabase"."issue_invoice_tax"(v_row."id", v_row."issued_on");
      perform "better_supabase"."set_invoice_lines_recount"(v_row."id");
      select jsonb_build_object('listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text), (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") into v_new, v_balance_after
      from "better_supabase"."invoices" x where x."id" = v_row."id";
      if v_new = v_old then
        raise exception using errcode = 'P0BSB', message = 'unchanged';
      end if;
      if recompute_invoice_totals.dry_run then
        raise exception using errcode = 'P0BSB', message = 'dry run';
      end if;
    exception
      when sqlstate 'P0BSB' then
        null;
    end;
    if v_new = v_old then
      continue;
    end if;
    v_changed := v_changed + 1;
    v_entry := null;
    v_entry_number := null;
    v_period := null;
    select e."id", e."number", p."status"
      into v_entry, v_entry_number, v_period
    from "better_supabase"."accounting_entries" e
    left join "better_supabase"."accounting_periods" p on p."id" = e."period_id"
    where e."tenant_id" = v_row."tenant_id"
      and e."source_type" = 'invoice'
      and e."source_id" = v_row."id"::text
      and e."status" = 'posted';
    v_ledger := jsonb_build_object('posted', v_entry is not null, 'entryId', v_entry, 'entryNumber', v_entry_number,
      'periodStatus', v_period, 'needsCorrectingEntry', v_entry is not null);
    v_detail := jsonb_build_object('correction', 'credit_restriction', 'old', v_old, 'new', v_new, 'ledger', v_ledger);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'invoiceId', v_row."id", 'identifier', v_row."identifier", 'currency', v_row."currency", 'status', v_row."status",
      'old', v_old, 'new', v_new, 'balance', v_balance::text, 'balanceAfter', v_balance_after::text,
      'ledger', v_ledger));
    if not recompute_invoice_totals.dry_run then
      perform better_supabase.audit_event(
    event_type => 'invoice.totals_corrected',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice totals corrected (system correction)',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => v_detail
  );
      
    end if;
  end loop;
  return jsonb_build_object('dryRun', recompute_invoice_totals.dry_run, 'checked', v_checked, 'changed', v_changed,
    'applied', case when recompute_invoice_totals.dry_run then 0 else v_changed end, 'invoices', v_items);
end;
$function$;

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD CONSTRAINT "intrastat_lines_receipt_line_id_fkey" FOREIGN KEY (receipt_line_id) REFERENCES better_supabase.inventory_receipt_lines(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD CONSTRAINT "intrastat_lines_receipt_line_id_key" UNIQUE (receipt_line_id);

ALTER TABLE "better_supabase"."intrastat_lines"
  ADD CONSTRAINT "intrastat_lines_source_check" CHECK ((source = ANY (ARRAY['shipment'::text, 'receipt'::text, 'manual'::text])));

CREATE TRIGGER bsb_invoices_entity_numbers
  BEFORE INSERT OR UPDATE OF number, identifier, direction, kind, legal_entity_id ON better_supabase.invoices
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_invoices_entity_numbers();

CREATE TRIGGER bsb_legal_entity_default_guard
  AFTER UPDATE OF is_default ON better_supabase.legal_entities
  FOR EACH ROW
  WHEN ((new.is_default AND (NOT old.is_default)))
  EXECUTE FUNCTION better_supabase.legal_entity_default_guard();

CREATE TRIGGER bsb_orders_entity_numbers
  BEFORE INSERT OR UPDATE OF number, invoice_number, legal_entity_id ON better_supabase.orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_orders_entity_numbers();

CREATE TRIGGER bsb_quotes_entity_numbers
  BEFORE INSERT OR UPDATE OF number, revision, legal_entity_id ON better_supabase.quotes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_quotes_entity_numbers();

REVOKE ALL ON FUNCTION "api"."legal_entities_disable_check"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."legal_entities_disable_check"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."recompute_invoice_totals"(uuid, uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."recompute_invoice_totals"(uuid, uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bsb_invoices_entity_numbers"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_orders_entity_numbers"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_quotes_entity_numbers"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."legal_entities_disable_check"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."legal_entities_disable_check"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."legal_entity_default_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."recompute_invoice_totals"(uuid, uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."recompute_invoice_totals"(uuid, uuid[], boolean) TO "authenticated", "service_role";
