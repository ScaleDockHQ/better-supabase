import type { BlockSqlContext } from "../context.ts";

import { createdOrUpdated } from "../event-verbs.ts";
import {
  fail,
  NOTHING,
  pageSize,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import {
  assigneeJson,
  scheduleFunctions,
  scheduleInternals,
  schedulesSteps,
  stepRuleChecks,
  stepRuleJson,
} from "./enrollments-schedule.ts";
import { moduleOperations } from "./permissions-model.ts";

const STEP_ID = "^[a-z][a-z0-9_.-]{0,63}$";
const TYPE = "^[a-z][a-z0-9_-]{0,62}$";

function maxStepsOf(ctx: BlockSqlContext): string {
  const value = ctx.number("maxSteps", 100);

  if (!Number.isInteger(value) || value < 1 || value > 1000) {
    throw new TypeError(
      "blocks.enrollments.options.maxSteps must be a whole number from 1 to 1000",
    );
  }

  return String(value);
}

/** The enrollments module's functions. */
export function enrollmentsFunctions(ctx: BlockSqlContext): string {
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
  const manage = ctx.permission("manage", permissions.manage);
  const maxSteps = maxStepsOf(ctx);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const forbidden = (message: string): string =>
    fail("ENROLLMENTS_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("ENROLLMENTS_INVALID", message, "22023");

  const programMissing = fail(
    "ENROLLMENTS_PROGRAM_NOT_FOUND",
    "enrollment program not found",
    "P0002",
  );

  const enrollmentMissing = fail(
    "ENROLLMENTS_NOT_FOUND",
    "enrollment not found",
    "P0002",
  );

  /** Column `column` of row `row` in `table`, or null when the table lacks it. */
  const field = (table: string, row: string, column: string): string =>
    ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

  const hasDescription = ctx.has("programs", "description");
  const hasVersion = ctx.has("enrollments", "programVersion");
  const scheduled = schedulesSteps(ctx);

  const schedule = (id: string): string =>
    scheduled ? `\n  perform ${fn("enrollment_schedule")}(${id});` : "";

  const assigned = (row: string, step: string): string =>
    scheduled
      ? ` or exists (select 1 from ${steps} a where a.${s("enrollment")} = ${row}.${e("id")} and a.${s("step")} = ${step} and a.${s("assigneeUser")} = auth.uid())`
      : "";

  const programInsert = (
    [
      ["tenant", "save_enrollment_program.tenant"],
      ["key", "v_key"],
      ["name", "v_name"],
      ["description", "v_description"],
      ["subjectTypes", "v_types"],
      ["steps", "v_steps"],
      ["enabled", "v_enabled"],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => ctx.has("programs", column));

  const enrollmentInsert = (
    [
      ["tenant", "enrollment_ensure.tenant"],
      ["program", "enrollment_ensure.program"],
      ["programVersion", "enrollment_ensure.program_version"],
      ["subjectType", "enrollment_ensure.subject_type"],
      ["subjectId", "enrollment_ensure.subject_id"],
      [
        "user",
        "case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end",
      ],
      ["steps", "enrollment_ensure.steps"],
      ["enrolledBy", "enrollment_ensure.actor"],
    ] as const
  ).filter(([column]) => ctx.has("enrollments", column));

  const self = (row: string): string =>
    `(${row}.${e("user")} is not null and coalesce(${row}.${e("user")} = auth.uid(), false))`;

  const programJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'key', ${row}.${p("key")}, 'name', ${row}.${p("name")}, 'description', ${field("programs", row, "description")}, 'subjectTypes', to_jsonb(${row}.${p("subjectTypes")}), 'steps', ${row}.${p("steps")}, 'enabled', ${row}.${p("enabled")}, 'version', ${row}.${p("version")}, 'createdBy', ${field("programs", row, "createdBy")}, 'createdAt', ${field("programs", row, "createdAt")}, 'updatedAt', ${field("programs", row, "updatedAt")})`;

  const programRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'key', ${row}.${p("key")}, 'version', ${row}.${p("version")})`,
      subject: `'enrollment-programs/' || ${row}.${p("id")}::text`,
      tenant: `${row}.${p("tenant")}`,
      audit: {
        category: "data",
        targetType: "enrollment_program",
        recordId: `${row}.${p("id")}::text`,
        targetLabel: `${row}.${p("name")}`,
        summary: `'${summary}'`,
      },
    });

  const event = (
    type: string,
    row: string,
    step: string,
    reason: string | undefined,
  ) => ({
    type,
    payload: `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'id', ${row}.${e("id")}, 'program', ${row}.${e("program")}, 'subjectType', ${row}.${e("subjectType")}, 'subjectId', ${row}.${e("subjectId")}, 'status', ${row}.${e("status")}, 'step', ${step}, 'completedSteps', ${row}.${e("completedSteps")}, 'totalSteps', cardinality(${row}.${e("steps")})${reason === undefined ? "" : `, 'reason', ${reason}`})`,
    subject: `'enrollments/' || ${row}.${e("id")}::text`,
    tenant: `${row}.${e("tenant")}`,
  });

  const inTenant = (row: string, statement: string): string =>
    statement === ""
      ? ""
      : `
  if ${row}.${e("tenant")} is not null then
    ${statement}
  end if;`;

  const emit = (
    type: string,
    row: string,
    step = "null::text",
    reason?: string,
  ): string => inTenant(row, ctx.emit(event(type, row, step, reason)));

  // A module's change the caller made goes to the audit log as well; what
  // its runner does (no actor) only emits.
  const emitOrAudit = (
    type: string,
    row: string,
    actor: string,
    summary: string,
    reason?: string,
  ): string => {
    const plain = ctx.emit(event(type, row, "null::text", reason));

    const audited = ctx.audit({
      ...event(type, row, "null::text", reason),
      audit: {
        category: "data",
        targetType: "enrollment",
        recordId: `${row}.${e("id")}::text`,
        targetLabel: `${row}.${e("program")}`,
        summary: `'${summary}'`,
        actor,
      },
    });

    const audit =
      audited === NOTHING
        ? ""
        : `
  if ${actor} is not null and ${row}.${e("tenant")} is not null then
    ${audited}
  end if;`;

    return `${inTenant(row, plain)}${audit}`;
  };

  const done = (count: string): string =>
    `(${count} >= cardinality(x.${e("steps")}) and cardinality(x.${e("steps")}) > 0)`;

  const count = `(select count(*)::integer from ${steps} y where y.${s("enrollment")} = x.${e("id")} and y.${s("step")} = any(x.${e("steps")}) and y.${s("completedAt")} is not null)`;

  // Counts the completed steps of the program's current steps and sets the
  // status; a cancelled enrollment stays cancelled.
  const recount = (id: string, into: string): string => `update ${enrollments} x
  set ${e("completedSteps")} = ${count},
    ${e("status")} = ${ctx.cast("enrollments", "status", `case when x.${e("status")} = 'cancelled' then 'cancelled' when ${done(count)} then 'completed' else 'active' end`)},
    ${e("completedAt")} = case when x.${e("status")} <> 'cancelled' and ${done(count)} then coalesce(x.${e("completedAt")}, now()) end,
    ${e("updatedAt")} = now()
  where x.${e("id")} = ${id}
  returning * into ${into};`;

  const stepIds = (json: string): string =>
    `array(select t.value ->> 'id' from jsonb_array_elements(${json}) with ordinality as t(value, ord) order by t.ord)`;

  const hasPause = ctx.has("enrollments", "pausedAt");
  const hasReason = ctx.has("enrollments", "cancelReason");

  const stateInternals = (): string => `
-- Pauses or resumes an active enrollment of a program a module drives, such
-- as a sequence; false when it already was. actor, when set, is audited.
create or replace function ${fn("enrollment_pause")}(enrollment_id uuid, paused boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_pause.enrollment_id for update;
  if v_row.${e("id")} is null then
    ${enrollmentMissing}
  end if;${
    hasPause
      ? `
  if v_row.${e("status")} <> 'active' or (v_row.${e("pausedAt")} is not null) = enrollment_pause.paused then
    return false;
  end if;
  update ${enrollments} x
  set ${e("pausedAt")} = case when enrollment_pause.paused then now() end, ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  if enrollment_pause.paused then${emitOrAudit("enrollment.paused", "v_row", "enrollment_pause.actor", "paused an enrollment")}
  else${emitOrAudit("enrollment.resumed", "v_row", "enrollment_pause.actor", "resumed an enrollment")}
  end if;
  return true;`
      : `
  ${invalid("this enrollments table has no paused_at column")}`
  }
end;
$$;
revoke execute on function ${fn("enrollment_pause")}(uuid, boolean, uuid) from public, anon, authenticated;

-- Cancels an active enrollment of a program a module drives with why it
-- ended; false when it wasn't active. Its completed steps stay and its open
-- steps go. actor, when set, is audited.
create or replace function ${fn("enrollment_cancel")}(enrollment_id uuid, reason text, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_cancel.enrollment_id for update;
  if v_row.${e("id")} is null then
    ${enrollmentMissing}
  end if;
  if v_row.${e("status")} <> 'active' then
    return false;
  end if;
  delete from ${steps} y where y.${s("enrollment")} = v_row.${e("id")} and y.${s("completedAt")} is null;
  update ${enrollments} x
  set ${e("status")} = 'cancelled', ${e("cancelledAt")} = now(),${hasPause ? ` ${e("pausedAt")} = null,` : ""}${hasReason ? ` ${e("cancelReason")} = enrollment_cancel.reason,` : ""} ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;${emitOrAudit("enrollment.cancelled", "v_row", "enrollment_cancel.actor", "cancelled an enrollment", "enrollment_cancel.reason")}
  return true;
end;
$$;
revoke execute on function ${fn("enrollment_cancel")}(uuid, text, uuid) from public, anon, authenticated;

-- Starts an enrollment of a program a module drives over: active, with steps
-- and none of them done. Emits enrollment.created again.
create or replace function ${fn("enrollment_restart")}(enrollment_id uuid, program_version integer, steps text[], actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_restart.enrollment_id for update;
  if v_row.${e("id")} is null then
    ${enrollmentMissing}
  end if;
  delete from ${steps} y where y.${s("enrollment")} = v_row.${e("id")};
  update ${enrollments} x
  set ${e("status")} = 'active', ${e("steps")} = enrollment_restart.steps,${hasVersion ? ` ${e("programVersion")} = enrollment_restart.program_version,` : ""} ${e("completedSteps")} = 0,
    ${e("completedAt")} = null, ${e("cancelledAt")} = null,${hasPause ? ` ${e("pausedAt")} = null,` : ""}${hasReason ? ` ${e("cancelReason")} = null,` : ""}
    ${e("enrolledBy")} = enrollment_restart.actor, ${e("enrolledAt")} = now(), ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;${emit("enrollment.created", "v_row")}
end;
$$;
revoke execute on function ${fn("enrollment_restart")}(uuid, integer, text[], uuid) from public, anon, authenticated;
`;

  return `-- An enrollment with its steps and the completed ones, oldest first.
create or replace function ${fn("enrollment_json")}(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x.${e("id")}, 'organizationId', x.${e("tenant")}, 'program', x.${e("program")}, 'programVersion', ${field("enrollments", "x", "programVersion")},
    'subjectType', x.${e("subjectType")}, 'subjectId', x.${e("subjectId")}, 'status', x.${e("status")},
    'steps', to_jsonb(x.${e("steps")}), 'completedSteps', x.${e("completedSteps")}, 'totalSteps', cardinality(x.${e("steps")}),
    'enrolledBy', x.${e("enrolledBy")}, 'enrolledAt', x.${e("enrolledAt")}, 'completedAt', x.${e("completedAt")},
    'cancelledAt', x.${e("cancelledAt")}, 'pausedAt', ${field("enrollments", "x", "pausedAt")}, 'cancelReason', ${field("enrollments", "x", "cancelReason")},
    'updatedAt', x.${e("updatedAt")},
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y.${s("step")}, 'completedAt', y.${s("completedAt")}, 'completedBy', y.${s("completedBy")}) order by y.${s("completedAt")}, array_position(x.${e("steps")}, y.${s("step")}), y.${s("step")})
      from ${steps} y where y.${s("enrollment")} = x.${e("id")} and y.${s("completedAt")} is not null
    ), '[]'::jsonb)${
      scheduled
        ? `,
    'startsAt', x.${e("startsAt")}, 'endsAt', x.${e("endsAt")},
    'schedule', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('step', y.${s("step")}, 'assignee', ${assigneeJson(ctx, "y")}, 'dueAt', y.${s("dueAt")}, 'completedAt', y.${s("completedAt")})) order by array_position(x.${e("steps")}, y.${s("step")}), y.${s("step")})
      from ${steps} y
      where y.${s("enrollment")} = x.${e("id")}
        and (y.${s("assigneeRole")} is not null or y.${s("assigneeUser")} is not null or y.${s("dueAt")} is not null)
    ), '[]'::jsonb)`
        : ""
    }
  )
  from ${enrollments} x
  where x.${e("id")} = enrollment_json.enrollment_id
$$;
revoke execute on function ${fn("enrollment_json")}(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function ${fn("enrollment_ensure")}(tenant ${idType}, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
  v_was text;
begin
  select * into v_row from ${enrollments} x
  where x.${e("tenant")} is not distinct from enrollment_ensure.tenant and x.${e("program")} = enrollment_ensure.program
    and x.${e("subjectType")} = enrollment_ensure.subject_type and x.${e("subjectId")} = enrollment_ensure.subject_id
  for update;
  if v_row.${e("id")} is null then
    insert into ${enrollments} (${enrollmentInsert.map(([column]) => e(column)).join(", ")})
    values (${enrollmentInsert.map(([, value]) => value).join(", ")})
    on conflict do nothing
    returning * into v_row;
    if v_row.${e("id")} is null then
      select * into v_row from ${enrollments} x
      where x.${e("tenant")} is not distinct from enrollment_ensure.tenant and x.${e("program")} = enrollment_ensure.program
        and x.${e("subjectType")} = enrollment_ensure.subject_type and x.${e("subjectId")} = enrollment_ensure.subject_id;
      return v_row.${e("id")};
    end if;${emit("enrollment.created", "v_row")}
    return v_row.${e("id")};
  end if;
  if v_row.${e("steps")} is distinct from enrollment_ensure.steps${hasVersion ? ` or v_row.${e("programVersion")} is distinct from enrollment_ensure.program_version` : ""} then
    v_was := v_row.${e("status")};
    update ${enrollments} x set ${e("steps")} = enrollment_ensure.steps${hasVersion ? `, ${e("programVersion")} = enrollment_ensure.program_version` : ""}
    where x.${e("id")} = v_row.${e("id")};
    ${recount(`v_row.${e("id")}`, "v_row")}
    -- Removing the steps that were left can complete the enrollment.
    if v_was <> 'completed' and v_row.${e("status")} = 'completed' then${emit("enrollment.completed", "v_row")}
      null;
    end if;
  end if;
  return v_row.${e("id")};
end;
$$;
revoke execute on function ${fn("enrollment_ensure")}(${idType}, text, integer, text[], text, text, uuid) from public, anon, authenticated;
${scheduleInternals(ctx)}
-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function ${fn("enrollment_mark")}(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${enrollments};
  v_was text;
  v_count integer;
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_mark.enrollment_id for update;
  if v_row.${e("id")} is null then
    ${enrollmentMissing}
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row.${e("steps")})) then
    ${invalid("this step is not part of the program")}
  end if;
  if v_row.${e("status")} = 'cancelled' then
    ${invalid("the enrollment is cancelled")}
  end if;
  v_was := v_row.${e("status")};
  -- An open row of a step with a schedule is completed in place.
  if enrollment_mark.done then
    update ${steps} y
    set ${s("completedBy")} = enrollment_mark.actor, ${s("completedAt")} = now()
    where y.${s("enrollment")} = v_row.${e("id")} and y.${s("step")} = enrollment_mark.step and y.${s("completedAt")} is null;
    get diagnostics v_count = row_count;
    if v_count = 0 then
      insert into ${steps} (${s("enrollment")}, ${s("tenant")}, ${s("step")}, ${s("completedBy")}, ${s("completedAt")})
      values (v_row.${e("id")}, v_row.${e("tenant")}, enrollment_mark.step, enrollment_mark.actor, now())
      on conflict do nothing;
      get diagnostics v_count = row_count;
    end if;
  else
    delete from ${steps} x
    where x.${s("enrollment")} = v_row.${e("id")} and x.${s("step")} = enrollment_mark.step and x.${s("completedAt")} is not null;
    get diagnostics v_count = row_count;
  end if;
  if v_count = 0 then
    return false;
  end if;${
    scheduled
      ? `
  -- A reset step with a schedule gets its open row back.
  if not enrollment_mark.done then
    perform ${fn("enrollment_schedule")}(v_row.${e("id")});
  end if;`
      : ""
  }
  ${recount(`v_row.${e("id")}`, "v_row")}
  if enrollment_mark.done then${emit("enrollment.step_completed", "v_row", "enrollment_mark.step")}
    if v_was <> 'completed' and v_row.${e("status")} = 'completed' then${emit("enrollment.completed", "v_row")}
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function ${fn("enrollment_mark")}(uuid, text, boolean, uuid) from public, anon, authenticated;
${stateInternals()}
-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function ${fn("save_enrollment_program")}(tenant ${idType}, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${programs};
  v_row ${programs};
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not ${allowed("save_enrollment_program.tenant", manage)} then
    ${forbidden("not allowed to manage enrollment programs")}
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    ${invalid("program must be an object")}
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${programs} x
    where x.${p("id")} = v_id and x.${p("tenant")} = save_enrollment_program.tenant
    for update;
    if v_old.${p("id")} is null then
      ${programMissing}
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old.${p("version")} then
      ${fail("ENROLLMENTS_PROGRAM_CONFLICT", "the program changed since you read it", "40001")}
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    ${invalid("subjectTypes must be an array of subject types")}
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old.${p("key")});
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old.${p("name")}));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else ${field("programs", "v_old", "description")} end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old.${p("subjectTypes")}, '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old.${p("steps")}, '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old.${p("enabled")}, true) end;
  if v_key is null or v_key !~ '${TYPE}' then
    ${invalid('key: use lowercase letters, digits, "_" or "-", starting with a letter')}
  end if;
  if v_old.${p("id")} is not null and v_key <> v_old.${p("key")} then
    ${invalid("a program's key can't change")}
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    ${invalid("name must be 1 to 200 characters")}
  end if;
  if length(v_description) > 2000 then
    ${invalid("description must be at most 2000 characters")}
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '${TYPE}') then
    ${invalid("subjectTypes must be lower-case subject types")}
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    ${invalid("steps: pass at least one step")}
  end if;
  if jsonb_array_length(v_steps) > ${maxSteps} then
    ${invalid(`a program holds at most ${maxSteps} steps`)}
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '${STEP_ID}' then
      ${invalid('each step needs an id of lowercase letters, digits, "_", "." or "-"')}
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      ${invalid("step ids must be unique")}
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      ${invalid("a step title holds at most 200 characters and a description 2000")}
    end if;
    ${stepRuleChecks(invalid)}
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description',
      ${stepRuleJson("t.value")})) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old.${p("id")} is null then
    insert into ${programs} (${programInsert.map(([column]) => p(column)).join(", ")})
    values (${programInsert.map(([, value]) => value).join(", ")})
    on conflict (${p("tenant")}, ${p("key")}) do nothing
    returning * into v_row;
    if v_row.${p("id")} is null then
      ${fail("ENROLLMENTS_PROGRAM_EXISTS", "a program with this key already exists", "23505")}
    end if;
  else
    update ${programs} x
    set ${p("name")} = v_name,${hasDescription ? ` ${p("description")} = v_description,` : ""} ${p("subjectTypes")} = v_types, ${p("steps")} = v_steps,
      ${p("enabled")} = v_enabled,
      ${p("version")} = x.${p("version")} + case when x.${p("steps")} is distinct from v_steps then 1 else 0 end${
        ctx.has("programs", "updatedAt")
          ? `,
      ${p("updatedAt")} = now()`
          : ""
      }
    where x.${p("id")} = v_old.${p("id")}
    returning * into v_row;
  end if;
  ${createdOrUpdated(`v_old.${p("id")} is null`, (verb) => programRecord(`enrollment_program.${verb}`, "v_row", `${verb} an enrollment program`))}
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("save_enrollment_program")}(${idType}, jsonb)`)}

