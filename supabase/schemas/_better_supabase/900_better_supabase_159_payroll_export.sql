-- better-supabase module: payroll-export
-- @bsb-block payroll-export@1 managed
-- @bsb-hash sha256:448ed0be772acb6006cf7537db94de11ed5bd50c43580509393625a567ad4081
-- Payroll runs that collect the hours worked, the approved leave and optionally the scheduled shifts of a period into lines per person, locked by an export through a versioned PayrollExportFormat port.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."payroll_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."payroll_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."payroll_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."payroll_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."payroll_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."payroll_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."payroll_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."payroll_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."payroll_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."payroll_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Payroll runs per organization: one run collects the hours worked, the
-- approved leave and optionally the scheduled shifts of a period into lines per
-- person. A PayrollExportFormat renders the lines in TypeScript; exporting
-- locks the run and keeps the checksum of the file.
create table if not exists "better_supabase"."payroll_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "period_from" date not null,
  "period_to" date not null,
  "label" text check ("label" is null or length("label") between 1 and 200),
  "status" text not null default 'draft' check ("status" in ('draft', 'exported')),
  "format" text check ("format" is null or length("format") between 1 and 100),
  -- The hex SHA-256 of the exported file.
  "checksum" text check ("checksum" is null or "checksum" ~ '^[0-9a-f]{64}$'),
  "exported_at" timestamptz,
  "exported_by" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("period_from" <= "period_to"),
  check ("period_to" - "period_from" <= 400),
  check (("status" = 'exported') = ("exported_at" is not null and "format" is not null and "checksum" is not null))
);
create index if not exists "payroll_runs_tenant_idx" on "better_supabase"."payroll_runs" ("tenant_id", "period_from" desc);
alter table "better_supabase"."payroll_runs" enable row level security;
revoke all on "better_supabase"."payroll_runs" from public, anon, authenticated;
grant select on "better_supabase"."payroll_runs" to authenticated;
grant all on "better_supabase"."payroll_runs" to service_role;
drop policy if exists payroll_runs_read on "better_supabase"."payroll_runs";
create policy payroll_runs_read on "better_supabase"."payroll_runs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')));

create table if not exists "better_supabase"."payroll_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "run_id" uuid not null,
  "user_id" uuid,
  "employee_id" uuid,
  -- The name when the run was collected, so an exported file stays reproducible.
  "employee_name" text,
  "kind" text not null check ("kind" in ('worked', 'leave', 'scheduled')),
  -- The leave type's key; null for worked and scheduled time.
  "code" text check ("code" is null or length("code") between 1 and 200),
  "paid" boolean not null default true,
  "unit" text not null check ("unit" in ('hours', 'days')),
  "quantity" numeric(12, 2) not null check ("quantity" >= 0),
  -- How many entries, requests or assignments the line adds up.
  "source_count" integer not null default 1 check ("source_count" >= 0),
  "created_at" timestamptz not null default now(),
  check ("user_id" is not null or "employee_id" is not null),
  foreign key ("tenant_id", "run_id") references "better_supabase"."payroll_runs" ("tenant_id", "id") on delete cascade
);
create unique index if not exists "payroll_lines_person_key" on "better_supabase"."payroll_lines" ("run_id", coalesce("user_id", "employee_id"), "kind", coalesce("code", ''));
create index if not exists "payroll_lines_run_idx" on "better_supabase"."payroll_lines" ("tenant_id", "run_id");
alter table "better_supabase"."payroll_lines" enable row level security;
revoke all on "better_supabase"."payroll_lines" from public, anon, authenticated;
grant select on "better_supabase"."payroll_lines" to authenticated;
grant all on "better_supabase"."payroll_lines" to service_role;
drop policy if exists payroll_lines_read on "better_supabase"."payroll_lines";
create policy payroll_lines_read on "better_supabase"."payroll_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')));

