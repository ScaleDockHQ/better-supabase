import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

/** The subject type a schedule's rule has in reminders' `recurrence_rules`. */
export const SCHEDULE_SUBJECT = "template_schedule";

const MAX_INPUT_BYTES = 65_536;

/**
 * Whether recurring records render: reminders keeps their rules, so it must be
 * installed with its `rrule` column (`ruleFormat: "rrule"`).
 */
export function recurringEnabled(ctx: BlockSqlContext): boolean {
  if (
    !ctx.installed("reminders") ||
    !ctx.hasTable("schedules") ||
    !ctx.hasTable("runs")
  ) {
    return false;
  }

  const reminders = ctx.of("reminders");

  return (
    reminders.text("ruleFormat", "rrule") === "rrule" &&
    reminders.has("rules", "rrule")
  );
}

export function recurringContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!recurringEnabled(ctx)) {
    return [];
  }

  return [
    {
      name: "save_template_schedule",
      args: [
        "uuid",
        "uuid",
        "{id}",
        "timestamp with time zone",
        "text",
        "text",
        "jsonb",
        "boolean",
      ],
      returns: "jsonb",
    },
    { name: "remove_template_schedule", args: ["uuid"], returns: "boolean" },
    {
      name: "template_schedules_list",
      args: ["{id}", "uuid"],
      returns: "jsonb",
    },
    { name: "list_template_schedule", args: [], returns: "jsonb" },
    {
      name: "claim_template_occurrence",
      args: ["uuid", "timestamp with time zone"],
      returns: "jsonb",
    },
    {
      name: "finish_template_occurrence",
      args: ["uuid", "timestamp with time zone", "uuid"],
      returns: "boolean",
    },
  ];
}

/**
 * Recurring records: a schedule applies its template in its tenant at each
 * occurrence of a recurrence rule, which lives in reminders' `recurrence_rules`
 * (subject type `template_schedule`, subject id the schedule). The client
 * expands the rules and enqueues one job per occurrence; each occurrence is
 * claimed once in `template_schedule_runs`.
 */
