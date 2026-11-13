-- ==== alone: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:5fc2085d312bba191a2b9ef5bcb89a942ee6bf42e6303f657cb41520becc39a9
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table "better_supabase"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound')),
  "from_location_id" uuid,
  "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0),
  "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_shipments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_shipments_check1 check (("label_cost" is null) = ("currency" is null)),
  constraint bsb_shipments_check2 check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index "shipments_tenant_idx" on "better_supabase"."shipments" ("tenant_id", "created_at" desc, "id" desc);
create index "shipments_status_idx" on "better_supabase"."shipments" ("tenant_id", "status");
create unique index "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index "shipments_subject_idx" on "better_supabase"."shipments" ("tenant_id", "subject_type", "subject_id");
create index "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
revoke all on "better_supabase"."shipments" from public, anon, authenticated;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
create policy bsb_shipments_read on "better_supabase"."shipments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table "better_supabase"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_packages_position_check check ("position" >= 1),
  "weight_grams" integer not null constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0),
  "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0),
  "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "better_supabase"."shipment_packages" enable row level security;
revoke all on "better_supabase"."shipment_packages" from public, anon, authenticated;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
create policy bsb_shipment_packages_read on "better_supabase"."shipment_packages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "better_supabase"."shipments" add column "delivered_to" text;
alter table "better_supabase"."shipments" add column "proof_reference" text;
alter table "better_supabase"."shipments" add column "proof_attachment_id" uuid;
alter table "better_supabase"."shipments" add column "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table "better_supabase"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "external_id" text not null constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000),
  "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200),
  "source" text not null constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
revoke all on "better_supabase"."shipment_tracking_events" from public, anon, authenticated;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_read on "better_supabase"."shipment_tracking_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "better_supabase"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "better_supabase"."shipment_tracking_events"
  for each row execute function "better_supabase"."shipment_events_append_only"('tenant_id');

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table "better_supabase"."shipment_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_lines_position_check check ("position" >= 1),
  "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return')),
  "variant_id" uuid not null,
  "location_id" uuid not null,
  "quantity" numeric(20, 6) not null constraint bsb_shipment_lines_quantity_check check ("quantity" > 0),
  "allocation_id" uuid,
  "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object'),
  "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap')),
  "movement_id" uuid,
  "moved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_shipment_lines_check check (("direction" = 'return') = ("disposition" is not null)),
  unique ("shipment_id", "position")
);
create index "shipment_lines_variant_idx" on "better_supabase"."shipment_lines" ("variant_id", "location_id");
create index "shipment_lines_location_idx" on "better_supabase"."shipment_lines" ("location_id");
create index "shipment_lines_allocation_idx" on "better_supabase"."shipment_lines" ("allocation_id");
alter table "better_supabase"."shipment_lines" enable row level security;
revoke all on "better_supabase"."shipment_lines" from public, anon, authenticated;
grant select on "better_supabase"."shipment_lines" to authenticated;
grant all on "better_supabase"."shipment_lines" to service_role;
create policy bsb_shipment_lines_read on "better_supabase"."shipment_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    and null::text is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null then
    raise exception 'install the assets block to ship from one of its locations' using errcode = '22023', hint = 'SHIPMENT_ASSETS_MISSING';
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "better_supabase"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "better_supabase"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  null;
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "better_supabase"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    null;
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$$;
revoke execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "better_supabase"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "better_supabase"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "better_supabase"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
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
  update "better_supabase"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "better_supabase"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "better_supabase"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "better_supabase"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status")), '[]'::jsonb)
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_tracking_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."shipments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_packages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_packages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_packages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_packages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_tracking_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_tracking_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:204aa9c388d72f95c75897ff7d2e48f69b253146c4f34a2932e5102987b54834
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table "better_supabase"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound')),
  "from_location_id" uuid,
  "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0),
  "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_shipments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_shipments_check1 check (("label_cost" is null) = ("currency" is null)),
  constraint bsb_shipments_check2 check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index "shipments_tenant_idx" on "better_supabase"."shipments" ("tenant_id", "created_at" desc, "id" desc);
create index "shipments_status_idx" on "better_supabase"."shipments" ("tenant_id", "status");
create unique index "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index "shipments_subject_idx" on "better_supabase"."shipments" ("tenant_id", "subject_type", "subject_id");
create index "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
revoke all on "better_supabase"."shipments" from public, anon, authenticated;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
create policy bsb_shipments_read on "better_supabase"."shipments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table "better_supabase"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_packages_position_check check ("position" >= 1),
  "weight_grams" integer not null constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0),
  "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0),
  "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "better_supabase"."shipment_packages" enable row level security;
revoke all on "better_supabase"."shipment_packages" from public, anon, authenticated;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
create policy bsb_shipment_packages_read on "better_supabase"."shipment_packages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "better_supabase"."shipments" add column "delivered_to" text;
alter table "better_supabase"."shipments" add column "proof_reference" text;
alter table "better_supabase"."shipments" add column "proof_attachment_id" uuid;
alter table "better_supabase"."shipments" add column "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table "better_supabase"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "external_id" text not null constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000),
  "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200),
  "source" text not null constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
revoke all on "better_supabase"."shipment_tracking_events" from public, anon, authenticated;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_read on "better_supabase"."shipment_tracking_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "better_supabase"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."tenant_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_at" <= now()
    ) then
      return old;
    end if;
  end if;
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "better_supabase"."shipment_tracking_events"
  for each row execute function "better_supabase"."shipment_events_append_only"('tenant_id');
