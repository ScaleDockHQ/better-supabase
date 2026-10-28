import type { BlockSqlContext } from "../context.ts";
import type { ShareLinkContribution } from "../contributions.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { feedDateWindow, feedOptions } from "../feed-options.ts";
import { extraFieldsJson } from "../shared.ts";
import { leaveByEmployee, leavePartsMapped } from "./leave-owner.ts";
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

  if (leavePartsMapped(ctx)) {
    const start = `${row}.${ctx.col("requests", "startPart")}::text`;
    const end = `${row}.${ctx.col("requests", "endPart")}::text`;
    const single = `${row}.${ctx.col("requests", "startsOn")} = ${row}.${ctx.col("requests", "endsOn")}`;

    return `(case when ${start} = 'hours' or ${end} = 'hours' then 'hours' when ${single} and ${start} = 'afternoon' then 'afternoon' when ${single} and ${end} = 'morning' then 'morning' else 'full' end)`;
  }

  const unit = ctx.label("types", "unit", `p.${ctx.col("types", "unit")}`);

  return `(select case when ${unit} = 'hours' then 'hours' else 'full' end from ${ctx.table("types")} p where p.${ctx.col("types", "id")} = ${row}.${ctx.col("requests", "type")})`;
}

export function leaveStartPart(ctx: BlockSqlContext, row: string): string {
  return leavePartsMapped(ctx)
    ? `${row}.${ctx.col("requests", "startPart")}::text`
    : `(case ${leavePartial(ctx, row)} when 'afternoon' then 'afternoon' when 'hours' then 'hours' else 'full' end)`;
}

export function leaveEndPart(ctx: BlockSqlContext, row: string): string {
  return leavePartsMapped(ctx)
    ? `${row}.${ctx.col("requests", "endPart")}::text`
    : `(case ${leavePartial(ctx, row)} when 'morning' then 'morning' when 'hours' then 'hours' else 'full' end)`;
}

export function leaveRequestUser(ctx: BlockSqlContext, row: string): string {
  if (ctx.has("requests", "user") || !leaveByEmployee(ctx)) {
    return `${row}.${ctx.col("requests", "user")}`;
  }

  const staff = ctx.of("employees");

  return `(select y.${staff.col("employees", "user")} from ${staff.table("employees")} y where y.${staff.col("employees", "id")} = ${row}.${ctx.col("requests", "employee")})`;
}

/** The share-links subject of an organization's leave feed. */
const LEAVE_FEED_SUBJECT = "leave_feed";

/** The share-links subject of one team's leave feed; its id is the team's. */
const LEAVE_TEAM_FEED_SUBJECT = "leave_team_feed";

const FEED_WHERE = "blocks.leave.options.feed";

/** What `options.feed` adds for leave on top of the share-link feed options. */
interface LeaveFeedExtras {
  /** Each entry carries the employee's name. */
  readonly names: boolean;
  /** Type keys whose name the feed leaves out. */
  readonly hideTypes: readonly string[];
  /** A `leave_team_feed` link shares one team's leave. */
  readonly teams: boolean;
  /** Each entry carries the request's extra columns. */
  readonly fields: boolean;
}

function leaveFeedExtras(ctx: BlockSqlContext): LeaveFeedExtras {
  const raw = ctx.option("feed") ?? {};
  const feed = isRecord(raw) ? raw : {};
  const { names = false, hideTypes = [], teams = false, fields = false } = feed;

  for (const [key, value] of Object.entries({ names, teams, fields })) {
    if (typeof value !== "boolean") {
      throw new TypeError(`${FEED_WHERE}.${key} is a boolean`);
    }
  }

  if (
    !Array.isArray(hideTypes) ||
    !hideTypes.every((key) => typeof key === "string")
  ) {
    throw new TypeError(`${FEED_WHERE}.hideTypes is a list of type keys`);
  }

  if (names === true && !ctx.installed("employees")) {
    throw new TypeError(`${FEED_WHERE}.names needs the employees block`);
  }

  if (teams === true && !ctx.installed("teams")) {
    throw new TypeError(`${FEED_WHERE}.teams needs the teams block`);
  }

  return {
    names: names === true,
    hideTypes,
    teams: teams === true,
    fields: fields === true,
  };
}

/** The employee name of request row `row`. */
function employeeName(ctx: BlockSqlContext, row: string): string {
  const staff = ctx.of("employees");
  const y = (column: string): string => `y.${staff.col("employees", column)}`;

  return leaveByEmployee(ctx)
    ? `(select ${y("name")} from ${staff.table("employees")} y where ${y("id")} = ${row}.${ctx.col("requests", "employee")})`
    : `(select ${y("name")} from ${staff.table("employees")} y where ${y("tenant")} = ${row}.${ctx.col("requests", "tenant")} and ${y("user")} = ${row}.${ctx.col("requests", "user")} limit 1)`;
}

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
 * The `leave_team_feed` subject with `options.feed.teams`: its id is a team of
 * the organization, and a member who reads everyone's leave can share it.
 */
