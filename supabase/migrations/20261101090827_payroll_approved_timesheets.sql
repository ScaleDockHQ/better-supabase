SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.collect_payroll_lines (
  run_id uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    and "better_supabase"."time_week_approved"(x."tenant_id", x."user_id", x."started_at")
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.time_week_approved (
  tenant  uuid,
  user_id uuid,
  at      timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    where s."tenant_id" = time_week_approved.tenant and s."user_id" = time_week_approved.user_id
      and s."week" = "better_supabase"."time_week"(time_week_approved.at)
      and s."approved_at" is not null
  );
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."time_week_approved"(uuid, uuid, timestamp WITH time zone) FROM PUBLIC;
