-- ==== alone: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:fd2fd070f2a9b16fbbf43f698505c667bac8ff7b339a11cd1774fb5e88fa7800
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table "better_supabase"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200),
  "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320),
  "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_employees_check check ("manager_id" is null or "manager_id" <> "id"),
  constraint bsb_employees_check1 check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  constraint bsb_employees_check2 check (("origin_type" is null) = ("origin_id" is null))
);
create unique index employees_user_idx on "better_supabase"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index employees_origin_idx on "better_supabase"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index employees_tenant_status_idx on "better_supabase"."employees" ("tenant_id", "status");
create index employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
revoke all on "better_supabase"."employees" from public, anon, authenticated;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
create policy bsb_employees_read on "better_supabase"."employees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table "better_supabase"."employee_private_details" (
  "employee_id" uuid primary key references "better_supabase"."employees" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid,
  "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64),
  "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40),
  "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
revoke all on "better_supabase"."employee_private_details" from public, anon, authenticated;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
create policy bsb_employee_private_details_read on "better_supabase"."employee_private_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table "better_supabase"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "employee_id" uuid not null references "better_supabase"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0),
  "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_employee_contracts_check check ("ends_on" is null or "ends_on" >= "starts_on"),
  constraint bsb_employee_contracts_check1 check (("salary" is null) = ("currency" is null))
);
create index employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
revoke all on "better_supabase"."employee_contracts" from public, anon, authenticated;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
create policy bsb_employee_contracts_read on "better_supabase"."employee_contracts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "better_supabase"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."get_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "better_supabase"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        null;
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "better_supabase"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."purge_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;


-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  null;
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."employees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_private_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_private_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_private_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_private_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:1d56522645050939804385286b539759c239bb506dec3061c07b02f8a03b70fd
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table "better_supabase"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200),
  "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320),
  "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_employees_check check ("manager_id" is null or "manager_id" <> "id"),
  constraint bsb_employees_check1 check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  constraint bsb_employees_check2 check (("origin_type" is null) = ("origin_id" is null))
);
create unique index employees_user_idx on "better_supabase"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index employees_origin_idx on "better_supabase"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index employees_tenant_status_idx on "better_supabase"."employees" ("tenant_id", "status");
create index employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
revoke all on "better_supabase"."employees" from public, anon, authenticated;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
create policy bsb_employees_read on "better_supabase"."employees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table "better_supabase"."employee_private_details" (
  "employee_id" uuid primary key references "better_supabase"."employees" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid,
  "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64),
  "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40),
  "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