export function leaveTeamFeedSubject(
  own: BlockSqlContext,
): readonly ShareLinkContribution[] {
  if (!leaveFeedExtras(own).teams) {
    return [];
  }

  const teams = own.of("teams");
  const t = (column: string): string => `t.${teams.col("teams", column)}`;

  return [
    {
      subject: LEAVE_TEAM_FEED_SUBJECT,
      exists: (subject) =>
        `(exists (select 1 from ${teams.table("teams")} t where ${t("id")}::text = ${subject.id} and ${t("tenant")} = ${subject.tenant}) and ${own.scope.can(subject.tenant, read(own))})`,
      single: feedOptions(own, "blocks.leave.options").single,
    },
  ];
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
  const extras = leaveFeedExtras(ctx);
  const teams = extras.teams ? ctx.of("teams") : undefined;

  const subjects = [
    LEAVE_FEED_SUBJECT,
    ...(teams === undefined ? [] : [LEAVE_TEAM_FEED_SUBJECT]),
  ];

  const typeName =
    extras.hideTypes.length === 0
      ? ty("name")
      : `case when ${leaveTypeKey(ctx, "t")} = any (${sqlString(`{${extras.hideTypes.join(",")}}`)}::text[]) then null else ${ty("name")} end`;

  const teamFilter =
    teams === undefined
      ? ""
      : `
          and (v_team is null or ${leaveRequestUser(ctx, "r")} in (select m.${teams.col("members", "user")} from ${teams.table("members")} m where m.${teams.col("members", "team")}::text = v_team))`;

  return `
-- The approved leave of the organization or team a share link points at,
-- for an iCal feed: a year back and everything ahead. Open to anon: the
-- token is the credential, and the link's creator must still read
-- everyone's leave.
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
  v_team text;
begin
  if leave_feed.token is null or length(leave_feed.token) < 32 then
    return null;
  end if;
  select ${l("id")}, ${l("tenant")}, ${l("createdBy")}, case when ${l("subjectType")} = '${LEAVE_TEAM_FEED_SUBJECT}' then ${l("subjectId")} end
  into v_link, v_tenant, v_creator, v_team
  from ${links} l
  where ${liveShareLink(s, "l", "leave_feed.token", `any (array[${subjects.map((subject) => `'${subject}'`).join(", ")}])`)}
    and (${l("subjectType")} <> '${LEAVE_FEED_SUBJECT}' or ${l("subjectId")} = ${l("tenant")}::text)
  for update;
  if v_tenant is null or v_creator is null or not ${ctx.scope.canUser("v_creator", "v_tenant", read(ctx))} then
    return null;
  end if;
  ${touchShareLink(s, "v_link")}
  return jsonb_build_object(
    'organizationId', v_tenant,${teams === undefined ? "" : "\n    'teamId', v_team,"}
    'requests', coalesce((
      select jsonb_agg(x.item order by x.starts_on, x.id)
      from (
        select jsonb_build_object('id', ${q("id")}, 'userId', ${leaveRequestUser(ctx, "r")}${leaveByEmployee(ctx) ? `, 'employeeId', ${q("employee")}` : ""}, ${extras.names ? `'name', ${employeeName(ctx, "r")}, ` : ""}'typeId', ${q("type")}, 'type', ${typeName}, 'unit', ${ty("unit")},
          'startsOn', ${q("startsOn")}, 'endsOn', ${q("endsOn")}, 'partial', ${leavePartial(ctx, "r")}, 'startPart', ${leaveStartPart(ctx, "r")}, 'endPart', ${leaveEndPart(ctx, "r")}, 'amount', ${q("amount")}::text, 'approvedAt', ${q("approvedAt")}, 'updatedAt', ${q("updatedAt")}${extras.fields ? extraFieldsJson("r", ctx.extraColumns("requests", ["fields"])) : ""}) as item,
          ${q("startsOn")} as starts_on, ${q("id")} as id
        from ${ctx.table("requests")} r
        join ${ctx.table("types")} t on ${ty("id")} = ${q("type")}
        where ${q("tenant")} = v_tenant and ${q("approvedAt")} is not null and ${q("cancelledAt")} is null
          and ${feedDateWindow(feed, q("startsOn"), q("endsOn"))}${teamFilter}
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
