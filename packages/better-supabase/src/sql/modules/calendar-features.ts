import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent } from "../../core/template.ts";
import { policy, renderPolicy } from "../policy.ts";
import { fail, lockTable, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

export interface CalendarFeatures {
  readonly access: boolean;
  readonly readFn: string | undefined;
  readonly writeFn: string | undefined;
  readonly grants: boolean;
  readonly userFeed: boolean;
  readonly table: boolean;
  readonly rdates: boolean;
  readonly anyAttendee: boolean;
  readonly details: boolean;
}

const QUALIFIED = /^[A-Za-z_][\w$]*\.[A-Za-z_][\w$]*$/;

function appFunction(value: unknown, key: string): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string" || !QUALIFIED.test(value)) {
    throw new TypeError(
      `blocks.calendar.options.accessFunctions.${key} must be a schema-qualified function name, such as public.can_read_calendar`,
    );
  }

  return value.split(".").map(sqlIdent).join(".");
}

export function calendarFeatures(ctx: BlockSqlContext): CalendarFeatures {
  const access = ctx.flag("access", false);
  const functions = ctx.option("accessFunctions");

  if (functions !== undefined && (!access || !isRecord(functions))) {
    throw new TypeError(
      "blocks.calendar.options.accessFunctions takes { read, write } and needs options.access",
    );
  }

  const recurrence = ctx.text("recurrence", "inline");

  if (recurrence !== "inline" && recurrence !== "table") {
    throw new TypeError(
      'blocks.calendar.options.recurrence must be "inline" or "table"',
    );
  }

  const attendeeKey = ctx.text("attendeeKey", "email");

  if (attendeeKey !== "email" && attendeeKey !== "any") {
    throw new TypeError(
      'blocks.calendar.options.attendeeKey must be "email" or "any"',
    );
  }

  const table = recurrence === "table";

  if (table && (!ctx.hasTable("rules") || !ctx.hasTable("recurrenceDates"))) {
    throw new TypeError(
      'blocks.calendar.options.recurrence "table" needs the rules and recurrenceDates tables',
    );
  }

  const readFn = isRecord(functions)
    ? appFunction(functions["read"], "read")
    : undefined;

  const writeFn = isRecord(functions)
    ? appFunction(functions["write"], "write")
    : undefined;

  return {
    access,
    readFn,
    writeFn,
    grants:
      access &&
      ctx.hasTable("grants") &&
      (readFn === undefined || writeFn === undefined),
    userFeed: ctx.flag("userFeed", false),
    table,
    rdates: table || ctx.flag("rdates", false),
    anyAttendee: attendeeKey === "any",
    details: ctx.flag("calendarDetails", false),
  };
}

export function unusedCalendarColumns(
  ctx: BlockSqlContext,
  table: "calendars" | "events" | "attendees",
): readonly string[] {
  const features = calendarFeatures(ctx);

  switch (table) {
    case "calendars": {
      return [
        ...(features.access ? [] : ["visibility"]),
        ...(features.details ? [] : ["description", "rank", "isDefault"]),
      ];
    }

    case "events": {
      return [
        ...(features.access ? [] : ["visibility", "owner"]),
        ...(features.rdates && !features.table ? [] : ["rdates"]),
        ...(features.table ? ["rrule", "exdates"] : []),
      ];
    }

    case "attendees": {
      return features.anyAttendee
        ? []
        : ["subjectType", "subjectId", "organizer", "optional"];
    }

    default: {
      const never: never = table;

      return never;
    }
  }
}

export function ownerText(ctx: BlockSqlContext, alias: string): string {
  const values = ctx.config.values?.["calendars"];

  const cast =
    ctx.appOwned.includes("calendars") &&
    isRecord(values) &&
    values["ownerId"] !== undefined;

  return `${alias}${ctx.col("calendars", "ownerId")}${cast ? "::text" : ""}`;
}

function ownedBy(ctx: BlockSqlContext, alias: string, user: string): string {
  if (!ctx.has("calendars", "ownerId")) {
    return "false";
  }

  const type = ctx.has("calendars", "ownerType")
    ? `${alias}${ctx.col("calendars", "ownerType")} = 'user' and `
    : "";

  return `coalesce(${type}${alias}${ctx.col("calendars", "ownerId")}::text = (${user})::text, false)`;
}

export function privateCalendar(ctx: BlockSqlContext, alias: string): string {
  return ctx.has("calendars", "visibility")
    ? `coalesce(${ctx.is("calendars", "visibility", `${alias}${ctx.col("calendars", "visibility")}`, ["private"])}, false)`
    : "false";
}