revoke all on "better_supabase"."employee_private_details" from public, anon, authenticated;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
create policy bsb_employee_private_details_read on "better_supabase"."employee_private_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table "better_supabase"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "employee_id" uuid not null references "better_supabase"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0),
  "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_employee_contracts_check check ("ends_on" is null or "ends_on" >= "starts_on"),
  constraint bsb_employee_contracts_check1 check (("salary" is null) = ("currency" is null))
);
create index employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
revoke all on "better_supabase"."employee_contracts" from public, anon, authenticated;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
create policy bsb_employee_contracts_read on "better_supabase"."employee_contracts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();
create trigger "bsb_approval_memo" after insert or update or delete on "better_supabase"."employees"
  for each statement execute function "better_supabase"."approval_memo_bump"();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "better_supabase"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."get_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'employee', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'employee' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('employee.created', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'managerId', v_row."manager_id", 'status', v_row."status"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "better_supabase"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fromManagerId', v_was."manager_id", 'toManagerId', v_row."manager_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'employeeId')::uuid = v_row."id")), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'userId', v_report."user_id", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  perform "better_supabase".emit_event('employee.offboarded', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'endDate', v_row."end_date"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "better_supabase"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'userId', v_report."user_id", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  perform "better_supabase".emit_event('employee.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."purge_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;

-- The employee for a hired application, in preboarding: the name comes from
-- the candidate's record in config.recordTypes, and the job title, team and
-- employment type from the job. attrs overrides any of them. Calling it
-- again returns the same employee, and with the relations module the
-- employee is created_from the application.
create or replace function "better_supabase"."employee_from_application"(application uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."job_openings";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', null::text,
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$$;
revoke execute on function "better_supabase"."employee_from_application"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."employee_from_application"(uuid, jsonb) to authenticated, service_role;

-- Offboards the employee, cancels their active enrollments and releases their
-- open shift assignments that start from today to window_days days ahead, in
-- one transaction. Steps that are already done change nothing, so it can run
-- again. Returns the employee, and how many enrollments and assignments it
-- ended.
create or replace function "better_supabase"."offboard_with_work"(employee uuid, end_date date, reason text, window_days integer default 30)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_employee jsonb;
  v_user uuid;
  v_id uuid;
  v_enrollments integer := 0;
  v_assignments integer := 0;
begin
  v_employee := "better_supabase"."offboard_employee"(offboard_with_work.employee, offboard_with_work.end_date, offboard_with_work.reason);
  select x."user_id" into v_user from "better_supabase"."employees" x where x."id" = offboard_with_work.employee;
  for v_id in
    select x."id" from "better_supabase"."enrollments" x
    where x."subject_type" = 'employee' and x."subject_id" = offboard_with_work.employee::text and x."status" = 'active'
      and position(':' in x."program") = 0
    order by x."id"
  loop
    perform "better_supabase"."cancel_enrollment"(v_id);
    v_enrollments := v_enrollments + 1;
  end loop;
  if v_user is not null then
    for v_id in
      select x."id" from "better_supabase"."shift_assignments" x
      where x."user_id" = v_user and x."status" in ('assigned', 'requested')
        and x."starts_at" >= current_date and x."starts_at" < current_date + offboard_with_work.window_days
      order by x."starts_at", x."id"
    loop
      perform "better_supabase"."unassign_shift"(v_id, offboard_with_work.reason);
      v_assignments := v_assignments + 1;
    end loop;
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollments', v_enrollments, 'assignments', v_assignments);
end;
$$;
revoke execute on function "better_supabase"."offboard_with_work"(uuid, date, text, integer) from public, anon;
grant execute on function "better_supabase"."offboard_with_work"(uuid, date, text, integer) to authenticated, service_role;


-- Creates the employee (attrs as create_employee), enrolls them in the program
-- and sets the enrollment dates ({ startsAt?, endsAt? }, optional), in one
-- transaction. Returns { employee, enrollment }.
create or replace function "better_supabase"."onboard_with_program"(tenant uuid, attrs jsonb, program text, dates jsonb default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_employee jsonb;
  v_enrollment jsonb;
begin
  v_employee := "better_supabase"."create_employee"(onboard_with_program.tenant, onboard_with_program.attrs);
  v_enrollment := "better_supabase"."enroll"(onboard_with_program.tenant, onboard_with_program.program, 'employee', v_employee ->> 'id');
  if onboard_with_program.dates is not null and jsonb_typeof(onboard_with_program.dates) = 'object' and onboard_with_program.dates <> '{}'::jsonb then
    v_enrollment := "better_supabase"."set_enrollment_dates"((v_enrollment ->> 'id')::uuid, onboard_with_program.dates);
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollment', v_enrollment);
end;
$$;
revoke execute on function "better_supabase"."onboard_with_program"(uuid, jsonb, text, jsonb) from public, anon;
grant execute on function "better_supabase"."onboard_with_program"(uuid, jsonb, text, jsonb) to authenticated, service_role;

-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_employee."tenant_id", 'employeeId', v_employee."id", 'subjectType', 'employee', 'subjectId', v_employee."id"::text, 'name', v_employee."name", 'userId', v_employee."user_id", 'fields', jsonb_build_array('contract')), 'employees/' || v_employee."id"::text, (v_employee."tenant_id"::text)::text, null, 'better-supabase/employees');
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- time_entries.employee_id: the employee behind the row's user, kept in step with
-- employees by the two triggers below.
alter table "better_supabase"."time_entries" add column employee_id uuid references "better_supabase"."employees" ("id") on delete set null;
create index "time_entries_employee_idx" on "better_supabase"."time_entries" (employee_id) where employee_id is not null;

create or replace function better_supabase.bsb_time_entries_employee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.employee_id := (
    select x."id" from "better_supabase"."employees" x
    where x."tenant_id" = new."tenant_id" and x."user_id" = new."user_id"
  );
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_time_entries_employee() from public, anon, authenticated;
create trigger bsb_time_entries_employee before insert or update of "user_id" on "better_supabase"."time_entries"
for each row execute function better_supabase.bsb_time_entries_employee();

create or replace function better_supabase.bsb_time_entries_employee_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."user_id" is not null then
    update "better_supabase"."time_entries" set employee_id = null
    where employee_id = old."id" and "user_id" is distinct from new."user_id";
  end if;
  if new."user_id" is not null then
    update "better_supabase"."time_entries" set employee_id = new."id"
    where "tenant_id" = new."tenant_id" and "user_id" = new."user_id"
      and employee_id is distinct from new."id";
  end if;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_time_entries_employee_sync() from public, anon, authenticated;
create trigger bsb_time_entries_employee_sync after insert or update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_time_entries_employee_sync();

alter table "better_supabase"."team_members" add constraint "team_members_employee_fkey"
  foreign key ("employee_id") references "better_supabase"."employees" ("id") on delete cascade;

-- The employee's team rows carry the employee's account while it is a member
-- of the organization; linking an account merges that user's own rows.
-- Setting the team adds a row for it; the row of the previous team stays.
create or replace function better_supabase.bsb_employee_team_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if new."user_id" is not null and exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = new."tenant_id"
      and m."user_id" = new."user_id"
  ) then
    v_user := new."user_id";
  end if;
  if tg_op = 'INSERT' or new."user_id" is distinct from old."user_id" then
    if v_user is not null then
      delete from "better_supabase"."team_members" x
      where x."user_id" = v_user and x."employee_id" is null
        and exists (
          select 1 from "better_supabase"."team_members" y
          where y."team_id" = x."team_id" and y."employee_id" = new."id"
        );
      update "better_supabase"."team_members" set "employee_id" = new."id"
      where "tenant_id" = new."tenant_id" and "user_id" = v_user and "employee_id" is null;
    end if;
    update "better_supabase"."team_members" set "user_id" = v_user
    where "employee_id" = new."id" and "user_id" is distinct from v_user;
  end if;
  if new."team_id" is not null and (tg_op = 'INSERT' or new."team_id" is distinct from old."team_id") then
    insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
    select t."id", v_user, new."id", new."tenant_id"
    from "better_supabase"."teams" t
    where t."id" = new."team_id" and t."tenant_id" = new."tenant_id"
    on conflict do nothing;
  end if;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_team_members() from public, anon, authenticated;
create trigger bsb_employee_team_members after insert or update of "user_id", "team_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_team_members();

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."employees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_private_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_private_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_private_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_private_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.employees deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"employee","event_prefix":"employee"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:5f65a9d12b9c77288df5905502d7b1ef40c5b894b3641725b4839b6cb5d45fbb
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges for role postgres in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table "app_private"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200),
  "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320),
  "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "app_private"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_employees_check check ("manager_id" is null or "manager_id" <> "id"),
  constraint bsb_employees_check1 check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  constraint bsb_employees_check2 check (("origin_type" is null) = ("origin_id" is null))
);
create unique index employees_user_idx on "app_private"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index employees_account_idx on "app_private"."employees" ("user_id") where "user_id" is not null;
create unique index employees_origin_idx on "app_private"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index employees_tenant_status_idx on "app_private"."employees" ("tenant_id", "status");
create index employees_manager_idx on "app_private"."employees" ("manager_id") where "manager_id" is not null;
alter table "app_private"."employees" enable row level security;
revoke all on "app_private"."employees" from public, anon, authenticated;
grant select on "app_private"."employees" to authenticated;
grant all on "app_private"."employees" to service_role;
create policy bsb_employees_read on "app_private"."employees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table "app_private"."employee_private_details" (
  "employee_id" uuid primary key references "app_private"."employees" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid,
  "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64),
  "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40),
  "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index employee_private_details_user_idx on "app_private"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "app_private"."employee_private_details" enable row level security;
