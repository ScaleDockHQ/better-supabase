import type { BlockSqlContext } from "../context.ts";
import type { CasesSql } from "./cases-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, serviceGrant, triggerGrant, userGrant } from "../shared.ts";
import { casesSql } from "./cases-sql.ts";
import { driveControl } from "./drive-documents.ts";
import { driveSubjectType } from "./drive-kit.ts";

/**
 * The blocker checks of the cases row `row` (a `cases` composite), each
 * appending its hint code to `v_blockers`.
 */
function blockerChecks(ctx: BlockSqlContext, q: CasesSql, row: string): string {
  const { k, c, a, actions } = q;
  const tasks = q.tasks;

  const actionChecks =
    tasks === undefined
      ? ""
      : `
  if v_kind.${k("requiresActions")} and not exists (
    select 1 from ${actions} x where x.${a("case")} = ${row}.${c("id")} and x.${a("required")}
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_REQUIRED'::text;
  end if;
  if exists (
    select 1 from ${actions} x
    join ${tasks.table("items")} i on i.${tasks.col("items", "id")} = x.${a("task")}
    where x.${a("case")} = ${row}.${c("id")} and x.${a("required")}
      and ${tasks.is("items", "state", `i.${tasks.col("items", "state")}`, ["completed", "canceled"], true)}
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_OPEN'::text;
  end if;`;

  const drive =
    ctx.installed("drive") &&
    ctx.of("drive").mode !== "custom" &&
    driveControl(ctx.of("drive")) !== undefined &&
    q.relations !== undefined
      ? ctx.of("drive")
      : undefined;

  const relations = q.relations;

  const revisionCheck =
    drive === undefined || relations === undefined
      ? ""
      : `
  if v_kind.${k("requiresRevisions")} and exists (
    select 1 from ${relations.table("relations")} r
    join ${drive.table("nodes")} n on n.${drive.col("nodes", "id")}::text = r.${relations.col("relations", "targetId")}
    where r.${relations.col("relations", "kind")} = 'affects'
      and r.${relations.col("relations", "sourceType")} = ${q.subject}
      and r.${relations.col("relations", "sourceId")} = ${row}.${c("id")}::text
      and r.${relations.col("relations", "targetType")} = ${sqlString(driveSubjectType(drive))}
      and (n.${drive.col("nodes", "effectiveFrom")} is null or n.${drive.col("nodes", "effectiveFrom")} <= ${row}.${c("createdAt")})
  ) then
    v_blockers := v_blockers || 'CASE_DOCUMENTS_NOT_REVISED'::text;
  end if;`;

  const approvals = q.approvals;

  const approvalCheck =
    approvals === undefined
      ? ""
      : `
  v_policy := ${approvals.fn("approval_effective_policy")}(${row}.${c("tenant")}, ${q.subject}, 'close',
    jsonb_build_object('caseId', ${row}.${c("id")}, 'kind', v_kind.${k("key")}, 'severity', ${q.caseOf(row, "severity")}));
  if (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0)
    and not exists (
      select 1 from ${approvals.table("requests")} r
      where r.${approvals.col("requests", "subjectType")} = ${q.subject}
        and r.${approvals.col("requests", "subjectId")} = ${row}.${c("id")}::text
        and r.${approvals.col("requests", "action")} = 'close'
        and r.${approvals.col("requests", "status")} = 'approved'
    ) then
    v_blockers := v_blockers || 'CASE_APPROVAL_REQUIRED'::text;
  end if;`;

  return `select * into v_kind from ${q.kinds} y where y.${k("id")} = ${row}.${c("kind")};
  if v_kind.${k("requiresRootCause")} and coalesce(trim(${row}.${c("rootCause")}), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;${actionChecks}
  if v_kind.${k("requiresEffectiveness")} and ${row}.${c("effective")} is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;${revisionCheck}${approvalCheck}`;
}

