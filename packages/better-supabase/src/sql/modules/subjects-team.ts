import type { SubjectsEvents } from "../../blocks/subjects/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlTableSpec,
} from "../context.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { DEFAULT_RECORD_TEAM_ROLES } from "../../blocks/subjects/options.ts";
import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  pageSize,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { registeredIdMatches, teamActions } from "../subject-registry.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { teamIdType } from "./teams.ts";

export const RECORD_TEAM_EVENTS: BlockSqlEvents<SubjectsEvents> = {
  "subject_member.added": {
    subject: "subjects",
    payload: [
      "organizationId",
      "id",
      "subjectType",
      "subjectId",
      "userId",
      "teamId",
      "role",
      "endsOn",
    ],
  },
  "subject_member.ended": {
    subject: "subjects",
    payload: [
      "organizationId",
      "id",
      "subjectType",
      "subjectId",
      "userId",
      "teamId",
      "role",
      "endsOn",
    ],
  },
};

export const SUBJECT_MEMBERS_TABLE: BlockSqlTableSpec = {
  name: "subject_members",
  app: {},
  lifecycle: { tenant: "tenant", user: "user", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    subjectType: "subject_type",
    subjectId: "subject_id",
    user: "user_id",
    team: "team_id",
    role: "role",
    startsOn: "starts_on",
    endsOn: "ends_on",
    endsAt: "ends_at",
    emergency: "emergency",
    reason: "reason",
    createdBy: "created_by",
    createdAt: "created_at",
  },
  optional: ["endsAt"],
};

/** The most rows one `my_subjects` call returns. */
const MAX_MY_SUBJECTS = 200;

const ROLE = /^[a-z][a-z0-9_-]{0,62}$/;

/** `blocks.subjects.options.recordTeam.roles`, checked. */
export function recordTeamRoles(ctx: BlockSqlContext): readonly string[] {
  const raw = ctx.option("recordTeam");

  if (raw === undefined) {
    return DEFAULT_RECORD_TEAM_ROLES;
  }

  const roles: unknown = isRecord(raw) ? raw["roles"] : undefined;

  if (isRecord(raw) && roles === undefined) {
    return DEFAULT_RECORD_TEAM_ROLES;
  }

  if (
    !Array.isArray(roles) ||
    roles.length === 0 ||
    roles.some((role) => typeof role !== "string" || !ROLE.test(role))
  ) {
    throw new TypeError(
      'blocks.subjects.options.recordTeam.roles must be a non-empty list of lowercase role names, such as ["lead", "member"]',
    );
  }

  return roles.filter((role): role is string => typeof role === "string");
}

/** The subject types whose records have a team (`subjects.<type>.team`). */
function teamSubjects(
  subjects: readonly RegisteredSubject[],
): readonly RegisteredSubject[] {
  return subjects.filter((subject) => teamActions(subject).length > 0);
}

/** The teams module's context when it renders its tables, else `undefined`. */
function teamsOf(ctx: BlockSqlContext): BlockSqlContext | undefined {
  return ctx.installed("teams") && ctx.of("teams").mode !== "custom"
    ? ctx.of("teams")
    : undefined;
}

/** The `team_id` column type: the teams block's id type, uuid without it. */
function teamType(ctx: BlockSqlContext): string {
  const teams = teamsOf(ctx);

  return teams === undefined ? "uuid" : teamIdType(teams);
}

/**
 * Row `m` of `subject_members` counts for `user` today: their own row or one
 * for a team they are on, with dates that include today.
 */
export function activeFor(
  ctx: BlockSqlContext,
  user: string,
  through: "table" | "caller",
  alias = "m",
): string {
  const c = (column: string): string =>
    `${alias}.${ctx.col("members", column)}`;

  return `(${c("user")} = ${user}${viaTeam(ctx, c("team"), user, through)})
        and ${datesInclude(ctx, alias)}`;
}

