import type { RemindersEvents } from "../../blocks/reminders/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Subject } from "../subjects.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addCheck,
  addExtraColumns,
  columnsObject,
  extraFieldsArg,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  qualifiedTable,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<RemindersEvents> = {
  "reminder.sent": {
    subject: "reminders",
    payload: ["organizationId", "id", "subjectType", "subjectId", "userId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    reminder: { table: "reminders", singular: "reminder", primary: true },
  },
  events: EVENTS,
  options: ["ruleFormat", "extraColumns"],
  tables: {
    rules: {
      name: "recurrence_rules",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        dtstart: "dtstart",
        tzid: "tzid",
        rrule: "rrule",
        frequency: "frequency",
        intervalCount: "interval_count",
        weekDays: "week_days",
        monthDay: "month_day",
        monthWeekday: "month_weekday",
        monthOrdinal: "month_ordinal",
      },
      optional: [
        "rrule",
        "frequency",
        "intervalCount",
        "weekDays",
        "monthDay",
        "monthWeekday",
        "monthOrdinal",
      ],
    },
    reminders: {
      name: "reminders",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        user: "user_id",
        method: "method",
        offsetMinutes: "offset_minutes",
        remindAt: "remind_at",
      },
      optional: ["remindAt"],
    },
    deliveries: {
      name: "reminder_deliveries",
      app: {},
      columns: {
        id: "id",
        reminder: "reminder_id",
        occurrenceAt: "occurrence_at",
        sentAt: "sent_at",
      },
    },
  },
};

/** `options.extraColumns`, added to a managed reminders table. */
const extrasOf = (ctx: BlockSqlContext) => ctx.extraColumns("reminders");

const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;

/**
 * `blocks.reminders.on`, every registered subject when unset. `at` names the
 * subject's timestamp column that a reminder without a rule counts back from.
 */
