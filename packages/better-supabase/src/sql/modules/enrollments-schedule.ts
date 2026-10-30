import type { BlockSqlContext } from "../context.ts";

import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const ROLE = "^[a-z][a-z0-9_-]{0,62}$";
const UUID = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$";
const MAX_DAYS = 3650;

/**
 * Whether the tables hold the columns of step schedules: the anchor dates on
 * enrollments, and the assignee and due date on steps.
 */
export function schedulesSteps(ctx: BlockSqlContext): boolean {
  return (
    ctx.has("enrollments", "startsAt") &&
    ctx.has("enrollments", "endsAt") &&
    ctx.has("steps", "assigneeRole") &&
    ctx.has("steps", "assigneeUser") &&
    ctx.has("steps", "dueAt")
  );
}

/** `{ role }`, `{ userId }` or null for the step row `row`. */
export function assigneeJson(ctx: BlockSqlContext, row: string): string {
  const s = (column: string): string => ctx.col("steps", column);

  return `case when ${row}.${s("assigneeRole")} is not null then jsonb_build_object('role', ${row}.${s("assigneeRole")}) when ${row}.${s("assigneeUser")} is not null then jsonb_build_object('userId', ${row}.${s("assigneeUser")}) end`;
}

/**
 * PL/pgSQL that rejects a bad `assignee` or `due` on the program step in
 * `v_step`. `assignee` is `{ role }` or `{ userId }`; `due` is `{ days, from }`
 * with `from` either `start` or `end`.
 */
export function stepRuleChecks(invalid: (message: string) => string): string {
  const assignee = "v_step -> 'assignee'";
  const due = "v_step -> 'due'";

  const badAssignee = invalid(
    "a step assignee is { role } with a lowercase role or { userId } with a user id",
  );

  const badDue = invalid(
    `a step due date is { days, from } with whole days from -${String(MAX_DAYS)} to ${String(MAX_DAYS)} and from "start" or "end"`,
  );

  return `if jsonb_typeof(${assignee}) is not null and jsonb_typeof(${assignee}) <> 'null' then
      if jsonb_typeof(${assignee}) <> 'object' then
        ${badAssignee}
      end if;
      if (select count(*) from jsonb_object_keys(${assignee})) <> 1
        or not (coalesce(${assignee} ->> 'role', '') ~ '${ROLE}' or coalesce(${assignee} ->> 'userId', '') ~ '${UUID}') then
        ${badAssignee}
      end if;
    end if;
    if jsonb_typeof(${due}) is not null and jsonb_typeof(${due}) <> 'null' then
      if jsonb_typeof(${due}) <> 'object' then
        ${badDue}
      end if;
      if exists (select 1 from jsonb_object_keys(${due}) as k(key) where k.key not in ('days', 'from'))
        or coalesce(${due} ->> 'from', '') not in ('start', 'end')
        or jsonb_typeof(${due} -> 'days') is distinct from 'number'
        or (case when (${due} ->> 'days') ~ '^-?[0-9]{1,4}$' then abs((${due} ->> 'days')::integer) > ${String(MAX_DAYS)} else true end) then
        ${badDue}
      end if;
    end if;`;
}

/** The normalized `assignee` and `due` keys of the program step `step`. */
export function stepRuleJson(step: string): string {
  return `'assignee', case when jsonb_typeof(${step} -> 'assignee') = 'object' then ${step} -> 'assignee' end,
      'due', case when jsonb_typeof(${step} -> 'due') = 'object' then jsonb_build_object('days', (${step} -> 'due' ->> 'days')::integer, 'from', ${step} -> 'due' ->> 'from') end`;
}

/**
 * The internal `enrollment_schedule`, which renders the open step rows of an
 * enrollment in an organization program from its program's steps.
 */