/** Row `alias` of `subject_members` counts now: its days and its end time. */
function datesInclude(ctx: BlockSqlContext, alias: string): string {
  const c = (column: string): string =>
    `${alias}.${ctx.col("members", column)}`;

  const endsAt = ctx.has("members", "endsAt")
    ? `\n        and (${c("endsAt")} is null or ${c("endsAt")} > now())`
    : "";

  return `(${c("startsOn")} is null or ${c("startsOn")} <= current_date)
        and (${c("endsOn")} is null or ${c("endsOn")} >= current_date)${endsAt}`;
}

/** The role a lead holds: `lead`, else the first of `recordTeam.roles`. */
export function leadRole(roles: readonly string[]): string {
  return roles.includes("lead") ? "lead" : (roles[0] ?? "lead");
}

/** The role an approved request adds: `member`, else the last role. */
function memberRole(roles: readonly string[]): string {
  return roles.includes("member") ? "member" : (roles.at(-1) ?? "member");
}

/**
 * ` or <team> is one of user's teams`, empty without the teams block. `table`
 * reads team_members directly, for security definer code; `caller` goes through
 * team_ids_of, which reads past the teams policies for the caller only.
 */
function viaTeam(
  ctx: BlockSqlContext,
  team: string,
  user: string,
  through: "table" | "caller",
): string {
  const teams = teamsOf(ctx);

  if (teams === undefined) {
    return "";
  }

  return through === "caller"
    ? ` or (${team} is not null and ${team} in (select ${teams.fn("team_ids_of")}(${user})))`
    : ` or (${team} is not null and exists (
          select 1 from ${teams.table("members")} tm
          where tm.${teams.col("members", "team")} = ${team}
            and tm.${teams.col("members", "user")} = ${user}))`;
}

/**
 * `user` is on the team of row `s` of `subject` today; `undefined` when
 * `action` isn't one of the type's team actions.
 */
export function teamGrantFor(
  ctx: BlockSqlContext,
  subject: RegisteredSubject,
  action: string,
  user: string,
): string | undefined {
  if (!teamActions(subject).includes(action) || subject.tenant === undefined) {
    return undefined;
  }

  const c = (column: string): string => `m.${ctx.col("members", column)}`;

  return `exists (
            select 1 from ${ctx.table("members")} m
            where ${c("subjectType")} = ${sqlString(subject.type)}
              and ${c("subjectId")} = s.${subject.id}::text
              and ${c("tenant")} = s.${subject.tenant}
              and ${activeFor(ctx, user, "table")})`;
}

/**
 * The caller is on the team of row `s` today, through `is_subject_member`;
 * `undefined` when `action` isn't one of the type's team actions.
 */
export function teamGrant(
  ctx: BlockSqlContext,
  subject: RegisteredSubject,
  action: string,
): string | undefined {
  return teamActions(subject).includes(action)
    ? `${ctx.fn("is_subject_member")}(${sqlString(subject.type)}, s.${subject.id}::text)`
    : undefined;
}

/** `subject_members` and `is_subject_member`, before `can_subject`. */
export function recordTeamTable(ctx: BlockSqlContext): string {
  const t = ctx.table("members");
  const c = (column: string): string => ctx.col("members", column);
  const fn = (name: string): string => ctx.fn(name);
  const teams = teamsOf(ctx);
  const rename = (name: string): string => ctx.naming.rename(name);

  const teamRef =
    teams === undefined
      ? ""
      : ` references ${teams.table("teams")} (${teams.col("teams", "id")}) on delete cascade`;

  const table = ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("user")} uuid references auth.users (id) on delete cascade,
  ${c("team")} ${teamType(ctx)}${teamRef},
  ${c("role")} text not null default 'member',
  ${c("startsOn")} date,
  ${c("endsOn")} date,${ctx.has("members", "endsAt") ? `\n  ${c("endsAt")} timestamptz,` : ""}
  ${c("emergency")} boolean not null default false,
  ${c("reason")} text,
  ${c("createdBy")} uuid default auth.uid(),
  ${c("createdAt")} timestamptz not null default now(),
  constraint ${rename("subject_members_one_member")} check ((${c("user")} is null) <> (${c("team")} is null)),
  constraint ${rename("subject_members_dates")} check (${c("endsOn")} is null or ${c("startsOn")} is null or ${c("endsOn")} >= ${c("startsOn")})
);
create unique index if not exists ${rename("subject_members_user_key")} on ${t} (${c("subjectType")}, ${c("subjectId")}, ${c("user")}, ${c("role")}) where ${c("user")} is not null;
create unique index if not exists ${rename("subject_members_team_key")} on ${t} (${c("subjectType")}, ${c("subjectId")}, ${c("team")}, ${c("role")}) where ${c("team")} is not null;
create index if not exists ${rename("subject_members_user_idx")} on ${t} (${c("user")}, ${c("tenant")});
create index if not exists ${rename("subject_members_team_idx")} on ${t} (${c("team")});
${ctx.has("members", "endsAt") ? `alter table ${t} add column if not exists ${c("endsAt")} timestamptz;\n` : ""}${lockTable(t, { read: true })}
`
    : "";

  return `
