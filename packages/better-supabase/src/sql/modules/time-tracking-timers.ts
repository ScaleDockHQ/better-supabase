import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";

const WHERE = "blocks.time-tracking.options";

/**
 * `options.overlap` ("refuse" or "allow") and `options.timers` ("one" or
 * "many"). Several running timers overlap, so they need overlaps allowed.
 */
export function timerOptions(ctx: BlockSqlContext): {
  readonly allowOverlap: boolean;
  readonly manyTimers: boolean;
} {
  const overlap = ctx.text("overlap", "refuse");
  const timers = ctx.text("timers", "one");

  if (overlap !== "refuse" && overlap !== "allow") {
    throw new TypeError(`${WHERE}.overlap must be "refuse" or "allow"`);
  }

  if (timers !== "one" && timers !== "many") {
    throw new TypeError(`${WHERE}.timers must be "one" or "many"`);
  }

  if (timers === "many" && overlap === "refuse") {
    throw new TypeError(
      `${WHERE}.timers "many" runs timers side by side, so it needs ${WHERE}.overlap "allow"`,
    );
  }

  return { allowOverlap: overlap === "allow", manyTimers: timers === "many" };
}

/** What the timer functions read from the time-tracking module. */
export interface TimerParts {
  readonly entries: string;
  readonly e: (column: string) => string;
  readonly fn: (name: string) => string;
  readonly track: string;
  readonly entryJson: (row: string) => string;
  readonly entryRecord: (
    type: string,
    row: string,
    recorded: boolean,
  ) => string;
  readonly running: (alias: string) => string;
  readonly stop: (alias: string, at: string) => string;
  readonly overlap: (row: string) => string;
  readonly saved: (row: string) => string;
  readonly myEmployee: (tenant: string) => string;
  readonly eOwner: string;
  readonly ownerVar: string;
  readonly employeeMode: boolean;
  readonly durationMode: boolean;
  readonly manyTimers: boolean;
}

/**
 * `running_timers(tenant)`, and over a duration column `resume_timer(entry)`,
 * which runs a stopped entry again and adds the next segment on stop.
 */
export function timerFunctions(
  ctx: BlockSqlContext,
  parts: TimerParts,
): string {
  const {
    entries,
    e,
    fn,
    track,
    entryJson,
    entryRecord,
    running,
    stop,
    overlap,
    saved,
    myEmployee,
    eOwner,
    ownerVar,
    employeeMode,
    durationMode,
    manyTimers,
  } = parts;

  return `drop function if exists ${fn("stop_timer")}(${ctx.idType});
create or replace function ${fn("stop_timer")}(tenant ${ctx.idType}, entry uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row ${entries}%rowtype;${employeeMode ? `\n  v_owner uuid := ${myEmployee("stop_timer.tenant")};` : ""}
begin
  select * into v_row from ${entries} x
    where x.${e("tenant")} = stop_timer.tenant and x.${eOwner} = ${ownerVar} and ${running("x")}
      and (stop_timer.entry is null or x.${e("id")} = stop_timer.entry)
    order by x.${e("startedAt")} desc
    limit 1
    for update;
  if not found then
    ${fail("TIME_NO_TIMER", "no timer is running", "P0002")}
  end if;
  update ${entries} x set ${stop("x", "v_at")}, ${e("updatedAt")} = v_at
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${entryRecord("time_entry.recorded", "v_row", true)}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("stop_timer")}(${ctx.idType}, uuid)`)}

-- The caller's running timer, or null.
create or replace function ${fn("running_timer")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${entryJson("x")} from ${entries} x
  where x.${e("tenant")} = running_timer.tenant and x.${e("user")} = auth.uid() and ${running("x")};
$$;
${userGrant(`${fn("running_timer")}(${ctx.idType})`)}

-- Every timer the caller has running, newest first.
create or replace function ${fn("running_timers")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${entryJson("x")} order by x.${e("startedAt")} desc), '[]'::jsonb) from ${entries} x
  where x.${e("tenant")} = running_timers.tenant and x.${e("user")} = auth.uid() and ${running("x")};
$$;
${userGrant(`${fn("running_timers")}(${ctx.idType})`)}
${
  durationMode
    ? `
-- Runs a stopped entry of the caller's again from now: its start and the
-- time it has stay, and the next stop adds the new segment.${manyTimers ? "" : " The timer that runs stops first."}
create or replace function ${fn("resume_timer")}(entry uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row ${entries}%rowtype;
  v_other ${entries}%rowtype;${employeeMode ? "\n  v_owner uuid;" : ""}
begin
  select * into v_row from ${entries} x where x.${e("id")} = resume_timer.entry for update;
  if not found or v_me is null or not ${ctx.can("tenant", `v_row.${e("tenant")}`, track)} then
    ${fail("TIME_ENTRY_NOT_FOUND", "no such entry of yours", "P0002")}
  end if;${employeeMode ? `\n  v_owner := ${myEmployee(`v_row.${e("tenant")}`)};` : ""}
  if v_row.${eOwner} is distinct from ${ownerVar} then
    ${fail("TIME_ENTRY_NOT_FOUND", "no such entry of yours", "P0002")}
  end if;
  if ${running("v_row")} then
    ${fail("TIME_TIMER_RUNNING", "this timer is already running", "55000")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || v_row.${e("tenant")}::text || ':' || ${ownerVar}::text, 0));${
    manyTimers
      ? ""
      : `
  update ${entries} x set ${stop("x", "v_at")}, ${e("updatedAt")} = v_at
    where x.${e("tenant")} = v_row.${e("tenant")} and x.${eOwner} = ${ownerVar} and ${running("x")}
    returning * into v_other;
  if found then
    ${entryRecord("time_entry.recorded", "v_other", true)}
  end if;`
  }
  v_row.${e("runningSince")} := v_at;
  ${overlap("v_row")}
  update ${entries} x set ${e("runningSince")} = v_at, ${e("updatedAt")} = v_at
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${entryRecord("time_entry.started", "v_row", false)}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("resume_timer")}(uuid)`)}
`
    : ""
}
`;
}