export function recurringParts(
  ctx: BlockSqlContext,
  shared: {
    readonly read: string;
    readonly mayManage: (tenant: string) => string;
    /** `or` the template at `prefix` is visible in `tenant` (brand starters). */
    readonly visible: (prefix: string, tenant: string) => string;
    readonly system: (prefix: string) => string;
  },
): string {
  if (!recurringEnabled(ctx)) {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("templates");
  const s = ctx.table("schedules");
  const r = ctx.table("runs");
  const ct = (column: string): string => ctx.col("templates", column);
  const cs = (column: string): string => ctx.col("schedules", column);
  const cr = (column: string): string => ctx.col("runs", column);
  const reminders = ctx.of("reminders");
  const rules = reminders.table("rules");
  const cu = (column: string): string => reminders.col("rules", column);
  const creator = ctx.has("schedules", "createdBy");
  const subject = `'${SCHEDULE_SUBJECT}'`;

  const ruleOf = (alias: string, schedule: string): string =>
    `${alias}.${cu("tenant")} = ${schedule}.${cs("tenant")}
      and ${alias}.${cu("subjectType")} = ${subject}
      and ${alias}.${cu("subjectId")} = ${schedule}.${cs("id")}::text`;

  const scheduleJson = (alias: string, rule: string): string =>
    `jsonb_build_object(
    'id', ${alias}.${cs("id")},
    'template', ${alias}.${cs("template")},
    'tenant', ${alias}.${cs("tenant")},
    'input', ${alias}.${cs("input")},
    'enabled', ${alias}.${cs("enabled")},
    'dtstart', ${rule}.${cu("dtstart")},
    'tzid', ${rule}.${cu("tzid")},
    'rrule', ${rule}.${cu("rrule")},
    'createdBy', ${creator ? `${alias}.${cs("createdBy")}` : "null"},
    'createdAt', ${alias}.${cs("createdAt")},
    'updatedAt', ${alias}.${cs("updatedAt")}
  )`;

  const removeRule = fn("template_schedule_removed");

  return `
-- Recurring records: each schedule applies template_id in tenant_id with
-- input at every occurrence of its rule in ${rules}
-- (subject_type ${subject}). The client expands the rules and enqueues
-- one job per occurrence.
create table if not exists ${s} (
  ${cs("id")} uuid primary key default gen_random_uuid(),
  ${cs("template")} uuid not null references ${t} (${ct("id")}) on delete cascade,
  ${cs("tenant")} ${id} not null,
  ${cs("input")} jsonb not null default '{}'::jsonb
    check (jsonb_typeof(${cs("input")}) = 'object' and pg_column_size(${cs("input")}) <= ${String(MAX_INPUT_BYTES)}),
  ${cs("enabled")} boolean not null default true,
${creator ? `  ${cs("createdBy")} uuid references auth.users (id) on delete set null,\n` : ""}  ${cs("createdAt")} timestamptz not null default now(),
  ${cs("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("template_schedules_tenant_idx")} on ${s} (${cs("tenant")}, ${cs("template")});
create index if not exists ${ctx.naming.rename("template_schedules_template_idx")} on ${s} (${cs("template")});
${creator ? `create index if not exists ${ctx.naming.rename("template_schedules_created_by_idx")} on ${s} (${cs("createdBy")});\n` : ""}${lockModuleTable(ctx, "schedules", { read: true })}
${renderPolicy(makePolicy({ table: s, name: ctx.naming.rename("template_schedules_read"), command: "select", roles: ["authenticated"], using: `${cs("tenant")} in (select ${ctx.scope.ids(shared.read)})` }), { drop: true, target: s })}

-- One row per occurrence a schedule claimed, and the application it made.
create table if not exists ${r} (
  ${cr("schedule")} uuid not null references ${s} (${cs("id")}) on delete cascade,
  ${cr("tenant")} ${id} not null,
  ${cr("occurrence")} timestamptz not null,
  ${cr("application")} uuid references ${ctx.table("applications")} (${ctx.col("applications", "id")}) on delete set null,
  ${cr("createdAt")} timestamptz not null default now(),
  primary key (${cr("schedule")}, ${cr("occurrence")})
);${appUniqueIndex(ctx, "runs", ["schedule", "occurrence"])}
create index if not exists ${ctx.naming.rename("template_schedule_runs_tenant_idx")} on ${r} (${cr("tenant")}, ${cr("occurrence")} desc);
create index if not exists ${ctx.naming.rename("template_schedule_runs_application_idx")} on ${r} (${cr("application")});
${lockModuleTable(ctx, "runs", { read: true })}
${renderPolicy(makePolicy({ table: r, name: ctx.naming.rename("template_schedule_runs_read"), command: "select", roles: ["authenticated"], using: `${cr("tenant")} in (select ${ctx.scope.ids(shared.read)})` }), { drop: true, target: r })}

-- A removed schedule (or one its template took with it) drops its rule.
create or replace function ${removeRule}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${rules} u where ${ruleOf("u", "old")};
  return old;
end;
$$;
${triggerGrant(`${removeRule}()`)}
drop trigger if exists ${sqlIdent("bsb_template_schedule_removed")} on ${s};
create trigger ${sqlIdent("bsb_template_schedule_removed")} after delete on ${s}
for each row execute function ${removeRule}();

-- Creates a schedule (schedule_id null) or changes one: template_id applies
-- in tenant with input at each occurrence of rrule from dtstart in tzid.
-- templates.manage in tenant; the template must be visible there.
create or replace function ${fn("save_template_schedule")}(schedule_id uuid, template_id uuid, tenant ${id}, dtstart timestamptz, tzid text, rrule text, input jsonb, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_row ${s}%rowtype;
  v_rule ${rules}%rowtype;
begin
  if save_template_schedule.tenant is null then
    ${fail("TEMPLATE_INVALID", "A schedule needs a tenant", "22023")}
  end if;
  if not ${shared.mayManage("save_template_schedule.tenant")} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not schedule templates here")}
  end if;
  if save_template_schedule.dtstart is null or coalesce(length(save_template_schedule.rrule), 0) not between 1 and 1000 then
    ${fail("TEMPLATE_SCHEDULE_INVALID", "A schedule needs a start and a rule", "22023")}
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(save_template_schedule.tzid, 'UTC')) then
    ${fail("TEMPLATE_SCHEDULE_INVALID", "tzid must be an IANA time zone", "22023")}
  end if;
  if save_template_schedule.input is not null and jsonb_typeof(save_template_schedule.input) <> 'object' then
    ${fail("TEMPLATE_INVALID", "input must be an object", "22023")}
  end if;
  select * into v_tpl from ${t} x where x.${ct("id")} = save_template_schedule.template_id;
  if not found or not (${shared.system("v_tpl.")} or v_tpl.${ct("tenant")} = save_template_schedule.tenant${shared.visible("v_tpl.", "save_template_schedule.tenant")}) then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if save_template_schedule.schedule_id is null then
    insert into ${s} (${cs("template")}, ${cs("tenant")}, ${cs("input")}, ${cs("enabled")}${creator ? `, ${cs("createdBy")}` : ""})
    values (v_tpl.${ct("id")}, save_template_schedule.tenant, coalesce(save_template_schedule.input, '{}'::jsonb),
      coalesce(save_template_schedule.enabled, true)${creator ? ", (select auth.uid())" : ""})
    returning * into v_row;
  else
    update ${s} x set
      ${cs("template")} = v_tpl.${ct("id")},
      ${cs("input")} = coalesce(save_template_schedule.input, x.${cs("input")}),
      ${cs("enabled")} = coalesce(save_template_schedule.enabled, x.${cs("enabled")}),
      ${cs("updatedAt")} = now()
    where x.${cs("id")} = save_template_schedule.schedule_id and x.${cs("tenant")} = save_template_schedule.tenant
    returning * into v_row;
    if not found then
      ${fail("TEMPLATE_SCHEDULE_NOT_FOUND", "No such schedule", "P0002")}
    end if;
  end if;
  update ${rules} u set
    ${cu("dtstart")} = save_template_schedule.dtstart,
    ${cu("tzid")} = coalesce(save_template_schedule.tzid, 'UTC'),
    ${cu("rrule")} = save_template_schedule.rrule
  where ${ruleOf("u", "v_row")}
  returning * into v_rule;
  if not found then
    insert into ${rules} (${cu("tenant")}, ${cu("subjectType")}, ${cu("subjectId")}, ${cu("dtstart")}, ${cu("tzid")}, ${cu("rrule")})
    values (v_row.${cs("tenant")}, ${subject}, v_row.${cs("id")}::text, save_template_schedule.dtstart,
      coalesce(save_template_schedule.tzid, 'UTC'), save_template_schedule.rrule)
    returning * into v_rule;
  end if;
  return ${scheduleJson("v_row", "v_rule")};
end;
$$;
${userGrant(`${fn("save_template_schedule")}(uuid, uuid, ${id}, timestamptz, text, text, jsonb, boolean)`)}

-- Removes a schedule and its rule. templates.manage in its tenant.
create or replace function ${fn("remove_template_schedule")}(schedule_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${s}%rowtype;
begin
  select * into v_row from ${s} x where x.${cs("id")} = remove_template_schedule.schedule_id;
  if not found then
    return false;
  end if;
  if not ${shared.mayManage(`v_row.${cs("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not remove this schedule")}
  end if;
  delete from ${s} x where x.${cs("id")} = v_row.${cs("id")};
  return true;
end;
$$;
${userGrant(`${fn("remove_template_schedule")}(uuid)`)}

-- The tenant's schedules with their rules, of one template when given.
-- templates.read in tenant.
create or replace function ${fn("template_schedules_list")}(tenant ${id}, template_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("template_schedules_list.tenant", shared.read)}) then
    ${fail("TEMPLATE_FORBIDDEN", "You may not read schedules here")}
  end if;
  return (
    select coalesce(jsonb_agg(${scheduleJson("x", "u")} order by x.${cs("createdAt")}, x.${cs("id")}), '[]'::jsonb)
    from ${s} x
    left join ${rules} u on ${ruleOf("u", "x")}
    where x.${cs("tenant")} = template_schedules_list.tenant
      and (template_schedules_list.template_id is null or x.${cs("template")} = template_schedules_list.template_id)
  );
end;
$$;
${userGrant(`${fn("template_schedules_list")}(${id}, uuid)`)}

-- Every enabled schedule with its rule, for the client to expand.
create or replace function ${fn("list_template_schedule")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${scheduleJson("x", "u")} order by x.${cs("id")}), '[]'::jsonb)
  from ${s} x
  join ${rules} u on ${ruleOf("u", "x")}
  where x.${cs("enabled")} and u.${cu("rrule")} is not null
