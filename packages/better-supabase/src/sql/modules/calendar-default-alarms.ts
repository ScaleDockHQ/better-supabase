import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy, renderPolicy } from "../policy.ts";
import { addCheck, fail, lockTable, userGrant } from "../shared.ts";
import {
  ALARM_ACTIONS,
  ALARM_LIMIT,
  TRIGGER_BOUND,
} from "./calendar-alarms.ts";
import { accessCall, calendarFeatures } from "./calendar-features.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The time of day an all-day event's default alarm counts from. */
const ANCHOR = "time '09:00'";

const ACTIONS = `(${ALARM_ACTIONS.map((action) => `'${action}'`).join(", ")})`;

/**
 * The `calendar_default_alarms` table: the alarms a calendar gives a new event
 * that sets none. A row counts for timed events, or with `all_day` for all-day
 * ones, where the offset is in minutes before `anchor_time` on the event's
 * day.
 */
export function defaultAlarmsTable(ctx: BlockSqlContext): string {
  if (!calendarFeatures(ctx).defaultAlarms || !ctx.owns("defaultAlarms")) {
    return "";
  }

  const table = ctx.table("defaultAlarms");
  const d = (column: string) => ctx.col("defaultAlarms", column);
  const name = ctx.tableName("defaultAlarms").name;
  const read = ctx.permission("read", moduleOperations("calendar").read);

  const optional = (
    [
      ["method", "text not null default 'display'"],
      ["anchor", "time"],
      ["createdAt", "timestamptz not null default now()"],
    ] as const
  )
    .filter(([column]) => ctx.has("defaultAlarms", column))
    .map(([column, type]) => `,\n  ${d(column)} ${type}`)
    .join("");

  const using = calendarFeatures(ctx).access
    ? accessCall(ctx, d("calendar"), "read", "(select auth.uid())")
    : ctx.scope.check(d("tenant"), read);

  return `
create table if not exists ${table} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("calendar")} uuid not null references ${ctx.table("calendars")} (${ctx.col("calendars", "id")}) on delete cascade,
  ${d("allDay")} boolean not null default false,
  ${d("offsetMinutes")} integer not null${optional}
);
create index if not exists ${sqlIdent(`${name}_calendar_idx`)} on ${table} (${d("calendar")});
${lockTable(table, { read: true })}
${addCheck({
  table,
  name: `${name}_offset_check`,
  expression: `${d("offsetMinutes")} between -${TRIGGER_BOUND} and ${TRIGGER_BOUND}`,
})}${
    ctx.has("defaultAlarms", "method")
      ? `\n${addCheck({
          table,
          name: `${name}_method_check`,
          expression: `${d("method")} in ${ACTIONS}`,
        })}`
      : ""
  }
${renderPolicy(
  policy({
    table,
    name: `${name}_read`,
    command: "select",
    roles: ["authenticated"],
    using,
  }),
  { drop: true, target: table },
)}
`;
}

/**
 * The statements of `save_calendar_event` that copy the calendar's default
 * alarms onto a new event (not an override) whose item has no `alarms`.
 */
export function defaultAlarmWrites(ctx: BlockSqlContext): string {
  if (!calendarFeatures(ctx).defaultAlarms) {
    return "";
  }

  const d = (column: string) => `d.${ctx.col("defaultAlarms", column)}`;
  const l = (column: string) => ctx.col("alarms", column);
  const e = (column: string) => `e.${ctx.col("events", column)}`;

  const anchor = ctx.has("defaultAlarms", "anchor")
    ? ` - (extract(epoch from coalesce(${d("anchor")}, ${ANCHOR})) / 60)::integer`
    : "";

  const method: readonly (readonly [string, string])[] = ctx.has(
    "alarms",
    "method",
  )
    ? [
        [
          l("method"),
          ctx.cast(
            "alarms",
            "method",
            ctx.has("defaultAlarms", "method")
              ? ctx.label("defaultAlarms", "method", d("method"))
              : "'display'",
          ),
        ],
      ]
    : [];

  const columns: readonly (readonly [string, string])[] = [
    [l("tenant"), "v_tenant"],
    [l("event"), "v_id"],
    [
      l("offsetMinutes"),
      `case when ${d("allDay")} then ${d("offsetMinutes")}${anchor} else ${d("offsetMinutes")} end`,
    ],
    ...method,
  ];

  const displayOnly =
    !ctx.has("alarms", "method") && ctx.has("defaultAlarms", "method")
      ? ` and ${ctx.label("defaultAlarms", "method", d("method"))} = 'display'`
      : "";

  return `
  if v_created and v_master is null and not (v_item ? 'alarms') then
    insert into ${ctx.table("alarms")} (${columns.map(([column]) => column).join(", ")})
    select ${columns.map(([, value]) => value).join(", ")}
    from ${ctx.table("defaultAlarms")} d
    join ${ctx.table("events")} e on ${e("id")} = v_id
    where ${d("calendar")} = save_calendar_event.calendar_id and ${d("allDay")} = ${e("allDay")}${displayOnly};
  end if;`;
}

