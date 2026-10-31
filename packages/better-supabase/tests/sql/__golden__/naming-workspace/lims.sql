-- ==== schema supabase/schemas/900_better_supabase_164_lims.sql
-- better-supabase module: lims
-- @bsb-block lims@1 managed
-- @bsb-hash sha256:9a6d135f3336ae7bbdc3c3b83e63bdd72707cddba37041c42a572e39c9a868da
-- Samples, test methods with specification limits, results through forms, a nonconformity case for every out of specification result and instruments from assets that must hold a valid qualification.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."lims_methods";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_methods";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_methods";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_methods";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_methods";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."lims_samples";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_samples";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_samples";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_samples";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_samples";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."lims_results";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_results";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_results";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_results";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_results";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A laboratory information system: samples, test methods with specification
-- limits, results and the instruments that produced them.

-- What a laboratory measures: a key, a unit and the specification limits a
-- result must stay within. form_id names the form that captures the readings.
create table if not exists "better_supabase"."lims_methods" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  "unit" text check ("unit" is null or length("unit") <= 40),
  "lower_limit" numeric,
  "upper_limit" numeric,
  "form_id" uuid,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  check ("lower_limit" is null or "upper_limit" is null or "lower_limit" <= "upper_limit")
);
alter table "better_supabase"."lims_methods" enable row level security;
revoke all on "better_supabase"."lims_methods" from public, anon, authenticated;
grant select on "better_supabase"."lims_methods" to authenticated;
grant all on "better_supabase"."lims_methods" to service_role;
drop policy if exists lims_methods_read on "better_supabase"."lims_methods";
create policy lims_methods_read on "better_supabase"."lims_methods"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')));

-- A sample received for testing. The number is SMP-1, SMP-2 and so on, or the
-- numbering block's format.
create table if not exists "better_supabase"."lims_samples" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" text not null,
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "kind" text check ("kind" is null or length("kind") <= 100),
  "lot" text check ("lot" is null or length("lot") <= 100),
  "received_on" date not null default current_date,
  "status" text not null default 'registered' check ("status" in ('registered', 'in_testing', 'completed', 'released', 'rejected')),
  "notes" text check ("notes" is null or length("notes") <= 4000),
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 500),
  "completed_at" timestamptz,
  "released_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "sequence")
);
create index if not exists "lims_samples_status_idx" on "better_supabase"."lims_samples" ("tenant_id", "status");
alter table "better_supabase"."lims_samples" enable row level security;
revoke all on "better_supabase"."lims_samples" from public, anon, authenticated;
grant select on "better_supabase"."lims_samples" to authenticated;
grant all on "better_supabase"."lims_samples" to service_role;
drop policy if exists lims_samples_read on "better_supabase"."lims_samples";
create policy lims_samples_read on "better_supabase"."lims_samples"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')));

-- One measurement of a method on a sample. outcome is decided from the
-- method's limits when the result is recorded; a retest adds a row and the
-- latest per method counts. instrument_id is an asset, submission_id the form
-- submission with the readings, case_id the nonconformity an out of
-- specification result raised.
create table if not exists "better_supabase"."lims_results" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "sample_id" uuid not null,
  "method_id" uuid not null,
  "value" numeric not null,
  "outcome" text not null check ("outcome" in ('in_spec', 'out_of_spec')),
  "instrument_id" uuid,
  "submission_id" uuid,
  "case_id" uuid,
  "note" text check ("note" is null or length("note") <= 2000),
  "tested_by" uuid,
  "tested_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now()
);
create index if not exists "lims_results_sample_idx" on "better_supabase"."lims_results" ("sample_id", "method_id", "tested_at" desc);
alter table "better_supabase"."lims_results" enable row level security;
revoke all on "better_supabase"."lims_results" from public, anon, authenticated;
grant select on "better_supabase"."lims_results" to authenticated;
grant all on "better_supabase"."lims_results" to service_role;
drop policy if exists lims_results_read on "better_supabase"."lims_results";
create policy lims_results_read on "better_supabase"."lims_results"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')));