-- Record teams (subjects.<type>.team, ADR 0134): the users and teams on one
-- record, each with a role and the days the membership counts.
${table}
-- Whether the caller is on the record's team today, directly or through a
-- team. Reads past the table's policies; it answers for the caller only.
create or replace function ${fn("is_subject_member")}(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  return exists (
    select 1 from ${t} m
    where m.${c("subjectType")} = is_subject_member.subject_type
      and m.${c("subjectId")} = is_subject_member.subject_id
      and ${activeFor(ctx, "auth.uid()", "caller")}
  );
end;
$$;
${userGrant(`${fn("is_subject_member")}(text, text)`)}

-- Whether the caller is on the record's team today in one of roles, for a
-- read rule that only some roles pass. The caller only, like
-- is_subject_member.
create or replace function ${fn("has_subject_role")}(subject_type text, subject_id text, roles text[])
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(cardinality(has_subject_role.roles), 0) = 0 then
    return false;
  end if;
  return exists (
    select 1 from ${t} m
    where m.${c("subjectType")} = has_subject_role.subject_type
      and m.${c("subjectId")} = has_subject_role.subject_id
      and m.${c("role")} = any (has_subject_role.roles)
      and ${activeFor(ctx, "auth.uid()", "caller")}
  );
end;
$$;
${userGrant(`${fn("has_subject_role")}(text, text, text[])`)}
`;
}

/** The row `s` of `subject` is `id` and, with `deletedAt`, not deleted. */
function live(subject: RegisteredSubject, id: string): string {
  const match = registeredIdMatches(subject, id);

  return subject.config.deletedAt === undefined
    ? match
    : `${match} and s.${sqlIdent(subject.config.deletedAt)} is null`;
}

/**
 * The record team's policy and functions, after `can_subject`: the read policy
 * calls it, and the write functions ask it for `manage`.
 */
export function recordTeamSql(
  ctx: BlockSqlContext,
  subjects: readonly RegisteredSubject[],
): string {
  const t = ctx.table("members");
  const c = (column: string): string => ctx.col("members", column);
  const fn = (name: string): string => ctx.fn(name);
  const teams = teamsOf(ctx);
  const roles = recordTeamRoles(ctx);
  const withTeam = teamSubjects(subjects);
  const manage = ctx.permission("manage", OPERATIONS["subjects.manage"]);
  const team = teamType(ctx);

  const types = `array[${withTeam.map((subject) => sqlString(subject.type)).join(", ")}]::text[]`;

  const declaresManage = withTeam.filter(
    (subject) =>
      teamActions(subject).includes("manage") ||
      Object.hasOwn(subject.config.permissions ?? {}, "manage"),
  );

  const manageTypes = `array[${declaresManage.map((subject) => sqlString(subject.type)).join(", ")}]::text[]`;

  const allowed = (type: string, id: string, tenant: string): string =>
    `(${SERVICE_CALLER}
      or ${ctx.scope.can(tenant, manage)}
      or (${type} = any (${manageTypes}) and coalesce(${fn("can_subject")}(${type}, ${id}, 'manage'), false)))`;

  const tenantLookup =
    withTeam.length === 0
      ? "    when '' then null;"
      : withTeam
          .map(
            (subject) => `    when ${sqlString(subject.type)} then
      select s.${subject.tenant!} into v_tenant from ${subject.qualified} s
      where ${live(subject, "add_subject_member.subject_id")};`,
          )
          .join("\n");

  const memberJson = (alias: string): string => {
    const a = (column: string): string => `${alias}.${c(column)}`;

    return `jsonb_build_object(
      'id', ${a("id")}, 'organizationId', ${a("tenant")},
      'subjectType', ${a("subjectType")}, 'subjectId', ${a("subjectId")},
      'userId', ${a("user")}, 'teamId', ${a("team")}, 'role', ${a("role")},
      'startsOn', ${a("startsOn")}, 'endsOn', ${a("endsOn")},${ctx.has("members", "endsAt") ? ` 'endsAt', ${a("endsAt")},` : ""}
      'emergency', ${a("emergency")}, 'reason', ${a("reason")},
      'active', ${datesInclude(ctx, alias)},
      'createdBy', ${a("createdBy")}, 'createdAt', ${a("createdAt")})`;
  };

  const record = (type: keyof typeof RECORD_TEAM_EVENTS, row: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'id', ${row}.${c("id")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'userId', ${row}.${c("user")}, 'teamId', ${row}.${c("team")}, 'role', ${row}.${c("role")}, 'endsOn', ${row}.${c("endsOn")})`,
      subject: `'subjects/' || ${row}.${c("subjectType")} || '/' || ${row}.${c("subjectId")}`,
      tenant: `${row}.${c("tenant")}`,
      audit: {
        category: "access",
        targetType: "subject_member",
        recordId: `${row}.${c("id")}::text`,
      },
    });

  const memberships = ctx.installed("memberships")
    ? ctx.of("memberships")
    : undefined;

  const userCheck =
    memberships === undefined
      ? ""
      : `
  if add_subject_member.user_id is not null and not exists (
    select 1 from ${memberships.table("memberships")} om
    where om.${memberships.col("memberships", "tenant")} = v_tenant
      and om.${memberships.col("memberships", "user")} = add_subject_member.user_id
  ) then
    ${fail("SUBJECT_MEMBER_INVALID", "user is not a member of the record's tenant", "22023")}
  end if;`;

  const teamCheck =
    teams === undefined
      ? `
  if add_subject_member.team_id is not null then
    ${fail("SUBJECT_MEMBER_INVALID", "a team needs the teams block", "22023")}
  end if;`
      : `
  if add_subject_member.team_id is not null and not exists (
    select 1 from ${teams.table("teams")} tt
    where tt.${teams.col("teams", "id")} = add_subject_member.team_id
      and tt.${teams.col("teams", "tenant")} = v_tenant
  ) then
    ${fail("SUBJECT_MEMBER_INVALID", "team is not in the record's tenant", "22023")}
  end if;`;

  const teamOfCaller = viaTeam(ctx, c("team"), "(select auth.uid())", "caller");

  return `
-- A caller reads their own record team rows, those of their teams, every row
-- of a tenant where they hold subjects.manage, and the team of a record they
-- can read.
${renderPolicy(
  makePolicy({
    table: t,
    name: ctx.naming.rename("subject_members_read"),
    command: "select",
    roles: ["authenticated"],
    using: `${c("user")} = (select auth.uid())${teamOfCaller}
    or ${c("tenant")} in (select ${ctx.scope.ids(manage)})
    or coalesce(${fn("can_subject")}(${c("subjectType")}, ${c("subjectId")}, 'read'), false)`,
  }),
  { drop: true, target: t },
)}

-- Puts a user or a team on a record's team, or reopens their membership in
-- that role with the new dates. Needs subjects.manage in the record's tenant,
-- or can_subject(..., 'manage') on a type that declares a manage action.
create or replace function ${fn("add_subject_member")}(subject_type text, subject_id text, user_id uuid default null, team_id ${team} default null, role text default 'member', starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_row ${t};
begin
  if not (add_subject_member.subject_type = any (${types})) then
    ${fail("SUBJECT_MEMBER_INVALID", "this subject type has no record team (subjects.<type>.team)", "22023")}
  end if;
  if (add_subject_member.user_id is null) = (add_subject_member.team_id is null) then
    ${fail("SUBJECT_MEMBER_INVALID", "pass exactly one of user_id and team_id", "22023")}
  end if;
  if add_subject_member.role is null or not (add_subject_member.role = any (${sqlString(`{${roles.join(",")}}`)}::text[])) then
    ${fail("SUBJECT_MEMBER_INVALID", `role must be one of ${roles.join(", ")}`, "22023")}
  end if;
  if add_subject_member.ends_on < add_subject_member.starts_on then
    ${fail("SUBJECT_MEMBER_INVALID", "ends_on is before starts_on", "22023")}
  end if;
  begin
    case add_subject_member.subject_type
${tenantLookup}
      else
        v_tenant := null;
    end case;
  exception
    when invalid_text_representation then
      ${fail("SUBJECT_MEMBER_INVALID", "the subject id does not match its type's id column", "22023")}
  end;
  if v_tenant is null then
    ${fail("SUBJECT_MEMBER_NOT_FOUND", "subject not found", "P0002")}
  end if;
  if not ${allowed("add_subject_member.subject_type", "add_subject_member.subject_id", "v_tenant")} then
    ${fail("SUBJECT_MEMBER_FORBIDDEN", "not allowed to manage this record's team")}
  end if;${userCheck}${teamCheck}
  if add_subject_member.user_id is not null then
    insert into ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("user")}, ${c("role")}, ${c("startsOn")}, ${c("endsOn")}, ${c("createdBy")})
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.user_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict (${c("subjectType")}, ${c("subjectId")}, ${c("user")}, ${c("role")}) where ${c("user")} is not null
    do update set ${c("startsOn")} = excluded.${c("startsOn")}, ${c("endsOn")} = excluded.${c("endsOn")}
    returning * into v_row;
  else
    insert into ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("team")}, ${c("role")}, ${c("startsOn")}, ${c("endsOn")}, ${c("createdBy")})
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.team_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict (${c("subjectType")}, ${c("subjectId")}, ${c("team")}, ${c("role")}) where ${c("team")} is not null
    do update set ${c("startsOn")} = excluded.${c("startsOn")}, ${c("endsOn")} = excluded.${c("endsOn")}
    returning * into v_row;
  end if;
  ${record("subject_member.added", "v_row")}
  return ${memberJson("v_row")};
end;
$$;
${userGrant(`${fn("add_subject_member")}(text, text, uuid, ${team}, text, date, date)`)}

-- Ends a membership: it counts through ends_on (today by default), so access
-- stops the next day. The same callers as add_subject_member.
create or replace function ${fn("end_subject_member")}(member_id uuid, ends_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} m where m.${c("id")} = end_subject_member.member_id;
  if not found then
    ${fail("SUBJECT_MEMBER_NOT_FOUND", "record team member not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${c("subjectType")}`, `v_row.${c("subjectId")}`, `v_row.${c("tenant")}`)} then
    ${fail("SUBJECT_MEMBER_FORBIDDEN", "not allowed to manage this record's team")}
  end if;
  if end_subject_member.ends_on is null or end_subject_member.ends_on < v_row.${c("startsOn")} then
    ${fail("SUBJECT_MEMBER_INVALID", "ends_on is missing or before starts_on", "22023")}
  end if;
  update ${t} m set ${c("endsOn")} = end_subject_member.ends_on
  where m.${c("id")} = end_subject_member.member_id
  returning * into v_row;
  ${record("subject_member.ended", "v_row")}
  return ${memberJson("v_row")};