alter table "better_supabase"."shipments" add constraint "shipments_from_location_fkey"
  foreign key ("from_location_id") references "better_supabase"."asset_locations" ("id") on delete set null;

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table "better_supabase"."shipment_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_lines_position_check check ("position" >= 1),
  "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return')),
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete restrict,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete restrict,
  "quantity" numeric(20, 6) not null constraint bsb_shipment_lines_quantity_check check ("quantity" > 0),
  "allocation_id" uuid references "better_supabase"."stock_allocations" ("id") on delete set null,
  "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object'),
  "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap')),
  "movement_id" uuid,
  "moved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_shipment_lines_check check (("direction" = 'return') = ("disposition" is not null)),
  unique ("shipment_id", "position")
);
create index "shipment_lines_variant_idx" on "better_supabase"."shipment_lines" ("variant_id", "location_id");
create index "shipment_lines_location_idx" on "better_supabase"."shipment_lines" ("location_id");
create index "shipment_lines_allocation_idx" on "better_supabase"."shipment_lines" ("allocation_id");
alter table "better_supabase"."shipment_lines" enable row level security;
revoke all on "better_supabase"."shipment_lines" from public, anon, authenticated;
grant select on "better_supabase"."shipment_lines" to authenticated;
grant all on "better_supabase"."shipment_lines" to service_role;
create policy bsb_shipment_lines_read on "better_supabase"."shipment_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

-- One line of the monthly Intrastat declaration. A shipment line that leaves for
-- or comes back from another member state, and a purchase receipt line that
-- names the member state it came from, are derived into lines by
-- prepare_intrastat; a manual line is saved by hand and stays when the month is
-- prepared again.
create table "better_supabase"."intrastat_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "period" date not null constraint bsb_intrastat_lines_period_check check ("period" = date_trunc('month', "period")::date),
  "flow" text not null constraint bsb_intrastat_lines_flow_check check ("flow" in ('arrival', 'dispatch')),
  "source" text not null default 'shipment' constraint bsb_intrastat_lines_source_check check ("source" in ('shipment', 'receipt', 'manual')),
  "shipment_line_id" uuid unique references "better_supabase"."shipment_lines" ("id") on delete cascade,
  "receipt_line_id" uuid unique references "better_supabase"."inventory_receipt_lines" ("id") on delete cascade,
  "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete set null,
  "trade_code" text constraint bsb_intrastat_lines_trade_code_check check ("trade_code" is null or "trade_code" ~ '^[0-9]{4,10}$'),
  "country" char(2) constraint bsb_intrastat_lines_country_check check ("country" is null or "country" ~ '^[A-Z]{2}$'),
  "net_mass_kg" numeric(20, 3) constraint bsb_intrastat_lines_net_mass_kg_check check ("net_mass_kg" is null or "net_mass_kg" >= 0),
  "quantity" numeric(20, 6) constraint bsb_intrastat_lines_quantity_check check ("quantity" is null or "quantity" > 0),
  "value" bigint constraint bsb_intrastat_lines_value_check check ("value" is null or "value" >= 0),
  "currency" char(3) constraint bsb_intrastat_lines_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index "intrastat_lines_period_idx" on "better_supabase"."intrastat_lines" ("tenant_id", "period");
create index "intrastat_lines_variant_idx" on "better_supabase"."intrastat_lines" ("variant_id") where "variant_id" is not null;
alter table "better_supabase"."intrastat_lines" enable row level security;
revoke all on "better_supabase"."intrastat_lines" from public, anon, authenticated;
grant select on "better_supabase"."intrastat_lines" to authenticated;
grant all on "better_supabase"."intrastat_lines" to service_role;
create policy bsb_intrastat_lines_read on "better_supabase"."intrastat_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    and null::text is distinct from create_shipment.tenant::text then
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
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "better_supabase"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "better_supabase"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "better_supabase"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "better_supabase"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "better_supabase"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "better_supabase"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "better_supabase"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "better_supabase"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
-- Replaces the outbound lines of a draft shipment: [{ variantId, locationId,
-- quantity, allocationId?, detail? { binId, lotId, serials } }]. The stock
-- leaves when the shipment gets its label.
create or replace function "better_supabase"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

-- Receives stock a recipient sent back on a shipment that left: [{
-- variantId, locationId, quantity, disposition, detail? }]. restock puts it
-- back in stock, hold puts it in the hold bin detail.binId names, and scrap
-- writes it off. A variant comes back at most as often as it went out.
create or replace function "better_supabase"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- Derives the Intrastat lines of a month (period is any date in it) from the
-- shipment lines moved in it and the goods receipt lines received in it, and
-- lists them with their exceptions. A receipt line is an arrival when its
-- detail names the member state it came from; a manual arrival line for the same
-- variant and country wins and is reported under superseded. An outbound
-- line to another member state is a dispatch and a return line from one an
-- arrival; the partner country is the shipment's destination, and the shipment's
-- own country (its from address) is left out. Trade code and net mass come from
-- the variant (mass is its weight times the quantity), value from the line's
-- detail or, in a known currency, the variant's price; a line's detail can
-- carry netMassKg, value and currency instead. A line that lacks a trade code,
-- a country, a net mass or a value is an exception. Preparing again replaces the
-- derived lines of the month and keeps the manual ones. Returns { period,
-- lines, exceptions }.
create or replace function "better_supabase"."prepare_intrastat"(tenant uuid, period date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."prepare_intrastat"(uuid, date) from public, anon;
grant execute on function "better_supabase"."prepare_intrastat"(uuid, date) to authenticated, service_role;

-- Saves a line the shipments and receipts don't derive (line
-- null creates one). attrs: { period, flow, country, tradeCode?, netMassKg?,
-- quantity?, value? (minor units as text), currency?, variantId? }. Returns the
-- line's id and whether it was created.
create or replace function "better_supabase"."save_intrastat_line"(tenant uuid, line uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."save_intrastat_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_intrastat_line"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a manual line; derived lines come from the shipments.
create or replace function "better_supabase"."delete_intrastat_line"(line uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."delete_intrastat_line"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_intrastat_line"(uuid) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "better_supabase"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status")), '[]'::jsonb)
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_tracking_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."shipments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_packages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_packages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_packages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_packages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_tracking_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_tracking_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."intrastat_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."intrastat_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."intrastat_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."intrastat_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.shipments deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shipment","event_prefix":"shipment"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.shipment_packages deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shipment_package","event_prefix":"shipment_package"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.shipment_tracking_events deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shipment_tracking_event","event_prefix":"shipment_tracking_event"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.shipment_lines deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shipment_line","event_prefix":"shipment_line"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:eabe8f5be105fdaa14c780580fe73aed1cd7a622d0606ba275339ea91c778fc9
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table "app_private"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound')),
  "from_location_id" uuid,
  "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0),
  "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_shipments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_shipments_check1 check (("label_cost" is null) = ("currency" is null)),
  constraint bsb_shipments_check2 check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index "shipments_tenant_idx" on "app_private"."shipments" ("tenant_id", "created_at" desc, "id" desc);
