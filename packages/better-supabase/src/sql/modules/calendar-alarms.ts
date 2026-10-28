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
 * The `calendar_event_alarms` table: one row per `VALARM` of an event, with an
 * offset in minutes before the start or end (`offset_minutes`, the reminders
 * block's sign) or an absolute time (`trigger_at`). A row without a user is
 * event data, the same for everyone who reads the event; a row with one counts
 * only for that user. An app keeps its own alarms by mapping `tables.alarms`.
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
    ...(
      [
        ["user", "uuid"],
        ["method", "text not null default 'display'"],
      ] as const
    )
      .filter(([column]) => ctx.has("alarms", column))
      .map(([column, type]) => `${l(column)} ${type}`),
    `${l("offsetMinutes")} integer`,
    ...(
      [
        ["related", "text not null default 'start'"],
        ["at", "timestamptz"],
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
        ...(ctx.has("alarms", "method")
          ? [
              addCheck({
                table: alarms,
                name: `${name}_method_check`,
                expression: `${l("method")} in ${list(ALARM_ACTIONS)}`,
              }),
            ]
          : []),
        addCheck({
          table: alarms,
          name: `${name}_offset_check`,
          expression: `${l("offsetMinutes")} between -${TRIGGER_BOUND} and ${TRIGGER_BOUND}`,
        }),
        addCheck({
          table: alarms,
          name: `${name}_trigger_check`,
          expression: ctx.has("alarms", "at")
            ? `(${l("offsetMinutes")} is null) <> (${l("at")} is null)`
            : `${l("offsetMinutes")} is not null`,
        }),
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

  const own = ctx.has("alarms", "user")
    ? ` and (${l("user")} is null or ${l("user")} = (select auth.uid()))`
    : "";

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
    using: `${using}${own}`,
  }),
  { drop: true, target: alarms },
)}
`;
}

/** `item ->> key` as the column's type, for the columns the table has. */
function alarmValues(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  const l = (column: string) => ctx.col("alarms", column);

  const values: [string, string][] = [
    [l("tenant"), "v_tenant"],
    [l("event"), "v_id"],
    [l("offsetMinutes"), "(x ->> 'offsetMinutes')::integer"],
  ];

  const optional: readonly (readonly [string, string])[] = [
    [
      "method",
      ctx.has("alarms", "method")
        ? ctx.cast("alarms", "method", "coalesce(x ->> 'method', 'display')")
        : "",
    ],
    ["related", "coalesce(x ->> 'related', 'start')"],
    ["at", "(x ->> 'at')::timestamptz"],
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
 * `v_id` and `v_tenant` set, and leave the alarms of single users alone.
 */
export function alarmWrites(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("alarms")) {
    return "";
  }

  const alarms = ctx.table("alarms");
  const values = alarmValues(ctx);

  const invalid = (message: string): string =>
    fail("CALENDAR_EVENT_INVALID", message, "22023");

  const unsupported = (
    [
      ["method", "coalesce(x ->> 'method', 'display') <> 'display'"],
      ["related", "coalesce(x ->> 'related', 'start') <> 'start'"],
      ["at", "x ->> 'at' is not null"],
      ["repeat", "coalesce((x ->> 'repeat')::integer, 0) <> 0"],
    ] as const
  )
    .filter(([column]) => !ctx.has("alarms", column))
    .map(([, test]) => `\n        or ${test}`)
    .join("");

  return `
  if v_item ? 'alarms' then
    if jsonb_typeof(v_item -> 'alarms') <> 'array' or jsonb_array_length(v_item -> 'alarms') > ${ALARM_LIMIT} then
      ${invalid(`alarms must be an array of at most ${ALARM_LIMIT}`)}
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_item -> 'alarms') x
      where jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'method', 'display') not in ${list(ALARM_ACTIONS)}
        or coalesce(x ->> 'related', 'start') not in ('start', 'end')
        or (x ->> 'offsetMinutes' is null) = (x ->> 'at' is null)
        or abs(coalesce((x ->> 'offsetMinutes')::integer, 0)) > ${TRIGGER_BOUND}
        or coalesce((x ->> 'repeat')::integer, 0) < 0
        or (coalesce((x ->> 'repeat')::integer, 0) > 0) <> (x ->> 'repeatMinutes' is not null)
        or coalesce((x ->> 'repeatMinutes')::integer, 1) <= 0${unsupported}
    ) then
      ${invalid("each alarm needs a method of display, email or audio, offsetMinutes or at, and repeat with repeatMinutes")}
    end if;
    delete from ${alarms} where ${ctx.col("alarms", "event")} = v_id${ctx.has("alarms", "user") ? ` and ${ctx.col("alarms", "user")} is null` : ""};
    insert into ${alarms} (${values.map(([column]) => column).join(", ")})
    select ${values.map(([, value]) => value).join(", ")}
    from jsonb_array_elements(v_item -> 'alarms') x;
  end if;`;
}

/**
 * The alarms of event `event` that `viewer` gets, as a jsonb array in the
 * `CalendarReminder` shape: the event's own and the viewer's.
 */
export function alarmsArray(
  ctx: BlockSqlContext,
  event: string,
  viewer: string,
): string {
  const l = (column: string) => `l.${ctx.col("alarms", column)}`;

  const optional = (key: string, column: string, fallback = "null"): string =>
    `'${key}', ${ctx.has("alarms", column) ? l(column) : fallback}`;

  const method = ctx.has("alarms", "method")
    ? ctx.label("alarms", "method", l("method"))
    : "'display'";

  const json = `jsonb_build_object('id', ${l("id")}, 'method', ${method}, 'offsetMinutes', ${l("offsetMinutes")}, ${optional("related", "related", "'start'")}, ${optional("at", "at")}, ${optional("repeat", "repeat", "0")}, ${optional("repeatMinutes", "repeatMinutes")}, ${optional("description", "description")}, ${optional("summary", "summary")})`;

  const own = ctx.has("alarms", "user")
    ? ` and (${l("user")} is null or ${l("user")} = ${viewer})`
    : "";

  return `coalesce((select jsonb_agg(${json} order by ${l("offsetMinutes")} nulls last, ${ctx.has("alarms", "at") ? `${l("at")}, ` : ""}${l("id")}) from ${ctx.table("alarms")} l where ${l("event")} = ${event}${own}), '[]'::jsonb)`;
}

/** `, 'alarms', [...]` for an event row `e`, or nothing without the table. */
export function alarmsJson(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("alarms")) {
    return "";
  }

  return `, 'alarms', ${alarmsArray(ctx, `e.${ctx.col("events", "id")}`, "(select auth.uid())")}`;
}