revoke all on "app_private"."employee_private_details" from public, anon, authenticated;
grant select on "app_private"."employee_private_details" to authenticated;
grant all on "app_private"."employee_private_details" to service_role;
create policy bsb_employee_private_details_read on "app_private"."employee_private_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table "app_private"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "employee_id" uuid not null references "app_private"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0),
  "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_employee_contracts_check check ("ends_on" is null or "ends_on" >= "starts_on"),
  constraint bsb_employee_contracts_check1 check (("salary" is null) = ("currency" is null))
);
create index employee_contracts_employee_idx on "app_private"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "app_private"."employee_contracts" enable row level security;
revoke all on "app_private"."employee_contracts" from public, anon, authenticated;
grant select on "app_private"."employee_contracts" to authenticated;
grant all on "app_private"."employee_contracts" to service_role;
create policy bsb_employee_contracts_read on "app_private"."employee_contracts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "app_private"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "app_private"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "app_private"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "app_private"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "app_private"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "app_private"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "app_private"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "app_private"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "app_private"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."employees";
begin
  select * into v_row from "app_private"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "app_private"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "app_private"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "app_private"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."get_employee"(uuid) from public, anon;
grant execute on function "app_private"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "app_private"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "app_private"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "app_private"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "app_private"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "app_private"."employees";
  v_was "app_private"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "app_private"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "app_private"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "app_private"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "app_private"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "app_private"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "app_private"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "app_private"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "app_private"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "app_private"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "app_private"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "app_private"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "app_private"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "app_private"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        null;
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "app_private"."employees" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "app_private"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "app_private"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "app_private"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."employees";
  v_report "app_private"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "app_private"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "app_private"."employees" x where x."manager_id" = v_row."id" loop
    update "app_private"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  update "app_private"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "app_private"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "app_private"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."employees";
  v_report "app_private"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "app_private"."employees" x where x."manager_id" = v_row."id" loop
    update "app_private"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  begin
    delete from "app_private"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."purge_employee"(uuid) from public, anon;