function subjectsOf(
  ctx: BlockSqlContext,
): readonly (readonly [string, Subject])[] {
  const subjects = subjectsOption(ctx, ["at"]);

  for (const [type, subject] of subjects) {
    const at = subject.extra["at"];

    if (at !== undefined && (typeof at !== "string" || !COLUMN.test(at))) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${type}.at must be a column name, such as due_at`,
      );
    }
  }

  return subjects;
}

/** The schedule rows of subjects with an `at` column and no recurrence rule. */
function subjectTimes(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  absolute: string,
): string {
  const reminders = ctx.table("reminders");
  const rules = ctx.table("rules");
  const r = (column: string): string => `r.${ctx.col("reminders", column)}`;

  return subjects
    .flatMap(([type, subject]) => {
      const at = subject.extra["at"];

      if (typeof at !== "string") {
        return [];
      }

      const column = `s.${sqlIdent(at)}`;

      const tenant =
        subject.tenant === false
          ? ""
          : `\n    and s.${sqlIdent(subject.tenant ?? ctx.naming.rename("organization_id"))}::text = ${r("tenant")}::text`;

      return [
        `
  union all
  select ${r("id")}, ${column}::timestamptz, 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text,
    ${r("offsetMinutes")}, ${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("user")}
  from ${reminders} r
  join ${qualifiedTable(subject.table)} s on ${subjectIdMatches(subject, r("subjectId"))}${tenant}
  where ${r("subjectType")} = ${sqlString(type)}${absolute}
    and ${column} is not null
    and not exists (
      select 1 from ${rules} u
      where u.${ctx.col("rules", "tenant")} = ${r("tenant")}
        and u.${ctx.col("rules", "subjectType")} = ${r("subjectType")}
        and u.${ctx.col("rules", "subjectId")} = ${r("subjectId")}
    )`,
      ];
    })
    .join("");
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const extras = extrasOf(ctx);
  const format = ctx.text("ruleFormat", "rrule");

  if (format !== "rrule" && format !== "columns") {
    throw new TypeError(
      'blocks.reminders.options.ruleFormat must be "rrule" or "columns"',
    );
  }

  const rules = ctx.table("rules");
  const reminders = ctx.table("reminders");
  const deliveries = ctx.table("deliveries");
  const manage = ctx.permission("manage", OPERATIONS["reminders.manage"]);
  const subjects = subjectsOf(ctx);
  const at = ctx.has("reminders", "remindAt");
  const remindAt = at ? ctx.col("reminders", "remindAt") : "";
  const absolute = at ? `\n    and r.${remindAt} is null` : "";
  const saveArgs = `${ctx.idType}, text, text, integer${at ? ", timestamptz" : ""}`;
  const fields = extraFieldsArg(extras);

  const listed = subjects.map(([type]) => sqlString(type)).join(", ");

  const typeGuard =
    ctx.on === undefined
      ? ""
      : `
  if save_reminder.subject_type is null or save_reminder.subject_type not in (${listed}) then
    raise exception 'blocks.${ctx.instance}.on does not allow this record type'
      using errcode = '22023', hint = 'REMINDER_SUBJECT_UNSUPPORTED';
  end if;`;

  // A registered subject must exist in the tenant and be readable by the
  // caller; types `on` doesn't list pass, unless `on` is set.
  const readCheck =
    subjects.length === 0
      ? ""
      : `
  if not (auth.role() = 'service_role')
    and save_reminder.subject_type in (${listed})
    and not (${subjectReadable(ctx, subjects, { type: "save_reminder.subject_type", id: "save_reminder.subject_id", tenant: "save_reminder.tenant" })}) then
    ${fail("REMINDER_SUBJECT_NOT_FOUND", "the record was not found in this organization", "P0002")}
  end if;`;

  const ruleColumns =
    format === "columns"
      ? `${ctx.has("rules", "frequency") ? `${ctx.col("rules", "frequency")} text,` : ""}
  ${ctx.has("rules", "intervalCount") ? `${ctx.col("rules", "intervalCount")} integer,` : ""}
  ${ctx.has("rules", "weekDays") ? `${ctx.col("rules", "weekDays")} integer[],` : ""}
  ${ctx.has("rules", "monthDay") ? `${ctx.col("rules", "monthDay")} integer,` : ""}
  ${ctx.has("rules", "monthWeekday") ? `${ctx.col("rules", "monthWeekday")} integer,` : ""}
  ${ctx.has("rules", "monthOrdinal") ? `${ctx.col("rules", "monthOrdinal")} integer,` : ""}`
      : ctx.has("rules", "rrule")
        ? `${ctx.col("rules", "rrule")} text,`
        : "";

  const tables = ctx.manages
    ? `create table if not exists ${rules} (
  ${ctx.col("rules", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("rules", "tenant")} ${ctx.idType} not null,
  ${ctx.col("rules", "subjectType")} text not null,
  ${ctx.col("rules", "subjectId")} text not null,
  ${ctx.col("rules", "dtstart")} timestamptz not null,
  ${ctx.col("rules", "tzid")} text not null default 'UTC',
  ${ruleColumns}
  unique (${ctx.col("rules", "tenant")}, ${ctx.col("rules", "subjectType")}, ${ctx.col("rules", "subjectId")})
);
${lockTable(rules, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("rules").name}_subject_idx`)} on ${rules} (${ctx.col("rules", "subjectType")}, ${ctx.col("rules", "subjectId")});
create table if not exists ${reminders} (
  ${ctx.col("reminders", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("reminders", "tenant")} ${ctx.idType} not null,
  ${ctx.col("reminders", "subjectType")} text not null,
  ${ctx.col("reminders", "subjectId")} text not null,
  ${ctx.col("reminders", "user")} uuid,
  ${ctx.col("reminders", "method")} text not null default 'notification',
  ${ctx.col("reminders", "offsetMinutes")} integer not null default 0
);${at ? `\nalter table ${reminders} add column if not exists ${remindAt} timestamptz;` : ""}${addExtraColumns(reminders, extras)}
${lockTable(reminders, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("reminders").name}_subject_idx`)} on ${reminders} (${ctx.col("reminders", "subjectType")}, ${ctx.col("reminders", "subjectId")});
create index if not exists ${sqlIdent(`${ctx.tableName("reminders").name}_tenant_idx`)} on ${reminders} (${ctx.col("reminders", "tenant")});
-- A negative offset fires after the occurrence; a year either way bounds it.
${addCheck({
  table: reminders,
  name: `${ctx.tableName("reminders").name}_offset_check`,
  expression: `${ctx.col("reminders", "offsetMinutes")} between -525600 and 525600`,
})}
create table if not exists ${deliveries} (
  ${ctx.col("deliveries", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("deliveries", "reminder")} uuid not null references ${reminders} (${ctx.col("reminders", "id")}) on delete cascade,
  ${ctx.col("deliveries", "occurrenceAt")} timestamptz not null,
  ${ctx.col("deliveries", "sentAt")} timestamptz,
  unique (${ctx.col("deliveries", "reminder")}, ${ctx.col("deliveries", "occurrenceAt")})
);
${lockTable(deliveries, { read: true })}
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
${fields.drop(ctx.fn("save_reminder"), saveArgs)}${
    at
      ? `
drop function if exists ${ctx.fn("save_reminder")}(${ctx.idType}, text, text, integer);
drop function if exists ${ctx.fn("save_reminder")}(${ctx.idType}, text, text, integer, jsonb);`
      : ""
  }
create or replace function ${ctx.fn("save_reminder")}(tenant ${ctx.idType}, subject_type text, subject_id text, offset_minutes integer${at ? ", remind_at timestamptz default null" : ""}${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("save_reminder.tenant", manage)}) then
    ${fail("REMINDER_FORBIDDEN", "not allowed to manage reminders")}
  end if;${typeGuard}${readCheck}
  insert into ${reminders} (${ctx.col("reminders", "tenant")}, ${ctx.col("reminders", "subjectType")}, ${ctx.col("reminders", "subjectId")}, ${ctx.col("reminders", "user")}, ${ctx.col("reminders", "offsetMinutes")}${at ? `, ${remindAt}` : ""})
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0)${at ? ", save_reminder.remind_at" : ""})
  returning ${ctx.col("reminders", "id")} into v_id;${writeExtraColumns(reminders, extras, "save_reminder.fields", `x.${ctx.col("reminders", "id")} = v_id`)}
  return jsonb_build_object('id', v_id${
    extras.length === 0
      ? ""
      : `, 'fields', (select ${columnsObject(
          "r",
          extras.map((extra) => extra.name),
        )} from ${reminders} r where r.${ctx.col("reminders", "id")} = v_id)`
  });
end;
$$;
${userGrant(`${ctx.fn("save_reminder")}(${saveArgs}${fields.type})`)}

-- The caller's reminders on one subject, the earliest first.
create or replace function ${ctx.fn("list_my_reminders")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("list_my_reminders.tenant", manage)}) then
    ${fail("REMINDER_FORBIDDEN", "not allowed to manage reminders")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.${ctx.col("reminders", "id")},
      'method', r.${ctx.col("reminders", "method")},
      'offsetMinutes', r.${ctx.col("reminders", "offsetMinutes")}${at ? `,\n      'remindAt', r.${remindAt}` : ""}
    ) order by r.${ctx.col("reminders", "offsetMinutes")} desc, r.${ctx.col("reminders", "id")}), '[]'::jsonb)
    from ${reminders} r
    where r.${ctx.col("reminders", "tenant")} = list_my_reminders.tenant
      and r.${ctx.col("reminders", "subjectType")} = list_my_reminders.subject_type
      and r.${ctx.col("reminders", "subjectId")} = list_my_reminders.subject_id
      and r.${ctx.col("reminders", "user")} = auth.uid()
  );