create index "shipments_status_idx" on "app_private"."shipments" ("tenant_id", "status");
create unique index "shipments_tracking_key" on "app_private"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index "shipments_subject_idx" on "app_private"."shipments" ("tenant_id", "subject_type", "subject_id");
create index "shipments_location_idx" on "app_private"."shipments" ("from_location_id");
alter table "app_private"."shipments" enable row level security;
revoke all on "app_private"."shipments" from public, anon, authenticated;
grant select on "app_private"."shipments" to authenticated;
grant all on "app_private"."shipments" to service_role;
create policy bsb_shipments_read on "app_private"."shipments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table "app_private"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "app_private"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_packages_position_check check ("position" >= 1),
  "weight_grams" integer not null constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0),
  "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0),
  "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "app_private"."shipment_packages" enable row level security;
revoke all on "app_private"."shipment_packages" from public, anon, authenticated;
grant select on "app_private"."shipment_packages" to authenticated;
grant all on "app_private"."shipment_packages" to service_role;
create policy bsb_shipment_packages_read on "app_private"."shipment_packages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "app_private"."shipments" add column "delivered_to" text;
alter table "app_private"."shipments" add column "proof_reference" text;
alter table "app_private"."shipments" add column "proof_attachment_id" uuid;
alter table "app_private"."shipments" add column "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table "app_private"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "app_private"."shipments" ("id") on delete cascade,
  "external_id" text not null constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000),
  "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200),
  "source" text not null constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index "shipment_tracking_events_timeline_idx" on "app_private"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "app_private"."shipment_tracking_events" enable row level security;
revoke all on "app_private"."shipment_tracking_events" from public, anon, authenticated;
grant select on "app_private"."shipment_tracking_events" to authenticated;
grant all on "app_private"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_read on "app_private"."shipment_tracking_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "app_private"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "app_private"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "app_private"."shipment_tracking_events"
  for each row execute function "app_private"."shipment_events_append_only"('tenant_id');

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table "app_private"."shipment_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "app_private"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_lines_position_check check ("position" >= 1),
  "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return')),
  "variant_id" uuid not null,
  "location_id" uuid not null,
  "quantity" numeric(20, 6) not null constraint bsb_shipment_lines_quantity_check check ("quantity" > 0),
  "allocation_id" uuid,
  "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object'),
  "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap')),
  "movement_id" uuid,
  "moved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_shipment_lines_check check (("direction" = 'return') = ("disposition" is not null)),
  unique ("shipment_id", "position")
);
create index "shipment_lines_variant_idx" on "app_private"."shipment_lines" ("variant_id", "location_id");
create index "shipment_lines_location_idx" on "app_private"."shipment_lines" ("location_id");
create index "shipment_lines_allocation_idx" on "app_private"."shipment_lines" ("allocation_id");
alter table "app_private"."shipment_lines" enable row level security;
revoke all on "app_private"."shipment_lines" from public, anon, authenticated;
grant select on "app_private"."shipment_lines" to authenticated;
grant all on "app_private"."shipment_lines" to service_role;
create policy bsb_shipment_lines_read on "app_private"."shipment_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "app_private"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
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
    and null::text is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null then
    raise exception 'install the assets block to ship from one of its locations' using errcode = '22023', hint = 'SHIPMENT_ASSETS_MISSING';
  end if;
  begin
    insert into "app_private"."shipments" ("tenant_id", "reference", "from_address", "to_address", "from_location_id", "subject_type", "subject_id", "created_by")
    values (create_shipment.tenant,
      coalesce(nullif(btrim(create_shipment.reference), ''), 'SHP-' || upper(substr(md5(gen_random_uuid()::text), 1, 10))),
      create_shipment.from_address, create_shipment.to_address, create_shipment.from_location_id,
      create_shipment.subject_type, create_shipment.subject_id, auth.uid())
    returning * into v_ship;
  exception when check_violation then
    raise exception 'a shipment reference has 1 to 100 characters' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end;
  begin
    insert into "app_private"."shipment_packages" ("tenant_id", "shipment_id", "position", "weight_grams", "length_mm", "width_mm", "height_mm", "reference")
    select v_ship."tenant_id", v_ship."id", k.position,
      (k.item ->> 'weightGrams')::integer, (k.item ->> 'lengthMm')::integer, (k.item ->> 'widthMm')::integer, (k.item ->> 'heightMm')::integer,
      nullif(k.item ->> 'reference', '')
    from jsonb_array_elements(create_shipment.packages) with ordinality as k(item, position);
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'each package needs a weightGrams and sizes in whole millimeters above zero' using errcode = '22023', hint = 'SHIPMENT_PACKAGE_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "app_private"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "app_private"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
begin
  select * into v_ship from "app_private"."shipments" x where x."id" = get_shipment.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."get_shipment"(uuid) from public, anon;