-- The organization's programs by key.
create or replace function ${fn("enrollment_programs")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("enrollment_programs.tenant", read)} then
    ${forbidden("not allowed to read enrollment programs")}
  end if;
  return coalesce((
    select jsonb_agg(${programJson("x")} order by x.${p("key")})
    from ${programs} x where x.${p("tenant")} = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("enrollment_programs")}(${idType})`)}

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function ${fn("delete_enrollment_program")}(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs};
begin
  select * into v_row from ${programs} x where x.${p("id")} = delete_enrollment_program.program_id for update;
  if v_row.${p("id")} is null then
    return false;
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${forbidden("not allowed to manage enrollment programs")}
  end if;
  delete from ${enrollments} x where x.${e("tenant")} = v_row.${p("tenant")} and x.${e("program")} = v_row.${p("key")};
  delete from ${programs} x where x.${p("id")} = v_row.${p("id")};
  ${programRecord("enrollment_program.deleted", "v_row", "deleted an enrollment program")}
  return true;
end;
$$;
${userGrant(`${fn("delete_enrollment_program")}(uuid)`)}

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function ${fn("enroll")}(tenant ${idType}, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program ${programs};
  v_row ${enrollments};
  v_id uuid;
  v_steps text[];
begin
  if not ${allowed("enroll.tenant", enroll)} then
    ${forbidden("not allowed to enroll")}
  end if;
  select * into v_program from ${programs} x
  where x.${p("tenant")} = enroll.tenant and x.${p("key")} = enroll.program;
  if v_program.${p("id")} is null then
    ${programMissing}
  end if;
  if not v_program.${p("enabled")} then
    ${invalid("this program is turned off")}
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '${TYPE}' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    ${invalid("an enrollment needs a subject type and id")}
  end if;
  if cardinality(v_program.${p("subjectTypes")}) > 0 and not (enroll.subject_type = any(v_program.${p("subjectTypes")})) then
    ${invalid("this program doesn't enroll this subject type")}
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    ${invalid("a user subject needs a user id")}
  end if;
  v_steps := ${stepIds(`v_program.${p("steps")}`)};
  ${ctx.hook("before_enrollment_create", [
    [idType, "enroll.tenant"],
    ["text", "enroll.program"],
    ["text", "enroll.subject_type"],
    ["text", "enroll.subject_id"],
  ])}
  select * into v_row from ${enrollments} x
  where x.${e("tenant")} = enroll.tenant and x.${e("program")} = enroll.program
    and x.${e("subjectType")} = enroll.subject_type and x.${e("subjectId")} = enroll.subject_id
  for update;
  if v_row.${e("status")} = 'cancelled' then
    update ${enrollments} x
    set ${e("status")} = 'active', ${e("cancelledAt")} = null, ${e("enrolledBy")} = auth.uid(), ${e("enrolledAt")} = now(),
      ${e("steps")} = v_steps${hasVersion ? `, ${e("programVersion")} = v_program.${p("version")}` : ""}
    where x.${e("id")} = v_row.${e("id")};
    ${recount(`v_row.${e("id")}`, "v_row")}${emit("enrollment.created", "v_row")}
    v_id := v_row.${e("id")};
  else
    v_id := ${fn("enrollment_ensure")}(enroll.tenant, enroll.program, v_program.${p("version")}, v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;${schedule("v_id")}
  ${ctx.hook("after_enrollment_create", [["uuid", "v_id"]])}
  return ${fn("enrollment_json")}(v_id);
end;
$$;
${userGrant(`${fn("enroll")}(${idType}, text, text, text)`)}

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function ${fn("enrollment")}(tenant ${idType}, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (${allowed("enrollment.tenant", read)} or (enrollment.subject_type = 'user' and coalesce(enrollment.subject_id = auth.uid()::text, false))) then
    ${forbidden("not allowed to read enrollments")}
  end if;
  select x.${e("id")} into v_id from ${enrollments} x
  where x.${e("tenant")} = enrollment.tenant and x.${e("program")} = enrollment.program
    and x.${e("subjectType")} = enrollment.subject_type and x.${e("subjectId")} = enrollment.subject_id;
  return case when v_id is null then null else ${fn("enrollment_json")}(v_id) end;
end;
$$;
${userGrant(`${fn("enrollment")}(${idType}, text, text, text)`)}

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function ${fn("list_enrollments")}(tenant ${idType}, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := ${allowed("list_enrollments.tenant", read)};
begin
  if not v_read and auth.uid() is null then
    ${forbidden("not allowed to read enrollments")}
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    ${invalid("status must be active, completed or cancelled")}
  end if;
  return coalesce((
    select jsonb_agg(${fn("enrollment_json")}(y.${e("id")}) order by y.${e("updatedAt")} desc, y.${e("id")})
    from (
      select x.${e("id")}, x.${e("updatedAt")} from ${enrollments} x
      where x.${e("tenant")} = list_enrollments.tenant
        and (v_read or x.${e("user")} = auth.uid())
        and (list_enrollments.program is null or x.${e("program")} = list_enrollments.program)
        and (list_enrollments.subject_type is null or x.${e("subjectType")} = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x.${e("subjectId")} = list_enrollments.subject_id)
        and (list_enrollments.status is null or x.${e("status")} = ${ctx.cast("enrollments", "status", "list_enrollments.status")})
        and (list_enrollments.before is null or x.${e("updatedAt")} < list_enrollments.before)
      order by x.${e("updatedAt")} desc, x.${e("id")}
      limit ${pageSize("list_enrollments.page_size", 50, 200)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_enrollments")}(${idType}, text, text, text, text, integer, timestamptz)`)}

