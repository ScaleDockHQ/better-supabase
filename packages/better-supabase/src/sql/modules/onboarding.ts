import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["checklists"],
  tables: {
    progress: {
      name: "onboarding_progress",
      lifecycle: { user: "user", tenant: "tenant" },
      columns: {
        id: "id",
        checklist: "checklist",
        step: "step",
        user: "user_id",
        tenant: "organization_id",
        completedBy: "completed_by",
        completedAt: "completed_at",
      },
    },
  },
};

const ID = /^[a-z][a-z0-9_.-]{0,63}$/;
const EVENT = /^[a-z][a-z0-9_.:-]{0,127}$/;

interface StepOption {
  readonly checklist: string;
  readonly step: string;
  readonly scope: "user" | "organization";
  readonly events: readonly string[];
}

const isObject = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const where = "sql.modules.onboarding.options.checklists";

function idOf(value: unknown, path: string): string {
  if (typeof value !== "string" || !ID.test(value)) {
    throw new TypeError(
      `${path}: use lowercase letters, digits, "_", "." or "-", starting with a letter`,
    );
  }
  return value;
}

function eventsOf(value: unknown, path: string): readonly string[] {
  if (value === undefined) return [];
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
function checklistSteps(ctx: ModuleContext): readonly StepOption[] {
  const option = ctx.option("checklists");
  if (option === undefined) return [];
  if (!Array.isArray(option) && !isObject(option)) {
    throw new TypeError(`${where}: pass an array of defineChecklist() results`);
  }
  const list: readonly unknown[] = Array.isArray(option)
    ? option
    : Object.values(option);
  const steps: StepOption[] = [];
  const seen = new Set<string>();
  for (const [index, entry] of list.entries()) {
    const path = `${where}[${index}]`;
    if (!isObject(entry)) throw new TypeError(`${path}: not a checklist`);
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
    if (!Array.isArray(raw))
      throw new TypeError(`${path}.steps: pass an array`);
    const entries: readonly unknown[] = raw;
    const ids = new Set<string>();
    for (const [n, item] of entries.entries()) {
      if (!isObject(item))
        throw new TypeError(`${path}.steps[${n}]: not a step`);
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

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const p = ctx.table("progress");
  const c = (logical: string): string => ctx.col("progress", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.onboarding;
  const can = (tenant: string, action: "read" | "complete"): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false))`;
  const steps = checklistSteps(ctx);
  const stepRows =
    steps.length === 0
      ? "select null::text as checklist, null::text as step, null::text as scope where false"
      : `values ${steps.map((s) => `(${sqlString(s.checklist)}, ${sqlString(s.step)}, ${sqlString(s.scope)})`).join(", ")}`;
  const lookup = (checklist: string, step: string): string =>
    `(select s.scope from (${stepRows}) as s(checklist, step, scope) where s.checklist = ${checklist} and (${step} is null or s.step = ${step}) limit 1)`;
  const scopeCheck = (fnName: string): string => `
  v_scope := ${lookup(`${fnName}.checklist`, `${fnName}.step`)};
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', ${fnName}.checklist, coalesce(${fnName}.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if ${fnName}.tenant is null then
      raise exception 'Checklist % belongs to an organization', ${fnName}.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif ${fnName}.tenant is not null then
    raise exception 'Checklist % belongs to a user', ${fnName}.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;`;
  const subject = (fnName: string): string =>
    `x.${c("checklist")} = ${fnName}.checklist
      and (case when v_scope = 'organization' then x.${c("tenant")} = ${fnName}.tenant else x.${c("user")} = auth.uid() end)`;

  return `${schemaPreamble(ctx)}
-- Completed onboarding steps, one row per step and subject: a user for a
-- user checklist, an organization for an organization checklist. The
-- checklists live in the app (defineChecklist); the functions check steps
-- against options.checklists.
create table if not exists ${p} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("checklist")} text not null,
  ${c("step")} text not null,
  ${c("user")} uuid references auth.users (id) on delete cascade,
  ${c("tenant")} ${id},
  ${c("completedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("completedAt")} timestamptz not null default now(),
  check ((${c("user")} is null) <> (${c("tenant")} is null)),
  unique nulls not distinct (${c("checklist")}, ${c("step")}, ${c("user")}, ${c("tenant")})
);
create index if not exists onboarding_progress_user_idx on ${p} (${c("user")});
create index if not exists onboarding_progress_tenant_idx on ${p} (${c("tenant")});
create index if not exists onboarding_progress_completed_by_idx on ${p} (${c("completedBy")});
alter table ${p} enable row level security;
revoke all on ${p} from anon, authenticated;
grant select on ${p} to authenticated;
grant all on ${p} to service_role;
drop policy if exists "onboarding_progress_read" on ${p};
create policy "onboarding_progress_read" on ${p} for select to authenticated
  using (
    ${c("user")} = (select auth.uid())
    or ${tenantIn(c("tenant"), ctx.permission("read", permissions.read))}
  );

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
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not ${can("onboarding_progress.tenant", "read")} then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', x.${c("step")},
      'completedAt', x.${c("completedAt")},
      'completedBy', x.${c("completedBy")}
    ) order by x.${c("completedAt")}), '[]'::jsonb)
    from ${p} x
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
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin${scopeCheck("complete_onboarding_step")}
  if v_scope = 'organization' and not ${can("complete_onboarding_step.tenant", "complete")} then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  insert into ${p} (${c("checklist")}, ${c("step")}, ${c("user")}, ${c("tenant")}, ${c("completedBy")})
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
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
  v_count integer;
