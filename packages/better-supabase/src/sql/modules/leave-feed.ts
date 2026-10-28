import type { BlockSqlContext } from "../context.ts";
import type { ShareLinkContribution } from "../contributions.ts";

import { feedDateWindow, feedOptions } from "../feed-options.ts";
import { moduleOperations } from "./permissions-model.ts";
import { liveShareLink, touchShareLink } from "./share-links.ts";

/** A type row's key: its key column, or its id without one. */
export const leaveTypeKey = (ctx: BlockSqlContext, row: string): string =>
  ctx.has("types", "key")
    ? `${row}.${ctx.col("types", "key")}`
    : `${row}.${ctx.col("types", "id")}::text`;

/**
 * A request row's part of the day: its partial column, or without one `hours`
 * for an hours type and `full` otherwise.
 */
export function leavePartial(ctx: BlockSqlContext, row: string): string {
  if (ctx.has("requests", "partial")) {
    return `${row}.${ctx.col("requests", "partial")}`;
  }

  const unit = ctx.label("types", "unit", `p.${ctx.col("types", "unit")}`);

  return `(select case when ${unit} = 'hours' then 'hours' else 'full' end from ${ctx.table("types")} p where p.${ctx.col("types", "id")} = ${row}.${ctx.col("requests", "type")})`;
}

/** The share-links subject of an organization's leave feed. */
const LEAVE_FEED_SUBJECT = "leave_feed";

const read = (ctx: BlockSqlContext): string =>
  ctx.permission("read", moduleOperations("leave").read);

/**
 * The `leave_feed` share-links subject: its id is the organization's id, and a
 * member who reads everyone's leave can share it.
 */
export function leaveFeedSubject(own: BlockSqlContext): ShareLinkContribution {
  return {
    subject: LEAVE_FEED_SUBJECT,
    exists: (subject) =>
      `(${subject.id} = ${subject.tenant}::text and ${own.scope.can(subject.tenant, read(own))})`,
    single: feedOptions(own, "blocks.leave.options").single,
  };
}

/**
 * `leave_feed(token)`: the approved leave of the organization a share link
 * points at, for an iCal feed. Open to anon: the token is the credential, and
 * the link's creator must still read everyone's leave.
 */
export function leaveFeed(ctx: BlockSqlContext): string {
  if (!ctx.installed("share-links")) {
    return "";
  }

  const s = ctx.of("share-links");
  const links = s.table("links");
  const l = (column: string): string => `l.${s.col("links", column)}`;
  const q = (column: string): string => `r.${ctx.col("requests", column)}`;
  const ty = (column: string): string => `t.${ctx.col("types", column)}`;
  const fn = ctx.fn("leave_feed");
  const feed = feedOptions(ctx, "blocks.leave.options");

  return `
-- The approved leave of the organization a share link points at, for an
-- iCal feed: a year back and everything ahead. Open to anon: the token is
-- the credential, and the link's creator must still read everyone's leave.
create or replace function ${fn}(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_tenant ${ctx.idType};
  v_creator uuid;
begin
  if leave_feed.token is null or length(leave_feed.token) < 32 then
    return null;
  end if;
  select ${l("id")}, ${l("tenant")}, ${l("createdBy")} into v_link, v_tenant, v_creator
  from ${links} l
  where ${liveShareLink(s, "l", "leave_feed.token", `'${LEAVE_FEED_SUBJECT}'`)} and ${l("subjectId")} = ${l("tenant")}::text
  for update;
  if v_tenant is null or v_creator is null or not ${ctx.scope.canUser("v_creator", "v_tenant", read(ctx))} then
    return null;
  end if;
  ${touchShareLink(s, "v_link")}
  return jsonb_build_object(
    'organizationId', v_tenant,
    'requests', coalesce((
      select jsonb_agg(x.item order by x.starts_on, x.id)
      from (
        select jsonb_build_object('id', ${q("id")}, 'userId', ${q("user")}, 'typeId', ${q("type")}, 'type', ${ty("name")}, 'unit', ${ty("unit")},
          'startsOn', ${q("startsOn")}, 'endsOn', ${q("endsOn")}, 'partial', ${leavePartial(ctx, "r")}, 'amount', ${q("amount")}::text, 'approvedAt', ${q("approvedAt")}, 'updatedAt', ${q("updatedAt")}) as item,
          ${q("startsOn")} as starts_on, ${q("id")} as id
        from ${ctx.table("requests")} r
        join ${ctx.table("types")} t on ${ty("id")} = ${q("type")}
        where ${q("tenant")} = v_tenant and ${q("approvedAt")} is not null and ${q("cancelledAt")} is null
          and ${feedDateWindow(feed, q("startsOn"), q("endsOn"))}
        order by ${q("startsOn")}, ${q("id")}
        limit ${String(feed.limit)}
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function ${fn}(text) from public;
grant execute on function ${fn}(text) to anon, authenticated, service_role;
`;
}