export function scheduleInternals(ctx: BlockSqlContext): string {
  if (!schedulesSteps(ctx)) {
    return "";
  }

  const programs = ctx.table("programs");
  const enrollments = ctx.table("enrollments");
  const steps = ctx.table("steps");
  const p = (column: string): string => ctx.col("programs", column);
  const e = (column: string): string => ctx.col("enrollments", column);
  const s = (column: string): string => ctx.col("steps", column);
  const fn = (name: string): string => ctx.fn(name);
  const planned = `exists (select 1 from jsonb_array_elements(v_plan) as z(value) where z.value ->> 'step' = y.${s("step")})`;

  const after = (from: string): string =>
    `${from} + make_interval(days => (t.value -> 'due' ->> 'days')::integer)`;

  return `
-- Renders the open step rows of an enrollment from its program: one per step
-- of the enrollment that has an assignee or a due date, due its days after
-- the enrollment's start (or enrolled_at) or its end. A due date from the end
-- stays null until the enrollment has one. Completed rows keep their
-- completion; open rows of steps without a schedule go. Module programs
-- (keys with a colon) are not in the programs table, so their module keeps
-- their open rows.
create or replace function ${fn("enrollment_schedule")}(target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
  v_program ${programs};
  v_plan jsonb;
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_schedule.target;
  if v_row.${e("id")} is null or v_row.${e("tenant")} is null or position(':' in v_row.${e("program")}) > 0 then
    return;
  end if;
  select * into v_program from ${programs} x
  where x.${p("tenant")} = v_row.${e("tenant")} and x.${p("key")} = v_row.${e("program")};
  v_plan := coalesce((
    select jsonb_agg(jsonb_build_object(
      'step', t.value ->> 'id',
      'role', t.value -> 'assignee' ->> 'role',
      'userId', t.value -> 'assignee' ->> 'userId',
      'dueAt', case t.value -> 'due' ->> 'from'
        when 'start' then ${after(`coalesce(v_row.${e("startsAt")}, v_row.${e("enrolledAt")})`)}
        when 'end' then ${after(`v_row.${e("endsAt")}`)}
      end
    ))
    from jsonb_array_elements(coalesce(v_program.${p("steps")}, '[]'::jsonb)) as t(value)
    where t.value ->> 'id' = any(v_row.${e("steps")})
      and (jsonb_typeof(t.value -> 'assignee') = 'object' or jsonb_typeof(t.value -> 'due') = 'object')
  ), '[]'::jsonb);
  delete from ${steps} y
  where y.${s("enrollment")} = v_row.${e("id")} and y.${s("completedAt")} is null and not ${planned};
  update ${steps} y
  set ${s("assigneeRole")} = null, ${s("assigneeUser")} = null, ${s("dueAt")} = null
  where y.${s("enrollment")} = v_row.${e("id")} and not ${planned}
    and (y.${s("assigneeRole")} is not null or y.${s("assigneeUser")} is not null or y.${s("dueAt")} is not null);
  insert into ${steps} as y (${s("enrollment")}, ${s("tenant")}, ${s("step")}, ${s("assigneeRole")}, ${s("assigneeUser")}, ${s("dueAt")}, ${s("completedBy")}, ${s("completedAt")})
  select v_row.${e("id")}, v_row.${e("tenant")}, z.value ->> 'step', z.value ->> 'role', (z.value ->> 'userId')::uuid, (z.value ->> 'dueAt')::timestamptz, null, null
  from jsonb_array_elements(v_plan) as z(value)
  on conflict (${s("enrollment")}, ${s("step")}) do update
  set ${s("assigneeRole")} = excluded.${s("assigneeRole")}, ${s("assigneeUser")} = excluded.${s("assigneeUser")}, ${s("dueAt")} = excluded.${s("dueAt")};
end;
$$;
revoke execute on function ${fn("enrollment_schedule")}(uuid) from public, anon, authenticated;
`;
}

/**
 * `set_enrollment_dates`, which sets the dates due dates count from, and
 * `open_enrollment_steps`, the open steps with an assignee or a due date.
 */