grant execute on function "app_private"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "app_private"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
      select 1 from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
      select 1 from "app_private"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "app_private"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "app_private"."shipments" x where x."id" = set_shipment_label.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft shipment gets a label' using errcode = '55000', hint = 'SHIPMENT_NOT_DRAFT';
  end if;
  begin
    update "app_private"."shipments" x set
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
  insert into "app_private"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  null;
  select t."status", t."occurred_at" into v_status, v_at
    from "app_private"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "app_private"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "app_private"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "app_private"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "app_private"."shipments" x where x."id" = record_tracking_events.shipment_id for update;
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
      insert into "app_private"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
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
    from "app_private"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "app_private"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$$;
revoke execute on function "app_private"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "app_private"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "app_private"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "app_private"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "app_private"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
      on conflict ("shipment_id", "external_id") do nothing
      returning 1
    )
    select count(*)::integer into v_count from inserted;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'each tracking event needs an id, a known status and an ISO 8601 occurredAt' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end;
  select t."status", t."occurred_at" into v_status, v_at
    from "app_private"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "app_private"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "app_private"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "app_private"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "app_private"."shipments" x where x."id" = cancel_shipment.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" not in ('draft', 'label_created') then
    raise exception 'only a draft or a shipment that hasn''t left gets cancelled' using errcode = '55000', hint = 'SHIPMENT_SHIPPED';
  end if;
  update "app_private"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."cancel_shipment"(uuid) from public, anon;
grant execute on function "app_private"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "app_private"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "app_private"."shipments" x where x."id" = set_shipment_direction.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if set_shipment_direction.direction is null or set_shipment_direction.direction not in ('outbound', 'inbound') then
    raise exception 'a shipment is outbound or inbound' using errcode = '22023', hint = 'SHIPMENT_DIRECTION_INVALID';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft changes direction' using errcode = '55000', hint = 'SHIPMENT_SHIPPED';
  end if;
  update "app_private"."shipments" x set "direction" = set_shipment_direction.direction, "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "app_private"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "app_private"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "app_private"."shipments" x where x."id" = record_delivery_proof.shipment_id for update;
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
  update "app_private"."shipments" x set
      "delivered_to" = btrim(record_delivery_proof.delivered_to),
      "proof_reference" = record_delivery_proof.proof_reference,
      "proof_attachment_id" = record_delivery_proof.attachment_id,
      "proof_recorded_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "app_private"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "app_private"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "app_private"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "app_private"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "app_private"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "app_private"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "app_private"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "app_private"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "app_private"."shipments"%rowtype;
begin
  select * into v_ship from "app_private"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status")), '[]'::jsonb)
    from "app_private"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "app_private"."list_tracking_events"(uuid) from public, anon;
grant execute on function "app_private"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."shipments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."shipments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."shipments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."shipments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."shipment_packages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."shipment_packages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."shipment_packages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."shipment_packages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."shipment_tracking_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."shipment_tracking_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."shipment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."shipment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."shipment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."shipment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:8050afdeca14f2e7882c222673df3346f2f023b3abc2e7f60cdcd762ac24c8a9
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table "better_supabase"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound')),
  "from_location_id" uuid,
  "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0),
  "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_shipments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_shipments_check1 check (("label_cost" is null) = ("currency" is null)),
  constraint bsb_shipments_check2 check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index "shipments_tenant_idx" on "better_supabase"."shipments" ("tenant_id", "created_at" desc, "id" desc);
create index "shipments_status_idx" on "better_supabase"."shipments" ("tenant_id", "status");
create unique index "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index "shipments_subject_idx" on "better_supabase"."shipments" ("tenant_id", "subject_type", "subject_id");
create index "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
revoke all on "better_supabase"."shipments" from public, anon, authenticated;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
create policy bsb_shipments_read on "better_supabase"."shipments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table "better_supabase"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_packages_position_check check ("position" >= 1),
  "weight_grams" integer not null constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0),
  "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0),
  "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "better_supabase"."shipment_packages" enable row level security;
revoke all on "better_supabase"."shipment_packages" from public, anon, authenticated;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
create policy bsb_shipment_packages_read on "better_supabase"."shipment_packages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "better_supabase"."shipments" add column "delivered_to" text;
alter table "better_supabase"."shipments" add column "proof_reference" text;
alter table "better_supabase"."shipments" add column "proof_attachment_id" uuid;
alter table "better_supabase"."shipments" add column "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table "better_supabase"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "external_id" text not null constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000),
  "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200),
  "source" text not null constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