function privateEvent(ctx: BlockSqlContext, alias: string): string {
  return ctx.has("events", "visibility")
    ? `coalesce(${ctx.is("events", "visibility", `${alias}${ctx.col("events", "visibility")}`, ["private"])}, false)`
    : "false";
}

function eventOwner(ctx: BlockSqlContext): string | undefined {
  if (ctx.has("events", "owner")) {
    return ctx.col("events", "owner");
  }

  return ctx.has("events", "createdBy")
    ? ctx.col("events", "createdBy")
    : undefined;
}

export const accessCall = (
  ctx: BlockSqlContext,
  calendar: string,
  action: "read" | "write" | "manage" | "private",
  user = "auth.uid()",
): string => `${ctx.fn("calendar_access")}(${calendar}, ${user}, '${action}')`;

export const eventAccessCall = (
  ctx: BlockSqlContext,
  event: string,
  action: "read" | "write",
  user = "auth.uid()",
): string =>
  `${ctx.fn("calendar_event_access")}(${event}, ${user}, '${action}')`;

export function accessFunctions(ctx: BlockSqlContext): string {
  const features = calendarFeatures(ctx);

  if (!features.access) {
    return "";
  }

  const perms = moduleOperations("calendar");
  const read = ctx.permission("read", perms.read);
  const write = ctx.permission("write", perms.write);
  const manage = ctx.permission("manage", perms.manage);
  const calendars = ctx.table("calendars");
  const events = ctx.table("events");
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const user = "calendar_access.user_id";
  const can = (key: string) => ctx.scope.canUser(user, "v_tenant", key);

  const grant = features.grants
    ? `
  select case when bool_or(${ctx.is("grants", "role", `g.${ctx.col("grants", "role")}`, ["editor"])}) then 'editor' else 'viewer' end
    into v_grant
  from ${ctx.table("grants")} g
  where g.${ctx.col("grants", "calendar")} = calendar_access.calendar_id
    and g.${ctx.col("grants", "user")} = ${user}
  having count(*) > 0;`
    : "";

  const custom = (fn: string | undefined, actions: string) =>
    fn === undefined
      ? ""
      : `
  if calendar_access.action in (${actions}) then
    return coalesce(${fn}(calendar_access.calendar_id, ${user}), false);
  end if;`;

  const owner = eventOwner(ctx);

  return `
-- Whether user_id may read, write or manage a calendar, or see its private
-- events: its owner may do all of it; an editor grant writes and sees private
-- events; on a shared calendar the tenant's keys decide.
create or replace function ${ctx.fn("calendar_access")}(calendar_id uuid, user_id uuid, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_owner boolean;
  v_private boolean;
  v_grant text;
begin
  if ${user} is null then
    return auth.role() = 'service_role';
  end if;
  select ${k("tenant")}, ${ownedBy(ctx, "k.", user)}, ${privateCalendar(ctx, "k.")}
    into v_tenant, v_owner, v_private
  from ${calendars} k
  where ${k("id")} = calendar_access.calendar_id;
  if not found or not ${can(read)} then
    return false;
  end if;${custom(features.readFn, "'read'")}${custom(features.writeFn, "'write', 'manage', 'private'")}
  if v_owner then
    return true;
  end if;${grant}
  return case calendar_access.action
    when 'read' then not v_private or v_grant is not null
    when 'write' then coalesce(v_grant = 'editor', false) or (not v_private and ${can(write)})
    when 'manage' then not v_private and ${can(manage)}
    when 'private' then coalesce(v_grant = 'editor', false)
    else false
  end;
end;
$$;
${userGrant(`${ctx.fn("calendar_access")}(uuid, uuid, text)`)}

-- Whether user_id may read or write one event: the calendar's access, and for
-- a private event its owner or someone who sees the calendar's private events.
create or replace function ${ctx.fn("calendar_event_access")}(event_id uuid, user_id uuid, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_calendar uuid;
  v_private boolean;
  v_mine boolean;
begin
  if calendar_event_access.user_id is null then
    return auth.role() = 'service_role';
  end if;
  select ${e("calendar")}, ${privateEvent(ctx, "e.")}, ${owner === undefined ? "false" : `coalesce(e.${owner} = calendar_event_access.user_id, false)`}
    into v_calendar, v_private, v_mine
  from ${events} e
  where ${e("id")} = calendar_event_access.event_id;
  if not found or not ${ctx.fn("calendar_access")}(v_calendar, calendar_event_access.user_id, case when calendar_event_access.action = 'write' then 'write' else 'read' end) then
    return false;
  end if;
  return not v_private or v_mine or ${ctx.fn("calendar_access")}(v_calendar, calendar_event_access.user_id, 'private');
end;
$$;
${userGrant(`${ctx.fn("calendar_event_access")}(uuid, uuid, text)`)}
`;
}

