import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy, renderPolicy } from "../policy.ts";
import { addCheck, fail, lockTable } from "../shared.ts";
import { calendarFeatures, eventAccessCall } from "./calendar-features.ts";
import { moduleOperations } from "./permissions-model.ts";

/** RFC 5545 `ACTION` values the alarms table stores, in lowercase. */
const ALARM_ACTIONS = ["display", "email", "audio"] as const;

/** A year either way, the bound `reminders` puts on its offsets too. */
const TRIGGER_BOUND = 525_600;

/** At most this many alarms per event. */
const ALARM_LIMIT = 20;

const list = (values: readonly string[]): string =>
  `(${values.map((value) => `'${value}'`).join(", ")})`;

/**
 * The `calendar_event_alarms` table: one row per `VALARM` of an event, with a
 * relative trigger (`trigger_minutes`, RFC 5545 sign, from the start or end) or
 * an absolute one (`trigger_at`). It is event data, the same for everyone who
 * reads the event; per-user reminders stay in the reminders block.
 */
export function alarmsTable(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("alarms")) {
    return "";
  }

  const alarms = ctx.table("alarms");
  const l = (column: string) => ctx.col("alarms", column);
  const name = ctx.tableName("alarms").name;
  const read = ctx.permission("read", moduleOperations("calendar").read);

  const columns = [
    `${l("id")} uuid primary key default gen_random_uuid()`,
    `${l("tenant")} ${ctx.idType} not null`,
    `${l("event")} uuid not null references ${ctx.table("events")} (${ctx.col("events", "id")}) on delete cascade`,
    `${l("action")} text not null default 'display'`,
    `${l("trigger")} integer`,
    ...(
      [
        ["related", "text not null default 'start'"],
        ["triggerAt", "timestamptz"],
        ["repeat", "integer not null default 0"],
        ["repeatMinutes", "integer"],
        ["description", "text"],
        ["summary", "text"],
        ["createdAt", "timestamptz not null default now()"],
      ] as const
    )
      .filter(([column]) => ctx.has("alarms", column))
      .map(([column, type]) => `${l(column)} ${type}`),
  ];

  const checks = ctx.owns("alarms")
    ? [
        addCheck({
          table: alarms,
          name: `${name}_action_check`,
          expression: `${l("action")} in ${list(ALARM_ACTIONS)}`,
        }),
        addCheck({
          table: alarms,
          name: `${name}_trigger_check`,
          expression: `${l("trigger")} between -${TRIGGER_BOUND} and ${TRIGGER_BOUND}`,
        }),
        ...(ctx.has("alarms", "triggerAt")
          ? [
              addCheck({
                table: alarms,
                name: `${name}_trigger_kind_check`,
                expression: `(${l("trigger")} is null) <> (${l("triggerAt")} is null)`,
              }),
            ]
          : []),
        ...(ctx.has("alarms", "related")
          ? [
              addCheck({
                table: alarms,
                name: `${name}_related_check`,
                expression: `${l("related")} in ('start', 'end')`,
              }),
            ]
          : []),
        ...(ctx.has("alarms", "repeat") && ctx.has("alarms", "repeatMinutes")
          ? [
              addCheck({
                table: alarms,
                name: `${name}_repeat_check`,
                expression: `${l("repeat")} >= 0 and (${l("repeat")} = 0) = (${l("repeatMinutes")} is null) and coalesce(${l("repeatMinutes")}, 1) > 0`,
              }),
            ]
          : []),
      ].join("\n")
    : "";

  const using = calendarFeatures(ctx).access
    ? eventAccessCall(ctx, l("event"), "read", "(select auth.uid())")
    : ctx.scope.check(l("tenant"), read);

  return `
create table if not exists ${alarms} (
  ${columns.join(",\n  ")}
);
create index if not exists ${sqlIdent(`${name}_event_idx`)} on ${alarms} (${l("event")});
${lockTable(alarms, { read: true })}
${checks}
${renderPolicy(
  policy({
    table: alarms,
    name: `${name}_read`,
    command: "select",
    roles: ["authenticated"],
    using,
  }),
  { drop: true, target: alarms },
)}
`;
}

