import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, fail, raise } from "../shared.ts";
import { enrollmentTables } from "./enrollments.ts";
import { moduleOperations } from "./permissions-model.ts";

const NAMES: BlockSqlNames = { options: ["checklists"], tables: {} };

/** The prefix of the enrollment program each checklist runs as. */
const PROGRAM = "onboarding:";

const ID = /^[a-z][a-z0-9_.-]{0,63}$/;
const EVENT = /^[a-z][a-z0-9_.:-]{0,127}$/;

interface StepOption {
  readonly checklist: string;
  readonly step: string;
  readonly scope: "user" | "organization";
  readonly events: readonly string[];
}

const where = "blocks.onboarding.options.checklists";

function idOf(value: unknown, path: string): string {
  if (typeof value !== "string" || !ID.test(value)) {
    throw new TypeError(
      `${path}: use lowercase letters, digits, "_", "." or "-", starting with a letter`,
    );
  }

  return value;
}

function eventsOf(value: unknown, path: string): readonly string[] {
  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new TypeError(`${path}: pass an array of outbox event types`);
  }

  const list: readonly unknown[] = value;

  return list.map((event, index) => {
    if (typeof event !== "string" || !EVENT.test(event)) {
      throw new TypeError(`${path}[${index}]: not an event type`);
    }

    return event;
  });
}

/** The steps of every `defineChecklist()` result in `options.checklists`. */
function checklistSteps(ctx: BlockSqlContext): readonly StepOption[] {
  const option = ctx.option("checklists");

  if (option === undefined) {
    return [];
  }

  if (!Array.isArray(option) && !isRecord(option)) {
    throw new TypeError(`${where}: pass an array of defineChecklist() results`);
  }

  const list: readonly unknown[] = Array.isArray(option)
    ? option
    : Object.values(option);

  const steps: StepOption[] = [];
  const seen = new Set<string>();

  for (const [index, entry] of list.entries()) {
    const path = `${where}[${index}]`;

    if (!isRecord(entry)) {
      throw new TypeError(`${path}: not a checklist`);
    }

    const checklist = idOf(entry["id"], `${path}.id`);

    if (seen.has(checklist)) {
      throw new TypeError(`${path}.id: "${checklist}" is listed twice`);
    }

    seen.add(checklist);
    const scope = entry["scope"];

    if (scope !== "user" && scope !== "organization") {
      throw new TypeError(`${path}.scope: use "user" or "organization"`);
    }

    const raw = entry["steps"];

    if (!Array.isArray(raw)) {
      throw new TypeError(`${path}.steps: pass an array`);
    }

    const entries: readonly unknown[] = raw;
    const ids = new Set<string>();

    for (const [n, item] of entries.entries()) {
      if (!isRecord(item)) {
        throw new TypeError(`${path}.steps[${n}]: not a step`);
      }

      const step = idOf(item["id"], `${path}.steps[${n}].id`);

      if (ids.has(step)) {
        throw new TypeError(
          `${path}.steps[${n}].id: "${step}" is listed twice`,
        );
      }

      ids.add(step);
      steps.push({
        checklist,
        step,
        scope,
        events: eventsOf(item["events"], `${path}.steps[${n}].events`),
      });
    }
  }

  return steps;
}

/** `(checklist, scope, steps)` rows, the steps in order. */
function checklistRows(steps: readonly StepOption[]): string {
  const lists = new Map<string, { scope: string; steps: string[] }>();

  for (const s of steps) {
    const list = lists.get(s.checklist) ?? { scope: s.scope, steps: [] };
    list.steps.push(s.step);
    lists.set(s.checklist, list);
  }

  return lists.size === 0
    ? "select null::text as checklist, null::text as scope, null::text[] as steps where false"
    : `values ${[...lists].map(([checklist, list]) => `(${sqlString(checklist)}, ${sqlString(list.scope)}, array[${list.steps.map(sqlString).join(", ")}]::text[])`).join(", ")}`;
}