end;
$$;
${userGrant(`${fn("end_subject_member")}(uuid, date)`)}

-- The record's team, current and past, for a caller who can read the record
-- (the table's policy decides). Leads first, then by when they joined.
create or replace function ${fn("list_subject_members")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${memberJson("m")}
    order by m.${c("role")}, m.${c("createdAt")}, m.${c("id")}), '[]'::jsonb)
  from ${t} m
  where m.${c("subjectType")} = list_subject_members.subject_type
    and m.${c("subjectId")} = list_subject_members.subject_id;
$$;
${userGrant(`${fn("list_subject_members")}(text, text)`)}

-- The records whose team the caller is on today in tenant, by type and id,
-- with their roles, a page at a time: cursor is the last item's
-- "<type>:<id>", and nextCursor is null on the last page.
create or replace function ${fn("my_subjects")}(tenant ${ctx.idType}, subject_type text default null, page_size integer default 100, cursor text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_size integer := ${pageSize("my_subjects.page_size", 100, MAX_MY_SUBJECTS)};
  v_after_type text := split_part(my_subjects.cursor, ':', 1);
  v_after_id text := substr(my_subjects.cursor, length(split_part(my_subjects.cursor, ':', 1)) + 2);
  v_items jsonb;
  v_count integer;
begin
  if v_me is null then
    return jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', p.subject_type, 'subjectId', p.subject_id,
      'organizationId', p.tenant, 'roles', p.roles, 'endsOn', p.ends_on,
      'emergency', p.emergency,
      'title', ${fn("subject_title")}(p.subject_type, p.subject_id),
      'url', ${fn("subject_url")}(p.subject_type, p.subject_id))
    order by p.subject_type, p.subject_id), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select m.${c("subjectType")} as subject_type, m.${c("subjectId")} as subject_id,
      min(m.${c("tenant")}::text) as tenant,
      jsonb_agg(distinct m.${c("role")}) as roles,
      case when bool_or(m.${c("endsOn")} is null) then null else max(m.${c("endsOn")}) end as ends_on,
      bool_or(m.${c("emergency")}) as emergency
    from ${t} m
    where m.${c("tenant")} = my_subjects.tenant
      and (my_subjects.subject_type is null or m.${c("subjectType")} = my_subjects.subject_type)
      and (my_subjects.cursor is null
        or (m.${c("subjectType")}, m.${c("subjectId")}) > (v_after_type, v_after_id))
      and ${activeFor(ctx, "v_me", "caller")}
    group by m.${c("subjectType")}, m.${c("subjectId")}
    order by m.${c("subjectType")}, m.${c("subjectId")}
    limit v_size
  ) p;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_size
      then (v_items -> -1 ->> 'subjectType') || ':' || (v_items -> -1 ->> 'subjectId')
      else null end);