revoke all on "better_supabase"."shipment_tracking_events" from public, anon, authenticated;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_read on "better_supabase"."shipment_tracking_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "better_supabase"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "better_supabase"."shipment_tracking_events"
  for each row execute function "better_supabase"."shipment_events_append_only"('tenant_id');

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table "better_supabase"."shipment_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_lines_position_check check ("position" >= 1),
  "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return')),
  "variant_id" uuid not null,
  "location_id" uuid not null,
  "quantity" numeric(20, 6) not null constraint bsb_shipment_lines_quantity_check check ("quantity" > 0),
  "allocation_id" uuid,
  "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object'),
  "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap')),
  "movement_id" uuid,
  "moved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_shipment_lines_check check (("direction" = 'return') = ("disposition" is not null)),
  unique ("shipment_id", "position")
);
create index "shipment_lines_variant_idx" on "better_supabase"."shipment_lines" ("variant_id", "location_id");
create index "shipment_lines_location_idx" on "better_supabase"."shipment_lines" ("location_id");
create index "shipment_lines_allocation_idx" on "better_supabase"."shipment_lines" ("allocation_id");
alter table "better_supabase"."shipment_lines" enable row level security;
revoke all on "better_supabase"."shipment_lines" from public, anon, authenticated;
grant select on "better_supabase"."shipment_lines" to authenticated;
grant all on "better_supabase"."shipment_lines" to service_role;
create policy bsb_shipment_lines_read on "better_supabase"."shipment_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    and null::text is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null then
    raise exception 'install the assets block to ship from one of its locations' using errcode = '22023', hint = 'SHIPMENT_ASSETS_MISSING';
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "better_supabase"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "better_supabase"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  null;
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "better_supabase"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    null;
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$$;
revoke execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "better_supabase"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "better_supabase"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "better_supabase"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
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
  update "better_supabase"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "better_supabase"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "better_supabase"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "better_supabase"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status")), '[]'::jsonb)
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_tracking_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."shipments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_packages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_packages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_packages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_packages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_tracking_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_tracking_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.shipments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_shipment"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "api"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_shipment"(shipment_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_shipment"($1) $$;
revoke execute on function "api"."get_shipment"(uuid) from public, anon;
grant execute on function "api"."get_shipment"(uuid) to authenticated, service_role;

create or replace function "api"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_shipments"($1, $2) $$;
revoke execute on function "api"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_shipments"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_shipment_label"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "api"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

create or replace function "api"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_tracking_events"($1, $2, $3) $$;
revoke execute on function "api"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ingest_tracking_events"($1, $2, $3) $$;
revoke execute on function "api"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."ingest_tracking_events"(text, text, jsonb) to service_role;