function blockers(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, c, cases, kinds } = q;
  const guard = ctx.naming.rename("bsb_case_guard");
  const versions = q.versions;
  const stages = q.pipelines;

  // What approvals runs once a request to close is approved: the case moves to
  // its first success stage when nothing else blocks it, otherwise it stays
  // open and the blockers show, so an approval never fails to finalize.
  const approved =
    q.approvals === undefined
      ? ""
      : `
create or replace function ${fn("case_close_approved")}(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_stage uuid;
begin
  select * into v_row from ${cases} x where x.${c("id")} = case_close_approved.case_id for update;
  if not found or v_row.${c("status")} <> 'open' or cardinality(${fn("case_blockers_of")}(v_row)) > 0 then
    return;
  end if;
  select s.${stages.col("stages", "id")} into v_stage from ${stages.table("stages")} s
  where s.${stages.col("stages", "pipeline")} = v_row.${c("pipeline")} and s.${stages.col("stages", "outcome")} = 'success' and s.${stages.col("stages", "archivedAt")} is null
  order by s.${stages.col("stages", "rank")} collate "C"
  limit 1;
  if v_stage is not null then
    update ${cases} x set ${c("stage")} = v_stage where x.${c("id")} = v_row.${c("id")};
  end if;
end;
$$;
${serviceGrant(`${fn("case_close_approved")}(uuid)`)}
`;

  // The case as it closed, frozen in versions.
  const snapshot =
    versions === undefined
      ? ""
      : `
      perform ${versions.fn("version_insert")}(new.${c("tenant")}, ${q.subject}, new.${c("id")}::text,
        ${q.caseJson("new")}, null, 'Closed ' || new.${c("number")}, 'manual', true, auth.uid());`;

  return `
-- What still stops the case in row from closing, as hint codes in check order.
create or replace function ${fn("case_blockers_of")}(target ${cases})
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind ${kinds};
  v_blockers text[] := '{}';${q.approvals === undefined ? "" : "\n  v_policy jsonb;"}
begin
  ${blockerChecks(ctx, q, "case_blockers_of.target")}
  return v_blockers;
end;
$$;
${serviceGrant(`${fn("case_blockers_of")}(${cases})`)}

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function ${fn("case_close_blockers")}(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
begin
  select * into v_row from ${cases} x where x.${c("id")} = case_close_blockers.case_id;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${c("tenant")}`, q.read)} then
    ${q.forbidden("not allowed to read cases")}
  end if;
  return ${fn("case_blockers_of")}(v_row);