export function grantsTable(ctx: BlockSqlContext): string {
  if (!ctx.manages || !calendarFeatures(ctx).grants) {
    return "";
  }

  const grants = ctx.table("grants");
  const g = (column: string) => ctx.col("grants", column);
  const name = ctx.tableName("grants").name;

  return `create table if not exists ${grants} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("calendar")} uuid not null references ${ctx.table("calendars")} (${ctx.col("calendars", "id")}) on delete cascade,
  ${g("user")} uuid not null,
  ${g("role")} text not null default 'viewer' check (${g("role")} in ('viewer', 'editor')),
  ${g("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${name}_calendar_idx`)} on ${grants} (${g("calendar")}, ${g("user")});
${lockTable(grants, { read: true })}
${renderPolicy(
  policy({
    table: grants,
    name: `${name}_read`,
    command: "select",
    roles: ["authenticated"],
    using: `${g("user")} = (select auth.uid()) or ${accessCall(ctx, g("calendar"), "manage", "(select auth.uid())")}`,
  }),
  { drop: true, target: grants },
)}
`;
}

export function grantFunctions(ctx: BlockSqlContext): string {
  if (!calendarFeatures(ctx).grants) {
    return "";
  }

  const grants = ctx.table("grants");
  const g = (column: string) => ctx.col("grants", column);
  const calendars = ctx.table("calendars");
  const k = (column: string) => ctx.col("calendars", column);

  return `