export function scheduleFunctions(ctx: BlockSqlContext): string {
  if (!schedulesSteps(ctx)) {
    return "";
  }

  const programs = ctx.table("programs");
  const enrollments = ctx.table("enrollments");
  const steps = ctx.table("steps");
  const p = (column: string): string => ctx.col("programs", column);
  const e = (column: string): string => ctx.col("enrollments", column);
  const s = (column: string): string => ctx.col("steps", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("enrollments");
  const read = ctx.permission("read", permissions.read);
  const enroll = ctx.permission("enroll", permissions.enroll);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const invalid = (message: string): string =>
    fail("ENROLLMENTS_INVALID", message, "22023");

  const date = (
    key: string,
    target: string,
  ): string => `if dates ? '${key}' then
    begin
      ${target} := (dates ->> '${key}')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow or invalid_text_representation then
      ${invalid(`${key} must be an ISO 8601 instant or null`)}
    end;
  end if;`;

  return `
-- Sets the dates an enrollment's due dates count from and renders them again.
-- dates is { startsAt?, endsAt? }; keys left out keep their value and null
-- clears one. Needs enrollments.enroll. Module programs have no schedules.
create or replace function ${fn("set_enrollment_dates")}(enrollment_id uuid, dates jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
  v_starts timestamptz;
  v_ends timestamptz;
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = set_enrollment_dates.enrollment_id for update;
  if v_row.${e("id")} is null or not ${allowed(`v_row.${e("tenant")}`, read)} then
    ${fail("ENROLLMENTS_NOT_FOUND", "enrollment not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`, enroll)} then
    ${fail("ENROLLMENTS_FORBIDDEN", "not allowed to change this enrollment")}
  end if;
  if position(':' in v_row.${e("program")}) > 0 then
    ${invalid("this enrollment belongs to a module and has no schedule")}
  end if;
  if dates is null or jsonb_typeof(dates) <> 'object' then
    ${invalid("dates must be an object")}
  end if;
  v_starts := v_row.${e("startsAt")};
  v_ends := v_row.${e("endsAt")};
  ${date("startsAt", "v_starts")}
  ${date("endsAt", "v_ends")}
  if v_ends < v_starts then
    ${invalid("endsAt can't be before startsAt")}
  end if;
  update ${enrollments} x
  set ${e("startsAt")} = v_starts, ${e("endsAt")} = v_ends, ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")};
  perform ${fn("enrollment_schedule")}(v_row.${e("id")});
  return ${fn("enrollment_json")}(v_row.${e("id")});
end;
$$;
${userGrant(`${fn("set_enrollment_dates")}(uuid, jsonb)`)}

-- The open steps of active enrollments that have an assignee or a due date,
-- soonest due first and undated last. Without enrollments.read, the steps
-- assigned to the caller.
create or replace function ${fn("open_enrollment_steps")}(tenant ${idType}, assignee_role text default null, assignee_user uuid default null, due_before timestamptz default null, page_size integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := ${allowed("open_enrollment_steps.tenant", read)};
begin
  if not v_read and auth.uid() is null then
    ${fail("ENROLLMENTS_FORBIDDEN", "not allowed to read enrollments")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', o.row_id, 'organizationId', o.scope_id, 'program', o.program,
      'subjectType', o.subject_type, 'subjectId', o.subject_id, 'step', o.step, 'title', o.title,
      'assignee', o.assignee, 'dueAt', o.due_at
    )) order by o.due_at nulls last, o.row_id, o.step)
    from (
      select x.${e("id")} as row_id, x.${e("tenant")} as scope_id, x.${e("program")} as program,
        x.${e("subjectType")} as subject_type, x.${e("subjectId")} as subject_id, y.${s("step")} as step,
        ${assigneeJson(ctx, "y")} as assignee, y.${s("dueAt")} as due_at,
        (select t.value ->> 'title' from ${programs} q, jsonb_array_elements(q.${p("steps")}) as t(value)
          where q.${p("tenant")} = x.${e("tenant")} and q.${p("key")} = x.${e("program")} and t.value ->> 'id' = y.${s("step")} limit 1) as title
      from ${steps} y
      join ${enrollments} x on x.${e("id")} = y.${s("enrollment")}
      where y.${s("tenant")} = open_enrollment_steps.tenant and x.${e("tenant")} = open_enrollment_steps.tenant
        and y.${s("completedAt")} is null and x.${e("status")} = ${ctx.cast("enrollments", "status", "'active'")}
        -- A sequence's open step is its next run, which its runner takes.
        and x.${e("program")} not like 'sequence:%'
        and (v_read or y.${s("assigneeUser")} = auth.uid())
        and (open_enrollment_steps.assignee_role is null or y.${s("assigneeRole")} = open_enrollment_steps.assignee_role)
        and (open_enrollment_steps.assignee_user is null or y.${s("assigneeUser")} = open_enrollment_steps.assignee_user)
        and (open_enrollment_steps.due_before is null or y.${s("dueAt")} < open_enrollment_steps.due_before)
      order by y.${s("dueAt")} nulls last, x.${e("id")}, y.${s("step")}
      limit ${pageSize("open_enrollment_steps.page_size", 50, 200)}
    ) o
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("open_enrollment_steps")}(${idType}, text, uuid, timestamptz, integer)`)}
`;
}