end;
$$;
${userGrant(`${fn("case_close_blockers")}(uuid)`)}

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.${guard}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new.${c("stage")} is not distinct from old.${c("stage")} then
    return new;
  end if;
  v_outcome := ${q.outcome(`new.${c("stage")}`)};
  if v_outcome = 'success' then
    if old.${c("status")} <> 'closed' then
      v_blockers := ${fn("case_blockers_of")}(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new.${c("status")} := 'closed';
      new.${c("closedAt")} := now();
      new.${c("closedBy")} := auth.uid();${snapshot}
    end if;
  elsif v_outcome = 'failure' then
    if old.${c("status")} <> 'canceled' then
      new.${c("status")} := 'canceled';
      new.${c("closedAt")} := now();
      new.${c("closedBy")} := auth.uid();
    end if;
  elsif old.${c("status")} <> 'open' then
    new.${c("status")} := 'open';
    new.${c("closedAt")} := null;
    new.${c("closedBy")} := null;
    new.${c("closeNote")} := null;
  end if;
  new.${c("updatedAt")} := now();
  return new;
end;
$$;
${triggerGrant(`better_supabase.${guard}()`)}
drop trigger if exists ${guard} on ${cases};
create trigger ${guard} before update of ${c("stage")} on ${cases}
for each row execute function better_supabase.${guard}();
${approved}`;
}

function transitions(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, k, c, cases, caseJson } = q;
  const p = q.pipelines;

  const stageOf = (outcome: string): string =>
    `select s.${p.col("stages", "id")} into v_stage from ${p.table("stages")} s
  where s.${p.col("stages", "pipeline")} = v_row.${c("pipeline")} and s.${p.col("stages", "outcome")} = '${outcome}' and s.${p.col("stages", "archivedAt")} is null
  order by s.${p.col("stages", "rank")} collate "C"
  limit 1;
  if v_stage is null then
    ${fail("CASE_STAGE_MISSING", `the case's pipeline has no active ${outcome} stage`, "55000")}
  end if;`;

  const kindKey = `(select y.${k("key")} from ${q.kinds} y where y.${k("id")} = v_row.${c("kind")})`;

  const load = (name: string): string =>
    `select * into v_row from ${cases} x where x.${c("id")} = ${name}.case_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${c("tenant")}`, q.close)} then
    ${q.forbidden("not allowed to close, cancel or reopen cases")}
  end if;`;

  const reason = (name: string, arg: string): string =>
    `if length(${name}.${arg}) > 4000 then
    ${q.invalid(`${arg} is at most 4000 characters`)}
  end if;`;

  return `
-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function ${fn("close_case")}(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_stage uuid;
begin
  select * into v_row from ${cases} x where x.${c("id")} = close_case.case_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.ownerOr("v_row", q.close)} then
    ${q.forbidden("not allowed to close this case")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${q.closed}
  end if;
  ${reason("close_case", "note")}
  ${ctx.hook("before_case_close", [["uuid", `v_row.${c("id")}`]])}
  ${stageOf("success")}
  update ${cases} x set ${c("stage")} = v_stage, ${c("closeNote")} = nullif(trim(close_case.note), '')
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${q.record("case.closed", "v_row", kindKey, "case closed", `, 'note', v_row.${c("closeNote")}`)}
  ${ctx.hook("after_case_close", [["uuid", `v_row.${c("id")}`]])}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("close_case")}(uuid, text)`)}

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function ${fn("cancel_case")}(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_stage uuid;
begin
  ${load("cancel_case")}
  if v_row.${c("status")} <> 'open' then
    ${q.closed}
  end if;
  ${reason("cancel_case", "reason")}
  ${stageOf("failure")}
  update ${cases} x set ${c("stage")} = v_stage, ${c("closeNote")} = nullif(trim(cancel_case.reason), '')
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${q.record("case.cancelled", "v_row", kindKey, "case cancelled", ", 'reason', nullif(trim(cancel_case.reason), '')")}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_case")}(uuid, text)`)}

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function ${fn("reopen_case")}(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_stage uuid;
begin
  ${load("reopen_case")}
  if v_row.${c("status")} = 'open' then
    ${q.invalid("the case is open")}
  end if;
  ${reason("reopen_case", "reason")}
  ${stageOf("open")}
  update ${cases} x set ${c("stage")} = v_stage
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${q.record("case.reopened", "v_row", kindKey, "case reopened", ", 'reason', nullif(trim(reopen_case.reason), '')")}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("reopen_case")}(uuid, text)`)}
`;
}