-- Gives user_id viewer or editor access to a calendar. The calendar's owner,
-- or a manager of a shared calendar, may.
create or replace function ${ctx.fn("set_calendar_grant")}(calendar_id uuid, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  if coalesce(set_calendar_grant.role, '') not in ('viewer', 'editor') or set_calendar_grant.user_id is null then
    ${fail("CALENDAR_GRANT_INVALID", "a grant needs a user and the role viewer or editor", "22023")}
  end if;
  select ${k("tenant")} into v_tenant from ${calendars} where ${k("id")} = set_calendar_grant.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${accessCall(ctx, "set_calendar_grant.calendar_id", "manage")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage this calendar")}
  end if;
  update ${grants} set ${g("role")} = ${ctx.cast("grants", "role", "set_calendar_grant.role")}
  where ${g("calendar")} = set_calendar_grant.calendar_id and ${g("user")} = set_calendar_grant.user_id;
  if not found then
    insert into ${grants} (${g("tenant")}, ${g("calendar")}, ${g("user")}, ${g("role")})
    values (v_tenant, set_calendar_grant.calendar_id, set_calendar_grant.user_id, ${ctx.cast("grants", "role", "set_calendar_grant.role")});
  end if;
  return true;
end;
$$;
${userGrant(`${ctx.fn("set_calendar_grant")}(uuid, uuid, text)`)}

create or replace function ${ctx.fn("remove_calendar_grant")}(calendar_id uuid, user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${accessCall(ctx, "remove_calendar_grant.calendar_id", "manage")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage this calendar")}
  end if;
  delete from ${grants} where ${g("calendar")} = remove_calendar_grant.calendar_id and ${g("user")} = remove_calendar_grant.user_id;
  return found;
end;
$$;
${userGrant(`${ctx.fn("remove_calendar_grant")}(uuid, uuid)`)}

-- [{ userId, role }] of a calendar. Runs as the caller, so the policy decides.
create or replace function ${ctx.fn("list_calendar_grants")}(calendar_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', g.${g("user")}, 'role', ${ctx.label("grants", "role", `g.${g("role")}`)}) order by g.${g("user")}), '[]'::jsonb)
  from ${grants} g
  where g.${g("calendar")} = list_calendar_grants.calendar_id
$$;
${userGrant(`${ctx.fn("list_calendar_grants")}(uuid)`)}
`;
}

export interface RecurrenceSql {
  rule(prefix: string): string;
  exdates(prefix: string): string;
  rdates(prefix: string): string | undefined;
  exdatesOf(id: string): string;
  recurring(prefix: string): string;
  single(prefix: string): string;
}

function ruleText(ctx: BlockSqlContext): string {
  const r = (column: string) => `r.${ctx.col("rules", column)}`;

  if (ctx.has("rules", "rrule")) {
    return r("rrule");
  }

  const list = (key: string, column: string) =>
    ctx.has("rules", column)
      ? [`'${key}=' || nullif(translate(${r(column)}::text, '{}" ', ''), '')`]
      : [];

  const parts = [
    `'FREQ=' || upper(${ctx.label("rules", "freq", r("freq"))})`,
    ...(ctx.has("rules", "interval")
      ? [`'INTERVAL=' || ${r("interval")}`]
      : []),
    ...(ctx.has("rules", "count") ? [`'COUNT=' || ${r("count")}`] : []),
    ...(ctx.has("rules", "until")
      ? [
          `'UNTIL=' || to_char(${r("until")}::timestamptz at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"')`,
        ]
      : []),
    ...list("BYDAY", "byDay"),
    ...list("BYMONTHDAY", "byMonthDay"),
    ...list("BYMONTH", "byMonth"),
    ...list("BYSETPOS", "bySetPos"),
  ];

  return `nullif(concat_ws(';', ${parts.join(", ")}), '')`;
}

export function recurrenceSql(ctx: BlockSqlContext): RecurrenceSql {
  const features = calendarFeatures(ctx);
  const e = (column: string) => ctx.col("events", column);

  if (!features.table) {
    const rdates = features.rdates
      ? (prefix: string) => `${prefix}${e("rdates")}`
      : undefined;

    const recurring = (prefix: string) =>
      rdates === undefined
        ? `${prefix}${e("rrule")} is not null`
        : `(${prefix}${e("rrule")} is not null or cardinality(${prefix}${e("rdates")}) > 0)`;

    return {
      rule: (prefix) => `${prefix}${e("rrule")}`,
      exdates: (prefix) => `${prefix}${e("exdates")}`,
      rdates: (prefix) => rdates?.(prefix),
      exdatesOf: () => e("exdates"),
      recurring,
      single: (prefix) =>
        rdates === undefined
          ? `${prefix}${e("rrule")} is null`
          : `not ${recurring(prefix)}`,
    };
  }

  const events = ctx.table("events");
  const rules = ctx.table("rules");
  const dates = ctx.table("recurrenceDates");
  const r = (column: string) => `r.${ctx.col("rules", column)}`;
  const d = (column: string) => `d.${ctx.col("recurrenceDates", column)}`;

  const id = (prefix: string) =>
    `${prefix === "" ? `${events}.` : prefix}${e("id")}`;

  const datesOf = (event: string, kind: string) =>
    `coalesce((select array_agg(${d("at")} order by ${d("at")}) from ${dates} d where ${d("event")} = ${event} and ${ctx.is("recurrenceDates", "kind", d("kind"), [kind])}), '{}'::timestamptz[])`;

  const recurring = (prefix: string) =>
    `(exists (select 1 from ${rules} r where ${r("event")} = ${id(prefix)}) or exists (select 1 from ${dates} d where ${d("event")} = ${id(prefix)} and ${ctx.is("recurrenceDates", "kind", d("kind"), ["rdate"])}))`;

  return {
    rule: (prefix) =>
      `(select ${ruleText(ctx)} from ${rules} r where ${r("event")} = ${id(prefix)} limit 1)`,
    exdates: (prefix) => datesOf(id(prefix), "exdate"),
    rdates: (prefix) => datesOf(id(prefix), "rdate"),
    exdatesOf: (event) => datesOf(event, "exdate"),
    recurring,
    single: (prefix) => `not ${recurring(prefix)}`,
  };
}

export function insertRule(
  ctx: BlockSqlContext,
  id: string,
  tenant: string,
  source: string,
): string {
  const rules = ctx.table("rules");
  const r = (column: string) => ctx.col("rules", column);
  const columns: string[] = [];
  const values: string[] = [];

  if (ctx.has("rules", "tenant")) {
    columns.push(r("tenant"));
    values.push(tenant);
  }

  columns.push(r("event"));
  values.push(id);

  if (ctx.has("rules", "rrule")) {
    columns.push(r("rrule"));
    values.push(source);
  } else {
    const part = (key: string, pattern = "[^;]+") =>
      `substring(upper(${source}) from '(?:^|;)${key}=(${pattern})')`;

    const add = (column: string, value: () => string) => {
      if (ctx.has("rules", column)) {
        columns.push(r(column));
        values.push(value());
      }
    };

    add("freq", () => ctx.cast("rules", "freq", part("FREQ", "[A-Z]+")));
    add("interval", () => `(${part("INTERVAL", "[0-9]+")})::integer`);
    add("count", () => `(${part("COUNT", "[0-9]+")})::integer`);
    add(
      "until",
      () =>
        `case when ${part("UNTIL")} is null then null else to_timestamp(rpad(translate(${part("UNTIL")}, 'TZ', ''), 14, '0'), 'YYYYMMDDHH24MISS')::timestamp at time zone 'UTC' end`,
    );

    for (const [column, key] of [
      ["byDay", "BYDAY"],
      ["byMonthDay", "BYMONTHDAY"],
      ["byMonth", "BYMONTH"],
      ["bySetPos", "BYSETPOS"],
    ] as const) {
      add(column, () =>
        ctx.cast("rules", column, `'{' || ${part(key)} || '}'`),
      );
    }
  }

  return `insert into ${rules} (${columns.join(", ")}) values (${values.join(", ")});`;
}

export function replaceDates(
  ctx: BlockSqlContext,
  id: string,
  tenant: string,
  kind: "rdate" | "exdate",
  dates: string,
): string {
  const table = ctx.table("recurrenceDates");
  const d = (column: string) => ctx.col("recurrenceDates", column);
  const withTenant = ctx.has("recurrenceDates", "tenant");

  return `delete from ${table} where ${d("event")} = ${id} and ${ctx.is("recurrenceDates", "kind", d("kind"), [kind])};
    insert into ${table} (${withTenant ? `${d("tenant")}, ` : ""}${d("event")}, ${d("kind")}, ${d("at")})
    select ${withTenant ? `${tenant}, ` : ""}${id}, ${ctx.cast("recurrenceDates", "kind", `'${kind}'`)}, x from unnest(${dates}) x;`;
}

export function addDate(
  ctx: BlockSqlContext,
  id: string,
  tenant: string,
  kind: "rdate" | "exdate",
  at: string,
): string {
  const d = (column: string) => ctx.col("recurrenceDates", column);
  const withTenant = ctx.has("recurrenceDates", "tenant");

  return `insert into ${ctx.table("recurrenceDates")} (${withTenant ? `${d("tenant")}, ` : ""}${d("event")}, ${d("kind")}, ${d("at")})
    values (${withTenant ? `${tenant}, ` : ""}${id}, ${ctx.cast("recurrenceDates", "kind", `'${kind}'`)}, ${at});`;
}

export function recurrenceTables(ctx: BlockSqlContext): string {
  if (!ctx.manages || !calendarFeatures(ctx).table) {
    return "";
  }

  const events = ctx.table("events");
  const id = ctx.col("events", "id");
  const rules = ctx.table("rules");
  const dates = ctx.table("recurrenceDates");
  const r = (column: string) => ctx.col("rules", column);
  const d = (column: string) => ctx.col("recurrenceDates", column);
  const read = ctx.permission("read", moduleOperations("calendar").read);

  if (ctx.owns("rules") && !ctx.has("rules", "rrule")) {
    throw new TypeError(
      "blocks.calendar.columns.rules.rrule can be null only over your own rules table",
    );
  }

  const readPolicy = (table: string, name: string, tenant: string) =>
    renderPolicy(
      policy({
        table,
        name: `${name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: calendarFeatures(ctx).access
          ? eventAccessCall(ctx, tenant, "read", "(select auth.uid())")
          : ctx.scope.check(tenant, read),
      }),
      { drop: true, target: table },
    );

  const rulesName = ctx.tableName("rules").name;
  const datesName = ctx.tableName("recurrenceDates").name;

  return `create table if not exists ${rules} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("event")} uuid not null references ${events} (${id}) on delete cascade,
  ${r("rrule")} text not null
);
create index if not exists ${sqlIdent(`${rulesName}_event_idx`)} on ${rules} (${r("event")});
${lockTable(rules, { read: true })}
${readPolicy(rules, rulesName, calendarFeatures(ctx).access ? r("event") : r("tenant"))}
create table if not exists ${dates} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("event")} uuid not null references ${events} (${id}) on delete cascade,
  ${d("kind")} text not null check (${d("kind")} in ('rdate', 'exdate')),
  ${d("at")} timestamptz not null
);
create index if not exists ${sqlIdent(`${datesName}_event_idx`)} on ${dates} (${d("event")});
${lockTable(dates, { read: true })}
${readPolicy(dates, datesName, calendarFeatures(ctx).access ? d("event") : d("tenant"))}
`;
}