/** `item ->> key` as the column's type, or nothing when the column is absent. */
function alarmValues(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  const l = (column: string) => ctx.col("alarms", column);

  const values: [string, string][] = [
    [l("tenant"), "v_tenant"],
    [l("event"), "v_id"],
    [
      l("action"),
      ctx.cast("alarms", "action", "coalesce(x ->> 'action', 'display')"),
    ],
    [l("trigger"), "(x ->> 'triggerMinutes')::integer"],
  ];

  const optional: readonly (readonly [string, string])[] = [
    ["related", "coalesce(x ->> 'related', 'start')"],
    ["triggerAt", "(x ->> 'triggerAt')::timestamptz"],
    ["repeat", "coalesce((x ->> 'repeat')::integer, 0)"],
    ["repeatMinutes", "(x ->> 'repeatMinutes')::integer"],
    ["description", "x ->> 'description'"],
    ["summary", "x ->> 'summary'"],
  ];

  for (const [column, value] of optional) {
    if (ctx.has("alarms", column)) {
      values.push([l(column), value]);
    }
  }

  return values;
}

/**
 * The statements of `save_calendar_event` that replace the event's alarms when
 * the item has an `alarms` array. They run after the event row exists, with
 * `v_id` and `v_tenant` set.
 */
export function alarmWrites(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("alarms")) {
    return "";
  }

  const alarms = ctx.table("alarms");
  const values = alarmValues(ctx);

  const invalid = (message: string): string =>
    fail("CALENDAR_EVENT_INVALID", message, "22023");

  return `
  if v_item ? 'alarms' then
    if jsonb_typeof(v_item -> 'alarms') <> 'array' or jsonb_array_length(v_item -> 'alarms') > ${ALARM_LIMIT} then
      ${invalid(`alarms must be an array of at most ${ALARM_LIMIT}`)}
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_item -> 'alarms') x
      where jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'action', 'display') not in ${list(ALARM_ACTIONS)}
        or coalesce(x ->> 'related', 'start') not in ('start', 'end')
        or (x ->> 'triggerMinutes' is null) = (x ->> 'triggerAt' is null)${ctx.has("alarms", "triggerAt") ? "" : "\n        or x ->> 'triggerAt' is not null"}
        or abs(coalesce((x ->> 'triggerMinutes')::integer, 0)) > ${TRIGGER_BOUND}
        or coalesce((x ->> 'repeat')::integer, 0) < 0
        or (coalesce((x ->> 'repeat')::integer, 0) > 0) <> (x ->> 'repeatMinutes' is not null)
        or coalesce((x ->> 'repeatMinutes')::integer, 1) <= 0
    ) then
      ${invalid("each alarm needs an action of display, email or audio, triggerMinutes or triggerAt, and repeat with repeatMinutes")}
    end if;
    delete from ${alarms} where ${ctx.col("alarms", "event")} = v_id;
    insert into ${alarms} (${values.map(([column]) => column).join(", ")})
    select ${values.map(([, value]) => value).join(", ")}
    from jsonb_array_elements(v_item -> 'alarms') x;
  end if;`;
}

/** `, 'alarms', [...]` for an event row `e`, or nothing without the table. */
export function alarmsJson(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("alarms")) {
    return "";
  }

  const l = (column: string) => `l.${ctx.col("alarms", column)}`;

  const optional = (key: string, column: string, fallback = "null"): string =>
    `'${key}', ${ctx.has("alarms", column) ? l(column) : fallback}`;

  const json = `jsonb_build_object('id', ${l("id")}, 'action', ${ctx.label("alarms", "action", l("action"))}, 'triggerMinutes', ${l("trigger")}, ${optional("related", "related", "'start'")}, ${optional("triggerAt", "triggerAt")}, ${optional("repeat", "repeat", "0")}, ${optional("repeatMinutes", "repeatMinutes")}, ${optional("description", "description")}, ${optional("summary", "summary")})`;

  return `, 'alarms', coalesce((select jsonb_agg(${json} order by ${ctx.has("alarms", "createdAt") ? `${l("createdAt")}, ` : ""}${l("id")}) from ${ctx.table("alarms")} l where ${l("event")} = e.${ctx.col("events", "id")}), '[]'::jsonb)`;
}