function effectiveness(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, k, c, a, cases, actions } = q;
  const tasks = q.tasks;

  const allDone =
    tasks === undefined
      ? "false"
      : `exists (select 1 from ${actions} x where x.${a("case")} = v_row.${c("id")} and x.${a("required")})
    and not exists (
      select 1 from ${actions} x
      join ${tasks.table("items")} i on i.${tasks.col("items", "id")} = x.${a("task")}
      where x.${a("case")} = v_row.${c("id")} and x.${a("required")}
        and ${tasks.is("items", "state", `i.${tasks.col("items", "state")}`, ["completed", "canceled"], true)}
    )`;

  // The work items render after the cases (both sort before pipelines), so no
  // trigger on them can schedule the check; the date counts from the day the
  // last required work item closed instead.
  const doneOn =
    tasks === undefined
      ? "current_date"
      : `coalesce((
      select max(i.${tasks.col("items", "closedAt")})::date from ${actions} x
      join ${tasks.table("items")} i on i.${tasks.col("items", "id")} = x.${a("task")}
      where x.${a("case")} = v_row.${c("id")} and x.${a("required")}
    ), current_date)`;

  const notify = ctx.installed("notifications")
    ? `if v_row.${c("owner")} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'case.effectiveness_date_reached',
        'tenant', v_row.${c("tenant")},
        'actor', null,
        'subject_type', ${q.subject},
        'subject_id', v_row.${c("id")}::text,
        'summary', v_row.${c("number")} || ' ' || v_row.${c("title")},
        'recipients', to_jsonb(array[v_row.${c("owner")}]),
        'key', 'case.effectiveness_date_reached:' || v_row.${c("id")}::text || ':' || v_row.${c("effectivenessDueOn")}::text,
        'data', jsonb_build_object('caseId', v_row.${c("id")}, 'effectivenessDueOn', v_row.${c("effectivenessDueOn")})
      )`,
        { indent: "      " },
      )}
    end if;`
    : "";

  const kindKey = `(select y.${k("key")} from ${q.kinds} y where y.${k("id")} = v_row.${c("kind")})`;

  return `
-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function ${fn("schedule_case_effectiveness")}(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_days integer;
begin
  select * into v_row from ${cases} x where x.${c("id")} = schedule_case_effectiveness.case_id for update;
  if not found or v_row.${c("status")} <> 'open' or v_row.${c("effective")} is not null then
    return;
  end if;
  select y.${k("effectivenessAfterDays")} into v_days from ${q.kinds} y where y.${k("id")} = v_row.${c("kind")};
  if v_days is null then
    return;
  end if;
  if ${allDone} then
    if v_row.${c("effectivenessDueOn")} is null then
      update ${cases} x set ${c("effectivenessDueOn")} = ${doneOn} + v_days, ${c("updatedAt")} = now()
      where x.${c("id")} = v_row.${c("id")};
    end if;
  elsif v_row.${c("effectivenessDueOn")} is not null then
    update ${cases} x set ${c("effectivenessDueOn")} = null, ${c("updatedAt")} = now()
    where x.${c("id")} = v_row.${c("id")};
  end if;
end;
$$;
${serviceGrant(`${fn("schedule_case_effectiveness")}(uuid)`)}
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function ${fn("notify_due_case_effectiveness")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform ${fn("schedule_case_effectiveness")}(x.${c("id")}) from ${cases} x
  where x.${c("status")} = 'open' and x.${c("archivedAt")} is null and x.${c("effective")} is null
    and x.${c("effectivenessDueOn")} is null
    and exists (select 1 from ${actions} y where y.${a("case")} = x.${c("id")} and y.${a("required")});
  for v_row in
    select * from ${cases} x
    where x.${c("status")} = 'open' and x.${c("archivedAt")} is null and x.${c("effective")} is null
      and x.${c("effectivenessDueOn")} <= current_date
      and x.${c("effectivenessNotifiedFor")} is distinct from x.${c("effectivenessDueOn")}
    for update skip locked
  loop
    ${q.record("case.effectiveness_date_reached", "v_row", kindKey, "case effectiveness check due", `, 'ownerId', v_row.${c("owner")}, 'effectivenessDueOn', v_row.${c("effectivenessDueOn")}`)}
    ${notify}
    update ${cases} x set ${c("effectivenessNotifiedFor")} = v_row.${c("effectivenessDueOn")} where x.${c("id")} = v_row.${c("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_due_case_effectiveness")}()`)}
`;
}

export function caseCloseFunctions(ctx: BlockSqlContext): string {
  const q = casesSql(ctx);

  return `${blockers(ctx, q)}${transitions(ctx, q)}${effectiveness(ctx, q)}`;
}