create or replace function "api"."cancel_shipment"(shipment_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_shipment"($1) $$;
revoke execute on function "api"."cancel_shipment"(uuid) from public, anon;
grant execute on function "api"."cancel_shipment"(uuid) to authenticated, service_role;

create or replace function "api"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_shipment_direction"($1, $2) $$;
revoke execute on function "api"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "api"."set_shipment_direction"(uuid, text) to authenticated, service_role;

create or replace function "api"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_delivery_proof"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_shipment_lines"($1, $2) $$;
revoke execute on function "api"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."receive_shipment_return"($1, $2) $$;
revoke execute on function "api"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "api"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_tracking_events"(shipment_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tracking_events"($1) $$;
revoke execute on function "api"."list_tracking_events"(uuid) from public, anon;
grant execute on function "api"."list_tracking_events"(uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:4670f281bce16e0751e448aeb679ae585ec2ca2b51f1ed72748195850986af62
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
-- better_supabase.shipments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shipments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shipments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shipments" add column if not exists "reference" text constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100);
alter table "better_supabase"."shipments" add column if not exists "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled'));
alter table "better_supabase"."shipments" add column if not exists "from_address" jsonb constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000);
alter table "better_supabase"."shipments" add column if not exists "to_address" jsonb constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000);
alter table "better_supabase"."shipments" add column if not exists "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound'));
alter table "better_supabase"."shipments" add column if not exists "from_location_id" uuid;
alter table "better_supabase"."shipments" add column if not exists "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."shipments" add column if not exists "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200);
alter table "better_supabase"."shipments" add column if not exists "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100);
alter table "better_supabase"."shipments" add column if not exists "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100);
alter table "better_supabase"."shipments" add column if not exists "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100);
alter table "better_supabase"."shipments" add column if not exists "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000);
alter table "better_supabase"."shipments" add column if not exists "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200);
alter table "better_supabase"."shipments" add column if not exists "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000);
alter table "better_supabase"."shipments" add column if not exists "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl'));
alter table "better_supabase"."shipments" add column if not exists "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0);
alter table "better_supabase"."shipments" add column if not exists "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."shipments" add column if not exists "labeled_at" timestamptz;
alter table "better_supabase"."shipments" add column if not exists "delivered_at" timestamptz;
alter table "better_supabase"."shipments" add column if not exists "cancelled_at" timestamptz;
alter table "better_supabase"."shipments" add column if not exists "created_by" uuid;
alter table "better_supabase"."shipments" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."shipments" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "shipments_tenant_idx" on "better_supabase"."shipments" ("tenant_id", "created_at" desc, "id" desc);
create index if not exists "shipments_status_idx" on "better_supabase"."shipments" ("tenant_id", "status");
create unique index if not exists "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index if not exists "shipments_subject_idx" on "better_supabase"."shipments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
create policy bsb_shipments_select on "better_supabase"."shipments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- better_supabase.shipment_packages is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shipment_packages" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shipment_packages" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shipment_packages" add column if not exists "shipment_id" uuid references "better_supabase"."shipments" ("id") on delete cascade;
alter table "better_supabase"."shipment_packages" add column if not exists "position" integer constraint bsb_shipment_packages_position_check check ("position" >= 1);
alter table "better_supabase"."shipment_packages" add column if not exists "weight_grams" integer constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0);
alter table "better_supabase"."shipment_packages" add column if not exists "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0);
alter table "better_supabase"."shipment_packages" add column if not exists "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0);
alter table "better_supabase"."shipment_packages" add column if not exists "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0);
alter table "better_supabase"."shipment_packages" add column if not exists "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100);
alter table "better_supabase"."shipment_packages" enable row level security;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
create policy bsb_shipment_packages_select on "better_supabase"."shipment_packages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "better_supabase"."shipments" add column if not exists "delivered_to" text;
alter table "better_supabase"."shipments" add column if not exists "proof_reference" text;
alter table "better_supabase"."shipments" add column if not exists "proof_attachment_id" uuid;
alter table "better_supabase"."shipments" add column if not exists "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
-- better_supabase.shipment_tracking_events is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shipment_tracking_events" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shipment_tracking_events" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shipment_tracking_events" add column if not exists "shipment_id" uuid references "better_supabase"."shipments" ("id") on delete cascade;
alter table "better_supabase"."shipment_tracking_events" add column if not exists "external_id" text constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200);
alter table "better_supabase"."shipment_tracking_events" add column if not exists "status" text constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned'));
alter table "better_supabase"."shipment_tracking_events" add column if not exists "occurred_at" timestamptz;
alter table "better_supabase"."shipment_tracking_events" add column if not exists "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000);
alter table "better_supabase"."shipment_tracking_events" add column if not exists "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200);
alter table "better_supabase"."shipment_tracking_events" add column if not exists "source" text constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual'));
alter table "better_supabase"."shipment_tracking_events" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "shipment_tracking_events_shipment_id_external_id_key" on "better_supabase"."shipment_tracking_events" ("shipment_id", "external_id");
create index if not exists "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_select on "better_supabase"."shipment_tracking_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "better_supabase"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "better_supabase"."shipment_tracking_events"
  for each row execute function "better_supabase"."shipment_events_append_only"('tenant_id');

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
-- better_supabase.shipment_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shipment_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shipment_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shipment_lines" add column if not exists "shipment_id" uuid references "better_supabase"."shipments" ("id") on delete cascade;
alter table "better_supabase"."shipment_lines" add column if not exists "position" integer constraint bsb_shipment_lines_position_check check ("position" >= 1);
alter table "better_supabase"."shipment_lines" add column if not exists "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return'));
alter table "better_supabase"."shipment_lines" add column if not exists "variant_id" uuid;
alter table "better_supabase"."shipment_lines" add column if not exists "location_id" uuid;
alter table "better_supabase"."shipment_lines" add column if not exists "quantity" numeric(20, 6) constraint bsb_shipment_lines_quantity_check check ("quantity" > 0);
alter table "better_supabase"."shipment_lines" add column if not exists "allocation_id" uuid;
alter table "better_supabase"."shipment_lines" add column if not exists "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object');
alter table "better_supabase"."shipment_lines" add column if not exists "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap'));
alter table "better_supabase"."shipment_lines" add column if not exists "movement_id" uuid;
alter table "better_supabase"."shipment_lines" add column if not exists "moved_at" timestamptz;
alter table "better_supabase"."shipment_lines" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "shipment_lines_variant_idx" on "better_supabase"."shipment_lines" ("variant_id", "location_id");
create index if not exists "shipment_lines_location_idx" on "better_supabase"."shipment_lines" ("location_id");
create index if not exists "shipment_lines_allocation_idx" on "better_supabase"."shipment_lines" ("allocation_id");
alter table "better_supabase"."shipment_lines" enable row level security;
grant select on "better_supabase"."shipment_lines" to authenticated;
grant all on "better_supabase"."shipment_lines" to service_role;
create policy bsb_shipment_lines_select on "better_supabase"."shipment_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    and null::text is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null then
    raise exception 'install the assets block to ship from one of its locations' using errcode = '22023', hint = 'SHIPMENT_ASSETS_MISSING';
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "better_supabase"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      select (case v_facet when 'status' then (x."status"::text)::text when 'carrier' then (x."carrier")::text end) as v
      from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "better_supabase"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  null;
  select t."status"::text, t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status"::text) desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status"::text then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = better_supabase.as_column_type(v_status, (null::"better_supabase"."shipments")."status"),
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "better_supabase"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
      select v_ship."tenant_id", v_ship."id", i ->> 'id', better_supabase.as_column_type(i ->> 'status', (null::"better_supabase"."shipment_tracking_events")."status"), (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), record_tracking_events.source
      from jsonb_array_elements(record_tracking_events.events) i
      on conflict ("shipment_id", "external_id") do nothing
      returning 1
    )
    select count(*)::integer into v_count from inserted;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'each tracking event needs an id, a known status and an ISO 8601 occurredAt' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end;
  select t."status"::text, t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status"::text) desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status"::text then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = better_supabase.as_column_type(v_status, (null::"better_supabase"."shipments")."status"),
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$$;
revoke execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "better_supabase"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "better_supabase"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."tenant_id", v_ship."id", i ->> 'id', better_supabase.as_column_type(i ->> 'status', (null::"better_supabase"."shipment_tracking_events")."status"), (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
      on conflict ("shipment_id", "external_id") do nothing
      returning 1
    )
    select count(*)::integer into v_count from inserted;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'each tracking event needs an id, a known status and an ISO 8601 occurredAt' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end;
  select t."status"::text, t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status"::text) desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status"::text then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = better_supabase.as_column_type(v_status, (null::"better_supabase"."shipments")."status"),
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "better_supabase"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
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
  update "better_supabase"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "better_supabase"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "better_supabase"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "better_supabase"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status"::text)), '[]'::jsonb)
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_tracking_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."shipments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_packages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_packages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_packages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_packages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_tracking_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_tracking_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:b3a1a24aa5986acf27b48a220a0cd28860c5a5f8a289312995a86c8c9bfebbe2
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table "better_supabase"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "reference" text not null constraint bsb_shipments_reference_check check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' constraint bsb_shipments_status_check check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null constraint bsb_shipments_from_address_check check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null constraint bsb_shipments_to_address_check check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "direction" text not null default 'outbound' constraint bsb_shipments_direction check ("direction" in ('outbound', 'inbound')),
  "from_location_id" uuid,
  "subject_type" text constraint bsb_shipments_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_shipments_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text constraint bsb_shipments_carrier_check check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text constraint bsb_shipments_service_check check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text constraint bsb_shipments_tracking_number_check check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text constraint bsb_shipments_tracking_url_check check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text constraint bsb_shipments_label_id_check check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text constraint bsb_shipments_label_url_check check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text constraint bsb_shipments_label_format_check check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint constraint bsb_shipments_label_cost_check check ("label_cost" is null or "label_cost" >= 0),
  "currency" text constraint bsb_shipments_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_shipments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_shipments_check1 check (("label_cost" is null) = ("currency" is null)),
  constraint bsb_shipments_check2 check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index "shipments_tenant_idx" on "better_supabase"."shipments" ("org_id", "created_at" desc, "id" desc);
