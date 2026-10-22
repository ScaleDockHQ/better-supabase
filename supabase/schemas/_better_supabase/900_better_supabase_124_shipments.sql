-- better-supabase module: shipments
-- @bs-module shipments@1 managed
-- Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.

-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table if not exists "better_supabase"."shipments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null check (length("reference") >= 1 and length("reference") <= 100),
  "status" text not null default 'draft' check ("status" in ('draft', 'label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned', 'cancelled')),
  "from_address" jsonb not null check (jsonb_typeof("from_address") = 'object' and coalesce("from_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("from_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("from_address" ->> 'city', ''))) >= 1 and length("from_address"::text) <= 4000),
  "to_address" jsonb not null check (jsonb_typeof("to_address") = 'object' and coalesce("to_address" ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce("to_address" ->> 'line1', ''))) >= 1 and length(btrim(coalesce("to_address" ->> 'city', ''))) >= 1 and length("to_address"::text) <= 4000),
  "from_location_id" uuid,
  "subject_type" text check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "carrier" text check ("carrier" is null or length("carrier") >= 1 and length("carrier") <= 100),
  "service" text check ("service" is null or length("service") >= 1 and length("service") <= 100),
  "tracking_number" text check ("tracking_number" is null or length("tracking_number") >= 1 and length("tracking_number") <= 100),
  "tracking_url" text check ("tracking_url" is null or "tracking_url" ~ '^https://' and length("tracking_url") <= 2000),
  "label_id" text check ("label_id" is null or length("label_id") >= 1 and length("label_id") <= 200),
  "label_url" text check ("label_url" is null or "label_url" ~ '^https://' and length("label_url") <= 2000),
  "label_format" text check ("label_format" is null or "label_format" in ('pdf', 'png', 'zpl')),
  "label_cost" bigint check ("label_cost" is null or "label_cost" >= 0),
  "currency" text check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "labeled_at" timestamptz,
  "delivered_at" timestamptz,
  "cancelled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  check (("label_cost" is null) = ("currency" is null)),
  check ("status" in ('draft', 'cancelled') or ("carrier" is not null and "tracking_number" is not null))
);
create index if not exists "shipments_tenant_idx" on "better_supabase"."shipments" ("tenant_id", "created_at" desc);
create index if not exists "shipments_status_idx" on "better_supabase"."shipments" ("tenant_id", "status");
create unique index if not exists "shipments_tracking_key" on "better_supabase"."shipments" ("carrier", "tracking_number") where "tracking_number" is not null;
create index if not exists "shipments_subject_idx" on "better_supabase"."shipments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "shipments_location_idx" on "better_supabase"."shipments" ("from_location_id");
alter table "better_supabase"."shipments" enable row level security;
revoke all on "better_supabase"."shipments" from anon, authenticated;
grant select on "better_supabase"."shipments" to authenticated;
grant all on "better_supabase"."shipments" to service_role;
drop policy if exists "shipments_read" on "better_supabase"."shipments";
create policy "shipments_read" on "better_supabase"."shipments" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
create table if not exists "better_supabase"."shipment_packages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "position" integer not null check ("position" >= 1),
  "weight_grams" integer not null check ("weight_grams" > 0),
  "length_mm" integer check ("length_mm" is null or "length_mm" > 0),
  "width_mm" integer check ("width_mm" is null or "width_mm" > 0),
  "height_mm" integer check ("height_mm" is null or "height_mm" > 0),
  "reference" text check ("reference" is null or length("reference") <= 100),
  unique ("shipment_id", "position")
);
alter table "better_supabase"."shipment_packages" enable row level security;
revoke all on "better_supabase"."shipment_packages" from anon, authenticated;
grant select on "better_supabase"."shipment_packages" to authenticated;
grant all on "better_supabase"."shipment_packages" to service_role;
drop policy if exists "shipment_packages_read" on "better_supabase"."shipment_packages";
create policy "shipment_packages_read" on "better_supabase"."shipment_packages" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table if not exists "better_supabase"."shipment_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shipment_id" uuid not null references "better_supabase"."shipments" ("id") on delete cascade,
  "external_id" text not null check (length("external_id") >= 1 and length("external_id") <= 200),
  "status" text not null check ("status" in ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  "occurred_at" timestamptz not null,
  "description" text check ("description" is null or length("description") <= 1000),
  "location" text check ("location" is null or length("location") <= 200),
  "source" text not null check ("source" in ('carrier', 'webhook', 'manual')),
  "created_at" timestamptz not null default now(),
  unique ("shipment_id", "external_id")
);
create index if not exists "shipment_tracking_events_timeline_idx" on "better_supabase"."shipment_tracking_events" ("shipment_id", "occurred_at");
alter table "better_supabase"."shipment_tracking_events" enable row level security;
revoke all on "better_supabase"."shipment_tracking_events" from anon, authenticated;
grant select on "better_supabase"."shipment_tracking_events" to authenticated;
grant all on "better_supabase"."shipment_tracking_events" to service_role;
drop policy if exists "shipment_tracking_events_read" on "better_supabase"."shipment_tracking_events";
create policy "shipment_tracking_events_read" on "better_supabase"."shipment_tracking_events" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shipments.read')));
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."shipments"'::regclass and conname = 'shipments_from_location_fkey'
  ) then
    alter table "better_supabase"."shipments" add constraint "shipments_from_location_fkey"
      foreign key ("from_location_id") references "better_supabase"."asset_locations" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."shipments" validate constraint "shipments_from_location_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."shipments"', '"better_supabase"."shipments"', 'shipments_from_location_fkey';
    end;
  end if;
end;
$$;

drop function if exists "better_supabase"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text, jsonb);
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
    and (case create_shipment.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_shipment.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_shipment.subject_id)::uuid)
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"));
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."get_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_shipment"(uuid) to authenticated, service_role;

-- A tenant's shipments, newest first, filtered by status, record or carrier.
create or replace function "better_supabase"."list_shipments"(tenant uuid, status text default null, subject_type text default null, subject_id text default null, carrier text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_shipments.tenant, 'shipments.read'), false)) then
    raise exception 'not allowed to read shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id")) as item, x."created_at" as created, x."id" as id
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
$$;
revoke execute on function "better_supabase"."list_shipments"(uuid, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_shipments"(uuid, text, text, text, text, timestamptz, integer) to authenticated, service_role;

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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"));
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
  return jsonb_build_object('recorded', v_count, 'shipment', jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id")));
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
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_shipment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_shipment"(uuid) to authenticated, service_role;

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

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."shipments_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."shipments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."shipments_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."shipments_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

-- blocks.shipments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_shipment"(uuid, jsonb, jsonb, jsonb, text, uuid, text, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

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
security invoker
set search_path = ''
as $$ select "better_supabase"."get_shipment"($1) $$;
revoke execute on function "api"."get_shipment"(uuid) from public, anon;
grant execute on function "api"."get_shipment"(uuid) to authenticated, service_role;

create or replace function "api"."list_shipments"(tenant uuid, status text default null, subject_type text default null, subject_id text default null, carrier text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_shipments"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_shipments"(uuid, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_shipments"(uuid, text, text, text, text, timestamptz, integer) to authenticated, service_role;

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

create or replace function "api"."list_tracking_events"(shipment_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tracking_events"($1) $$;
revoke execute on function "api"."list_tracking_events"(uuid) from public, anon;
grant execute on function "api"."list_tracking_events"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