end;
$$;
${userGrant(`${fn("my_subjects")}(${ctx.idType}, text, integer, text)`)}
${recordAccessSql(ctx, withTeam, roles, record)}`;
}

/**
 * What access requests (ADR 0134) use to time-box team rows: the record's
 * tenant, its leads, and the grants it opens and closes. Granted to nobody, so
 * only security definer code of another module calls them. Empty without the
 * `endsAt` column, which an adopted table may leave out.
 */
function recordAccessSql(
  ctx: BlockSqlContext,
  withTeam: readonly RegisteredSubject[],
  roles: readonly string[],
  record: (type: keyof typeof RECORD_TEAM_EVENTS, row: string) => string,
): string {
  if (!ctx.has("members", "endsAt")) {
    return "";
  }

  const t = ctx.table("members");
  const c = (column: string): string => ctx.col("members", column);
  const fn = (name: string): string => ctx.fn(name);
  const teams = teamsOf(ctx);
  const lead = sqlString(leadRole(roles));
  const member = sqlString(memberRole(roles));

  const lookup =
    withTeam.length === 0
      ? "    when '' then null;"
      : withTeam
          .map(
            (subject) => `    when ${sqlString(subject.type)} then
      select s.${subject.tenant!} into v_tenant from ${subject.qualified} s
      where ${live(subject, "record_team_tenant.subject_id")};`,
          )
          .join("\n");

  const onRecord = (alias: string, fnName: string): string =>
    `${alias}.${c("subjectType")} = ${fnName}.subject_type
      and ${alias}.${c("subjectId")} = ${fnName}.subject_id`;

  const teamLeads =
    teams === undefined
      ? ""
      : `
    union
    select tm.${teams.col("members", "user")} from ${t} m
    join ${teams.table("members")} tm on tm.${teams.col("members", "team")} = m.${c("team")}
    where ${onRecord("m", "record_team_leads")}
      and m.${c("role")} = ${lead} and ${datesInclude(ctx, "m")}`;

  return `