-- Creates or updates a test method: what is measured, its unit and its specification limits.
-- input is { key, name, unit, lowerLimit, upperLimit, formId }; key is
-- lowercase letters, digits and underscores and cannot change once saved.
-- A result below lowerLimit or above upperLimit is out of specification. formId
-- names the form that captures the raw readings. Pass method_id to update.
-- Needs lims.manage.
create or replace function "better_supabase"."save_lims_method"(tenant uuid, input jsonb, method_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_methods";
  v_input jsonb := coalesce(save_lims_method.input, '{}'::jsonb);
  v_created boolean := save_lims_method.method_id is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_lims_method.tenant is not null and coalesce(better_supabase.can('tenant', save_lims_method.tenant, 'lims.manage'), false))) then
    raise exception 'not allowed to save test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_input ->> 'formId' is not null then
    raise exception 'formId needs the forms block' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  begin
    if save_lims_method.method_id is null then
      insert into "better_supabase"."lims_methods" ("tenant_id", "key", "name", "unit", "lower_limit", "upper_limit", "form_id")
      values (save_lims_method.tenant, v_input ->> 'key', trim(v_input ->> 'name'), nullif(trim(v_input ->> 'unit'), ''),
        (v_input ->> 'lowerLimit')::numeric, (v_input ->> 'upperLimit')::numeric, (v_input ->> 'formId')::uuid)
      returning * into v_row;
    else
      update "better_supabase"."lims_methods" x set "name" = trim(v_input ->> 'name'), "unit" = nullif(trim(v_input ->> 'unit'), ''),
        "lower_limit" = (v_input ->> 'lowerLimit')::numeric, "upper_limit" = (v_input ->> 'upperLimit')::numeric,
        "form_id" = (v_input ->> 'formId')::uuid, "updated_at" = now()
      where x."id" = save_lims_method.method_id and x."tenant_id" = save_lims_method.tenant
      returning * into v_row;
      if not found then
        raise exception 'no such test method' using errcode = 'P0002', hint = 'LIMS_METHOD_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'a method needs a key of lowercase letters, digits and underscores, a name of 1 to 200 characters and a lowerLimit not above the upperLimit' using errcode = '22023', hint = 'LIMS_INVALID';
  when unique_violation then
    raise exception 'this organization already has a method with that key' using errcode = '22023', hint = 'LIMS_INVALID';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'lowerLimit', v_row."lower_limit", 'upperLimit', v_row."upper_limit", 'formId', v_row."form_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_lims_method"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_lims_method"(uuid, jsonb, uuid) to authenticated, service_role;