end;
$$;
${userGrant(`${ctx.fn("list_my_reminders")}(${ctx.idType}, text, text)`)}

-- Removes one of the caller's reminders, with its delivery history.
create or replace function ${ctx.fn("delete_reminder")}(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select r.${ctx.col("reminders", "tenant")} into v_tenant
    from ${reminders} r
    where r.${ctx.col("reminders", "id")} = delete_reminder.reminder
      and (auth.role() = 'service_role' or r.${ctx.col("reminders", "user")} = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("REMINDER_FORBIDDEN", "not allowed to manage reminders")}
  end if;
  delete from ${reminders} r where r.${ctx.col("reminders", "id")} = delete_reminder.reminder;
  return true;
end;
$$;
${userGrant(`${ctx.fn("delete_reminder")}(uuid)`)}

create or replace function ${ctx.fn("mark_reminder_sent")}(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select ${ctx.col("reminders", "tenant")}, ${ctx.col("reminders", "subjectType")}, ${ctx.col("reminders", "subjectId")}, ${ctx.col("reminders", "user")}
    into v_tenant, v_subject_type, v_subject_id, v_user
    from ${reminders} where ${ctx.col("reminders", "id")} = mark_reminder_sent.reminder;
  if not found then
    ${fail("REMINDER_NOT_FOUND", "reminder not found", "P0002")}
  end if;
  insert into ${deliveries} (${ctx.col("deliveries", "reminder")}, ${ctx.col("deliveries", "occurrenceAt")}, ${ctx.col("deliveries", "sentAt")})
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict (${ctx.col("deliveries", "reminder")}, ${ctx.col("deliveries", "occurrenceAt")}) do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  ${ctx.record({
    type: "reminder.sent",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', mark_reminder_sent.reminder, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'userId', v_user)`,
    subject: `'reminders/' || mark_reminder_sent.reminder::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
revoke execute on function ${ctx.fn("mark_reminder_sent")}(uuid, timestamptz) from public, anon, authenticated;
grant execute on function ${ctx.fn("mark_reminder_sent")}(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's \`at\` column. Delivery dedupes on (reminder, occurrence).
drop function if exists ${ctx.fn("list_reminder_schedule")}();
create function ${ctx.fn("list_reminder_schedule")}()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant ${ctx.idType},
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.${ctx.col("reminders", "id")},
    u.${ctx.col("rules", "dtstart")},
    u.${ctx.col("rules", "tzid")},
    ${ctx.has("rules", "rrule") ? `u.${ctx.col("rules", "rrule")}` : "null::text"},
    r.${ctx.col("reminders", "offsetMinutes")},
    r.${ctx.col("reminders", "tenant")},
    r.${ctx.col("reminders", "subjectType")},
    r.${ctx.col("reminders", "subjectId")},
    r.${ctx.col("reminders", "user")}
  from ${reminders} r
  join ${rules} u
    on u.${ctx.col("rules", "tenant")} = r.${ctx.col("reminders", "tenant")}
   and u.${ctx.col("rules", "subjectType")} = r.${ctx.col("reminders", "subjectType")}
   and u.${ctx.col("rules", "subjectId")} = r.${ctx.col("reminders", "subjectId")}${at ? `\n  where r.${remindAt} is null` : ""}${
     at
       ? `
  union all
  select r.${ctx.col("reminders", "id")}, r.${remindAt}, 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r.${ctx.col("reminders", "tenant")}, r.${ctx.col("reminders", "subjectType")},
    r.${ctx.col("reminders", "subjectId")}, r.${ctx.col("reminders", "user")}
  from ${reminders} r
  where r.${remindAt} is not null`
       : ""
   }${subjectTimes(ctx, subjects, absolute)};
$$;
revoke execute on function ${ctx.fn("list_reminder_schedule")}() from public, anon, authenticated;
grant execute on function ${ctx.fn("list_reminder_schedule")}() to service_role;
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_reminder",
      args: [
        "{id}",
        "text",
        "text",
        "integer",
        ...(ctx.has("reminders", "remindAt") ? ["timestamptz"] : []),
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "list_my_reminders",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "delete_reminder", args: ["uuid"], returns: "boolean" },
    {
      name: "mark_reminder_sent",
      args: ["uuid", "timestamptz"],
      returns: "boolean",
    },
    { name: "list_reminder_schedule", args: [], returns: "table" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  subjects: (own, target) => [
    {
      work: `select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from ${target.fn("my_reminders_due")}(my_work.tenant) d
    where ${target.fn("can_subject")}(d.subject_type, d.subject_id, 'read')`,
      sql: `
-- The caller's own reminders sent in the last week, for my_work. Reminders
-- have no read policy, so this reads them past it, keeping only the caller's.
create or replace function ${target.fn("my_reminders_due")}(tenant ${target.idType} default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.${own.col("reminders", "id")}, r.${own.col("reminders", "subjectType")}::text,
    r.${own.col("reminders", "subjectId")}::text, max(d.${own.col("deliveries", "occurrenceAt")})
  from ${own.table("reminders")} r
  join ${own.table("deliveries")} d on d.${own.col("deliveries", "reminder")} = r.${own.col("reminders", "id")}
  where r.${own.col("reminders", "user")} = (select auth.uid())
    and (my_reminders_due.tenant is null or r.${own.col("reminders", "tenant")} = my_reminders_due.tenant)
    and d.${own.col("deliveries", "sentAt")} > now() - interval '7 days'
  group by 1, 2, 3
$$;
${userGrant(`${target.fn("my_reminders_due")}(${target.idType})`)}
`,
    },
  ],
};

export const REMINDERS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "reminders",
  scopes: ["tenant"],
  title: "Reminders",
  description:
    "Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.",
  requires: ["memberships", "permissions", "queue"],
  integrates: ["notifications", "outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