-- The tenant of a record whose type has a team; null for another type or a
-- missing row.
create or replace function ${fn("record_team_tenant")}(subject_type text, subject_id text)
returns ${ctx.idType}
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  case record_team_tenant.subject_type
${lookup}
    else
      v_tenant := null;
  end case;
  return v_tenant;
exception
  when invalid_text_representation then
    return null;
end;
$$;
revoke execute on function ${fn("record_team_tenant")}(text, text) from public, anon, authenticated;

-- The users who lead a record's team today, directly or through a team.
create or replace function ${fn("record_team_leads")}(subject_type text, subject_id text)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct l.id), '{}'::uuid[])
  from (
    select m.${c("user")} as id from ${t} m
    where ${onRecord("m", "record_team_leads")}
      and m.${c("role")} = ${lead} and m.${c("user")} is not null
      and ${datesInclude(ctx, "m")}${teamLeads}
  ) l;
$$;
revoke execute on function ${fn("record_team_leads")}(text, text) from public, anon, authenticated;

-- Puts a user on a record's team until ends_at, for an approved request or an
-- emergency. A membership that already counts without an end is left alone,
-- and the result is null, so ending the request never closes it.
create or replace function ${fn("grant_subject_member")}(subject_type text, subject_id text, user_id uuid, ends_at timestamptz, emergency boolean, reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType} := ${fn("record_team_tenant")}(grant_subject_member.subject_type, grant_subject_member.subject_id);
  v_row ${t};
