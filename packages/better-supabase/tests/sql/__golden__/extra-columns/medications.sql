-- ==== schema supabase/schemas/900_better_supabase_150_medications.sql
-- better-supabase module: medications
-- @bsb-block medications@1 managed
-- @bsb-hash sha256:1f4479d75467d89f92ad26324fdddab61a59a010e6bc1470582490f69f4ba027
-- A medication catalog per organization, orders for a record with a dose, route, schedule and an as-needed maximum, orders imported from a pharmacy, planned doses, each dose recorded as given, refused, skipped or missed with a second check for high-risk medication, and a medication chart per record.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."medications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."medications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."medications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medications";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."medication_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."medication_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medication_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."medication_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medication_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."medication_administrations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."medication_administrations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medication_administrations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."medication_administrations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medication_administrations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Medications: the organization's catalog, orders for a record with a dose,
-- route and schedule, planned doses, and each dose given, refused, skipped or
-- missed, with a second check for high-risk medication.

create table if not exists "better_supabase"."medications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 300),
  -- The catalog the code is from; custom is the organization's own entry.
  "code_system" text not null default 'custom' check ("code_system" in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom')),
  "code" text check ("code" is null or length("code") between 1 and 100),
  "form" text check ("form" is null or length("form") <= 100),
  "strength" text check ("strength" is null or length("strength") <= 100),
  "unit" text not null check (length("unit") between 1 and 50),
  -- A dose of a high-risk medication needs a second member to check it.
  "high_risk" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "medications_tenant_idx" on "better_supabase"."medications" ("tenant_id", "name");
create unique index if not exists "medications_code_idx" on "better_supabase"."medications" ("tenant_id", "code_system", "code") where "code" is not null;
alter table "better_supabase"."medications" enable row level security;
revoke all on "better_supabase"."medications" from public, anon, authenticated;
grant select on "better_supabase"."medications" to authenticated;
grant all on "better_supabase"."medications" to service_role;
drop policy if exists medications_read on "better_supabase"."medications";
create policy medications_read on "better_supabase"."medications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')));

create table if not exists "better_supabase"."medication_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The record the order is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  "medication_id" uuid not null,
  "dose" numeric not null check ("dose" > 0),
  "dose_unit" text not null check (length("dose_unit") between 1 and 50),
  "route" text check ("route" is null or length("route") <= 100),
  -- {times: ["08:00"]} or {everyHours: 8, startTime: "06:00"}, with optional
  -- ISO weekdays; null for an order given only as needed.
  "schedule" jsonb,
  "as_needed" boolean not null default false,
  "as_needed_reason" text check ("as_needed_reason" is null or length("as_needed_reason") <= 500),
  -- The most of the dose unit given in any 24 hours, for an as-needed order.
  "max_per_day" numeric check ("max_per_day" is null or "max_per_day" > 0),
  "starts_on" date not null,
  "ends_on" date,
  "prescriber" text check ("prescriber" is null or length("prescriber") <= 300),
  "source" text not null default 'prescriber' check ("source" in ('prescriber', 'pharmacy', 'import')),
  -- The order's id in the pharmacy or prescribing system it was imported from.
  "external_id" text check ("external_id" is null or length("external_id") <= 200),
  "requires_double_check" boolean not null default false,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'stopped')),
  "stopped_reason" text check ("stopped_reason" is null or length("stopped_reason") <= 1000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  check ("as_needed" or "schedule" is not null),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "medication_id") references "better_supabase"."medications" ("tenant_id", "id")
);
alter table "better_supabase"."medication_orders" add column if not exists "app_note" text;
create index if not exists "medication_orders_item_idx" on "better_supabase"."medication_orders" ("tenant_id", "medication_id");
create index if not exists "medication_orders_subject_idx" on "better_supabase"."medication_orders" ("subject_type", "subject_id");
create index if not exists "medication_orders_status_idx" on "better_supabase"."medication_orders" ("tenant_id", "status");
create unique index if not exists "medication_orders_external_idx" on "better_supabase"."medication_orders" ("tenant_id", "external_id") where "external_id" is not null;
alter table "better_supabase"."medication_orders" enable row level security;
revoke all on "better_supabase"."medication_orders" from public, anon, authenticated;
grant select on "better_supabase"."medication_orders" to authenticated;
grant all on "better_supabase"."medication_orders" to service_role;
drop policy if exists medication_orders_read on "better_supabase"."medication_orders";
create policy medication_orders_read on "better_supabase"."medication_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "better_supabase"."medication_administrations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  -- The planned time; null for an as-needed dose.
  "scheduled_at" timestamptz,
  "administered_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'given', 'refused', 'skipped', 'missed')),
  "dose" numeric check ("dose" is null or "dose" > 0),
  "performer_id" uuid,
  -- The second member who checked a high-risk dose.
  "checked_by" uuid,
  "reason" text check ("reason" is null or length("reason") <= 1000),
  "note" text check ("note" is null or length("note") <= 2000),
  check ("checked_by" is null or "checked_by" is distinct from "performer_id"),
  unique ("order_id", "scheduled_at"),
  foreign key ("tenant_id", "order_id") references "better_supabase"."medication_orders" ("tenant_id", "id") on delete cascade
);
create index if not exists "medication_administrations_order_idx" on "better_supabase"."medication_administrations" ("tenant_id", "order_id");
create index if not exists "medication_administrations_planned_idx" on "better_supabase"."medication_administrations" ("scheduled_at") where "status" = 'planned';
create index if not exists "medication_administrations_given_idx" on "better_supabase"."medication_administrations" ("order_id", "administered_at") where "status" = 'given';
alter table "better_supabase"."medication_administrations" enable row level security;
revoke all on "better_supabase"."medication_administrations" from public, anon, authenticated;
grant select on "better_supabase"."medication_administrations" to authenticated;
grant all on "better_supabase"."medication_administrations" to service_role;
drop policy if exists medication_administrations_read on "better_supabase"."medication_administrations";
create policy medication_administrations_read on "better_supabase"."medication_administrations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')) and exists (select 1 from "better_supabase"."medication_orders" x where x."id" = "order_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a medication to the organization's catalog, or changes one
-- (medication_id). A code from a catalog other than custom is unique in the
-- organization.
create or replace function "better_supabase"."save_medication"(tenant uuid, name text, unit text, code_system text default 'custom', code text default null, form text default null, strength text default null, high_risk boolean default false, medication_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  v_name := nullif(trim(save_medication.name), '');
  v_med_unit := nullif(trim(save_medication.unit), '');
  v_system := coalesce(nullif(trim(save_medication.code_system), ''), 'custom');
  v_code := nullif(trim(save_medication.code), '');
  v_form := nullif(trim(save_medication.form), '');
  v_strength := nullif(trim(save_medication.strength), '');
  v_high_risk := coalesce(save_medication.high_risk, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."medications" x
    where x."tenant_id" = save_medication.tenant and x."code_system" = v_system and x."code" = v_code
      and x."id" is distinct from save_medication.medication_id
  ) then
    raise exception 'the catalog already has a medication with this code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if save_medication.medication_id is null then
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (save_medication.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  else
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "archived_at" = null,
    "updated_at" = now()
    where x."id" = save_medication.medication_id and x."tenant_id" = save_medication.tenant
    returning x.* into v_medication;
    if not found then
      raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) to authenticated, service_role;

-- Archives a medication: new orders can't use it; its orders stay.
create or replace function "better_supabase"."archive_medication"(medication_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_medication from "better_supabase"."medications" x where x."id" = archive_medication.medication_id;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_medication."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  update "better_supabase"."medications" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_medication."id"
  returning x.* into v_medication;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_medication"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_medication"(uuid) to authenticated, service_role;

-- Stores an item picked from a MedicationCatalog (name, unit, codeSystem,
-- code, form, strength, highRisk) in the organization's catalog. An item
-- already there under its code is updated, so picking it twice is safe.
create or replace function "better_supabase"."import_medication"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', import_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if import_medication.item is null or jsonb_typeof(import_medication.item) <> 'object' then
    raise exception 'a catalog item is an object' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  v_name := nullif(trim(import_medication.item ->> 'name'), '');
  v_med_unit := nullif(trim(import_medication.item ->> 'unit'), '');
  v_system := coalesce(nullif(trim(import_medication.item ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim(import_medication.item ->> 'code'), '');
  v_form := nullif(trim(import_medication.item ->> 'form'), '');
  v_strength := nullif(trim(import_medication.item ->> 'strength'), '');
  v_high_risk := coalesce((import_medication.item ->> 'highRisk')::boolean, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."tenant_id" = import_medication.tenant and x."code_system" = v_system and x."code" = v_code
  for update;
  if found then
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "updated_at" = now()
    where x."id" = v_medication."id"
    returning x.* into v_medication;
  else
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (import_medication.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$$;
revoke execute on function "better_supabase"."import_medication"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_medication"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_medications"(tenant uuid, search text default null, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'codeSystem', x."code_system", 'code', x."code", 'form', x."form", 'strength', x."strength", 'unit', x."unit", 'highRisk', x."high_risk", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."medications" x
  where x."tenant_id" = list_medications.tenant
    and (coalesce(list_medications.include_archived, false) or x."archived_at" is null)
    and (nullif(trim(list_medications.search), '') is null
      or x."name" ilike '%' || trim(list_medications.search) || '%'
      or x."code" = trim(list_medications.search))
$$;
revoke execute on function "better_supabase"."list_medications"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_medications"(uuid, text, boolean) to authenticated, service_role;

-- Prescribes a medication for a record. attrs holds dose, doseUnit (the
-- medication's unit by default), route, schedule, asNeeded, asNeededReason,
-- maxPerDay, startsOn (today by default), endsOn, prescriber,
-- requiresDoubleCheck and fields, the extra columns by name.
create or replace function "better_supabase"."prescribe_medication"(tenant uuid, subject_type text, subject_id text, medication_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_attrs jsonb := coalesce(prescribe_medication.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', prescribe_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."id" = prescribe_medication.medication_id and x."tenant_id" = prescribe_medication.tenant and x."archived_at" is null;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_attrs ? 'fields' and jsonb_typeof(v_attrs -> 'fields') <> 'object' then
    raise exception 'fields is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_prescribe"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, prescribe_medication.medication_id;
    end if;
  end;
  insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, 'prescriber', null, v_double, (select auth.uid()))
    returning * into v_row;
  update "better_supabase"."medication_orders" x set "app_note" = case when coalesce(v_attrs -> 'fields', '{}'::jsonb) ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."medication_orders", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(coalesce(v_attrs -> 'fields', '{}'::jsonb)) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_prescribe"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."prescribe_medication"(uuid, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."prescribe_medication"(uuid, text, text, uuid, jsonb) to authenticated, service_role;

-- Imports orders from a pharmacy or prescribing system. Each item has
-- subjectType, subjectId, externalId, a medicationId or a catalog item under
-- medication, and the order fields prescribe_medication takes. An item whose
-- externalId was imported before is skipped, so the import can run again.
create or replace function "better_supabase"."import_medication_orders"(tenant uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_item jsonb;
  v_external text;
  v_created jsonb := '[]'::jsonb;
  v_skipped integer := 0;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if import_medication_orders.items is null or jsonb_typeof(import_medication_orders.items) <> 'array' then
    raise exception 'items is an array' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(import_medication_orders.items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'each item is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null then
      raise exception 'each imported order needs an externalId' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."medication_orders" x where x."tenant_id" = import_medication_orders.tenant and x."external_id" = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if jsonb_typeof(v_item -> 'medication') = 'object' then
      v_name := nullif(trim((v_item -> 'medication') ->> 'name'), '');
  v_med_unit := nullif(trim((v_item -> 'medication') ->> 'unit'), '');
  v_system := coalesce(nullif(trim((v_item -> 'medication') ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim((v_item -> 'medication') ->> 'code'), '');
  v_form := nullif(trim((v_item -> 'medication') ->> 'form'), '');
  v_strength := nullif(trim((v_item -> 'medication') ->> 'strength'), '');
  v_high_risk := coalesce(((v_item -> 'medication') ->> 'highRisk')::boolean, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."tenant_id" = import_medication_orders.tenant and x."code_system" = v_system and x."code" = v_code
  for update;
  if found then
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "updated_at" = now()
    where x."id" = v_medication."id"
    returning x.* into v_medication;
  else
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (import_medication_orders.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;
    else
      select * into v_medication from "better_supabase"."medications" x
      where x."id" = (v_item ->> 'medicationId')::uuid and x."tenant_id" = import_medication_orders.tenant;
      if not found then
        raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
      end if;
    end if;
    v_dose := case when v_item ? 'dose' then ((v_item -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_item ? 'doseUnit' then nullif(trim((v_item -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_item ? 'route' then nullif(trim((v_item -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_item ? 'schedule' then nullif((v_item -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_item ? 'asNeeded' then ((v_item -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_item ? 'asNeededReason' then nullif(trim((v_item -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_item ? 'maxPerDay' then ((v_item -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_item ? 'startsOn' then ((v_item -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_item ? 'endsOn' then ((v_item -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_item ? 'prescriber' then nullif(trim((v_item -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_item ? 'requiresDoubleCheck' then ((v_item -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
    if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
    if v_item ? 'fields' and jsonb_typeof(v_item -> 'fields') <> 'object' then
    raise exception 'fields is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
    insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (import_medication_orders.tenant, v_item ->> 'subjectType', v_item ->> 'subjectId', v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, coalesce(nullif(v_item ->> 'source', ''), 'import'), v_external, v_double, (select auth.uid()))
    returning * into v_row;
  update "better_supabase"."medication_orders" x set "app_note" = case when coalesce(v_item -> 'fields', '{}'::jsonb) ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."medication_orders", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(coalesce(v_item -> 'fields', '{}'::jsonb)) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note")));
  end loop;
  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_medication_orders"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_medication_orders"(uuid, jsonb) to service_role;

-- Changes an order's dose, unit, route, schedule, as-needed fields, dates,
-- prescriber, double check or extra columns (fields); a key attrs leaves out
-- keeps its value. The
-- planned doses after now are removed for planning to make again.
create or replace function "better_supabase"."update_medication_order"(order_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_attrs jsonb := coalesce(update_medication_order.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = update_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else v_row."dose" end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_row."dose_unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else v_row."route" end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else v_row."schedule" end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else v_row."as_needed" end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else v_row."as_needed_reason" end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else v_row."max_per_day" end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else v_row."ends_on" end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else v_row."prescriber" end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else v_row."requires_double_check" end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_attrs ? 'fields' and jsonb_typeof(v_attrs -> 'fields') <> 'object' then
    raise exception 'fields is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  update "better_supabase"."medication_orders" x set
    "dose" = v_dose,
    "dose_unit" = v_unit,
    "route" = v_route,
    "schedule" = v_schedule,
    "as_needed" = v_as_needed,
    "as_needed_reason" = v_as_needed_reason,
    "max_per_day" = v_max,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "prescriber" = v_prescriber,
    "requires_double_check" = v_double,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  update "better_supabase"."medication_orders" x set "app_note" = case when coalesce(v_attrs -> 'fields', '{}'::jsonb) ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."medication_orders", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(coalesce(v_attrs -> 'fields', '{}'::jsonb)) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."update_medication_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_medication_order"(uuid, jsonb) to authenticated, service_role;

-- Pauses an active order (paused true) or resumes a paused one. A paused
-- order gets no planned doses; the ones after now are removed.
create or replace function "better_supabase"."pause_medication_order"(order_id uuid, paused boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_status text := case when coalesce(pause_medication_order.paused, true) then 'paused' else 'active' end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = pause_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_row."status" = v_status then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
  end if;
  update "better_supabase"."medication_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  if v_status = 'paused' then
    delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."pause_medication_order"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."pause_medication_order"(uuid, boolean) to authenticated, service_role;

-- Stops an order for good, with the reason. The planned doses after now are
-- removed; the doses already recorded stay on the chart.
create or replace function "better_supabase"."stop_medication_order"(order_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(stop_medication_order.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = stop_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_reason is null then
    raise exception 'stopping an order needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_row."status" = 'stopped' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."medication_orders" x set "status" = 'stopped', "stopped_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."stop_medication_order"(uuid, text) from public, anon;
grant execute on function "better_supabase"."stop_medication_order"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."medication_orders_of"(subject_type text, subject_id text, include_stopped boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."medication_orders" x
  join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
  where x."subject_type" = medication_orders_of.subject_type
    and x."subject_id" = medication_orders_of.subject_id
    and (coalesce(medication_orders_of.include_stopped, false) or x."status" <> 'stopped')
$$;
revoke execute on function "better_supabase"."medication_orders_of"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."medication_orders_of"(text, text, boolean) to authenticated, service_role;

-- Plans the doses of the organization's active scheduled orders from now
-- until `until` (at most 31 days ahead), in the block's time zone. A dose
-- already planned is kept, so the planner can run on a timer. Returns how many
-- doses it planned.
create or replace function "better_supabase"."plan_medication_administrations"(tenant uuid, until timestamptz)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order "better_supabase"."medication_orders"%rowtype;
  v_until timestamptz;
  v_today date := (now() at time zone 'UTC')::date;
  v_last date;
  v_count integer := 0;
  v_planned integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', plan_medication_administrations.tenant, 'medications.manage'), false)) then
    raise exception 'not allowed to plan medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if plan_medication_administrations.until is null then
    raise exception 'planning needs an end time' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_until := least(plan_medication_administrations.until, now() + interval '31 days');
  v_last := (v_until at time zone 'UTC')::date;
  for v_order in
    select * from "better_supabase"."medication_orders" x
    where x."tenant_id" = plan_medication_administrations.tenant
      and x."status" = 'active'
      and x."schedule" is not null
      and x."starts_on" <= v_last
      and (x."ends_on" is null or x."ends_on" >= v_today)
  loop
    insert into "better_supabase"."medication_administrations" ("tenant_id", "order_id", "scheduled_at", "status", "dose")
    select v_order."tenant_id", v_order."id", s.at, 'planned', v_order."dose"
    from (
      select ((d.day + make_interval(mins => t.minute)) at time zone 'UTC') as at
      from generate_series(0, least(coalesce(v_order."ends_on", v_last), v_last) - greatest(v_order."starts_on", v_today)) as g(n)
      cross join lateral (select greatest(v_order."starts_on", v_today) + g.n as day) d
      cross join lateral (
        select split_part(x #>> '{}', ':', 1)::integer * 60 + split_part(x #>> '{}', ':', 2)::integer as minute
        from jsonb_array_elements(coalesce(v_order."schedule" -> 'times', '[]'::jsonb)) x
        union
        select coalesce(split_part(v_order."schedule" ->> 'startTime', ':', 1)::integer * 60 + split_part(v_order."schedule" ->> 'startTime', ':', 2)::integer, 0) + k * (v_order."schedule" ->> 'everyHours')::integer * 60
        from generate_series(0, 23) k
        where v_order."schedule" ? 'everyHours' and coalesce(split_part(v_order."schedule" ->> 'startTime', ':', 1)::integer * 60 + split_part(v_order."schedule" ->> 'startTime', ':', 2)::integer, 0) + k * (v_order."schedule" ->> 'everyHours')::integer * 60 < 1440
      ) t
      where not (v_order."schedule" ? 'weekdays')
        or extract(isodow from d.day)::integer in (select (w #>> '{}')::integer from jsonb_array_elements(v_order."schedule" -> 'weekdays') w)
    ) s
    where s.at > now() and s.at <= v_until
    on conflict ("order_id", "scheduled_at") do nothing;
    get diagnostics v_planned = row_count;
    v_count := v_count + v_planned;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."plan_medication_administrations"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."plan_medication_administrations"(uuid, timestamptz) to authenticated, service_role;

-- Records a planned or missed dose as given, refused or skipped. refused and
-- skipped need a reason. A dose of a high-risk medication, or of an order that
-- requires it, needs checked_by: another member who may administer.
create or replace function "better_supabase"."record_medication_administration"(administration_id uuid, status text, dose numeric default null, reason text default null, checked_by uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_status text := lower(trim(record_medication_administration.status));
  v_reason text := nullif(trim(record_medication_administration.reason), '');
  v_dose numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_administrations" x where x."id" = record_medication_administration.administration_id for update;
  if not found then
    raise exception 'medication dose not found' using errcode = 'P0002', hint = 'MEDICATION_ADMINISTRATION_NOT_FOUND';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_status is null or v_status not in ('given', 'refused', 'skipped') then
    raise exception 'a dose is recorded as given, refused or skipped' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_row."status" not in ('planned', 'missed') then
    raise exception 'the dose is already recorded' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_status in ('refused', 'skipped') and v_reason is null then
    raise exception 'a refused or skipped dose needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_status = 'given' then
    v_dose := coalesce(record_medication_administration.dose, v_row."dose", v_order."dose");
    if v_dose <= 0 then
      raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
    end if;
    if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_medication_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_medication_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_medication_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", v_status;
    end if;
  end;
  update "better_supabase"."medication_administrations" x set
    "status" = v_status,
    "administered_at" = now(),
    "dose" = case when v_status = 'given' then v_dose else x."dose" end,
    "performer_id" = (select auth.uid()),
    "checked_by" = case when v_status = 'given' then record_medication_administration.checked_by end,
    "reason" = v_reason, "note" = nullif(trim(record_medication_administration.note), '')
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note");
end;
$$;
revoke execute on function "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text) to authenticated, service_role;

-- Records a dose of an as-needed order, with the reason it was given. The
-- doses given in the last 24 hours plus this one stay within max_per_day.
create or replace function "better_supabase"."record_as_needed_administration"(order_id uuid, dose numeric default null, reason text default null, checked_by uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(record_as_needed_administration.reason), '');
  v_dose numeric;
  v_given numeric;
  v_today date := (now() at time zone 'UTC')::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = record_as_needed_administration.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not v_order."as_needed" then
    raise exception 'the order isn''t given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_order."status" <> 'active' or v_order."starts_on" > v_today or v_order."ends_on" < v_today then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_reason is null then
    raise exception 'an as-needed dose needs the reason it was given' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  v_dose := coalesce(record_as_needed_administration.dose, v_order."dose");
  if v_dose <= 0 then
    raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."max_per_day" is not null then
    select coalesce(sum(x."dose"), 0) into v_given from "better_supabase"."medication_administrations" x
    where x."order_id" = v_order."id" and x."status" = 'given' and x."administered_at" > now() - interval '24 hours';
    if v_given + v_dose > v_order."max_per_day" then
      raise exception 'this dose goes over the most the order allows in 24 hours' using errcode = '22023', hint = 'MEDICATION_MAX_DOSE_EXCEEDED';
    end if;
  end if;
  if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_as_needed_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_as_needed_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_as_needed_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", 'given';
    end if;
  end;
  insert into "better_supabase"."medication_administrations" ("tenant_id", "order_id", "administered_at", "status", "dose", "performer_id", "checked_by", "reason", "note")
  values (v_order."tenant_id", v_order."id", now(), 'given', v_dose, (select auth.uid()), record_as_needed_administration.checked_by, v_reason, nullif(trim(record_as_needed_administration.note), ''))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note");
end;
$$;
revoke execute on function "better_supabase"."record_as_needed_administration"(uuid, numeric, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_as_needed_administration"(uuid, numeric, text, uuid, text) to authenticated, service_role;

-- Marks the planned doses more than 60 minutes past their time as missed,
-- and tells the members who manage medication. Run it on a timer.
create or replace function "better_supabase"."mark_missed_medication_administrations"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."medication_administrations" x set "status" = 'missed'
    where x."status" = 'planned' and x."scheduled_at" < now() - interval '60 minutes'
    returning x.*
  loop
    select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
    null;
    
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."mark_missed_medication_administrations"() from public, anon, authenticated;
grant execute on function "better_supabase"."mark_missed_medication_administrations"() to service_role;

-- The orders of a record that run between since and until (today in the
-- block's time zone by default), with their medication, and the doses
-- planned or recorded in that range.
create or replace function "better_supabase"."medication_chart"(subject_type text, subject_id text, since timestamptz default null, until timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select
      coalesce(medication_chart.since, (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) as since,
      coalesce(medication_chart.until, ((date_trunc('day', now() at time zone 'UTC') + interval '1 day') at time zone 'UTC')) as until
  )
  select jsonb_build_object(
    'since', b.since,
    'until', b.until,
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on", x."id")
      from "better_supabase"."medication_orders" x
      join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and x."starts_on" <= (b.until at time zone 'UTC')::date
        and (x."ends_on" is null or x."ends_on" >= (b.since at time zone 'UTC')::date)
    ), '[]'::jsonb),
    'administrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'orderId', z."order_id", 'scheduledAt', z."scheduled_at", 'administeredAt', z."administered_at", 'status', z."status", 'dose', z."dose", 'performerId', z."performer_id", 'checkedBy', z."checked_by", 'reason', z."reason", 'note', z."note") order by coalesce(z."scheduled_at", z."administered_at"), z."id")
      from "better_supabase"."medication_administrations" z
      join "better_supabase"."medication_orders" x on x."tenant_id" = z."tenant_id" and x."id" = z."order_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and coalesce(z."scheduled_at", z."administered_at") >= b.since
        and coalesce(z."scheduled_at", z."administered_at") < b.until
    ), '[]'::jsonb)
  )
  from bounds b
$$;
revoke execute on function "better_supabase"."medication_chart"(text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."medication_chart"(text, text, timestamptz, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."medications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."medications";
create policy bsb_tenant_scope_select on "better_supabase"."medications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medications";
create policy bsb_tenant_scope_insert on "better_supabase"."medications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."medications";
create policy bsb_tenant_scope_update on "better_supabase"."medications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medications";
create policy bsb_tenant_scope_delete on "better_supabase"."medications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."medication_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."medication_orders";
create policy bsb_tenant_scope_select on "better_supabase"."medication_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medication_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."medication_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."medication_orders";
create policy bsb_tenant_scope_update on "better_supabase"."medication_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medication_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."medication_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."medication_administrations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."medication_administrations";
create policy bsb_tenant_scope_select on "better_supabase"."medication_administrations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('medications.read')) and exists (select 1 from "better_supabase"."medication_orders" x where x."id" = "order_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."medication_administrations";
create policy bsb_tenant_scope_insert on "better_supabase"."medication_administrations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."medication_administrations";
create policy bsb_tenant_scope_update on "better_supabase"."medication_administrations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."medication_administrations";
create policy bsb_tenant_scope_delete on "better_supabase"."medication_administrations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_150_medications.sql
-- better-supabase module: medications
-- @bsb-block-data medications
-- @bsb-hash sha256:5a31b4489eba3fccd92a203fd47e002c98354a7226595d3ed756da092d3c5994
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('medications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
