SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."maintenance_state" (
  "job"         text                     NOT NULL,
  "last_run_at" timestamp with time zone,
  "last_status" text,
  "last_result" jsonb,
  "last_error"  text,
  "runs"        bigint                   NOT NULL DEFAULT 0,
  CONSTRAINT "maintenance_state_last_status_check" CHECK ((last_status = ANY (ARRAY['ok'::text, 'error'::text]))),
  CONSTRAINT "maintenance_state_pkey" PRIMARY KEY (job)
);

ALTER TABLE "better_supabase"."maintenance_state"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.maintenance (
  job_name  text    DEFAULT NULL::text,
  force_run boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "better_supabase"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_schedule (
  cron_schedule text DEFAULT '*/5 * * * *'::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "better_supabase"."maintenance"()');
  return 'pg_cron';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_scheduler()
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$function$;

CREATE VIEW "better_supabase"."maintenance_jobs" WITH (security_invoker=true) AS  SELECT j.job,
    j.fn AS function,
    j.every_interval AS every,
    s.last_run_at,
    s.last_status,
    s.last_error,
    COALESCE(s.runs, (0)::bigint) AS runs,
    ((s.last_run_at IS NULL) OR ((s.last_run_at + j.every_interval) <= now())) AS due
   FROM (( VALUES ('expire_approvals'::text,'"better_supabase"."expire_approvals"'::text,'00:15:00'::interval), ('purge_chat_state'::text,'"better_supabase"."purge_chat_state"'::text,'00:15:00'::interval), ('purge_expired_trash'::text,'"better_supabase"."purge_expired_trash"'::text,'1 day'::interval), ('purge_rate_limits'::text,'better_supabase.purge_rate_limits'::text,'00:15:00'::interval)) j(job, fn, every_interval)
     LEFT JOIN better_supabase.maintenance_state s ON ((s.job = j.job)));

REVOKE ALL ON FUNCTION "better_supabase"."maintenance"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance"(text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_schedule"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_schedule"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_scheduler"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_scheduler"() TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."maintenance_state" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_jobs" TO "service_role";