begin
  if v_tenant is null then
    ${fail("SUBJECT_MEMBER_NOT_FOUND", "subject not found", "P0002")}
  end if;
  select * into v_row from ${t} m
  where ${onRecord("m", "grant_subject_member")}
    and m.${c("user")} = grant_subject_member.user_id and m.${c("role")} = ${member}
    and m.${c("endsOn")} is null and m.${c("endsAt")} is null and ${datesInclude(ctx, "m")};
  if found then
    return null;
  end if;
  insert into ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("user")}, ${c("role")}, ${c("endsOn")}, ${c("endsAt")}, ${c("emergency")}, ${c("reason")}, ${c("createdBy")})
  values (v_tenant, grant_subject_member.subject_type, grant_subject_member.subject_id, grant_subject_member.user_id, ${member}, grant_subject_member.ends_at::date, grant_subject_member.ends_at, coalesce(grant_subject_member.emergency, false), grant_subject_member.reason, auth.uid())
  on conflict (${c("subjectType")}, ${c("subjectId")}, ${c("user")}, ${c("role")}) where ${c("user")} is not null
  do update set ${c("startsOn")} = null, ${c("endsOn")} = excluded.${c("endsOn")}, ${c("endsAt")} = excluded.${c("endsAt")},
    ${c("emergency")} = excluded.${c("emergency")}, ${c("reason")} = excluded.${c("reason")}
  returning * into v_row;
  ${record("subject_member.added", "v_row")}
  return v_row.${c("id")};
end;
$$;
revoke execute on function ${fn("grant_subject_member")}(text, text, uuid, timestamptz, boolean, text) from public, anon, authenticated;

-- Ends a granted membership now, when its request ends early.
create or replace function ${fn("close_subject_member")}(member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  update ${t} m set ${c("endsAt")} = now()
  where m.${c("id")} = close_subject_member.member_id
    and (m.${c("endsAt")} is null or m.${c("endsAt")} > now())
  returning * into v_row;
  if found then
    ${record("subject_member.ended", "v_row")}
  end if;
end;
$$;
revoke execute on function ${fn("close_subject_member")}(uuid) from public, anon, authenticated;
`;
}

export function recordTeamContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const team = teamType(ctx);

  return [
    { name: "is_subject_member", args: ["text", "text"], returns: "boolean" },
    {
      name: "has_subject_role",
      args: ["text", "text", "text[]"],
      returns: "boolean",
    },
    {
      name: "add_subject_member",
      args: ["text", "text", "uuid", team, "text", "date", "date"],
      returns: "jsonb",
    },
    { name: "end_subject_member", args: ["uuid", "date"], returns: "jsonb" },
    { name: "list_subject_members", args: ["text", "text"], returns: "jsonb" },
    {
      name: "my_subjects",
      args: ["{id}", "text", "integer", "text"],
      returns: "jsonb",
    },
  ];
}
