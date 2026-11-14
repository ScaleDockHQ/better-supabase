-- ==== schema supabase/schemas/900_better_supabase_159_payroll_export.sql
-- better-supabase module: payroll-export
-- @bsb-block payroll-export@1 managed
-- @bsb-hash sha256:8dfeeeb8df3b635e1dbee15e4bfd26705216af6028bac3dfe4109fa7304fcb24
-- Payroll runs that collect the hours worked, the approved leave and optionally the scheduled shifts of a period into lines per person, locked by an export through a versioned PayrollExportFormat port.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Payroll runs per organization: one run collects the hours worked, the
-- approved leave and optionally the scheduled shifts of a period into lines per
-- person. A PayrollExportFormat renders the lines in TypeScript; exporting
-- locks the run and keeps the checksum of the file.
create table "better_supabase"."payroll_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "period_from" date not null,
  "period_to" date not null,
  "label" text constraint bsb_payroll_runs_label_check check ("label" is null or length("label") >= 1 and length("label") <= 200),
  "status" text not null default 'draft' constraint bsb_payroll_runs_status_check check ("status" in ('draft', 'exported')),
  "format" text constraint bsb_payroll_runs_format_check check ("format" is null or length("format") >= 1 and length("format") <= 100),
  -- The hex SHA-256 of the exported file.
  "checksum" text constraint bsb_payroll_runs_checksum_check check ("checksum" is null or "checksum" ~ '^[0-9a-f]{64}$'),
  "exported_at" timestamptz,
  "exported_by" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  constraint bsb_payroll_runs_check check ("period_from" <= "period_to"),
  constraint bsb_payroll_runs_check1 check ("period_to" - "period_from" <= 400),
  constraint bsb_payroll_runs_check2 check (("status" = 'exported') = ("exported_at" is not null and "format" is not null and "checksum" is not null))
);
create index "payroll_runs_tenant_idx" on "better_supabase"."payroll_runs" ("tenant_id", "period_from" desc);
alter table "better_supabase"."payroll_runs" enable row level security;
revoke all on "better_supabase"."payroll_runs" from public, anon, authenticated;
grant select on "better_supabase"."payroll_runs" to authenticated;
grant all on "better_supabase"."payroll_runs" to service_role;
create policy bsb_payroll_runs_read on "better_supabase"."payroll_runs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')));

create table "better_supabase"."payroll_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "run_id" uuid not null,
  "user_id" uuid,
  "employee_id" uuid,
  -- The name when the run was collected, so an exported file stays reproducible.
  "employee_name" text,
  "kind" text not null constraint bsb_payroll_lines_kind_check check ("kind" in ('worked', 'leave', 'scheduled')),
  -- The leave type's key; null for worked and scheduled time.
  "code" text constraint bsb_payroll_lines_code_check check ("code" is null or length("code") >= 1 and length("code") <= 200),
  "paid" boolean not null default true,
  "unit" text not null constraint bsb_payroll_lines_unit_check check ("unit" in ('hours', 'days')),
  "quantity" numeric(12, 2) not null constraint bsb_payroll_lines_quantity_check check ("quantity" >= 0),
  -- How many entries, requests or assignments the line adds up.
  "source_count" integer not null default 1 constraint bsb_payroll_lines_source_count_check check ("source_count" >= 0),
  "created_at" timestamptz not null default now(),
  constraint bsb_payroll_lines_check check ("user_id" is not null or "employee_id" is not null),
  foreign key ("tenant_id", "run_id") references "better_supabase"."payroll_runs" ("tenant_id", "id") on delete cascade
);
create unique index "payroll_lines_person_key" on "better_supabase"."payroll_lines" ("run_id", coalesce("user_id", "employee_id"), "kind", coalesce("code", ''));
create index "payroll_lines_run_idx" on "better_supabase"."payroll_lines" ("tenant_id", "run_id");
alter table "better_supabase"."payroll_lines" enable row level security;
revoke all on "better_supabase"."payroll_lines" from public, anon, authenticated;
grant select on "better_supabase"."payroll_lines" to authenticated;
grant all on "better_supabase"."payroll_lines" to service_role;
create policy bsb_payroll_lines_read on "better_supabase"."payroll_lines"
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
  null;
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

-- The organization's runs as a keyset page, newest period first (ADR 0749,
-- 0779). filters is { status (a value or a list of them), sort, direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_payroll_runs"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_payroll_runs.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_payroll_runs.tenant is not null and coalesce(better_supabase.can('tenant', page_payroll_runs.tenant, 'payroll_export.read'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('periodFrom', 'createdAt') then
    raise exception 'sort is one of periodFrom, createdAt' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" >= (v_after ->> 0)::date and ((x."period_from" > (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" <= (v_after ->> 0)::date and ((x."period_from" < (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'periodFrom' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" >= (v_after ->> 0)::date and ((x."period_from" > (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'periodFrom' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" <= (v_after ->> 0)::date and ((x."period_from" < (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_payroll_runs"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_payroll_runs"(uuid, jsonb) to authenticated, service_role;

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
  null;
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
create policy bsb_tenant_scope_select on "better_supabase"."payroll_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."payroll_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."payroll_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."payroll_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."payroll_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('payroll_export.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."payroll_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."payroll_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."payroll_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_159_payroll_export.sql
-- better-supabase module: payroll-export
-- @bsb-block-data payroll-export
-- @bsb-hash sha256:87e29a2610aa11f95cfd1ee674f2c7ad1a9b3fd957079d4d7faa69011f00cd1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('payroll-export', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