create index "shipments_status_idx" on "better_supabase"."shipments" ("org_id", "status");
create unique index "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index "shipments_subject_idx" on "better_supabase"."shipments" ("org_id", "subject_type", "subject_id");
create index "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
revoke all on "better_supabase"."shipments" from public, anon, authenticated;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
create policy bsb_shipments_read on "better_supabase"."shipments"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table "better_supabase"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_packages_position_check check ("position" >= 1),
  "weight_grams" integer not null constraint bsb_shipment_packages_weight_grams_check check ("weight_grams" > 0),
  "length_mm" integer constraint bsb_shipment_packages_length_mm_check check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer constraint bsb_shipment_packages_width_mm_check check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer constraint bsb_shipment_packages_height_mm_check check ("height_mm" is null or "height_mm" > 0),
  "reference" text constraint bsb_shipment_packages_reference_check check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "better_supabase"."shipment_packages" enable row level security;
revoke all on "better_supabase"."shipment_packages" from public, anon, authenticated;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
create policy bsb_shipment_packages_read on "better_supabase"."shipment_packages"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')));

alter table "better_supabase"."shipments" add column "delivered_to" text;
alter table "better_supabase"."shipments" add column "proof_reference" text;
alter table "better_supabase"."shipments" add column "proof_attachment_id" uuid;
alter table "better_supabase"."shipments" add column "proof_recorded_at" timestamptz;
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table "better_supabase"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "external_id" text not null constraint bsb_shipment_tracking_events_external_id_check check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null constraint bsb_shipment_tracking_events_status_check check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text constraint bsb_shipment_tracking_events_description_check check ("description" is null or length("description") <= 1000),
  "location" text constraint bsb_shipment_tracking_events_location_check check ("location" is null or length("location") <= 200),
  "source" text not null constraint bsb_shipment_tracking_events_source_check check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
revoke all on "better_supabase"."shipment_tracking_events" from public, anon, authenticated;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
create policy bsb_shipment_tracking_events_read on "better_supabase"."shipment_tracking_events"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Tracking events are append-only: a correction is a later event.
create or replace function "better_supabase"."shipment_events_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'tracking events can''t be changed or deleted; record a later event' using errcode = '55000', hint = 'SHIPMENT_EVENTS_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."shipment_events_append_only"() from public, anon, authenticated;
create trigger "bsb_shipment_events_append_only" before update or delete on "better_supabase"."shipment_tracking_events"
  for each row execute function "better_supabase"."shipment_events_append_only"('org_id');

