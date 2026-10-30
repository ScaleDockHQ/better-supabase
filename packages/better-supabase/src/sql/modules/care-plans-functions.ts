import type { BlockSqlContext } from "../context.ts";
import type { CarePlansSql } from "./care-plans-sql.ts";

import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, serviceGrant, userGrant, writeExtraColumns } from "../shared.ts";
import { carePlansSql } from "./care-plans-sql.ts";

/** Statements that check `source ->> 'rank'` when it is set. */
const rankCheck = (q: CarePlansSql, source: string): string => `
  if ${source} ? 'rank' and (${source} ->> 'rank') !~ ${RANK_KEY_PATTERN} then
    ${q.invalid("rank must be a rank key")}
  end if;`;

/** Statements that check `source -> key` is an object or null when set. */
const objectCheck = (q: CarePlansSql, source: string, key: string): string => `
  if ${source} ? '${key}' and jsonb_typeof(${source} -> '${key}') not in ('object', 'null') then
    ${q.invalid(`${key} must be an object`)}
  end if;`;

/** Statements that check a title in `value` of 1 to 300 characters. */
const titleCheck = (q: CarePlansSql, value: string, what: string): string => `
  if coalesce(length(${value}), 0) not between 1 and 300 then
    ${q.invalid(`${what} needs a title of 1 to 300 characters`)}
  end if;`;

/**
 * Loads plans row `id` into `v_plan` for update and checks the caller holds
 * `permission` and can read the client.
 */
