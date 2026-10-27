import type { BlockSqlContext } from "../context.ts";
import type { FeedOptions } from "../feed-options.ts";

import { feedOptions, feedWindow } from "../feed-options.ts";
import {
  accessCall,
  calendarFeatures,
  eventAccessCall,
  eventOwner,
  privateEvent,
  recurrenceSql,
} from "./calendar-features.ts";
import { eventJson } from "./calendar-rows.ts";
import { moduleOperations } from "./permissions-model.ts";
import { liveShareLink, touchShareLink } from "./share-links.ts";

const UUID = "'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'";

/** `blocks.calendar.options.feed`, checked against what the calendar has. */
export function calendarFeed(ctx: BlockSqlContext): FeedOptions {
  const feed = feedOptions(ctx, "blocks.calendar.options");

  if (
    feed.visibility === "public" &&
    (!calendarFeatures(ctx).access || !ctx.has("events", "visibility"))
  ) {
    throw new TypeError(
      'blocks.calendar.options.feed.visibility "public" needs options.access and the events visibility column',
    );
  }

  return feed;
}

/**
 * The events of a feed, as a JSON array: those of the calendars `where` selects
 * (over `k` and `e`), in the feed's window and visibility for `creator`, with
 * the creator's reminders, at most the feed's limit.
 */
function feedEvents(
  ctx: BlockSqlContext,
  events: string,
  calendars: string,
  attendees: string,
  where: string,
  creator: string,
): string {
  const feed = calendarFeed(ctx);
  const features = calendarFeatures(ctx);
  const recurrence = recurrenceSql(ctx);
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  const owner = eventOwner(ctx);

  const visible =
    feed.visibility === "public"
      ? `(not ${privateEvent(ctx, "e.")}${owner === undefined ? "" : ` or e.${owner} = ${creator}`})`
      : features.access
        ? eventAccessCall(ctx, e("id"), "read", creator)
        : "true";

  const reminders =
    ctx.installed("reminders") && ctx.of("reminders").hasTable("reminders")
      ? (() => {
          const r = ctx.of("reminders");
          const c = (column: string) => `r.${r.col("reminders", column)}`;

          return ` || jsonb_build_object('reminders', coalesce((select jsonb_agg(jsonb_build_object('method', ${c("method")}, 'offsetMinutes', ${c("offsetMinutes")}) order by ${c("offsetMinutes")}) from ${r.table("reminders")} r where ${c("subjectType")} = 'calendar_event' and ${c("subjectId")} = ${e("id")}::text and ${c("user")} = ${creator}), '[]'::jsonb))`;
        })()
      : "";

  return `coalesce((
      select jsonb_agg(f.item order by f.starts)
      from (
        select ${eventJson(ctx, attendees)}${reminders} as item, ${e("startsAt")} as starts
        from ${events} e
        join ${calendars} k on ${k("id")} = ${e("calendar")}
        where ${where}
          and ${feedWindow(feed, e("startsAt"), e("endsAt"), recurrence.recurring("e."))}
          and ${visible}
        order by ${e("startsAt")}
        limit ${String(feed.limit)}
      ) f
    ), '[]'::jsonb)`;
}

export function feed(
  ctx: BlockSqlContext,
  events: string,
  calendars: string,
  attendees: string,
): string {
  if (!ctx.installed("share-links")) {
    return "";
  }

  const s = ctx.of("share-links");
  const links = s.table("links");
  const l = (column: string) => `l.${s.col("links", column)}`;
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  const features = calendarFeatures(ctx);
  const read = ctx.permission("read", moduleOperations("calendar").read);

  return `
-- The events of the calendar a share link points at, for an iCal feed. Open
-- to anon: the token is the credential, and it is hashed before the lookup.
-- The link's creator must still read the calendar, and each fetch counts as
-- a use of the link.
create or replace function ${ctx.fn("calendar_feed")}(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_tenant ${ctx.idType};
  v_calendar uuid;
  v_creator uuid;
begin
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select ${l("id")}, ${l("subjectId")}, ${l("tenant")}, ${l("createdBy")} into v_link, v_subject, v_tenant, v_creator
  from ${links} l
  where ${liveShareLink(s, "l", "calendar_feed.token", "'calendar'")}
  for update;
  if v_subject is null or v_subject !~* ${UUID} then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  if v_creator is null or not ${ctx.scope.canUser("v_creator", "v_tenant", read)}${
    features.access
      ? ` or not ${accessCall(ctx, "v_calendar", "read", "v_creator")}`
      : ""
  } then
    return null;
  end if;
  ${touchShareLink(s, "v_link")}
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', ${k("id")}, 'name', ${k("name")}, 'tz', ${k("tz")}),
      'events', ${feedEvents(ctx, events, calendars, attendees, `${k("id")} = v_calendar`, "v_creator")}
    )
    from ${calendars} k where ${k("id")} = v_calendar and ${k("tenant")} = v_tenant
  );
end;
$$;
revoke all on function ${ctx.fn("calendar_feed")}(text) from public;
grant execute on function ${ctx.fn("calendar_feed")}(text) to anon, authenticated, service_role;
${userFeed(ctx, events, calendars, attendees)}`;
}

function userFeed(
  ctx: BlockSqlContext,
  events: string,
  calendars: string,
  attendees: string,
): string {
  const features = calendarFeatures(ctx);

  if (!features.userFeed) {
    return "";
  }

  const s = ctx.of("share-links");
  const links = s.table("links");
  const l = (column: string) => `l.${s.col("links", column)}`;
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  const read = ctx.permission("read", moduleOperations("calendar").read);

  const readable = features.access
    ? accessCall(ctx, k("id"), "read", "v_user")
    : ctx.scope.canUser("v_user", k("tenant"), read);

  return `
-- Every calendar the user a share link names can read, with their events, as
-- one iCal feed. Open to anon: the token is the credential, and each fetch
-- counts as a use of the link.
create or replace function ${ctx.fn("calendar_user_feed")}(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_tenant ${ctx.idType};
  v_user uuid;
begin
  if calendar_user_feed.token is null or length(calendar_user_feed.token) < 32 then
    return null;
  end if;
  select ${l("id")}, ${l("subjectId")}, ${l("tenant")} into v_link, v_subject, v_tenant
  from ${links} l
  where ${liveShareLink(s, "l", "calendar_user_feed.token", "'calendar_user'")}
  for update;
  if v_subject is null or v_subject !~* ${UUID} then
    return null;
  end if;
  v_user := v_subject::uuid;
  if not ${ctx.scope.canUser("v_user", "v_tenant", read)} then
    return null;
  end if;
  ${touchShareLink(s, "v_link")}
  return jsonb_build_object(
    'userId', v_user,
    'calendars', coalesce((
      select jsonb_agg(jsonb_build_object('id', ${k("id")}, 'name', ${k("name")}, 'tz', ${k("tz")}) order by ${k("name")})
      from ${calendars} k
      where ${k("tenant")} = v_tenant and ${readable}
    ), '[]'::jsonb),
    'events', ${feedEvents(ctx, events, calendars, attendees, `${k("tenant")} = v_tenant and ${readable}`, "v_user")}
  );
end;
$$;
revoke all on function ${ctx.fn("calendar_user_feed")}(text) from public;
grant execute on function ${ctx.fn("calendar_user_feed")}(text) to anon, authenticated, service_role;
`;
}