$$;
${serviceGrant(`${fn("list_template_schedule")}()`)}

-- Claims one occurrence of an enabled schedule: the schedule when the
-- occurrence is new or hasn't recorded an application yet, else null.
create or replace function ${fn("claim_template_occurrence")}(schedule_id uuid, occurrence_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${s}%rowtype;
  v_rule ${rules}%rowtype;
begin
  select * into v_row from ${s} x where x.${cs("id")} = claim_template_occurrence.schedule_id and x.${cs("enabled")};
  if not found then
    return null;
  end if;
  insert into ${r} (${cr("schedule")}, ${cr("tenant")}, ${cr("occurrence")})
  values (v_row.${cs("id")}, v_row.${cs("tenant")}, claim_template_occurrence.occurrence_at)
  on conflict (${cr("schedule")}, ${cr("occurrence")}) do nothing;
  if not found and exists (select 1 from ${r} y
      where y.${cr("schedule")} = v_row.${cs("id")} and y.${cr("occurrence")} = claim_template_occurrence.occurrence_at
        and y.${cr("application")} is not null) then
    return null;
  end if;
  select * into v_rule from ${rules} u where ${ruleOf("u", "v_row")};
  return ${scheduleJson("v_row", "v_rule")};
end;
$$;
${serviceGrant(`${fn("claim_template_occurrence")}(uuid, timestamptz)`)}

-- Records the application an occurrence made. False when it already had one.
create or replace function ${fn("finish_template_occurrence")}(schedule_id uuid, occurrence_at timestamptz, application_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${r} y set ${cr("application")} = finish_template_occurrence.application_id
  where y.${cr("schedule")} = finish_template_occurrence.schedule_id
    and y.${cr("occurrence")} = finish_template_occurrence.occurrence_at
    and y.${cr("application")} is null;
  return found;
end;
$$;
${serviceGrant(`${fn("finish_template_occurrence")}(uuid, timestamptz, uuid)`)}
`;
}