/** The enrollments the checklists run on, checked to be managed. */
function enrollmentsOf(ctx: BlockSqlContext): BlockSqlContext {
  const enrolled = ctx.of("enrollments");

  if (!enrolled.manages) {
    throw new TypeError(
      "blocks.onboarding: onboarding checklists run on the enrollments tables, so install enrollments in managed mode",
    );
  }

  return enrolled;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const enrolled = enrollmentsOf(ctx);
  const id = ctx.idType;
  const enrollments = enrolled.table("enrollments");
  const e = (column: string): string => enrolled.col("enrollments", column);
  const s = (column: string): string => enrolled.col("steps", column);
  const ensure = enrolled.fn("enrollment_ensure");
  const mark = enrolled.fn("enrollment_mark");
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("onboarding");

  const can = (tenant: string, action: "read" | "complete"): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, ctx.permission(action, permissions[action]))})`;

  const steps = checklistSteps(ctx);
  const lists = checklistRows(steps);

  const stepRows =
    steps.length === 0
      ? "select null::text as checklist, null::text as step, null::text as scope where false"
      : `values ${steps.map((step) => `(${sqlString(step.checklist)}, ${sqlString(step.step)}, ${sqlString(step.scope)})`).join(", ")}`;

  const lookup = (checklist: string, step: string): string =>
    `(select s.scope from (${stepRows}) as s(checklist, step, scope) where s.checklist = ${checklist} and (${step} is null or s.step = ${step}) limit 1)`;

  const stepsOf = (checklist: string): string =>
    `(select c.steps from (${lists}) as c(checklist, scope, steps) where c.checklist = ${checklist})`;

  const scopeCheck = (fnName: string): string => `
  v_scope := ${lookup(`${fnName}.checklist`, `${fnName}.step`)};
  if v_scope is null then
    ${raise("Unknown onboarding step %.%", "22023", "ONBOARDING_STEP_UNKNOWN", `${fnName}.checklist`, `coalesce(${fnName}.step, '*')`)}
  end if;
  if v_scope = 'organization' then
    if ${fnName}.tenant is null then
      ${raise("Checklist % belongs to an organization", "22023", "ONBOARDING_SCOPE", `${fnName}.checklist`)}
    end if;
  elsif ${fnName}.tenant is not null then
    ${raise("Checklist % belongs to a user", "22023", "ONBOARDING_SCOPE", `${fnName}.checklist`)}
  elsif auth.uid() is null then
    ${fail("ONBOARDING_FORBIDDEN", "Sign in first")}
  end if;`;

  // The enrollment of the checklist's subject: the organization, or the
  // caller for a user checklist (without a tenant).
  const subject = (
    fnName: string,
  ): string => `x.${e("program")} = ${sqlString(PROGRAM)} || ${fnName}.checklist
    and x.${e("tenant")} is not distinct from (case when v_scope = 'organization' then ${fnName}.tenant end)
    and x.${e("subjectType")} = v_scope
    and x.${e("subjectId")} = (case when v_scope = 'organization' then ${fnName}.tenant::text else auth.uid()::text end)`;

  const ensureFor = (fnName: string): string =>
    `${ensure}(case when v_scope = 'organization' then ${fnName}.tenant end, ${sqlString(PROGRAM)} || ${fnName}.checklist, null, ${stepsOf(`${fnName}.checklist`)}, v_scope, case when v_scope = 'organization' then ${fnName}.tenant::text else auth.uid()::text end, auth.uid())`;

  return `${schemaPreamble(ctx)}
-- Each checklist runs as the enrollment program onboarding:<checklist>: the
-- organization is enrolled in an organization checklist, the user (without a
-- tenant) in a user checklist. The checklists live in the app
-- (defineChecklist); the functions check steps against options.checklists.

-- [{ step, completedAt, completedBy }] of one checklist for the caller, or
-- for tenant when it is an organization checklist (onboarding.read).
create or replace function ${fn("onboarding_progress")}(checklist text, tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := ${lookup("onboarding_progress.checklist", "null::text")};
  if v_scope is null then
    ${raise("Unknown onboarding checklist %", "22023", "ONBOARDING_STEP_UNKNOWN", "onboarding_progress.checklist")}
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      ${raise("Checklist % belongs to an organization", "22023", "ONBOARDING_SCOPE", "onboarding_progress.checklist")}
    end if;
    if not ${can("onboarding_progress.tenant", "read")} then
      ${fail("ONBOARDING_FORBIDDEN", "You may not see this organization's onboarding")}
    end if;
  elsif onboarding_progress.tenant is not null then
    ${raise("Checklist % belongs to a user", "22023", "ONBOARDING_SCOPE", "onboarding_progress.checklist")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', y.${s("step")},
      'completedAt', y.${s("completedAt")},
      'completedBy', y.${s("completedBy")}
    ) order by y.${s("completedAt")}, array_position(x.${e("steps")}, y.${s("step")})), '[]'::jsonb)
    from ${enrollments} x
    join ${enrolled.table("steps")} y on y.${s("enrollment")} = x.${e("id")}
    where ${subject("onboarding_progress")}
  );