begin${scopeCheck("reset_onboarding_step")}
  if v_scope = 'organization' and not ${can("reset_onboarding_step.tenant", "complete")} then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  delete from ${p} x
  where x.${c("step")} = reset_onboarding_step.step and ${subject("reset_onboarding_step")};
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function ${fn("onboarding_progress")}(text, ${id}) from public, anon;
revoke execute on function ${fn("complete_onboarding_step")}(text, text, ${id}) from public, anon;
revoke execute on function ${fn("reset_onboarding_step")}(text, text, ${id}) from public, anon;
grant execute on function ${fn("onboarding_progress")}(text, ${id}) to authenticated, service_role;
grant execute on function ${fn("complete_onboarding_step")}(text, text, ${id}) to authenticated, service_role;
grant execute on function ${fn("reset_onboarding_step")}(text, text, ${id}) to authenticated, service_role;
${eventSteps(ctx, steps)}`;
}

/**
 * Completes the steps that list an outbox event type when such an event is
 * written: user steps for the event's actor, organization steps for its
 * tenant.
 */
function eventSteps(ctx: ModuleContext, steps: readonly StepOption[]): string {
  const rows = steps.flatMap((s) => s.events.map((event) => ({ ...s, event })));
  if (rows.length === 0) return "";
  if (!ctx.installed("outbox")) {
    throw new TypeError(`${where}: steps with events need the outbox module`);
  }
  const outbox = ctx.of("outbox");
  const events = outbox.table("events");
  const actor = outbox.has("events", "actor")
    ? `new.${outbox.col("events", "actor")}`
    : "null::uuid";
  const tenant = outbox.has("events", "tenant")
    ? `new.${outbox.col("events", "tenant")}`
    : `null::${ctx.idType}`;
  const p = ctx.table("progress");
  const c = (logical: string): string => ctx.col("progress", logical);
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
begin
  insert into ${p} (${c("checklist")}, ${c("step")}, ${c("user")}, ${c("tenant")}, ${c("completedBy")})
  select s.checklist, s.step,
    case when s.scope = 'user' then ${actor} end,
    case when s.scope = 'organization' then ${tenant} end,
    ${actor}
  from (values ${values}) as s(checklist, step, scope, event)
  where s.event = new.${outbox.col("events", "type")}
    and (case when s.scope = 'user' then ${actor} is not null else ${tenant} is not null end)
  on conflict do nothing;
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

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "onboarding_progress",
      args: ["text", "{id}"],
      returns: "jsonb",
    },
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

export const ONBOARDING: ModuleDefinition = {
  name: "onboarding",
  title: "Onboarding",
  description:
    "Onboarding checklists per user or organization: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