-- Archives a method so no new result can use it. Its results stay. Needs
-- lims.manage.
create or replace function "better_supabase"."archive_lims_method"(method_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_methods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lims_methods" x where x."id" = archive_lims_method.method_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such test method' using errcode = 'P0002', hint = 'LIMS_METHOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.manage'), false))) then
    raise exception 'not allowed to archive test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  update "better_supabase"."lims_methods" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'lowerLimit', v_row."lower_limit", 'upperLimit', v_row."upper_limit", 'formId', v_row."form_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_lims_method"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_lims_method"(uuid) to authenticated, service_role;

-- The organization's test methods by key; archived ones only with
-- include_archived.
create or replace function "better_supabase"."list_lims_methods"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_lims_methods.tenant is not null and coalesce(better_supabase.can('tenant', list_lims_methods.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."lims_methods" x
    where x."tenant_id" = list_lims_methods.tenant
      and (coalesce(list_lims_methods.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_lims_methods"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_lims_methods"(uuid, boolean) to authenticated, service_role;

-- Registers a sample as received and numbers it (SMP-1, or the numbering
-- block's format for lims_sample). input is { title, kind, lot, receivedOn,
-- notes }. Needs lims.write.
create or replace function "better_supabase"."register_sample"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_samples";
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (register_sample.tenant is not null and coalesce(better_supabase.can('tenant', register_sample.tenant, 'lims.write'), false))) then
    raise exception 'not allowed to register samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if jsonb_typeof(register_sample.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_lims_sample_register"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using register_sample.tenant, register_sample.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'lims_sample' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'lims_sample' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(register_sample.tenant::text || ':lims_sample', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."lims_samples" x where x."tenant_id" = register_sample.tenant;
  v_number := 'SMP-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."lims_samples" ("tenant_id", "number", "sequence", "title", "kind", "lot", "received_on", "notes", "created_by")
    values (register_sample.tenant, v_number, v_seq, trim(register_sample.input ->> 'title'),
      nullif(trim(register_sample.input ->> 'kind'), ''), nullif(trim(register_sample.input ->> 'lot'), ''),
      coalesce((register_sample.input ->> 'receivedOn')::date, current_date),
      nullif(trim(register_sample.input ->> 'notes'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a sample needs a title of 1 to 200 characters, a kind and lot of up to 100 and notes of up to 4000' using errcode = '22023', hint = 'LIMS_INVALID';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_lims_sample_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'kind', v_row."kind", 'lot', v_row."lot", 'receivedOn', v_row."received_on", 'status', v_row."status", 'notes', v_row."notes", 'rejectionReason', v_row."rejection_reason", 'completedAt', v_row."completed_at", 'releasedAt', v_row."released_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_sample"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."register_sample"(uuid, jsonb) to authenticated, service_role;

-- One sample with its results, newest first.
create or replace function "better_supabase"."get_sample"(sample_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_samples";
begin
  select * into v_row from "better_supabase"."lims_samples" x where x."id" = get_sample.sample_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such sample' using errcode = 'P0002', hint = 'LIMS_SAMPLE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'kind', v_row."kind", 'lot', v_row."lot", 'receivedOn', v_row."received_on", 'status', v_row."status", 'notes', v_row."notes", 'rejectionReason', v_row."rejection_reason", 'completedAt', v_row."completed_at", 'releasedAt', v_row."released_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('results', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sampleId', y."sample_id", 'methodId', y."method_id", 'value', y."value", 'outcome', y."outcome", 'instrumentId', y."instrument_id", 'submissionId', y."submission_id", 'caseId', y."case_id", 'note', y."note", 'testedBy', y."tested_by", 'testedAt', y."tested_at", 'createdAt', y."created_at") order by y."tested_at" desc, y."id")
    from "better_supabase"."lims_results" y where y."sample_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_sample"(uuid) from public, anon;
grant execute on function "better_supabase"."get_sample"(uuid) to authenticated, service_role;

-- Samples, newest first. filters is { status, limit, offset }.
create or replace function "better_supabase"."list_samples"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_samples.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_samples.tenant is not null and coalesce(better_supabase.can('tenant', list_samples.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'number', y."number", 'title', y."title", 'kind', y."kind", 'lot', y."lot", 'receivedOn', y."received_on", 'status', y."status", 'notes', y."notes", 'rejectionReason', y."rejection_reason", 'completedAt', y."completed_at", 'releasedAt', y."released_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."sequence" desc)
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      order by x."sequence" desc
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_samples"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_samples"(uuid, jsonb) to authenticated, service_role;

-- Marks testing as done. The sample needs a result and must be in testing.
-- Needs lims.write.
create or replace function "better_supabase"."complete_sample"(sample_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_samples";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lims_samples" x where x."id" = complete_sample.sample_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such sample' using errcode = 'P0002', hint = 'LIMS_SAMPLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.write'), false))) then
    raise exception 'not allowed to complete samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_testing' then
    raise exception 'only a sample in testing can be completed' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  update "better_supabase"."lims_samples" x set "status" = 'completed', "completed_at" = now(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'kind', v_row."kind", 'lot', v_row."lot", 'receivedOn', v_row."received_on", 'status', v_row."status", 'notes', v_row."notes", 'rejectionReason', v_row."rejection_reason", 'completedAt', v_row."completed_at", 'releasedAt', v_row."released_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_sample"(uuid) from public, anon;
grant execute on function "better_supabase"."complete_sample"(uuid) to authenticated, service_role;

-- Releases a completed sample. Refused while the latest result of any method is
-- out of specification: record a passing retest first. Needs lims.manage.
create or replace function "better_supabase"."release_sample"(sample_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_samples";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lims_samples" x where x."id" = release_sample.sample_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such sample' using errcode = 'P0002', hint = 'LIMS_SAMPLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.manage'), false))) then
    raise exception 'not allowed to release samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_row."status" <> 'completed' then
    raise exception 'only a completed sample can be released' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if exists (
    select 1 from (
      select distinct on (y."method_id") y."outcome" as outcome
      from "better_supabase"."lims_results" y where y."sample_id" = v_row."id"
      order by y."method_id", y."tested_at" desc, y."id" desc
    ) latest where latest.outcome = 'out_of_spec'
  ) then
    raise exception 'a method has an out of specification result; record a passing retest first' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  update "better_supabase"."lims_samples" x set "status" = 'released', "released_at" = now(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'kind', v_row."kind", 'lot', v_row."lot", 'receivedOn', v_row."received_on", 'status', v_row."status", 'notes', v_row."notes", 'rejectionReason', v_row."rejection_reason", 'completedAt', v_row."completed_at", 'releasedAt', v_row."released_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_sample"(uuid) from public, anon;
grant execute on function "better_supabase"."release_sample"(uuid) to authenticated, service_role;

-- Rejects a sample that is not released yet, with a reason of up to 500
-- characters. Needs lims.manage.
create or replace function "better_supabase"."reject_sample"(sample_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_samples";
  v_reason text := trim(reject_sample.reason);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lims_samples" x where x."id" = reject_sample.sample_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such sample' using errcode = 'P0002', hint = 'LIMS_SAMPLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.manage'), false))) then
    raise exception 'not allowed to reject samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_reason is null or length(v_reason) not between 1 and 500 then
    raise exception 'a rejection needs a reason of 1 to 500 characters' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_row."status" not in ('registered', 'in_testing', 'completed') then
    raise exception 'a released or rejected sample cannot be rejected' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  update "better_supabase"."lims_samples" x set "status" = 'rejected', "rejection_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'kind', v_row."kind", 'lot', v_row."lot", 'receivedOn', v_row."received_on", 'status', v_row."status", 'notes', v_row."notes", 'rejectionReason', v_row."rejection_reason", 'completedAt', v_row."completed_at", 'releasedAt', v_row."released_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_sample"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_sample"(uuid, text) to authenticated, service_role;

-- Records a result of a test method on a sample, as input { value, instrumentId,
-- submissionId, testedAt, note }. The result is checked against the method's
-- limits and an out of specification result raises the nonconformity case
-- (options.nonconformityKind) when the cases block is installed. The first
-- result moves the sample into testing. With options.instrumentQualification
-- the instrument must hold that qualification on the test date. Retests add
-- results; the latest per method counts. Needs lims.write.
create or replace function "better_supabase"."record_lims_result"(sample_id uuid, method_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sample "better_supabase"."lims_samples";
  v_method "better_supabase"."lims_methods";
  v_row "better_supabase"."lims_results";
  v_input jsonb := coalesce(record_lims_result.input, '{}'::jsonb);
  v_value numeric;
  v_instrument uuid;
  v_submission uuid;
  v_tested timestamptz;
  v_outcome text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sample from "better_supabase"."lims_samples" x where x."id" = record_lims_result.sample_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sample."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sample."tenant_id", 'lims.read'), false))) then
    raise exception 'no such sample' using errcode = 'P0002', hint = 'LIMS_SAMPLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sample."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sample."tenant_id", 'lims.write'), false))) then
    raise exception 'not allowed to record results' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_sample."status" not in ('registered', 'in_testing') then
    raise exception 'results can only be recorded while a sample is registered or in testing' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select * into v_method from "better_supabase"."lims_methods" x
  where x."id" = record_lims_result.method_id and x."tenant_id" = v_sample."tenant_id";
  if not found then
    raise exception 'no such test method' using errcode = 'P0002', hint = 'LIMS_METHOD_NOT_FOUND';
  end if;
  if v_method."archived_at" is not null then
    raise exception 'this method is archived' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  begin
    v_value := (v_input ->> 'value')::numeric;
    v_instrument := (v_input ->> 'instrumentId')::uuid;
    v_submission := (v_input ->> 'submissionId')::uuid;
    v_tested := coalesce((v_input ->> 'testedAt')::timestamptz, now());
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise exception 'value is a number, instrumentId and submissionId are ids and testedAt is a timestamp' using errcode = '22023', hint = 'LIMS_INVALID';
  end;
  if v_value is null or v_value = 'NaN'::numeric then
    raise exception 'a result needs a value' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  
  if v_instrument is not null then
    raise exception 'instrumentId needs the assets block' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_submission is not null then
    raise exception 'submissionId needs the forms block' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_lims_result_record"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using record_lims_result.sample_id, record_lims_result.method_id, record_lims_result.input;
    end if;
  end;
  v_outcome := case
    when (v_method."lower_limit" is not null and v_value < v_method."lower_limit")
      or (v_method."upper_limit" is not null and v_value > v_method."upper_limit") then 'out_of_spec'
    else 'in_spec'
  end;
  begin
    insert into "better_supabase"."lims_results" ("tenant_id", "sample_id", "method_id", "value", "outcome", "instrument_id", "submission_id", "note", "tested_by", "tested_at")
    values (v_sample."tenant_id", v_sample."id", v_method."id", v_value, v_outcome, v_instrument, v_submission,
      nullif(trim(v_input ->> 'note'), ''), auth.uid(), v_tested)
    returning * into v_row;
  exception when check_violation then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'LIMS_INVALID';
  end;
  if v_sample."status" = 'registered' then
    update "better_supabase"."lims_samples" x set "status" = 'in_testing', "updated_at" = now() where x."id" = v_sample."id";
  end if;
  null;
  if v_outcome = 'out_of_spec' then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_lims_result_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sampleId', v_row."sample_id", 'methodId', v_row."method_id", 'value', v_row."value", 'outcome', v_row."outcome", 'instrumentId', v_row."instrument_id", 'submissionId', v_row."submission_id", 'caseId', v_row."case_id", 'note', v_row."note", 'testedBy', v_row."tested_by", 'testedAt', v_row."tested_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_lims_result"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_lims_result"(uuid, uuid, jsonb) to authenticated, service_role;

-- Whether an instrument (an asset) may be used on a day. Without
-- options.instrumentQualification every instrument may. Returns { instrumentId,
-- required, qualified }.
create or replace function "better_supabase"."instrument_status"(tenant uuid, asset_id uuid, on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (instrument_status.tenant is not null and coalesce(better_supabase.can('tenant', instrument_status.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read instruments' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  return jsonb_build_object('instrumentId', instrument_status.asset_id, 'required', false, 'qualified', true);
end;
$$;
revoke execute on function "better_supabase"."instrument_status"(uuid, uuid, date) from public, anon;
grant execute on function "better_supabase"."instrument_status"(uuid, uuid, date) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."lims_methods";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_methods";
create policy bsb_tenant_scope_select on "better_supabase"."lims_methods" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_methods";
create policy bsb_tenant_scope_insert on "better_supabase"."lims_methods" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_methods";
create policy bsb_tenant_scope_update on "better_supabase"."lims_methods" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_methods";
create policy bsb_tenant_scope_delete on "better_supabase"."lims_methods" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."lims_samples";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_samples";
create policy bsb_tenant_scope_select on "better_supabase"."lims_samples" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_samples";
create policy bsb_tenant_scope_insert on "better_supabase"."lims_samples" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_samples";
create policy bsb_tenant_scope_update on "better_supabase"."lims_samples" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_samples";
create policy bsb_tenant_scope_delete on "better_supabase"."lims_samples" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."lims_results";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."lims_results";
create policy bsb_tenant_scope_select on "better_supabase"."lims_results" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('lims.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."lims_results";
create policy bsb_tenant_scope_insert on "better_supabase"."lims_results" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."lims_results";
create policy bsb_tenant_scope_update on "better_supabase"."lims_results" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."lims_results";
create policy bsb_tenant_scope_delete on "better_supabase"."lims_results" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_164_lims.sql
-- better-supabase module: lims
-- @bsb-block-data lims
-- @bsb-hash sha256:7b7e412cabd4be556c915fdce87de40880f85a2850a13ec2253ba8cffc91fa5e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lims', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