const loadPlan = (q: CarePlansSql, id: string, permission: string): string => `
  select * into v_plan from ${q.plans} x where x.${q.p("id")} = ${id} for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_plan.${q.p("tenant")}`, permission)} then
    ${q.forbidden("not allowed to change this care plan")}
  end if;
  if not ${q.clientReadable("v_plan")} then
    ${q.forbidden("not allowed to read this client")}
  end if;`;

const draftOnly = (q: CarePlansSql): string => `
  if v_plan.${q.p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_plan.${q.p("status")} <> 'draft' then
    ${q.notDraft}
  end if;`;

/** The plan as JSON with its problems, goals, actions and evaluations. */
function treeFunction(q: CarePlansSql): string {
  const { fn, p, pr, g, a, e } = q;

  const actions = `coalesce((select jsonb_agg(${q.actionJson("w")} order by w.${a("rank")}, w.${a("createdAt")}) from ${q.actions} w where w.${a("tenant")} = z.${g("tenant")} and w.${a("plan")} = z.${g("plan")} and w.${a("goal")} = z.${g("id")}), '[]'::jsonb)`;

  const goals = `coalesce((select jsonb_agg(${q.goalJson("z")} || jsonb_build_object('actions', ${actions}) order by z.${g("rank")}, z.${g("createdAt")}) from ${q.goals} z where z.${g("tenant")} = y.${pr("tenant")} and z.${g("plan")} = y.${pr("plan")} and z.${g("problem")} = y.${pr("id")}), '[]'::jsonb)`;

  const problems = `coalesce((select jsonb_agg(${q.problemJson("y")} || jsonb_build_object('goals', ${goals}) order by y.${pr("rank")}, y.${pr("createdAt")}) from ${q.problems} y where y.${pr("tenant")} = x.${p("tenant")} and y.${pr("plan")} = x.${p("id")}), '[]'::jsonb)`;

  const evaluations = `coalesce((select jsonb_agg(${q.evaluationJson("v")} order by v.${e("evaluatedAt")} desc) from ${q.evaluations} v where v.${e("tenant")} = x.${p("tenant")} and v.${e("plan")} = x.${p("id")}), '[]'::jsonb)`;

  return `
-- A plan with its problems, goals, actions and evaluations. The other
-- functions call it after their checks; it is not an entry point.
create or replace function ${fn("care_plan_json")}(plan_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${q.planJson("x")} || jsonb_build_object('problems', ${problems}, 'evaluations', ${evaluations})
  from ${q.plans} x where x.${p("id")} = care_plan_json.plan_id
$$;
${serviceGrant(`${fn("care_plan_json")}(uuid)`)}
`;
}

function planWrites(ctx: BlockSqlContext, q: CarePlansSql): string {
  const { fn, p, pr, g, a, plans, problems, goals, actions, extras } = q;
  const idType = ctx.idType;
  const createdBy = ctx.has("plans", "createdBy");

  const dates = (source: string): string => `
  if ${source} ? 'reviewOn' and ${source} ? 'startsOn'
    and (${source} ->> 'reviewOn')::date < (${source} ->> 'startsOn')::date then
    ${q.invalid("reviewOn can't be before startsOn")}
  end if;
  if ${source} ? 'fields' and jsonb_typeof(${source} -> 'fields') not in ('object', 'null') then
    ${q.invalid("fields must be an object")}
  end if;`;

  return `
-- A draft plan for a client the caller can read: input is { subjectType,
-- subjectId, title, startsOn, reviewOn, ownerId, copyFromPlanId, fields }.
-- Its version is one more than the client's last plan. copyFromPlanId copies
-- the problems, goals and actions of an earlier plan of the same client.
create or replace function ${fn("create_care_plan")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${plans};
  v_source ${plans};
  v_type text := nullif(trim(create_care_plan.input ->> 'subjectType'), '');
  v_id text := nullif(trim(create_care_plan.input ->> 'subjectId'), '');
  v_title text := trim(create_care_plan.input ->> 'title');
  v_version integer;
  v_problem ${problems};
  v_goal ${goals};
  v_new_problem uuid;
  v_new_goal uuid;
begin
  if not ${q.allowed("create_care_plan.tenant", q.write)} then
    ${q.forbidden("not allowed to write care plans")}
  end if;
  if jsonb_typeof(create_care_plan.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  if v_type is null or v_id is null then
    ${q.invalid("a care plan needs a subjectType and a subjectId")}
  end if;
  if not ${q.canClient("v_type", "v_id")} then
    ${q.forbidden("not allowed to read this client")}
  end if;${titleCheck(q, "v_title", "a care plan")}${dates("create_care_plan.input")}
  if create_care_plan.input ? 'copyFromPlanId' then
    select * into v_source from ${plans} x
    where x.${p("id")} = (create_care_plan.input ->> 'copyFromPlanId')::uuid
      and x.${p("tenant")} = create_care_plan.tenant;
    if not found then
      ${q.missing}
    end if;
    if v_source.${p("subjectType")} <> v_type or v_source.${p("subjectId")} <> v_id then
      ${q.invalid("copyFromPlanId must be a plan of the same client")}
    end if;
  end if;
  ${ctx.hook("before_care_plan_create", [
    [idType, "create_care_plan.tenant"],
    ["jsonb", "create_care_plan.input"],
  ])}
  perform pg_advisory_xact_lock(hashtextextended('care_plan:' || v_type || ':' || v_id, 0));
  select coalesce(max(x.${p("version")}), 0) + 1 into v_version from ${plans} x
  where x.${p("subjectType")} = v_type and x.${p("subjectId")} = v_id;
  insert into ${plans} (${p("tenant")}, ${p("subjectType")}, ${p("subjectId")}, ${p("title")}, ${p("version")}, ${p("startsOn")}, ${p("reviewOn")}, ${p("owner")}${createdBy ? `, ${p("createdBy")}` : ""})
  values (create_care_plan.tenant, v_type, v_id, v_title, v_version,
    nullif(create_care_plan.input ->> 'startsOn', '')::date,
    nullif(create_care_plan.input ->> 'reviewOn', '')::date,
    nullif(create_care_plan.input ->> 'ownerId', '')::uuid${createdBy ? ", auth.uid()" : ""})
  returning * into v_row;${writeExtraColumns(plans, extras, "coalesce(create_care_plan.input -> 'fields', '{}'::jsonb)", `x.${p("id")} = v_row.${p("id")}`, "v_row")}
  if v_source.${p("id")} is not null then
    for v_problem in
      select * from ${problems} y where y.${pr("tenant")} = v_source.${p("tenant")} and y.${pr("plan")} = v_source.${p("id")}
      order by y.${pr("rank")}
    loop
      insert into ${problems} (${pr("tenant")}, ${pr("plan")}, ${pr("codeSystem")}, ${pr("code")}, ${pr("title")}, ${pr("description")}, ${pr("status")}, ${pr("rank")})
      values (v_row.${p("tenant")}, v_row.${p("id")}, v_problem.${pr("codeSystem")}, v_problem.${pr("code")}, v_problem.${pr("title")}, v_problem.${pr("description")}, v_problem.${pr("status")}, v_problem.${pr("rank")})
      returning ${pr("id")} into v_new_problem;
      for v_goal in
        select * from ${goals} z where z.${g("tenant")} = v_problem.${pr("tenant")} and z.${g("plan")} = v_problem.${pr("plan")} and z.${g("problem")} = v_problem.${pr("id")}
        order by z.${g("rank")}
      loop
        insert into ${goals} (${g("tenant")}, ${g("plan")}, ${g("problem")}, ${g("title")}, ${g("targetOn")}, ${g("status")}, ${g("measure")}, ${g("rank")})
        values (v_row.${p("tenant")}, v_row.${p("id")}, v_new_problem, v_goal.${g("title")}, v_goal.${g("targetOn")}, v_goal.${g("status")}, v_goal.${g("measure")}, v_goal.${g("rank")})
        returning ${g("id")} into v_new_goal;
        -- Copies start over: planned, without the old plan's work item, approval or reviews.
        insert into ${actions} (${a("tenant")}, ${a("plan")}, ${a("goal")}, ${a("kind")}, ${a("title")}, ${a("instructions")}, ${a("frequency")}, ${a("teamRole")}, ${a("measureKind")}, ${a("bookingSeries")}, ${a("requiresApproval")}, ${a("reviewEvery")}, ${a("startsOn")}, ${a("endsOn")}, ${a("rank")})
        select v_row.${p("tenant")}, v_row.${p("id")}, v_new_goal, w.${a("kind")}, w.${a("title")}, w.${a("instructions")}, w.${a("frequency")}, w.${a("teamRole")}, w.${a("measureKind")}, w.${a("bookingSeries")}, w.${a("requiresApproval")}, w.${a("reviewEvery")}, w.${a("startsOn")}, w.${a("endsOn")}, w.${a("rank")}
        from ${actions} w
        where w.${a("tenant")} = v_goal.${g("tenant")} and w.${a("plan")} = v_goal.${g("plan")} and w.${a("goal")} = v_goal.${g("id")} and w.${a("status")} <> 'ended';
      end loop;
    end loop;
  end if;
  ${q.record("care_plan.created", "v_row", "care plan created")}
  ${ctx.hook("after_care_plan_create", [["uuid", `v_row.${p("id")}`]])}
  return ${fn("care_plan_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("create_care_plan")}(${idType}, jsonb)`)}

-- Changes a draft or active plan's title, dates, owner or extra fields.
create or replace function ${fn("update_care_plan")}(plan_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_title text;
begin${loadPlan(q, "update_care_plan.plan_id", q.write)}
  if v_plan.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if jsonb_typeof(update_care_plan.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  v_title := case when update_care_plan.changes ? 'title' then trim(update_care_plan.changes ->> 'title') else v_plan.${p("title")} end;${titleCheck(q, "v_title", "a care plan")}${dates("update_care_plan.changes")}
  update ${plans} x set
    ${p("title")} = v_title,
    ${p("startsOn")} = case when update_care_plan.changes ? 'startsOn' then nullif(update_care_plan.changes ->> 'startsOn', '')::date else x.${p("startsOn")} end,
    ${p("reviewOn")} = case when update_care_plan.changes ? 'reviewOn' then nullif(update_care_plan.changes ->> 'reviewOn', '')::date else x.${p("reviewOn")} end,
    ${p("owner")} = case when update_care_plan.changes ? 'ownerId' then nullif(update_care_plan.changes ->> 'ownerId', '')::uuid else x.${p("owner")} end,
    ${p("updatedAt")} = now()
  where x.${p("id")} = v_plan.${p("id")}
  returning * into v_plan;
  if v_plan.${p("reviewOn")} < v_plan.${p("startsOn")} then
    ${q.invalid("reviewOn can't be before startsOn")}
  end if;${writeExtraColumns(plans, extras, "coalesce(update_care_plan.changes -> 'fields', '{}'::jsonb)", `x.${p("id")} = v_plan.${p("id")}`, "v_plan")}
  ${q.record("care_plan.updated", "v_plan", "care plan updated")}
  return ${fn("care_plan_json")}(v_plan.${p("id")});
end;
$$;
${userGrant(`${fn("update_care_plan")}(uuid, jsonb)`)}
`;
}

function problemWrites(q: CarePlansSql): string {
  const { fn, p, pr, problems, plans } = q;

  const systemCheck = `if not (v_system = any (${q.codeSystems})) then
    ${fail("CARE_PLAN_CODE_SYSTEM_UNKNOWN", "the code system is not one of options.codeSystems", "22023")}
  end if;`;

  const text = (source: string): string => `
  if length(${source} ->> 'code') > 100 then
    ${q.invalid("code is at most 100 characters")}
  end if;
  if length(${source} ->> 'description') > 10000 then
    ${q.invalid("description is at most 10000 characters")}
  end if;${rankCheck(q, source)}`;

  return `
-- A problem on a draft plan: input is { codeSystem, code, title,
-- description, rank }. codeSystem is one of options.codeSystems (the first
-- when left out); new problems go last unless rank says where.
create or replace function ${fn("add_care_plan_problem")}(plan_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_row ${problems};
  v_system text;
  v_title text := trim(add_care_plan_problem.input ->> 'title');
  v_last text;
begin${loadPlan(q, "add_care_plan_problem.plan_id", q.write)}${draftOnly(q)}
  if jsonb_typeof(add_care_plan_problem.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  v_system := coalesce(nullif(add_care_plan_problem.input ->> 'codeSystem', ''), (${q.codeSystems})[1]);
  ${systemCheck}${titleCheck(q, "v_title", "a problem")}${text("add_care_plan_problem.input")}
  select max(y.${pr("rank")}) into v_last from ${problems} y
  where y.${pr("tenant")} = v_plan.${p("tenant")} and y.${pr("plan")} = v_plan.${p("id")};
  insert into ${problems} (${pr("tenant")}, ${pr("plan")}, ${pr("codeSystem")}, ${pr("code")}, ${pr("title")}, ${pr("description")}, ${pr("rank")})
  values (v_plan.${p("tenant")}, v_plan.${p("id")}, v_system,
    nullif(trim(add_care_plan_problem.input ->> 'code'), ''), v_title,
    nullif(trim(add_care_plan_problem.input ->> 'description'), ''),
    coalesce(add_care_plan_problem.input ->> 'rank', ${rankAfter("v_last")}))
  returning * into v_row;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.problemJson("v_row")};
end;
$$;
${userGrant(`${fn("add_care_plan_problem")}(uuid, jsonb)`)}

-- Changes a problem. On a draft plan every key of { codeSystem, code, title,
-- description, status, rank } changes; once the plan is active, only status
-- (active or resolved), which needs the evaluate permission.
create or replace function ${fn("update_care_plan_problem")}(problem_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_row ${problems};
  v_system text;
  v_title text;
  v_status text;
begin
  select * into v_row from ${problems} y where y.${pr("id")} = update_care_plan_problem.problem_id;
  if not found then
    ${fail("CARE_PLAN_NOT_FOUND", "no such problem on a care plan", "P0002")}
  end if;
  if jsonb_typeof(update_care_plan_problem.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;${loadPlan(q, `v_row.${pr("plan")}`, `case when (update_care_plan_problem.changes - 'status') = '{}'::jsonb then ${q.evaluate} else ${q.write} end`)}
  if v_plan.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_plan.${p("status")} <> 'draft' and (update_care_plan_problem.changes - 'status') <> '{}'::jsonb then
    ${q.notDraft}
  end if;
  v_system := case when update_care_plan_problem.changes ? 'codeSystem' then update_care_plan_problem.changes ->> 'codeSystem' else v_row.${pr("codeSystem")} end;
  ${systemCheck}
  v_title := case when update_care_plan_problem.changes ? 'title' then trim(update_care_plan_problem.changes ->> 'title') else v_row.${pr("title")} end;${titleCheck(q, "v_title", "a problem")}${text("update_care_plan_problem.changes")}
  v_status := case when update_care_plan_problem.changes ? 'status' then update_care_plan_problem.changes ->> 'status' else v_row.${pr("status")} end;
  if v_status is null or v_status not in ('active', 'resolved') then
    ${q.invalid("status is active or resolved")}
  end if;
  update ${problems} y set
    ${pr("codeSystem")} = v_system,
    ${pr("code")} = case when update_care_plan_problem.changes ? 'code' then nullif(trim(update_care_plan_problem.changes ->> 'code'), '') else y.${pr("code")} end,
    ${pr("title")} = v_title,
    ${pr("description")} = case when update_care_plan_problem.changes ? 'description' then nullif(trim(update_care_plan_problem.changes ->> 'description'), '') else y.${pr("description")} end,
    ${pr("status")} = v_status,
    ${pr("rank")} = coalesce(update_care_plan_problem.changes ->> 'rank', y.${pr("rank")}),
    ${pr("updatedAt")} = now()
  where y.${pr("id")} = v_row.${pr("id")}
  returning * into v_row;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.problemJson("v_row")};
end;
$$;
${userGrant(`${fn("update_care_plan_problem")}(uuid, jsonb)`)}
`;
}

function goalWrites(q: CarePlansSql): string {
  const { fn, p, pr, g, problems, goals, plans } = q;

  const statusChanged = q.recordChild(
    "care_plan_goal.status_changed",
    "v_plan",
    `jsonb_build_object('goalId', v_row.${g("id")}, 'title', v_row.${g("title")}, 'status', v_row.${g("status")}, 'previousStatus', v_previous)`,
    "care plan goal status changed",
  );

  return `
-- A goal for a problem on a draft plan: input is { title, targetOn,
-- measure, rank }. It starts planned.
create or replace function ${fn("add_care_plan_goal")}(problem_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_problem ${problems};
  v_row ${goals};
  v_title text := trim(add_care_plan_goal.input ->> 'title');
  v_last text;
begin
  select * into v_problem from ${problems} y where y.${pr("id")} = add_care_plan_goal.problem_id;
  if not found then
    ${fail("CARE_PLAN_NOT_FOUND", "no such problem on a care plan", "P0002")}
  end if;${loadPlan(q, `v_problem.${pr("plan")}`, q.write)}${draftOnly(q)}
  if jsonb_typeof(add_care_plan_goal.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;${titleCheck(q, "v_title", "a goal")}${objectCheck(q, "add_care_plan_goal.input", "measure")}${rankCheck(q, "add_care_plan_goal.input")}
  select max(z.${g("rank")}) into v_last from ${goals} z
  where z.${g("tenant")} = v_problem.${pr("tenant")} and z.${g("plan")} = v_problem.${pr("plan")} and z.${g("problem")} = v_problem.${pr("id")};
  insert into ${goals} (${g("tenant")}, ${g("plan")}, ${g("problem")}, ${g("title")}, ${g("targetOn")}, ${g("measure")}, ${g("rank")})
  values (v_problem.${pr("tenant")}, v_problem.${pr("plan")}, v_problem.${pr("id")}, v_title,
    nullif(add_care_plan_goal.input ->> 'targetOn', '')::date,
    nullif(add_care_plan_goal.input -> 'measure', 'null'::jsonb),
    coalesce(add_care_plan_goal.input ->> 'rank', ${rankAfter("v_last")}))
  returning * into v_row;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.goalJson("v_row")};
end;
$$;
${userGrant(`${fn("add_care_plan_goal")}(uuid, jsonb)`)}

-- Changes a goal. On a draft plan every key of { title, targetOn, measure,
-- status, rank } changes; once the plan is active, only status, which needs
-- the evaluate permission. A new status records care_plan_goal.status_changed.
create or replace function ${fn("update_care_plan_goal")}(goal_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_row ${goals};
  v_title text;
  v_status text;
  v_previous text;
begin
  select * into v_row from ${goals} z where z.${g("id")} = update_care_plan_goal.goal_id;
  if not found then
    ${q.goalMissing}
  end if;
  if jsonb_typeof(update_care_plan_goal.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;${loadPlan(q, `v_row.${g("plan")}`, `case when (update_care_plan_goal.changes - 'status') = '{}'::jsonb then ${q.evaluate} else ${q.write} end`)}
  if v_plan.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_plan.${p("status")} <> 'draft' and (update_care_plan_goal.changes - 'status') <> '{}'::jsonb then
    ${q.notDraft}
  end if;
  v_title := case when update_care_plan_goal.changes ? 'title' then trim(update_care_plan_goal.changes ->> 'title') else v_row.${g("title")} end;${titleCheck(q, "v_title", "a goal")}${objectCheck(q, "update_care_plan_goal.changes", "measure")}${rankCheck(q, "update_care_plan_goal.changes")}
  v_previous := v_row.${g("status")};
  v_status := case when update_care_plan_goal.changes ? 'status' then update_care_plan_goal.changes ->> 'status' else v_previous end;
  if v_status is null or v_status not in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled') then
    ${q.invalid("status is planned, in_progress, achieved, not_achieved or canceled")}
  end if;
  update ${goals} z set
    ${g("title")} = v_title,
    ${g("targetOn")} = case when update_care_plan_goal.changes ? 'targetOn' then nullif(update_care_plan_goal.changes ->> 'targetOn', '')::date else z.${g("targetOn")} end,
    ${g("measure")} = case when update_care_plan_goal.changes ? 'measure' then nullif(update_care_plan_goal.changes -> 'measure', 'null'::jsonb) else z.${g("measure")} end,
    ${g("status")} = v_status,
    ${g("rank")} = coalesce(update_care_plan_goal.changes ->> 'rank', z.${g("rank")}),
    ${g("updatedAt")} = now()
  where z.${g("id")} = v_row.${g("id")}
  returning * into v_row;
  if v_status is distinct from v_previous then
    ${statusChanged}
  end if;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.goalJson("v_row")};
end;
$$;
${userGrant(`${fn("update_care_plan_goal")}(uuid, jsonb)`)}
`;
}

function actionWrites(q: CarePlansSql): string {
  const { fn, p, g, a, goals, actions, plans } = q;

  const checks = (
    source: string,
  ): string => `${objectCheck(q, source, "frequency")}${rankCheck(q, source)}
  if length(${source} ->> 'instructions') > 10000 then
    ${q.invalid("instructions is at most 10000 characters")}
  end if;
  if length(${source} ->> 'teamRole') > 63 or length(${source} ->> 'measureKind') > 63 then
    ${q.invalid("teamRole and measureKind are at most 63 characters")}
  end if;`;

  const kindChecks = `if v_kind is null or v_kind not in ('intervention', 'appointment', 'task', 'measure') then
    ${q.invalid("kind is intervention, appointment, task or measure")}
  end if;
  if v_kind <> 'measure' and v_measure_kind is not null then
    ${q.invalid("only a measure has a measureKind")}
  end if;${
    q.measureKindList.length === 0
      ? ""
      : `
  if v_kind = 'measure' and (v_measure_kind is null or not (v_measure_kind = any (${q.measureKinds}))) then
    ${q.invalid("a measure needs a measureKind from options.measureKinds")}
  end if;`
  }
  if v_ends_on < v_starts_on then
    ${q.invalid("endsOn can't be before startsOn")}
  end if;`;

  // Keys an active plan's action still takes: how it runs, not what it is.
  const running = `'{bookingSeriesId,endsOn,frequency,instructions,reviewEvery,teamRole}'::text[]`;

  return `
-- An action toward a goal on a draft plan: input is { kind, title,
-- instructions, frequency, teamRole, measureKind, bookingSeriesId,
-- requiresApproval, reviewEvery, startsOn, endsOn, rank }. A measure always
-- requires an approval before it starts.
create or replace function ${fn("add_care_plan_action")}(goal_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_goal ${goals};
  v_row ${actions};
  v_kind text := coalesce(nullif(add_care_plan_action.input ->> 'kind', ''), 'intervention');
  v_title text := trim(add_care_plan_action.input ->> 'title');
  v_measure_kind text := nullif(trim(add_care_plan_action.input ->> 'measureKind'), '');
  v_starts_on date := nullif(add_care_plan_action.input ->> 'startsOn', '')::date;
  v_ends_on date := nullif(add_care_plan_action.input ->> 'endsOn', '')::date;
  v_last text;
begin
  select * into v_goal from ${goals} z where z.${g("id")} = add_care_plan_action.goal_id;
  if not found then
    ${q.goalMissing}
  end if;${loadPlan(q, `v_goal.${g("plan")}`, q.write)}${draftOnly(q)}
  if jsonb_typeof(add_care_plan_action.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;${titleCheck(q, "v_title", "an action")}${checks("add_care_plan_action.input")}
  ${kindChecks}
  select max(w.${a("rank")}) into v_last from ${actions} w
  where w.${a("tenant")} = v_goal.${g("tenant")} and w.${a("plan")} = v_goal.${g("plan")} and w.${a("goal")} = v_goal.${g("id")};
  insert into ${actions} (${a("tenant")}, ${a("plan")}, ${a("goal")}, ${a("kind")}, ${a("title")}, ${a("instructions")}, ${a("frequency")}, ${a("teamRole")}, ${a("measureKind")}, ${a("bookingSeries")}, ${a("requiresApproval")}, ${a("reviewEvery")}, ${a("startsOn")}, ${a("endsOn")}, ${a("rank")})
  values (v_goal.${g("tenant")}, v_goal.${g("plan")}, v_goal.${g("id")}, v_kind, v_title,
    nullif(trim(add_care_plan_action.input ->> 'instructions'), ''),
    nullif(add_care_plan_action.input -> 'frequency', 'null'::jsonb),
    nullif(trim(add_care_plan_action.input ->> 'teamRole'), ''),
    v_measure_kind,
    nullif(add_care_plan_action.input ->> 'bookingSeriesId', '')::uuid,
    v_kind = 'measure' or coalesce((add_care_plan_action.input ->> 'requiresApproval')::boolean, false),
    nullif(add_care_plan_action.input ->> 'reviewEvery', '')::interval,
    v_starts_on, v_ends_on,
    coalesce(add_care_plan_action.input ->> 'rank', ${rankAfter("v_last")}))
  returning * into v_row;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.actionJson("v_row")};
exception when check_violation then
  ${q.invalid("reviewEvery must be a positive interval")}
end;
$$;
${userGrant(`${fn("add_care_plan_action")}(uuid, jsonb)`)}

-- Changes an action. On a draft plan every input key of add_care_plan_action
-- changes; once the plan is active, only how it runs: bookingSeriesId,
-- endsOn, frequency, instructions, reviewEvery and teamRole.
create or replace function ${fn("update_care_plan_action")}(action_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_row ${actions};
  v_kind text;
  v_title text;
  v_measure_kind text;
  v_starts_on date;
  v_ends_on date;
begin
  select * into v_row from ${actions} w where w.${a("id")} = update_care_plan_action.action_id;
  if not found then
    ${fail("CARE_PLAN_NOT_FOUND", "no such action on a care plan", "P0002")}
  end if;
  if jsonb_typeof(update_care_plan_action.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;${loadPlan(q, `v_row.${a("plan")}`, q.write)}
  if v_plan.${p("status")} = 'archived' then
    ${q.archived}
  end if;
  if v_plan.${p("status")} <> 'draft' and (update_care_plan_action.changes - ${running}) <> '{}'::jsonb then
    ${q.notDraft}
  end if;
  if v_row.${a("status")} = 'ended' then
    ${q.invalid("the action has ended")}
  end if;
  v_kind := case when update_care_plan_action.changes ? 'kind' then update_care_plan_action.changes ->> 'kind' else v_row.${a("kind")} end;
  v_title := case when update_care_plan_action.changes ? 'title' then trim(update_care_plan_action.changes ->> 'title') else v_row.${a("title")} end;
  v_measure_kind := case when update_care_plan_action.changes ? 'measureKind' then nullif(trim(update_care_plan_action.changes ->> 'measureKind'), '') else v_row.${a("measureKind")} end;
  v_starts_on := case when update_care_plan_action.changes ? 'startsOn' then nullif(update_care_plan_action.changes ->> 'startsOn', '')::date else v_row.${a("startsOn")} end;
  v_ends_on := case when update_care_plan_action.changes ? 'endsOn' then nullif(update_care_plan_action.changes ->> 'endsOn', '')::date else v_row.${a("endsOn")} end;${titleCheck(q, "v_title", "an action")}${checks("update_care_plan_action.changes")}
  ${kindChecks}
  update ${actions} w set
    ${a("kind")} = v_kind,
    ${a("title")} = v_title,
    ${a("instructions")} = case when update_care_plan_action.changes ? 'instructions' then nullif(trim(update_care_plan_action.changes ->> 'instructions'), '') else w.${a("instructions")} end,
    ${a("frequency")} = case when update_care_plan_action.changes ? 'frequency' then nullif(update_care_plan_action.changes -> 'frequency', 'null'::jsonb) else w.${a("frequency")} end,
    ${a("teamRole")} = case when update_care_plan_action.changes ? 'teamRole' then nullif(trim(update_care_plan_action.changes ->> 'teamRole'), '') else w.${a("teamRole")} end,
    ${a("measureKind")} = v_measure_kind,
    ${a("bookingSeries")} = case when update_care_plan_action.changes ? 'bookingSeriesId' then nullif(update_care_plan_action.changes ->> 'bookingSeriesId', '')::uuid else w.${a("bookingSeries")} end,
    ${a("requiresApproval")} = v_kind = 'measure' or case when update_care_plan_action.changes ? 'requiresApproval' then coalesce((update_care_plan_action.changes ->> 'requiresApproval')::boolean, false) else w.${a("requiresApproval")} end,
    ${a("reviewEvery")} = case when update_care_plan_action.changes ? 'reviewEvery' then nullif(update_care_plan_action.changes ->> 'reviewEvery', '')::interval else w.${a("reviewEvery")} end,
    ${a("startsOn")} = v_starts_on,
    ${a("endsOn")} = v_ends_on,
    ${a("rank")} = coalesce(update_care_plan_action.changes ->> 'rank', w.${a("rank")}),
    ${a("updatedAt")} = now()
  where w.${a("id")} = v_row.${a("id")}
  returning * into v_row;
  update ${plans} x set ${p("updatedAt")} = now() where x.${p("id")} = v_plan.${p("id")};
  return ${q.actionJson("v_row")};
exception when check_violation then
  ${q.invalid("reviewEvery must be a positive interval")}
end;
$$;
${userGrant(`${fn("update_care_plan_action")}(uuid, jsonb)`)}
`;
}

function reads(q: CarePlansSql): string {
  const { fn, p, plans } = q;

  return `
-- A plan with its problems, goals, actions and evaluations, for a caller
-- who reads plans and the client, or a guest with options.guestRead.
create or replace function ${fn("get_care_plan")}(plan_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${plans};
begin
  select * into v_row from ${plans} x where x.${p("id")} = get_care_plan.plan_id;
  if not found or not ${q.visible("v_row")} then
    ${q.missing}
  end if;
  return ${fn("care_plan_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("get_care_plan")}(uuid)`)}

-- A client's plans the caller reads, the newest version first, without
-- their problems. include_archived adds the archived ones.
create or replace function ${fn("list_care_plans")}(subject_type text, subject_id text, include_archived boolean default false)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${q.planJson("x")} order by x.${p("version")} desc), '[]'::jsonb)
  from ${plans} x
  where x.${p("subjectType")} = list_care_plans.subject_type
    and x.${p("subjectId")} = list_care_plans.subject_id
    and (list_care_plans.include_archived or x.${p("status")} <> 'archived')
    and ${q.visible("x")}
$$;
${userGrant(`${fn("list_care_plans")}(text, text, boolean)`)}
`;
}

export function carePlanFunctions(ctx: BlockSqlContext): string {
  const q = carePlansSql(ctx);

  return `${treeFunction(q)}${planWrites(ctx, q)}${problemWrites(q)}${goalWrites(q)}${actionWrites(q)}${reads(q)}`;
}
