import type { BlockSqlContext } from "../context.ts";

import {
  accessCall,
  calendarFeatures,
  eventAccessCall,
  recurrenceSql,
} from "./calendar-features.ts";
import { eventJson } from "./calendar-rows.ts";
import { moduleOperations } from "./permissions-model.ts";
import { liveShareLink } from "./share-links.ts";

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
  const recurrence = recurrenceSql(ctx);
  const access = features.access;

  return `
-- The events of the calendar a share link points at, for an iCal feed. Open
-- to anon: the token is the credential, and it is hashed before the lookup.
create or replace function ${ctx.fn("calendar_feed")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_subject text;
  v_tenant text;
  v_calendar uuid;${access ? "\n  v_creator uuid;" : ""}
begin
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select ${l("subjectId")}, ${l("tenant")}::text${access ? `, ${l("createdBy")}` : ""} into v_subject, v_tenant${access ? ", v_creator" : ""}
  from ${links} l
  where ${liveShareLink(s, "l", "calendar_feed.token", "'calendar'")};
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;${
    access
      ? `
  if v_creator is null or not ${accessCall(ctx, "v_calendar", "read", "v_creator")} then
    return null;
  end if;`
      : ""
  }
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', ${k("id")}, 'name', ${k("name")}, 'tz', ${k("tz")}),
      'events', coalesce((
        select jsonb_agg(${eventJson(ctx, attendees)} order by e.${ctx.col("events", "startsAt")})
        from ${events} e
        where e.${ctx.col("events", "calendar")} = v_calendar
          and (${recurrence.recurring("e.")} or e.${ctx.col("events", "endsAt")} > now() - interval '1 year')${access ? `\n          and ${eventAccessCall(ctx, `e.${ctx.col("events", "id")}`, "read", "v_creator")}` : ""}
      ), '[]'::jsonb)
    )
    from ${calendars} k where ${k("id")} = v_calendar and ${k("tenant")}::text = v_tenant
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
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const read = ctx.permission("read", moduleOperations("calendar").read);
  const recurrence = recurrenceSql(ctx);

  const readable = features.access
    ? accessCall(ctx, k("id"), "read", "v_user")
    : ctx.scope.canUser("v_user", k("tenant"), read);

  const visible = features.access
    ? eventAccessCall(ctx, e("id"), "read", "v_user")
    : "true";

  return `
-- Every calendar the user a share link names can read, with their events, as
-- one iCal feed. Open to anon: the token is the credential.
create or replace function ${ctx.fn("calendar_user_feed")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_subject text;
  v_tenant text;
  v_user uuid;
begin
  if calendar_user_feed.token is null or length(calendar_user_feed.token) < 32 then
    return null;
  end if;
  select ${l("subjectId")}, ${l("tenant")}::text into v_subject, v_tenant
  from ${links} l
  where ${liveShareLink(s, "l", "calendar_user_feed.token", "'calendar_user'")};
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_user := v_subject::uuid;
  return jsonb_build_object(
    'userId', v_user,
    'calendars', coalesce((
      select jsonb_agg(jsonb_build_object('id', ${k("id")}, 'name', ${k("name")}, 'tz', ${k("tz")}) order by ${k("name")})
      from ${calendars} k
      where ${k("tenant")}::text = v_tenant and ${readable}
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(${eventJson(ctx, attendees)} order by ${e("startsAt")})
      from ${events} e
      join ${calendars} k on ${k("id")} = ${e("calendar")}
      where ${k("tenant")}::text = v_tenant and ${readable}
        and (${recurrence.recurring("e.")} or ${e("endsAt")} > now() - interval '1 year')
        and ${visible}
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function ${ctx.fn("calendar_user_feed")}(text) from public;
grant execute on function ${ctx.fn("calendar_user_feed")}(text) to anon, authenticated, service_role;
`;
}
