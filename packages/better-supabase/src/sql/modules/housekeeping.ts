import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { lockTable, schemaPreamble, serviceOnly } from "../shared.ts";

const NAMES: BlockSqlNames = {
  tables: {
    state: {
      name: "maintenance_state",
      app: { writes: false },
      columns: {
        job: "job",
        lastRunAt: "last_run_at",
        lastStatus: "last_status",
        lastResult: "last_result",
        lastError: "last_error",
        runs: "runs",
      },
    },
  },
};

const JOB_NAME = /^[a-z][a-z0-9_.-]*$/u;
const INTERVAL = /^\d+ (?:seconds?|minutes?|hours?|days?)$/u;
const FUNCTION = /^"?[a-z_][a-z0-9_]*"?\."?[a-z_][a-z0-9_]*"?$/u;

function build(ctx: BlockSqlContext): string {
  const jobs = uniqueContributions(
    "housekeeping",
    ctx.contributions("housekeeping"),
    (job) => job.job,
  );

  for (const job of jobs) {
    if (
      !JOB_NAME.test(job.job) ||
      !INTERVAL.test(job.every) ||
      !FUNCTION.test(job.function)
    ) {
      throw new TypeError(
        `housekeeping job "${job.job}" needs a lowercase name, a qualified function and an interval such as "15 minutes" (got "${job.function}", "${job.every}")`,
      );
    }
  }

  const state = ctx.table("state");
  const c = (column: string): string => ctx.col("state", column);

  const values =
    jobs.length === 0
      ? "select null::text, null::text, null::interval where false"
      : jobs
          .toSorted((a, b) => a.job.localeCompare(b.job))
          .map(
            (job) =>
              `    (${sqlString(job.job)}, ${sqlString(job.function)}, interval ${sqlString(job.every)})`,
          )
          .join(",\n");

  const registry =
    jobs.length === 0 ? `(${values})` : `(values\n${values}\n  )`;

  return `${schemaPreamble(ctx)}

-- One row per job the dispatcher ran: when, with what result, and how often.
create table if not exists ${state} (
  ${c("job")} text primary key,
  ${c("lastRunAt")} timestamptz,
  ${c("lastStatus")} text check (${c("lastStatus")} in ('ok', 'error')),
  ${c("lastResult")} jsonb,
  ${c("lastError")} text,
  ${c("runs")} bigint not null default 0
);
${lockTable(state)}

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' \`housekeeping\` contributions.
create or replace view ${ctx.fn("maintenance_jobs")} with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s.${c("lastRunAt")} as last_run_at, s.${c("lastStatus")} as last_status, s.${c("lastError")} as last_error,
  coalesce(s.${c("runs")}, 0) as runs,
  (s.${c("lastRunAt")} is null or s.${c("lastRunAt")} + j.every_interval <= now()) as due
from ${registry} j (job, fn, every_interval)
left join ${state} s on s.${c("job")} = j.job;
revoke all on ${ctx.fn("maintenance_jobs")} from public, anon, authenticated;
grant select on ${ctx.fn("maintenance_jobs")} to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function ${ctx.fn("maintenance")}(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from ${ctx.fn("maintenance_jobs")} j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into ${state} (${c("job")}, ${c("lastRunAt")}, ${c("lastStatus")}, ${c("lastResult")}, ${c("lastError")}, ${c("runs")})
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict (${c("job")}) do update set ${c("lastRunAt")} = now(), ${c("lastStatus")} = 'ok',
        ${c("lastResult")} = excluded.${c("lastResult")}, ${c("lastError")} = null, ${c("runs")} = ${state}.${c("runs")} + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into ${state} (${c("job")}, ${c("lastRunAt")}, ${c("lastStatus")}, ${c("lastResult")}, ${c("lastError")}, ${c("runs")})
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict (${c("job")}) do update set ${c("lastRunAt")} = now(), ${c("lastStatus")} = 'error',
        ${c("lastResult")} = null, ${c("lastError")} = excluded.${c("lastError")}, ${c("runs")} = ${state}.${c("runs")} + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function ${ctx.fn("maintenance_schedule")}(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select ${ctx.fn("maintenance")}()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function ${ctx.fn("maintenance_scheduler")}()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

${serviceOnly([
  "maintenance(text, boolean)",
  "maintenance_schedule(text)",
  "maintenance_scheduler()",
])}`;
}

export const HOUSEKEEPING: BlockSqlDefinition = {
  name: "housekeeping",
  version: 1,
  names: NAMES,
  title: "Housekeeping",
  description:
    "One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.",
  requires: [],
  target: "schema",
  build,
};