-- The stock a shipment carries out, and what comes back. An outbound line
-- leaves stock when the shipment gets its label; a return line comes back
-- with a disposition.
create table "better_supabase"."shipment_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null constraint bsb_shipment_lines_position_check check ("position" >= 1),
  "direction" text not null default 'outbound' constraint bsb_shipment_lines_direction_check check ("direction" in ('outbound', 'return')),
  "variant_id" uuid not null,
  "location_id" uuid not null,
  "quantity" numeric(20, 6) not null constraint bsb_shipment_lines_quantity_check check ("quantity" > 0),
  "allocation_id" uuid,
  "detail" jsonb constraint bsb_shipment_lines_detail_check check ("detail" is null or jsonb_typeof("detail") = 'object'),
  "disposition" text constraint bsb_shipment_lines_disposition_check check ("disposition" is null or "disposition" in ('restock', 'hold', 'scrap')),
  "movement_id" uuid,
  "moved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_shipment_lines_check check (("direction" = 'return') = ("disposition" is not null)),
  unique ("shipment_id", "position")
);
create index "shipment_lines_variant_idx" on "better_supabase"."shipment_lines" ("variant_id", "location_id");
create index "shipment_lines_location_idx" on "better_supabase"."shipment_lines" ("location_id");
create index "shipment_lines_allocation_idx" on "better_supabase"."shipment_lines" ("allocation_id");
alter table "better_supabase"."shipment_lines" enable row level security;
revoke all on "better_supabase"."shipment_lines" from public, anon, authenticated;
grant select on "better_supabase"."shipment_lines" to authenticated;
grant all on "better_supabase"."shipment_lines" to service_role;
create policy bsb_shipment_lines_read on "better_supabase"."shipment_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    and null::text is distinct from create_shipment.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'SHIPMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_shipment.from_location_id is not null then
    raise exception 'install the assets block to ship from one of its locations' using errcode = '22023', hint = 'SHIPMENT_ASSETS_MISSING';
  end if;
  begin
    insert into "better_supabase"."shipments" ("org_id", "reference", "from_address", "to_address", "from_location_id", "subject_type", "subject_id", "created_by")
    values (create_shipment.tenant,
      coalesce(nullif(btrim(create_shipment.reference), ''), 'SHP-' || upper(substr(md5(gen_random_uuid()::text), 1, 10))),
      create_shipment.from_address, create_shipment.to_address, create_shipment.from_location_id,
      create_shipment.subject_type, create_shipment.subject_id, auth.uid())
    returning * into v_ship;
  exception when check_violation then
    raise exception 'a shipment reference has 1 to 100 characters' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end;
  begin
    insert into "better_supabase"."shipment_packages" ("org_id", "shipment_id", "position", "weight_grams", "length_mm", "width_mm", "height_mm", "reference")
    select v_ship."org_id", v_ship."id", k.position,
      (k.item ->> 'weightGrams')::integer, (k.item ->> 'lengthMm')::integer, (k.item ->> 'widthMm')::integer, (k.item ->> 'heightMm')::integer,
      nullif(k.item ->> 'reference', '')
    from jsonb_array_elements(create_shipment.packages) with ordinality as k(item, position);
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'each package needs a weightGrams and sizes in whole millimeters above zero' using errcode = '22023', hint = 'SHIPMENT_PACKAGE_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text) to authenticated, service_role;

-- One shipment with its packages and label, or null.
create or replace function "better_supabase"."get_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = get_shipment.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first. filters is { status, carrier (each a
-- value or a list), subjectType, subjectId, before, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_shipments"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
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
      where x."org_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, jsonb) to authenticated, service_role;

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function "better_supabase"."set_shipment_label"(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_label.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.manage'), false)) then
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
  insert into "better_supabase"."shipment_tracking_events" ("org_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."org_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  null;
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_label"(uuid, text, text, text, text, bigint, text, text, text, text) to authenticated, service_role;

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function "better_supabase"."record_tracking_events"(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.manage'), false)) then
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
      insert into "better_supabase"."shipment_tracking_events" ("org_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."org_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), record_tracking_events.source
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
    null;
  end if;
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")));
end;
$$;
revoke execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_tracking_events"(uuid, jsonb, text) to authenticated, service_role;

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function "better_supabase"."ingest_tracking_events"(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
begin
  select * into v_ship from "better_supabase"."shipments" x
    where x."carrier" = ingest_tracking_events.carrier
      and x."tracking_number" = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
  if jsonb_typeof(ingest_tracking_events.events) is distinct from 'array' or jsonb_array_length(ingest_tracking_events.events) > 500 then
    raise exception 'pass the tracking events as an array of at most 500' using errcode = '22023', hint = 'SHIPMENT_TRACKING_INVALID';
  end if;
  begin
    with inserted as (
      insert into "better_supabase"."shipment_tracking_events" ("org_id", "shipment_id", "external_id", "status", "occurred_at", "description", "location", "source")
      select v_ship."org_id", v_ship."id", i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), 'webhook'
      from jsonb_array_elements(ingest_tracking_events.events) i
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
    null;
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'status', v_ship."status", 'recorded', v_count);
end;
$$;
revoke execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_tracking_events"(text, text, jsonb) to service_role;

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function "better_supabase"."cancel_shipment"(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = cancel_shipment.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" not in ('draft', 'label_created') then
    raise exception 'only a draft or a shipment that hasn''t left gets cancelled' using errcode = '55000', hint = 'SHIPMENT_SHIPPED';
  end if;
  update "better_supabase"."shipments" x set
    "status" = 'cancelled',
    "cancelled_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

-- Sets whether a draft shipment leaves the organization (outbound) or comes
-- to it (inbound). Lines keep their own direction.
create or replace function "better_supabase"."set_shipment_direction"(shipment_id uuid, direction text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_direction.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.manage'), false)) then
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."set_shipment_direction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_shipment_direction"(uuid, text) to authenticated, service_role;

-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function "better_supabase"."record_delivery_proof"(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = record_delivery_proof.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.manage'), false)) then
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
  null;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."org_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_delivery_proof"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."set_shipment_lines"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_shipment_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."receive_shipment_return"(shipment_id uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'install the inventory block to ship stock' using errcode = '22023', hint = 'SHIPMENT_INVENTORY_MISSING';
end;
$$;
revoke execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_shipment_return"(uuid, jsonb) to authenticated, service_role;

-- A shipment's tracking timeline, oldest first.
create or replace function "better_supabase"."list_tracking_events"(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  select * into v_ship from "better_supabase"."shipments" x where x."id" = list_tracking_events.shipment_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."org_id", 'shipments.read'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'externalId', t."external_id", 'status', t."status", 'occurredAt', t."occurred_at", 'description', t."description", 'location', t."location", 'source', t."source", 'createdAt', t."created_at") order by t."occurred_at", array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status")), '[]'::jsonb)
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_tracking_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tracking_events"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."shipments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_packages" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_packages" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_packages" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_packages" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_tracking_events" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_tracking_events" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_tracking_events" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_tracking_events" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."shipment_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shipments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."shipment_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."shipment_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."shipment_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:13d8415aa86013cc95a5be9f7bc68a5581466832d90edd04f4e030c611afee74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