/** `{ id, allDay, method, offsetMinutes, anchor }` for a default alarm row `d`. */
function rowJson(ctx: BlockSqlContext): string {
  const d = (column: string) => `d.${ctx.col("defaultAlarms", column)}`;

  const method = ctx.has("defaultAlarms", "method")
    ? ctx.label("defaultAlarms", "method", d("method"))
    : "'display'";

  const anchor = ctx.has("defaultAlarms", "anchor")
    ? `case when ${d("allDay")} then to_char(coalesce(${d("anchor")}, ${ANCHOR}), 'HH24:MI') end`
    : "null";

  return `jsonb_build_object('id', ${d("id")}, 'allDay', ${d("allDay")}, 'method', ${method}, 'offsetMinutes', ${d("offsetMinutes")}, 'anchor', ${anchor})`;
}

/**
 * `list_calendar_default_alarms` (through the table's read policy) and
 * `set_calendar_default_alarms`, which replaces a calendar's defaults and needs
 * the right to manage the calendar.
 */
export function defaultAlarmFunctions(ctx: BlockSqlContext): string {
  const features = calendarFeatures(ctx);

  if (!features.defaultAlarms) {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const table = ctx.table("defaultAlarms");
  const d = (column: string) => ctx.col("defaultAlarms", column);
  const k = (column: string) => ctx.col("calendars", column);
  const manage = ctx.permission("manage", moduleOperations("calendar").manage);

  const allowed = features.access
    ? accessCall(ctx, "set_calendar_default_alarms.calendar_id", "manage")
    : `(auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)})`;

  const invalid = fail(
    "CALENDAR_ALARM_INVALID",
    `alarms must be an array of at most ${ALARM_LIMIT} objects with a whole offsetMinutes, a method of display, email or audio, and an HH:MM anchor on all-day alarms`,
    "22023",
  );

  const unsupported = [
    ...(ctx.has("defaultAlarms", "method")
      ? []
      : ["coalesce(x ->> 'method', 'display') <> 'display'"]),
    ...(ctx.has("defaultAlarms", "anchor") ? [] : ["x ? 'anchor'"]),
  ]
    .map((test) => `\n      or ${test}`)
    .join("");

  const values: readonly (readonly [string, string])[] = [
    [d("tenant"), "v_tenant"],
    [d("calendar"), "set_calendar_default_alarms.calendar_id"],
    [d("allDay"), "coalesce((x ->> 'allDay')::boolean, false)"],
    [d("offsetMinutes"), "(x ->> 'offsetMinutes')::integer"],
    ...(ctx.has("defaultAlarms", "method")
      ? [
          [
            d("method"),
            ctx.cast(
              "defaultAlarms",
              "method",
              "coalesce(x ->> 'method', 'display')",
            ),
          ] as const,
        ]
      : []),
    ...(ctx.has("defaultAlarms", "anchor")
      ? [
          [
            d("anchor"),
            `case when coalesce((x ->> 'allDay')::boolean, false) then coalesce((x ->> 'anchor')::time, ${ANCHOR}) end`,
          ] as const,
        ]
      : []),
  ];

  return `
create or replace function ${fn("list_calendar_default_alarms")}(calendar_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${rowJson(ctx)} order by d.${d("allDay")}, d.${d("offsetMinutes")} desc, d.${d("id")}), '[]'::jsonb)
  from ${table} d
  where d.${d("calendar")} = list_calendar_default_alarms.calendar_id
$$;
${userGrant(`${fn("list_calendar_default_alarms")}(uuid)`)}

-- Replaces the calendar's default alarms. Events saved before keep theirs.
create or replace function ${fn("set_calendar_default_alarms")}(calendar_id uuid, alarms jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_alarms jsonb := coalesce(set_calendar_default_alarms.alarms, '[]'::jsonb);
begin
  select ${k("tenant")} into v_tenant from ${ctx.table("calendars")} where ${k("id")} = set_calendar_default_alarms.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${allowed} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage this calendar")}
  end if;
  if jsonb_typeof(v_alarms) <> 'array' or jsonb_array_length(v_alarms) > ${ALARM_LIMIT} then
    ${invalid}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_alarms) x
    where jsonb_typeof(x) <> 'object'
      or jsonb_typeof(x -> 'offsetMinutes') is distinct from 'number'
      or (x ->> 'offsetMinutes')::numeric <> trunc((x ->> 'offsetMinutes')::numeric)
      or abs((x ->> 'offsetMinutes')::numeric) > ${TRIGGER_BOUND}
      or (x ? 'allDay' and jsonb_typeof(x -> 'allDay') <> 'boolean')
      or coalesce(x ->> 'method', 'display') not in ${ACTIONS}
      or (x ->> 'anchor' is not null and (not coalesce((x ->> 'allDay')::boolean, false) or x ->> 'anchor' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'))${unsupported}
  ) then
    ${invalid}
  end if;
  delete from ${table} where ${d("calendar")} = set_calendar_default_alarms.calendar_id;
  insert into ${table} (${values.map(([column]) => column).join(", ")})
  select ${values.map(([, value]) => value).join(", ")}
  from jsonb_array_elements(v_alarms) x;
  return ${fn("list_calendar_default_alarms")}(set_calendar_default_alarms.calendar_id);
end;
$$;
${userGrant(`${fn("set_calendar_default_alarms")}(uuid, jsonb)`)}
`;
}

export function defaultAlarmsContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return calendarFeatures(ctx).defaultAlarms
    ? [
        {
          name: "list_calendar_default_alarms",
          args: ["uuid"],
          returns: "jsonb",
        },
        {
          name: "set_calendar_default_alarms",
          args: ["uuid", "jsonb"],
          returns: "jsonb",
        },
      ]
    : [];
}
