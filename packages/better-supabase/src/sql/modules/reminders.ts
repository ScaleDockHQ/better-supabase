import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { fail, lockTable, schemaPreamble, userGrant } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

const EVENTS: ModuleEvents = {
  "reminder.sent": {
    subject: "reminders",
    payload: ["organizationId", "id", "subjectType", "subjectId", "userId"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["ruleFormat"],
  tables: {
    rules: {
      name: "recurrence_rules",
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
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        user: "user_id",
        method: "method",
        offsetMinutes: "offset_minutes",
      },
    },
    deliveries: {
      name: "reminder_deliveries",
      columns: {
        id: "id",
        reminder: "reminder_id",
        occurrenceAt: "occurrence_at",
        sentAt: "sent_at",
      },
    },
  },
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const format = ctx.text("ruleFormat", "rrule");
  if (format !== "rrule" && format !== "columns") {
    throw new TypeError(
      'sql.modules.reminders.options.ruleFormat must be "rrule" or "columns"',
    );
  }
  const rules = ctx.table("rules");
  const reminders = ctx.table("reminders");
  const deliveries = ctx.table("deliveries");
  const manage = ctx.permission("manage", OPERATIONS["reminders.manage"]);
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
create table if not exists ${reminders} (
  ${ctx.col("reminders", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("reminders", "tenant")} ${ctx.idType} not null,
  ${ctx.col("reminders", "subjectType")} text not null,
  ${ctx.col("reminders", "subjectId")} text not null,
  ${ctx.col("reminders", "user")} uuid,
  ${ctx.col("reminders", "method")} text not null default 'notification',
  ${ctx.col("reminders", "offsetMinutes")} integer not null default 0
);
${lockTable(reminders, { read: true })}
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
create or replace function ${ctx.fn("save_reminder")}(tenant ${ctx.idType}, subject_type text, subject_id text, offset_minutes integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, ${manage}), false)) then
    ${fail("REMINDER_FORBIDDEN", "not allowed to manage reminders")}
  end if;
  insert into ${reminders} (${ctx.col("reminders", "tenant")}, ${ctx.col("reminders", "subjectType")}, ${ctx.col("reminders", "subjectId")}, ${ctx.col("reminders", "user")}, ${ctx.col("reminders", "offsetMinutes")})
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0))
  returning ${ctx.col("reminders", "id")} into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("save_reminder")}(${ctx.idType}, text, text, integer)`)}

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

create or replace function ${ctx.fn("list_reminder_schedule")}()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant ${ctx.idType},
  subject_type text,
  subject_id text
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
    r.${ctx.col("reminders", "subjectId")}
  from ${reminders} r
  join ${rules} u
    on u.${ctx.col("rules", "tenant")} = r.${ctx.col("reminders", "tenant")}
   and u.${ctx.col("rules", "subjectType")} = r.${ctx.col("reminders", "subjectType")}
   and u.${ctx.col("rules", "subjectId")} = r.${ctx.col("reminders", "subjectId")};
$$;
revoke execute on function ${ctx.fn("list_reminder_schedule")}() from public, anon, authenticated;
grant execute on function ${ctx.fn("list_reminder_schedule")}() to service_role;
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "save_reminder",
      args: ["{id}", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "mark_reminder_sent",
      args: ["uuid", "timestamptz"],
      returns: "boolean",
    },
    {
      name: "list_reminder_schedule",
      args: [],
      returns: "table",
    },
  ];
}

export const REMINDERS: ModuleDefinition = {
  name: "reminders",
  title: "Reminders",
  description:
    "Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.",
  requires: ["tenant", "access", "jobs"],
  integrates: ["notifications", "outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
