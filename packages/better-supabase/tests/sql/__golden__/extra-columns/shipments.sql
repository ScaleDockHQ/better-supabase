-- ==== schema supabase/schemas/900_better_supabase_124_shipments.sql
-- better-supabase module: shipments
-- @bsb-block shipments@4 managed
-- @bsb-hash sha256:384dcee385268379ddce9ecf29297a6dc98a07305503dc7991e87cef22297f65
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
create or replace function "better_supabase"."create_shipment"(tenant uuid, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null, fields jsonb default null)
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
  update "better_supabase"."shipments" x set "app_note" = case when create_shipment.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."shipments", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(create_shipment.fields) e where e.key in ('app_note'))) r
  where x."id" = v_ship."id"
  returning x.* into v_ship;
  null;
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
end;
$$;
revoke execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text, jsonb) to authenticated, service_role;

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
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
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
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
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
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
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
  return jsonb_build_object('recorded', v_count, 'shipment', (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note"))));
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
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
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
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
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
  return (jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id")) || jsonb_build_object('fields', jsonb_build_object('app_note', v_ship."app_note")));
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

-- ==== data supabase/better-supabase-data/900_better_supabase_124_shipments.sql
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