grant execute on function "app_private"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "app_private"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "app_private"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "app_private"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "app_private"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "app_private"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "app_private"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "app_private"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "app_private"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "app_private"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "app_private"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "app_private"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "app_private"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "app_private"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "app_private"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "app_private"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "app_private"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "app_private"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "app_private"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "app_private"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "app_private"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "app_private"."reports_of"(uuid, boolean) to authenticated, service_role;


-- An employee's private details, or null when none are saved.
create or replace function "app_private"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "app_private"."employees";
  v_row "app_private"."employee_private_details";
begin
  select * into v_employee from "app_private"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "app_private"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."employee_private_details"(uuid) from public, anon;
grant execute on function "app_private"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "app_private"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "app_private"."employees";
  v_row "app_private"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "app_private"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "app_private"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "app_private"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "app_private"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "app_private"."employees";
begin
  select * into v_employee from "app_private"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "app_private"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "app_private"."employee_contracts"(uuid) from public, anon;
grant execute on function "app_private"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "app_private"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "app_private"."employees";
  v_row "app_private"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "app_private"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "app_private"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "app_private"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "app_private"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  null;
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "app_private"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."employees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "app_private"."employees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."employees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."employees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."employee_private_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "app_private"."employee_private_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."employee_private_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."employee_private_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."employee_contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "app_private"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "app_private"."employee_contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."employee_contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."employee_contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:251bafa9d9637a743725e57c03a4d6d43fba3ae78475cfc056388aa1a7ceca9d
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table "better_supabase"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200),
  "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320),
  "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_employees_check check ("manager_id" is null or "manager_id" <> "id"),
  constraint bsb_employees_check1 check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  constraint bsb_employees_check2 check (("origin_type" is null) = ("origin_id" is null))
);
create unique index employees_user_idx on "better_supabase"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index employees_origin_idx on "better_supabase"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index employees_tenant_status_idx on "better_supabase"."employees" ("tenant_id", "status");
create index employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
revoke all on "better_supabase"."employees" from public, anon, authenticated;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
create policy bsb_employees_read on "better_supabase"."employees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table "better_supabase"."employee_private_details" (
  "employee_id" uuid primary key references "better_supabase"."employees" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid,
  "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64),
  "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40),
  "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