-- Rebuilds the lines of a draft run from the sources in options.sources.
create or replace function "better_supabase"."collect_payroll_lines"(run_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
  v_added integer;
  v_count integer := 0;
begin
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = collect_payroll_lines.run_id;
  delete from "better_supabase"."payroll_lines" where "run_id" = v_run."id";
  insert into "better_supabase"."payroll_lines" ("tenant_id", "run_id", "user_id", "employee_id", "kind", "unit", "quantity", "source_count")
  select v_run."tenant_id", v_run."id", x."user_id", null::uuid,
    'worked', 'hours', round(sum(extract(epoch from x."ended_at" - x."started_at"))::numeric / 3600, 2), count(*)
  from "better_supabase"."time_entries" x
  where x."tenant_id" = v_run."tenant_id"
    and x."ended_at" is not null
    and x."user_id" is not null
    and (x."started_at" at time zone 'UTC')::date between v_run."period_from" and v_run."period_to"
  group by x."user_id"
  having sum(extract(epoch from x."ended_at" - x."started_at")) > 0;
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;
  update "better_supabase"."payroll_lines" x
  set "employee_id" = e."id", "employee_name" = e."name"
  from "better_supabase"."employees" e
  where x."run_id" = v_run."id"
    and e."tenant_id" = v_run."tenant_id"
    and (e."id" = x."employee_id" or (x."employee_id" is null and e."user_id" = x."user_id"));
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."collect_payroll_lines"(uuid) from public, anon, authenticated;

-- Creates a draft run for { from, to, label } (dates as YYYY-MM-DD, at most 400
-- days) and collects its lines. A period an exported run already covers is
-- refused, so nobody is paid twice for the same days.
create or replace function "better_supabase"."create_payroll_run"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_payroll_run.tenant is not null and coalesce(better_supabase.can('tenant', create_payroll_run.tenant, 'payroll_export.export'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if jsonb_typeof(create_payroll_run.input) is distinct from 'object'
    or coalesce(create_payroll_run.input ->> 'from', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(create_payroll_run.input ->> 'to', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'a payroll run has a from and a to date as YYYY-MM-DD' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  v_run."tenant_id" := create_payroll_run.tenant;
  v_run."period_from" := (create_payroll_run.input ->> 'from')::date;
  v_run."period_to" := (create_payroll_run.input ->> 'to')::date;
  if exists (
    select 1 from "better_supabase"."payroll_runs" y
    where y."tenant_id" = v_run."tenant_id" and y."status" = 'exported'
      and y."period_from" <= v_run."period_to" and y."period_to" >= v_run."period_from"
  ) then
    raise exception 'an exported payroll run already covers part of this period' using errcode = '55000', hint = 'PAYROLL_PERIOD_EXPORTED';
  end if;
  insert into "better_supabase"."payroll_runs" ("tenant_id", "period_from", "period_to", "label", "created_by")
  values (v_run."tenant_id", v_run."period_from", v_run."period_to", nullif(trim(create_payroll_run.input ->> 'label'), ''), auth.uid())
  returning * into v_run;
  perform "better_supabase"."collect_payroll_lines"(v_run."id");
  perform "better_supabase".emit_event('payroll_run.created', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'status', v_run."status", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id")), 'payroll-runs/' || v_run."id"::text, (v_run."tenant_id")::text, null, 'better-supabase/payroll-export');
  perform better_supabase.audit_event(
    event_type => 'payroll_run.created',
    category => 'data',
    target_type => 'payroll_run',
    record_id => v_run."id"::text,
    target_label => v_run."period_from"::text || ' to ' || v_run."period_to"::text,
    summary => 'Payroll run created',
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'status', v_run."status", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"))
  );
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'label', v_run."label", 'status', v_run."status", 'format', v_run."format", 'checksum', v_run."checksum", 'exportedAt', v_run."exported_at", 'exportedBy', v_run."exported_by", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'updatedAt', v_run."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'userId', y."user_id", 'employeeId', y."employee_id", 'employeeName', y."employee_name", 'kind', y."kind", 'code', y."code", 'paid', y."paid", 'unit', y."unit", 'quantity', y."quantity"::text, 'sourceCount', y."source_count") order by y."employee_name" nulls last, coalesce(y."user_id", y."employee_id"), y."kind", y."code" nulls first) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), '[]'::jsonb));
exception
  when check_violation then
    raise exception 'the period ends on or after it starts and covers at most 400 days; a label has 1 to 200 characters' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  when datetime_field_overflow or invalid_datetime_format then
    raise exception 'from and to must be real dates' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
end;
$$;
revoke execute on function "better_supabase"."create_payroll_run"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_payroll_run"(uuid, jsonb) to authenticated, service_role;

-- Collects the lines of a draft run again, for time that changed since.
create or replace function "better_supabase"."refresh_payroll_run"(run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = refresh_payroll_run.run_id for update;
  if not found then
    raise exception 'no such payroll run' using errcode = 'P0002', hint = 'PAYROLL_RUN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'payroll_export.export'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if v_run."status" <> 'draft' then
    raise exception 'an exported payroll run can''t be refreshed' using errcode = '55000', hint = 'PAYROLL_RUN_EXPORTED';
  end if;
  perform "better_supabase"."collect_payroll_lines"(v_run."id");
  update "better_supabase"."payroll_runs" x set "updated_at" = now() where x."id" = v_run."id" returning * into v_run;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'label', v_run."label", 'status', v_run."status", 'format', v_run."format", 'checksum', v_run."checksum", 'exportedAt', v_run."exported_at", 'exportedBy', v_run."exported_by", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'updatedAt', v_run."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'userId', y."user_id", 'employeeId', y."employee_id", 'employeeName', y."employee_name", 'kind', y."kind", 'code', y."code", 'paid', y."paid", 'unit', y."unit", 'quantity', y."quantity"::text, 'sourceCount', y."source_count") order by y."employee_name" nulls last, coalesce(y."user_id", y."employee_id"), y."kind", y."code" nulls first) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."refresh_payroll_run"(uuid) from public, anon;
grant execute on function "better_supabase"."refresh_payroll_run"(uuid) to authenticated, service_role;

-- A run with its lines, or null when it doesn't exist or isn't visible.
create or replace function "better_supabase"."get_payroll_run"(run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
begin
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = get_payroll_run.run_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'payroll_export.read'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'label', v_run."label", 'status', v_run."status", 'format', v_run."format", 'checksum', v_run."checksum", 'exportedAt', v_run."exported_at", 'exportedBy', v_run."exported_by", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'updatedAt', v_run."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'userId', y."user_id", 'employeeId', y."employee_id", 'employeeName', y."employee_name", 'kind', y."kind", 'code', y."code", 'paid', y."paid", 'unit', y."unit", 'quantity', y."quantity"::text, 'sourceCount', y."source_count") order by y."employee_name" nulls last, coalesce(y."user_id", y."employee_id"), y."kind", y."code" nulls first) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_payroll_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_payroll_run"(uuid) to authenticated, service_role;

-- The organization's runs, newest period first, without their lines.
create or replace function "better_supabase"."list_payroll_runs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_payroll_runs.tenant is not null and coalesce(better_supabase.can('tenant', list_payroll_runs.tenant, 'payroll_export.read'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) order by x."period_from" desc, x."created_at" desc)
    from "better_supabase"."payroll_runs" x
    where x."tenant_id" = list_payroll_runs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_payroll_runs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_payroll_runs"(uuid) to authenticated, service_role;

-- Locks a draft run after its file was rendered: keeps the format and the
-- SHA-256 of the file. Exporting the same file again returns the run.
create or replace function "better_supabase"."mark_payroll_run_exported"(run_id uuid, format text, checksum text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = mark_payroll_run_exported.run_id for update;
  if not found then
    raise exception 'no such payroll run' using errcode = 'P0002', hint = 'PAYROLL_RUN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'payroll_export.export'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if mark_payroll_run_exported.checksum !~ '^[0-9a-f]{64}$'
    or length(coalesce(mark_payroll_run_exported.format, '')) not between 1 and 100 then
    raise exception 'an export has a format name and the hex SHA-256 of its file' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_run."status" = 'exported' then
    if v_run."format" = mark_payroll_run_exported.format and v_run."checksum" = mark_payroll_run_exported.checksum then
      return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'label', v_run."label", 'status', v_run."status", 'format', v_run."format", 'checksum', v_run."checksum", 'exportedAt', v_run."exported_at", 'exportedBy', v_run."exported_by", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'updatedAt', v_run."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'userId', y."user_id", 'employeeId', y."employee_id", 'employeeName', y."employee_name", 'kind', y."kind", 'code', y."code", 'paid', y."paid", 'unit', y."unit", 'quantity', y."quantity"::text, 'sourceCount', y."source_count") order by y."employee_name" nulls last, coalesce(y."user_id", y."employee_id"), y."kind", y."code" nulls first) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), '[]'::jsonb));
    end if;
  if v_run."status" <> 'draft' then
    raise exception 'an exported payroll run can''t be exported again with a different file' using errcode = '55000', hint = 'PAYROLL_RUN_EXPORTED';
  end if;
  end if;
  if exists (
    select 1 from "better_supabase"."payroll_runs" y
    where y."tenant_id" = v_run."tenant_id" and y."status" = 'exported'
      and y."id" <> v_run."id"
      and y."period_from" <= v_run."period_to" and y."period_to" >= v_run."period_from"
  ) then
    raise exception 'an exported payroll run already covers part of this period' using errcode = '55000', hint = 'PAYROLL_PERIOD_EXPORTED';
  end if;
  update "better_supabase"."payroll_runs" x set
    "status" = 'exported',
    "format" = mark_payroll_run_exported.format,
    "checksum" = mark_payroll_run_exported.checksum,
    "exported_at" = now(),
    "exported_by" = auth.uid(),
    "updated_at" = now()
  where x."id" = v_run."id"
  returning * into v_run;
  perform "better_supabase".emit_event('payroll_run.exported', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'status', v_run."status", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'format', v_run."format", 'checksum', v_run."checksum"), 'payroll-runs/' || v_run."id"::text, (v_run."tenant_id")::text, null, 'better-supabase/payroll-export');
  perform better_supabase.audit_event(
    event_type => 'payroll_run.exported',
    category => 'data',
    target_type => 'payroll_run',
    record_id => v_run."id"::text,
    target_label => v_run."period_from"::text || ' to ' || v_run."period_to"::text,
    summary => 'Payroll run exported',
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'status', v_run."status", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'format', v_run."format", 'checksum', v_run."checksum")
  );
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'periodFrom', v_run."period_from", 'periodTo', v_run."period_to", 'label', v_run."label", 'status', v_run."status", 'format', v_run."format", 'checksum', v_run."checksum", 'exportedAt', v_run."exported_at", 'exportedBy', v_run."exported_by", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'updatedAt', v_run."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'userId', y."user_id", 'employeeId', y."employee_id", 'employeeName', y."employee_name", 'kind', y."kind", 'code', y."code", 'paid', y."paid", 'unit', y."unit", 'quantity', y."quantity"::text, 'sourceCount', y."source_count") order by y."employee_name" nulls last, coalesce(y."user_id", y."employee_id"), y."kind", y."code" nulls first) from "better_supabase"."payroll_lines" y where y."run_id" = v_run."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."mark_payroll_run_exported"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_payroll_run_exported"(uuid, text, text) to authenticated, service_role;

-- Deletes a draft run and its lines.
create or replace function "better_supabase"."delete_payroll_run"(run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = delete_payroll_run.run_id for update;
  if not found then
    raise exception 'no such payroll run' using errcode = 'P0002', hint = 'PAYROLL_RUN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'payroll_export.export'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if v_run."status" <> 'draft' then
    raise exception 'an exported payroll run can''t be deleted' using errcode = '55000', hint = 'PAYROLL_RUN_EXPORTED';
  end if;
  delete from "better_supabase"."payroll_runs" x where x."id" = v_run."id";
end;
$$;
revoke execute on function "better_supabase"."delete_payroll_run"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_payroll_run"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."payroll_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."payroll_runs";
create policy bsb_tenant_scope_select on "better_supabase"."payroll_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."payroll_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."payroll_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."payroll_runs";
create policy bsb_tenant_scope_update on "better_supabase"."payroll_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."payroll_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."payroll_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."payroll_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."payroll_lines";
create policy bsb_tenant_scope_select on "better_supabase"."payroll_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."payroll_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."payroll_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."payroll_lines";
create policy bsb_tenant_scope_update on "better_supabase"."payroll_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."payroll_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."payroll_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.payroll-export.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."create_payroll_run"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_payroll_run"($1, $2) $$;
revoke execute on function "api"."create_payroll_run"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_payroll_run"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."refresh_payroll_run"(run_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."refresh_payroll_run"($1) $$;
revoke execute on function "api"."refresh_payroll_run"(uuid) from public, anon;
grant execute on function "api"."refresh_payroll_run"(uuid) to authenticated, service_role;

create or replace function "api"."get_payroll_run"(run_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_payroll_run"($1) $$;
revoke execute on function "api"."get_payroll_run"(uuid) from public, anon;
grant execute on function "api"."get_payroll_run"(uuid) to authenticated, service_role;

create or replace function "api"."list_payroll_runs"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_payroll_runs"($1) $$;
revoke execute on function "api"."list_payroll_runs"(uuid) from public, anon;
grant execute on function "api"."list_payroll_runs"(uuid) to authenticated, service_role;

create or replace function "api"."mark_payroll_run_exported"(run_id uuid, format text, checksum text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_payroll_run_exported"($1, $2, $3) $$;
revoke execute on function "api"."mark_payroll_run_exported"(uuid, text, text) from public, anon;
grant execute on function "api"."mark_payroll_run_exported"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."delete_payroll_run"(run_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_payroll_run"($1) $$;
revoke execute on function "api"."delete_payroll_run"(uuid) from public, anon;
grant execute on function "api"."delete_payroll_run"(uuid) to authenticated, service_role;

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