end;
$$;

-- Marks a step done; false when it already was. Organization steps need
-- onboarding.complete.
create or replace function ${fn("complete_onboarding_step")}(checklist text, step text, tenant ${id} default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin${scopeCheck("complete_onboarding_step")}
  if v_scope = 'organization' and not ${can("complete_onboarding_step.tenant", "complete")} then
    ${fail("ONBOARDING_FORBIDDEN", "You may not complete this organization's onboarding")}
  end if;
  return ${mark}(${ensureFor("complete_onboarding_step")}, complete_onboarding_step.step, true, auth.uid());
end;
$$;

-- Marks a step not done again; false when it wasn't done.
create or replace function ${fn("reset_onboarding_step")}(checklist text, step text, tenant ${id} default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
  v_id uuid;
begin${scopeCheck("reset_onboarding_step")}
  if v_scope = 'organization' and not ${can("reset_onboarding_step.tenant", "complete")} then
    ${fail("ONBOARDING_FORBIDDEN", "You may not change this organization's onboarding")}
  end if;
  select x.${e("id")} into v_id from ${enrollments} x where ${subject("reset_onboarding_step")};
  if v_id is null then
    return false;
  end if;
  return ${mark}(${ensureFor("reset_onboarding_step")}, reset_onboarding_step.step, false, auth.uid());
end;
$$;

revoke execute on function ${fn("onboarding_progress")}(text, ${id}) from public, anon;
revoke execute on function ${fn("complete_onboarding_step")}(text, text, ${id}) from public, anon;
revoke execute on function ${fn("reset_onboarding_step")}(text, text, ${id}) from public, anon;
grant execute on function ${fn("onboarding_progress")}(text, ${id}) to authenticated, service_role;
grant execute on function ${fn("complete_onboarding_step")}(text, text, ${id}) to authenticated, service_role;
grant execute on function ${fn("reset_onboarding_step")}(text, text, ${id}) to authenticated, service_role;
${eventSteps(ctx, steps, lists)}`;
}

/**
 * Completes the steps that list an outbox event type when such an event is
 * written: user steps for the event's actor, organization steps for its
 * tenant.
 */
function eventSteps(
  ctx: BlockSqlContext,
  steps: readonly StepOption[],
  lists: string,
): string {
  const rows = steps.flatMap((s) => s.events.map((event) => ({ ...s, event })));

  if (rows.length === 0) {
    return "";
  }

  if (!ctx.installed("outbox")) {
    throw new TypeError(`${where}: steps with events need the outbox module`);
  }

  const outbox = ctx.of("outbox");
  const events = outbox.table("events");
  const enrolled = ctx.of("enrollments");

  const actor = outbox.has("events", "actor")
    ? `new.${outbox.col("events", "actor")}`
    : "null::uuid";

  const tenant = outbox.has("events", "tenant")
    ? `new.${outbox.col("events", "tenant")}`
    : `null::${ctx.idType}`;

  const trigger = ctx.trigger("onboarding_events");
  const types = [...new Set(rows.map((r) => r.event))];

  const values = rows
    .map(
      (r) =>
        `(${sqlString(r.checklist)}, ${sqlString(r.step)}, ${sqlString(r.scope)}, ${sqlString(r.event)})`,
    )
    .join(", ");

  return `
create or replace function ${ctx.fn("onboarding_from_event")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select s.checklist, s.step, s.scope
    from (values ${values}) as s(checklist, step, scope, event)
    where s.event = new.${outbox.col("events", "type")}
      and (case when s.scope = 'user' then ${actor} is not null else ${tenant} is not null end)
  loop
    perform ${enrolled.fn("enrollment_mark")}(
      ${enrolled.fn("enrollment_ensure")}(
        case when r.scope = 'organization' then ${tenant} end,
        ${sqlString(PROGRAM)} || r.checklist,
        null,
        (select c.steps from (${lists}) as c(checklist, scope, steps) where c.checklist = r.checklist),
        r.scope,
        case when r.scope = 'organization' then ${tenant}::text else ${actor}::text end,
        ${actor}
      ),
      r.step,
      true,
      ${actor}
    );
  end loop;
  return null;
exception when others then
  raise warning 'better-supabase: onboarding step from % failed: %', new.${outbox.col("events", "type")}, sqlerrm;
  return null;
end;
$$;
revoke execute on function ${ctx.fn("onboarding_from_event")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${events};
create trigger ${trigger} after insert on ${events}
  for each row when (new.${outbox.col("events", "type")} in (${types.map(sqlString).join(", ")}))
  execute function ${ctx.fn("onboarding_from_event")}();`;
}

/**
 * Moves the completed steps of version 1 (onboarding_progress) onto
 * enrollments: one enrollment per checklist and subject with the checklist's
 * configured steps, then drops the table.
 */
function enrollmentsUpgrade(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const enrolled = enrollmentsOf(ctx);
  const enrollments = enrolled.table("enrollments");
  const steps = enrolled.table("steps");
  const e = (column: string): string => enrolled.col("enrollments", column);
  const s = (column: string): string => enrolled.col("steps", column);
  const old = `${ctx.schema}.onboarding_progress`;
  const lists = checklistRows(checklistSteps(ctx));

  const subjectType =
    "case when x.organization_id is null then 'user' else 'organization' end";

  const subjectId = "coalesce(x.organization_id::text, x.user_id::text)";
  const count = `(select count(*)::integer from ${steps} y where y.${s("enrollment")} = x.${e("id")} and y.${s("step")} = any(x.${e("steps")}))`;
  const done = `(${count} >= cardinality(x.${e("steps")}) and cardinality(x.${e("steps")}) > 0)`;

  return `${enrollmentTables(enrolled)}
do $upgrade$
begin
  if to_regclass(${sqlString(`${ctx.schemaName}.onboarding_progress`)}) is null then
    return;
  end if;
  insert into ${enrollments} (${e("tenant")}, ${e("program")}, ${e("subjectType")}, ${e("subjectId")}, ${e("user")}, ${e("steps")}, ${e("enrolledAt")})
  select x.organization_id, ${sqlString(PROGRAM)} || x.checklist, ${subjectType}, ${subjectId}, x.user_id,
    coalesce(c.steps, array_agg(distinct x.step order by x.step)), min(x.completed_at)
  from ${old} x
  left join (${lists}) as c(checklist, scope, steps) on c.checklist = x.checklist
  group by x.organization_id, x.user_id, x.checklist, c.steps
  on conflict do nothing;
  insert into ${steps} (${s("enrollment")}, ${s("tenant")}, ${s("step")}, ${s("completedBy")}, ${s("completedAt")})
  select y.${e("id")}, x.organization_id, x.step, x.completed_by, x.completed_at
  from ${old} x
  join ${enrollments} y on y.${e("tenant")} is not distinct from x.organization_id
    and y.${e("program")} = ${sqlString(PROGRAM)} || x.checklist
    and y.${e("subjectType")} = ${subjectType}
    and y.${e("subjectId")} = ${subjectId}
  on conflict do nothing;
  update ${enrollments} x
  set ${e("completedSteps")} = ${count},
    ${e("status")} = case when ${done} then 'completed' else 'active' end,
    ${e("completedAt")} = case when ${done} then (select max(y.${s("completedAt")}) from ${steps} y where y.${s("enrollment")} = x.${e("id")}) end
  where x.${e("program")} like ${sqlString(`${PROGRAM}%`)};
  drop table ${old};
end;
$upgrade$;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "onboarding_progress", args: ["text", "{id}"], returns: "jsonb" },
    {
      name: "complete_onboarding_step",
      args: ["text", "text", "{id}"],
      returns: "boolean",
    },
    {
      name: "reset_onboarding_step",
      args: ["text", "text", "{id}"],
      returns: "boolean",
    },
  ];
}

export const ONBOARDING: BlockSqlDefinition = {
  name: "onboarding",
  scopes: ["tenant"],
  title: "Onboarding",
  description:
    "Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.",
  requires: ["memberships", "permissions", "enrollments"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Onboarding checklists run on enrollments: each checklist and subject becomes an enrollment in the program onboarding:<checklist> with its completed steps, and onboarding_progress is dropped.",
      sql: enrollmentsUpgrade,
    },
  ],
  names: NAMES,
  contract,
  build,
};
