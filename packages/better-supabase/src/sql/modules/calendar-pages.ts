import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFirst,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { eventJson } from "./calendar-rows.ts";

/** What the page functions read from the calendar builder. */
interface CalendarPageParts {
  readonly ctx: BlockSqlContext;
  readonly fn: (name: string) => string;
  readonly events: string;
  readonly calendars: string;
  readonly attendees: string;
  readonly k: (column: string) => string;
  readonly calendarJson: (row: string) => string;
}

/**
 * The keyset page functions of the calendar block (ADR 1077). They run as the
 * caller, so the tables' policies decide which rows come back. The event page
 * returns the stored rows: single events, series and their overrides;
 * `occurrences` expands series in TypeScript.
 */
export function calendarPageSql(h: CalendarPageParts): string {
  const { ctx, fn, events, calendars, attendees, k, calendarJson } = h;
  const e = (column: string): string => `e.${ctx.col("events", column)}`;
  const eventKey = { expr: e("id"), dir: "asc", type: "uuid" } as const;

  const starts = [
    { expr: e("startsAt"), dir: "asc", type: "timestamptz" },
    eventKey,
  ] as const;

  const subject = (column: string): string =>
    ctx.has("events", column) ? e(column) : "null::text";

  const status = ctx.label("events", "status", e("status"));

  const eventPage = {
    name: "page_calendar_events",
    from: events,
    alias: "e",
    where: [
      filterAny("calendarId", e("calendar"), "uuid"),
      filterAny("status", status),
      filterAny("subjectType", subject("subjectType")),
      filterAny("subjectId", subject("subjectId")),
      `(${filterFirst("from")} is null or ${e("endsAt")} > (${filterFirst("from")})::timestamptz)`,
      `(${filterFirst("to")} is null or ${e("startsAt")} < (${filterFirst("to")})::timestamptz)`,
      `(v_search is null or ${e("title")} ilike v_search${ctx.has("events", "location") ? ` or ${e("location")} ilike v_search` : ""})`,
    ],
    keys: starts,
    sorts: {
      startsAt: starts,
      title: [
        { expr: `lower(${e("title")})`, dir: "asc", type: "text" },
        eventKey,
      ],
      updatedAt: [
        { expr: e("updatedAt"), dir: "desc", type: "timestamptz" },
        eventKey,
      ],
    },
    facets: { status, calendarId: `${e("calendar")}::text` },
    rowJson: eventJson(ctx, attendees),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("CALENDAR_INVALID", message, "22023"),
  } as const;

  const calendarKey = {
    expr: `k.${k("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const byName = [
    { expr: `lower(k.${k("name")})`, dir: "asc", type: "text" },
    calendarKey,
  ] as const;

  const ownerType = ctx.has("calendars", "ownerType")
    ? `k.${k("ownerType")}`
    : "null::text";

  const calendarPage = {
    name: "page_calendars",
    from: calendars,
    alias: "k",
    where: [
      `k.${k("tenant")} = page_calendars.tenant`,
      filterAny("ownerType", ownerType),
      `(v_search is null or k.${k("name")} ilike v_search)`,
    ],
    keys: byName,
    sorts: { name: byName },
    facets: { ownerType },
    rowJson: calendarJson("k"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("CALENDAR_INVALID", message, "22023"),
  } as const;

  return `
-- The stored calendar events as a keyset page, the earliest start first (ADR
-- 1077): single events, series and their overrides. filters is { calendarId,
-- status, subjectType, subjectId (each a value or a list), from, to (the first
-- value counts: events that overlap the window), search (title, location),
-- sort (startsAt, title, updatedAt), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${fn("page_calendar_events")}(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_calendar_events.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(eventPage)}
begin
  ${listBody(eventPage)}
end;
$$;
${userGrant(`${fn("page_calendar_events")}(jsonb)`)}

-- One event the caller reads, or null.
create or replace function ${fn("get_calendar_event")}(event_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${eventJson(ctx, attendees)} from ${events} e where ${e("id")} = get_calendar_event.event_id
$$;
${userGrant(`${fn("get_calendar_event")}(uuid)`)}

-- The tenant's calendars as a keyset page by name.
create or replace function ${fn("page_calendars")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_calendars.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(calendarPage)}
begin
  ${listBody(calendarPage)}
end;
$$;
${userGrant(`${fn("page_calendars")}(${ctx.idType}, jsonb)`)}

-- One calendar the caller reads, or null.
create or replace function ${fn("get_calendar")}(calendar_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${calendarJson("k")} from ${calendars} k where k.${k("id")} = get_calendar.calendar_id
$$;
${userGrant(`${fn("get_calendar")}(uuid)`)}
`;
}