revoke all on "better_supabase"."employee_private_details" from public, anon, authenticated;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
create policy bsb_employee_private_details_read on "better_supabase"."employee_private_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table "better_supabase"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "employee_id" uuid not null references "better_supabase"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0),
  "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_employee_contracts_check check ("ends_on" is null or "ends_on" >= "starts_on"),
  constraint bsb_employee_contracts_check1 check (("salary" is null) = ("currency" is null))
);
create index employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
revoke all on "better_supabase"."employee_contracts" from public, anon, authenticated;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
create policy bsb_employee_contracts_read on "better_supabase"."employee_contracts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "better_supabase"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."get_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "better_supabase"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        null;
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "better_supabase"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."purge_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;


-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  null;
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."employees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_private_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_private_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_private_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_private_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.employees.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_employees"($1, $2) $$;
revoke execute on function "api"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_employees"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_employee"(employee uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_employee"($1) $$;
revoke execute on function "api"."get_employee"(uuid) from public, anon;
grant execute on function "api"."get_employee"(uuid) to authenticated, service_role;

create or replace function "api"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_employee"($1, $2) $$;
revoke execute on function "api"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_employee"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_employees"($1, $2) $$;
revoke execute on function "api"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "api"."update_employees"(jsonb, boolean) to authenticated, service_role;

create or replace function "api"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."offboard_employee"($1, $2, $3) $$;
revoke execute on function "api"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "api"."offboard_employee"(uuid, date, text) to authenticated, service_role;

create or replace function "api"."purge_employee"(employee uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_employee"($1) $$;
revoke execute on function "api"."purge_employee"(uuid) from public, anon;
grant execute on function "api"."purge_employee"(uuid) to authenticated, service_role;

create or replace function "api"."org_chart"(tenant uuid, root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."org_chart"($1, $2) $$;
revoke execute on function "api"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "api"."org_chart"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."reports_of"($1, $2) $$;
revoke execute on function "api"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "api"."reports_of"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."employee_private_details"(employee uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."employee_private_details"($1) $$;
revoke execute on function "api"."employee_private_details"(uuid) from public, anon;
grant execute on function "api"."employee_private_details"(uuid) to authenticated, service_role;

create or replace function "api"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_employee_private_details"($1, $2) $$;
revoke execute on function "api"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."employee_contracts"(employee uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."employee_contracts"($1) $$;
revoke execute on function "api"."employee_contracts"(uuid) from public, anon;
grant execute on function "api"."employee_contracts"(uuid) to authenticated, service_role;

create or replace function "api"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_employee_contract"($1, $2) $$;
revoke execute on function "api"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "api"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:eecc454155f0ccff34c2880ab96fc763354d12122dda218d72fab14320fff640
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

-- better_supabase.employees is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."employees" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."employees" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."employees" add column if not exists "user_id" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."employees" add column if not exists "name" text constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200);
alter table "better_supabase"."employees" add column if not exists "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320);
alter table "better_supabase"."employees" add column if not exists "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200);
alter table "better_supabase"."employees" add column if not exists "team_id" uuid;
alter table "better_supabase"."employees" add column if not exists "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null;
alter table "better_supabase"."employees" add column if not exists "employment_type" text not null default 'employee';
alter table "better_supabase"."employees" add column if not exists "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded'));
alter table "better_supabase"."employees" add column if not exists "start_date" date;
alter table "better_supabase"."employees" add column if not exists "end_date" date;
alter table "better_supabase"."employees" add column if not exists "offboard_reason" text;
alter table "better_supabase"."employees" add column if not exists "origin_type" text;
alter table "better_supabase"."employees" add column if not exists "origin_id" text;
alter table "better_supabase"."employees" add column if not exists "created_by" uuid;
alter table "better_supabase"."employees" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."employees" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists employees_user_idx on "better_supabase"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index if not exists employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index if not exists employees_origin_idx on "better_supabase"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index if not exists employees_tenant_status_idx on "better_supabase"."employees" ("tenant_id", "status");
create index if not exists employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
create policy bsb_employees_select on "better_supabase"."employees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
-- better_supabase.employee_private_details is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."employee_private_details" add column if not exists "employee_id" uuid references "better_supabase"."employees" ("id") on delete cascade;
alter table "better_supabase"."employee_private_details" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."employee_private_details" add column if not exists "user_id" uuid;
alter table "better_supabase"."employee_private_details" add column if not exists "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64);
alter table "better_supabase"."employee_private_details" add column if not exists "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$');
alter table "better_supabase"."employee_private_details" add column if not exists "birth_date" date;
alter table "better_supabase"."employee_private_details" add column if not exists "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320);
alter table "better_supabase"."employee_private_details" add column if not exists "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40);
alter table "better_supabase"."employee_private_details" add column if not exists "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object');
alter table "better_supabase"."employee_private_details" add column if not exists "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array');
alter table "better_supabase"."employee_private_details" add column if not exists "offboarded_at" timestamptz;
alter table "better_supabase"."employee_private_details" add column if not exists "anonymized_at" timestamptz;
alter table "better_supabase"."employee_private_details" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."employee_private_details" add column if not exists "updated_by" uuid;
create index if not exists employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
create policy bsb_employee_private_details_select on "better_supabase"."employee_private_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
-- better_supabase.employee_contracts is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."employee_contracts" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."employee_contracts" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."employee_contracts" add column if not exists "employee_id" uuid references "better_supabase"."employees" ("id") on delete cascade;
alter table "better_supabase"."employee_contracts" add column if not exists "starts_on" date;
alter table "better_supabase"."employee_contracts" add column if not exists "ends_on" date;
alter table "better_supabase"."employee_contracts" add column if not exists "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168));
alter table "better_supabase"."employee_contracts" add column if not exists "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0);
alter table "better_supabase"."employee_contracts" add column if not exists "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."employee_contracts" add column if not exists "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year'));
alter table "better_supabase"."employee_contracts" add column if not exists "note" text;
alter table "better_supabase"."employee_contracts" add column if not exists "created_by" uuid;
alter table "better_supabase"."employee_contracts" add column if not exists "created_at" timestamptz not null default now();
create index if not exists employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
create policy bsb_employee_contracts_select on "better_supabase"."employee_contracts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "better_supabase"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."get_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, better_supabase.as_column_type(v_status, (null::"better_supabase"."employees")."status"), create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "better_supabase"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = better_supabase.as_column_type(v_change ->> 'value', (null::"better_supabase"."employees")."status"), "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        null;
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "better_supabase"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."purge_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;


-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    if add_employee_contract.attrs ? 'currency' then
      insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
      values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
      returning * into v_row;
    else
      insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "salary_period", "note", "created_by")
      values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
      returning * into v_row;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  null;
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."employees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_private_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_private_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_private_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_private_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- @bsb-hash sha256:c2ef10b72d10680b2bc9e0b3db5b7c31dd8aa82aadcfb88c8adf1ae216bc104a
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table "better_supabase"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null constraint bsb_employees_name_check check (length(trim("name")) between 1 and 200),
  "email" text constraint bsb_employees_email_check check ("email" is null or length("email") <= 320),
  "job_title" text constraint bsb_employees_job_title_check check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' constraint bsb_employees_status_check check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_employees_check check ("manager_id" is null or "manager_id" <> "id"),
  constraint bsb_employees_check1 check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  constraint bsb_employees_check2 check (("origin_type" is null) = ("origin_id" is null))
);
create unique index employees_user_idx on "better_supabase"."employees" ("org_id", "user_id") where "user_id" is not null;
create index employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index employees_origin_idx on "better_supabase"."employees" ("org_id", "origin_type", "origin_id") where "origin_id" is not null;
create index employees_tenant_status_idx on "better_supabase"."employees" ("org_id", "status");
create index employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
revoke all on "better_supabase"."employees" from public, anon, authenticated;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
create policy bsb_employees_read on "better_supabase"."employees"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table "better_supabase"."employee_private_details" (
  "employee_id" uuid primary key references "better_supabase"."employees" ("id") on delete cascade,
  "org_id" uuid not null,
  "user_id" uuid,
  "national_id" text constraint bsb_employee_private_details_national_id_check check ("national_id" is null or length("national_id") <= 64),
  "iban" text constraint bsb_employee_private_details_iban_check check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text constraint bsb_employee_private_details_personal_email_check check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text constraint bsb_employee_private_details_phone_check check ("phone" is null or length("phone") <= 40),
  "address" jsonb constraint bsb_employee_private_details_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' constraint bsb_employee_private_details_emergency_contacts_check check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
revoke all on "better_supabase"."employee_private_details" from public, anon, authenticated;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
create policy bsb_employee_private_details_read on "better_supabase"."employee_private_details"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table "better_supabase"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "employee_id" uuid not null references "better_supabase"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) constraint bsb_employee_contracts_hours_per_week_check check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint constraint bsb_employee_contracts_salary_check check ("salary" is null or "salary" >= 0),
  "currency" text constraint bsb_employee_contracts_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text constraint bsb_employee_contracts_salary_period_check check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_employee_contracts_check check ("ends_on" is null or "ends_on" >= "starts_on"),
  constraint bsb_employee_contracts_check1 check (("salary" is null) = ("currency" is null))
);
create index employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
revoke all on "better_supabase"."employee_contracts" from public, anon, authenticated;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
create policy bsb_employee_contracts_read on "better_supabase"."employee_contracts"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."org_id" = new."org_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- The organization's employees as a keyset page, by name (ADR 1077). Needs
-- employees.read. filters is { status, employmentType, teamId, managerId,
-- userId (each a value or a list), search, sort (name, startDate), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_employees"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."org_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or (x."employment_type")::text = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_employees"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_employees"(uuid, jsonb) to authenticated, service_role;

-- One employee by id. Needs employees.read, or being the employee or one of
-- their managers.
create or replace function "better_supabase"."get_employee"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."get_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."get_employee"(uuid) to authenticated, service_role;

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."org_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("org_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_row."org_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value, expectedUpdatedAt }
-- changes, each on its own: a change that fails is rejected with its reason
-- and the others stay. With atomic, the first failure raises and no change
-- stays. A change with expectedUpdatedAt fails with EMPLOYEE_STALE when the
-- employee's updated_at before the batch differs. status takes
-- preboarding, active or on_leave; setting it on an offboarded employee
-- rehires them. Returns { accepted: [{ employeeId, field }], rejected:
-- [{ employeeId, field, hint, reason }] }.

create or replace function "better_supabase"."update_employees"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_row."org_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        null;
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb, boolean) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). With offboarding.reports "manager", the
-- employee's reports move to their manager. Offboarding an offboarded
-- employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- Removes an employee for good, with their private details and contracts, for
-- one created by mistake: offboard_employee is how an employment ends. Needs
-- permissions.purge, which falls back to the write key. With
-- offboarding.reports "manager", their reports move to the employee's
-- manager; otherwise they are left without one. Fails with EMPLOYEE_IN_USE
-- while another block's rows still refer to the employee.
create or replace function "better_supabase"."purge_employee"(employee uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    null;
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."purge_employee"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_employee"(uuid) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."org_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."org_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;


-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."org_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."org_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "org_id", "user_id")
  values (v_employee."id", v_employee."org_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."org_id", 'employees.read_sensitive'), false) or coalesce(v_employee."user_id" = auth.uid(), false)) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."org_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."org_id", 'employees.read_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("org_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."org_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."employees" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employees" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employees" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employees" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_private_details" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or "user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_private_details" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_private_details" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_private_details" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."employee_contracts" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('employees.read_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."employee_contracts" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."employee_contracts" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."employee_contracts" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_102_employees.sql
-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