-- Marks a step of an enrollment done or not done: enrollments.enroll, the
-- enrolled user for their own, or the user a step is assigned to.
create or replace function ${fn("enrollment_step")}(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${enrollments};
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = enrollment_step.enrollment_id;
  if v_row.${e("id")} is null or not (${allowed(`v_row.${e("tenant")}`, read)} or ${self("v_row")}${assigned("v_row", "enrollment_step.step")}) then
    ${enrollmentMissing}
  end if;
  if not (${allowed(`v_row.${e("tenant")}`, enroll)} or ${self("v_row")}${assigned("v_row", "enrollment_step.step")}) then
    ${forbidden("not allowed to change this enrollment")}
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row.${e("program")} like 'course:%' then
    ${invalid("this enrollment belongs to a course; complete its lessons through courses")}
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row.${e("program")} like 'sequence:%' then
    ${invalid("this enrollment belongs to a sequence; its steps run on the sequence's schedule")}
  end if;
  perform ${fn("enrollment_mark")}(v_row.${e("id")}, enrollment_step.step, enrollment_step.done, auth.uid());
  return ${fn("enrollment_json")}(v_row.${e("id")});
end;
$$;
revoke execute on function ${fn("enrollment_step")}(uuid, text, boolean) from public, anon, authenticated;

create or replace function ${fn("complete_enrollment_step")}(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("enrollment_step")}(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
${userGrant(`${fn("complete_enrollment_step")}(uuid, text)`)}

create or replace function ${fn("reset_enrollment_step")}(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("enrollment_step")}(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
${userGrant(`${fn("reset_enrollment_step")}(uuid, text)`)}

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function ${fn("cancel_enrollment")}(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${enrollments};
begin
  select * into v_row from ${enrollments} x where x.${e("id")} = cancel_enrollment.enrollment_id for update;
  if v_row.${e("id")} is null or not (${allowed(`v_row.${e("tenant")}`, read)} or ${self("v_row")}) then
    ${enrollmentMissing}
  end if;
  if not (${allowed(`v_row.${e("tenant")}`, enroll)} or ${self("v_row")}) then
    ${forbidden("not allowed to change this enrollment")}
  end if;
  if position(':' in v_row.${e("program")}) > 0 then
    ${invalid("this enrollment belongs to a module and can't be cancelled")}
  end if;
  if v_row.${e("status")} = 'completed' then
    ${invalid("a completed enrollment can't be cancelled")}
  end if;
  ${ctx.hook("before_enrollment_cancel", [["uuid", "cancel_enrollment.enrollment_id"]])}
  if v_row.${e("status")} = 'active' then
    update ${enrollments} x
    set ${e("status")} = 'cancelled', ${e("cancelledAt")} = now(), ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${emit("enrollment.cancelled", "v_row", "null::text", "null::text")}
  end if;
  ${ctx.hook("after_enrollment_cancel", [["uuid", "cancel_enrollment.enrollment_id"]])}
  return ${fn("enrollment_json")}(v_row.${e("id")});
end;
$$;
${userGrant(`${fn("cancel_enrollment")}(uuid)`)}
${scheduleFunctions(ctx)}`;
}
