import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockSqlContext } from "../context.ts";
import type { Subject } from "../subjects.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import {
  qualifiedTable,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { roleNameOf } from "./memberships.ts";
import { moduleOperations, roleNames } from "./permissions-model.ts";

const COLUMN = /^[a-z_][a-z0-9_]*$/;

/**
 * The record types whose current version is a column on the record
 * (`on.<type>.versionColumn`, or a block's `acknowledgements` contribution),
 * keyed by type.
 */
function versionColumns(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
): readonly (readonly [string, Subject, string])[] {
  const byType = new Map(subjects);

  const own = subjects.flatMap(([type, subject]) => {
    const column = subject.extra["versionColumn"];

    if (column === undefined) {
      return [];
    }

    if (typeof column !== "string" || !COLUMN.test(column)) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${type}.versionColumn must be a column name`,
      );
    }

    return [[type, subject, column] as const];
  });

  const taken = new Set(own.map(([type]) => type));

  const contributed = uniqueContributions(
    "acknowledgements",
    ctx.contributions("acknowledgements"),
    (each) => each.subject,
  ).flatMap((each) => {
    const subject = byType.get(each.subject);

    return subject === undefined || taken.has(each.subject)
      ? []
      : [[each.subject, subject, each.versionColumn] as const];
  });

  return [...own, ...contributed];
}

/** The acknowledgement functions of the `acknowledgements` module. */
export function acknowledgementFunctions(ctx: BlockSqlContext): string {
  const assignments = ctx.table("assignments");
  const acks = ctx.table("acknowledgements");
  const notices = ctx.table("notices");
  const g = (column: string): string => ctx.col("assignments", column);
  const a = (column: string): string => ctx.col("acknowledgements", column);
  const n = (column: string): string => ctx.col("notices", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("acknowledgements");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const acknowledge = ctx.permission("acknowledge", permissions.acknowledge);
  const members = ctx.of("memberships");
  const memberships = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const mu = members.col("memberships", "user");
  const versions = ctx.of("versions");
  const vt = versions.table("versions");
  const v = (column: string): string => versions.col("versions", column);
  const contributed = ctx.contributions("acknowledgements");

  const contributedTables = new Set(
    contributed.flatMap((each) => ctx.subjects[each.subject]?.table ?? []),
  );

  // A block's own records join the subjects even when `on` lists others.
  const always = (entry: SubjectConfig): boolean =>
    contributedTables.has(entry.table);

  const listed = subjectsOption(ctx, ["versionColumn"], { always });

  const withRecords = subjectsOption(ctx, ["versionColumn"], {
    always,
    joined: Object.fromEntries(
      contributed.flatMap((each) =>
        each.record === undefined ? [] : [[each.subject, { ...each.record }]],
      ),
    ),
  });

  // With no subjects listed every record type stays acknowledgeable, so a
  // contributed record only narrows the types once the app lists some.
  const subjects = listed.length === 0 ? listed : withRecords;
  const columns = versionColumns(ctx, withRecords);

  // `subjectTypeGuard` rereads `on` without the `versionColumn` key.
  const typeGuard =
    ctx.on === undefined
      ? ""
      : `
  if assign_acknowledgement.subject_type not in (${subjects.map(([type]) => sqlString(type)).join(", ") || "null"}) then
    ${fail("ACKNOWLEDGEMENT_SUBJECT_UNSUPPORTED", `blocks.${ctx.instance}.on does not allow this record type`, "22023")}
  end if;`;

  const teams =
    ctx.installed("teams") && ctx.of("teams").mode !== "custom"
      ? ctx.of("teams")
      : undefined;

  const signatures =
    ctx.installed("signatures") && ctx.of("signatures").mode !== "custom"
      ? ctx.of("signatures")
      : undefined;

  const titles =
    ctx.installed("subjects") && ctx.of("subjects").mode !== "custom"
      ? ctx.of("subjects")
      : undefined;

  const forbidden = (message: string): string =>
    fail("ACKNOWLEDGEMENT_FORBIDDEN", message);

  const principalInvalid = (message: string): string =>
    fail("ACKNOWLEDGEMENT_PRINCIPAL_INVALID", message, "22023");

  const readable = (type: string, id: string, tenant: string): string =>
    subjectReadable(ctx, subjects, { type, id, tenant });

  const has = (logical: string, column: string, row: string): string =>
    ctx.has(logical, column) ? `${row}.${ctx.col(logical, column)}` : "null";

  // Whether the assignment row `x` covers the member row `m`: it names them,
  // a team they are in, or the role they hold.
  const covers = (x: string, m: string): string => {
    const team =
      teams === undefined
        ? ""
        : `
      or (${x}.${g("principalType")} = 'team' and exists (
        select 1 from ${teams.table("members")} tm
        where tm.${teams.col("members", "tenant")} = ${m}.${mt}
          and tm.${teams.col("members", "user")} = ${m}.${mu}
          and tm.${teams.col("members", "team")}::text = ${x}.${g("principalId")}
      ))`;

    return `((${x}.${g("principalType")} = 'user' and ${x}.${g("principalId")} = ${m}.${mu}::text)
      or (${x}.${g("principalType")} = 'role' and ${x}.${g("principalId")} = ${roleNameOf(members, m)})${team})`;
  };

  // The tenant of a record, from its assignments, acknowledgements or versions.
  const subjectTenant = (type: string, id: string): string =>
    `coalesce(
    (select x.${g("tenant")} from ${assignments} x where x.${g("subjectType")} = ${type} and x.${g("subjectId")} = ${id} limit 1),
    (select x.${a("tenant")} from ${acks} x where x.${a("subjectType")} = ${type} and x.${a("subjectId")} = ${id} limit 1),
    (select x.${v("tenant")} from ${vt} x where x.${v("subjectType")} = ${type} and x.${v("subjectId")} = ${id} limit 1)
  )`;

  const current = (tenant: string, type: string, id: string): string =>
    `${fn("current_acknowledgement_version")}(${tenant}, ${type}, ${id})`;

  const versionCases = columns
    .map(([type, subject, column]) => {
      const tenant =
        subject.tenant === false
          ? ""
          : ` and ${ctx.scope.eq(`s.${sqlIdent(subject.tenant ?? ctx.naming.rename("organization_id"))}`, "current_acknowledgement_version.tenant")}`;

      return `
  if current_acknowledgement_version.subject_type = ${sqlString(type)} then
    return (select s.${sqlIdent(column)}::uuid from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, "current_acknowledgement_version.subject_id")}${tenant});
  end if;`;
    })
    .join("");

  const title = (type: string, id: string): string =>
    titles === undefined
      ? "null::text"
      : `${titles.fn("subject_title")}(${type}, ${id})`;

  const assignmentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${g("id")}, 'organizationId', ${row}.${g("tenant")}, 'subjectType', ${row}.${g("subjectType")}, 'subjectId', ${row}.${g("subjectId")}, 'principalType', ${row}.${g("principalType")}, 'principalId', ${row}.${g("principalId")}, 'dueInDays', ${row}.${g("dueInDays")}, 'createdBy', ${has("assignments", "createdBy", row)}, 'createdAt', ${has("assignments", "createdAt", row)})`;

  const ackJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'subjectType', ${row}.${a("subjectType")}, 'subjectId', ${row}.${a("subjectId")}, 'versionId', ${row}.${a("version")}, 'userId', ${row}.${a("user")}, 'method', ${ctx.has("acknowledgements", "method") ? `${row}.${a("method")}` : "'click'"}, 'signatureId', ${has("acknowledgements", "signature", row)}, 'acknowledgedAt', ${row}.${a("acknowledgedAt")})`;

  const assignmentRecord = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${g("tenant")}, 'subjectType', v_row.${g("subjectType")}, 'subjectId', v_row.${g("subjectId")}, 'assignmentId', v_row.${g("id")}, 'principalType', v_row.${g("principalType")}, 'principalId', v_row.${g("principalId")})`,
      subject: `'acknowledgement-assignments/' || v_row.${g("id")}::text`,
      tenant: `v_row.${g("tenant")}`,
      audit: {
        category: "data",
        targetType: "acknowledgement_assignment",
        recordId: `v_row.${g("id")}::text`,
        summary,
      },
    });

  // The members a record's assignments cover, with the shortest due period.
  const covered = (tenant: string, type: string, id: string): string =>
    `select m.${mu} as user_id, min(x.${g("dueInDays")}) as due_in_days
      from ${assignments} x
      join ${memberships} m on m.${mt} = x.${g("tenant")}
      where x.${g("tenant")} = ${tenant} and x.${g("subjectType")} = ${type} and x.${g("subjectId")} = ${id}
        and ${covers("x", "m")}
      group by m.${mu}`;

  const dueOn = (createdAt: string, days: string): string =>
    `(${createdAt})::date + ${days}`;

  const signatureCheck =
    signatures === undefined
      ? `if acknowledge.signature_id is not null then
    ${fail("ACKNOWLEDGEMENT_SIGNATURE_INVALID", "acknowledging with a signature needs the signatures module", "22023")}
  end if;`
      : `if acknowledge.signature_id is not null and not exists (
    select 1 from ${signatures.table("signatures")} sg
    join ${signatures.table("requests")} sr on sr.${signatures.col("requests", "id")} = sg.${signatures.col("signatures", "request")}
    where sg.${signatures.col("signatures", "id")} = acknowledge.signature_id
      and sg.${signatures.col("signatures", "signer")} = v_me
      and sr.${signatures.col("requests", "status")} = 'completed'
      and sr.${signatures.col("requests", "tenant")} = v_tenant
      and sr.${signatures.col("requests", "subjectType")} = acknowledge.subject_type
      and sr.${signatures.col("requests", "subjectId")} = acknowledge.subject_id
      and sr.${signatures.col("requests", "version")} = v_version
  ) then
    ${fail("ACKNOWLEDGEMENT_SIGNATURE_INVALID", "the signature isn't your completed signature on this version", "22023")}
  end if;`;

  const roleCheck = `assign_acknowledgement.principal_id = any (array[${roleNames(ctx).map(sqlString).join(", ") || "null"}]::text[])
      or exists (select 1 from ${memberships} m where m.${mt} = assign_acknowledgement.tenant and ${roleNameOf(members, "m")} = assign_acknowledgement.principal_id)`;

  const teamCheck =
    teams === undefined
      ? principalInvalid("team assignments need the teams module")
      : `if not exists (
      select 1 from ${teams.table("teams")} t
      where t.${teams.col("teams", "id")}::text = assign_acknowledgement.principal_id
        and t.${teams.col("teams", "tenant")} = assign_acknowledgement.tenant
    ) then
      ${principalInvalid("the team isn't a team in this organization")}
    end if;`;

  const overdueNotify = ctx.installed("notifications")
    ? `
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'acknowledgement.reminded',
      'tenant', v_item.tenant,
      'actor', null,
      'subject_type', v_item.subject_type,
      'subject_id', v_item.subject_id,
      'summary', coalesce(${title("v_item.subject_type", "v_item.subject_id")}, v_item.subject_type),
      'recipients', to_jsonb(array[v_item.user_id]),
      'key', 'acknowledgement.reminded:' || v_item.subject_type || ':' || v_item.subject_id || ':' || v_item.version_id::text || ':' || v_item.user_id::text,
      'data', jsonb_build_object('versionId', v_item.version_id, 'dueOn', v_item.due_on)
    )`,
      { indent: "    " },
    )}`
    : "";

  return `
-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function ${fn("current_acknowledgement_version")}(tenant ${idType}, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${versionCases}
  return (
    select x.${v("id")} from ${vt} x
    where x.${v("tenant")} = current_acknowledgement_version.tenant
      and x.${v("subjectType")} = current_acknowledgement_version.subject_type
      and x.${v("subjectId")} = current_acknowledgement_version.subject_id
      and x.${v("frozen")}
    order by x.${v("number")} desc
    limit 1
  );
end;
$$;
revoke execute on function ${fn("current_acknowledgement_version")}(${idType}, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function ${fn("place_acknowledgement_assignment")}(tenant ${idType}, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assignments}%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from ${assignments} x
    where x.${g("tenant")} = place_acknowledgement_assignment.tenant
      and x.${g("subjectType")} = place_acknowledgement_assignment.subject_type
      and x.${g("subjectId")} = place_acknowledgement_assignment.subject_id
      and x.${g("principalType")} = place_acknowledgement_assignment.principal_type
      and x.${g("principalId")} = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into ${assignments} (${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("principalType")}, ${g("principalId")}, ${g("dueInDays")})
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict (${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("principalType")}, ${g("principalId")})
  do update set ${g("dueInDays")} = excluded.${g("dueInDays")}
  returning * into v_row;
  if not v_existed then
    ${assignmentRecord("acknowledgement_assignment.created", `'asked ' || v_row.${g("principalType")} || ' ' || v_row.${g("principalId")} || ' to acknowledge ' || v_row.${g("subjectType")} || ' ' || v_row.${g("subjectId")}`)}
  end if;
  return ${assignmentJson("v_row")};
end;
$$;
revoke execute on function ${fn("place_acknowledgement_assignment")}(${idType}, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function ${fn("drop_acknowledgement_assignment")}(tenant ${idType}, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assignments}%rowtype;
begin
  delete from ${assignments} x
  where x.${g("tenant")} = drop_acknowledgement_assignment.tenant
    and x.${g("subjectType")} = drop_acknowledgement_assignment.subject_type
    and x.${g("subjectId")} = drop_acknowledgement_assignment.subject_id
    and x.${g("principalType")} = drop_acknowledgement_assignment.principal_type
    and x.${g("principalId")} = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  ${assignmentRecord("acknowledgement_assignment.deleted", `'removed the acknowledgement assignment of ' || v_row.${g("principalType")} || ' ' || v_row.${g("principalId")} || ' on ' || v_row.${g("subjectType")} || ' ' || v_row.${g("subjectId")}`)}
  return true;
end;
$$;
revoke execute on function ${fn("drop_acknowledgement_assignment")}(${idType}, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function ${fn("assign_acknowledgement")}(tenant ${idType}, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "assign_acknowledgement.tenant", manage)} and ${readable("assign_acknowledgement.subject_type", "assign_acknowledgement.subject_id", "assign_acknowledgement.tenant")})) then
    ${forbidden("not allowed to assign acknowledgements on this record")}
  end if;${typeGuard}
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    ${fail("ACKNOWLEDGEMENT_DUE_INVALID", "due_in_days must be between 1 and 365", "22023")}
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from ${memberships} m
      where m.${mt} = assign_acknowledgement.tenant and m.${mu}::text = assign_acknowledgement.principal_id
    ) then
      ${principalInvalid("the user isn't a member of this organization")}
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    ${teamCheck}
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (${roleCheck}) then
      ${principalInvalid("the role isn't a role in this organization")}
    end if;
  else
    ${principalInvalid("principal_type must be user, team or role")}
  end if;
  ${ctx.hook("before_acknowledgement_assignment_create", [
    [idType, "assign_acknowledgement.tenant"],
    ["text", "assign_acknowledgement.subject_type"],
    ["text", "assign_acknowledgement.subject_id"],
    ["text", "assign_acknowledgement.principal_type"],
    ["text", "assign_acknowledgement.principal_id"],
  ])}
  v_assignment := ${fn("place_acknowledgement_assignment")}(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  ${ctx.hook("after_acknowledgement_assignment_create", [["uuid", "(v_assignment ->> 'id')::uuid"]])}
  return v_assignment;
end;
$$;
${userGrant(`${fn("assign_acknowledgement")}(${idType}, text, text, text, text, integer)`)}

-- Removes an assignment. Acknowledgements already given stay.
create or replace function ${fn("unassign_acknowledgement")}(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${assignments}%rowtype;
begin
  select * into v_row from ${assignments} x where x.${g("id")} = unassign_acknowledgement.assignment_id for update;
  if not found then
    ${fail("ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND", "acknowledgement assignment not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", `v_row.${g("tenant")}`, manage)} and ${readable(`v_row.${g("subjectType")}`, `v_row.${g("subjectId")}`, `v_row.${g("tenant")}`)})) then
    ${forbidden("not allowed to remove acknowledgement assignments on this record")}
  end if;
  delete from ${assignments} x where x.${g("id")} = v_row.${g("id")};
  ${assignmentRecord("acknowledgement_assignment.deleted", `'removed the acknowledgement assignment of ' || v_row.${g("principalType")} || ' ' || v_row.${g("principalId")} || ' on ' || v_row.${g("subjectType")} || ' ' || v_row.${g("subjectId")}`)}
  return ${assignmentJson("v_row")};
end;
$$;
${userGrant(`${fn("unassign_acknowledgement")}(uuid)`)}

create or replace function ${fn("list_acknowledgement_assignments")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := ${subjectTenant("list_acknowledgement_assignments.subject_type", "list_acknowledgement_assignments.subject_id")};
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", read)} and ${readable("list_acknowledgement_assignments.subject_type", "list_acknowledgement_assignments.subject_id", "v_tenant")})) then
    ${forbidden("not allowed to read acknowledgement assignments on this record")}
  end if;
  return (
    select coalesce(jsonb_agg(${assignmentJson("x")} order by x.${g("principalType")}, x.${g("principalId")}), '[]'::jsonb)
    from ${assignments} x
    where x.${g("tenant")} = v_tenant
      and x.${g("subjectType")} = list_acknowledgement_assignments.subject_type
      and x.${g("subjectId")} = list_acknowledgement_assignments.subject_id
  );
end;
$$;
${userGrant(`${fn("list_acknowledgement_assignments")}(text, text)`)}

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function ${fn("acknowledge")}(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant ${idType};
  v_version uuid;
  v_row ${acks}%rowtype;
begin
  if v_me is null then
    ${forbidden("sign in to acknowledge")}
  end if;
  select x.${g("tenant")} into v_tenant
    from ${assignments} x
    join ${memberships} m on m.${mt} = x.${g("tenant")} and m.${mu} = v_me
    where x.${g("subjectType")} = acknowledge.subject_type and x.${g("subjectId")} = acknowledge.subject_id
      and ${covers("x", "m")}
    limit 1;
  if v_tenant is null then
    ${fail("ACKNOWLEDGEMENT_NOT_ASSIGNED", "you aren't asked to acknowledge this record")}
  end if;
  if not (${ctx.can("tenant", "v_tenant", acknowledge)} and ${readable("acknowledge.subject_type", "acknowledge.subject_id", "v_tenant")}) then
    ${forbidden("not allowed to acknowledge this record")}
  end if;
  v_version := ${current("v_tenant", "acknowledge.subject_type", "acknowledge.subject_id")};
  if v_version is null then
    ${fail("ACKNOWLEDGEMENT_NO_VERSION", "the record has no version to acknowledge", "55000")}
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    ${fail("ACKNOWLEDGEMENT_VERSION_STALE", "the record has a newer version; acknowledge that one", "55000")}
  end if;
  ${signatureCheck}
  ${ctx.hook("before_acknowledgement_create", [
    [idType, "v_tenant"],
    ["text", "acknowledge.subject_type"],
    ["text", "acknowledge.subject_id"],
    ["uuid", "v_version"],
    ["uuid", "v_me"],
  ])}
  insert into ${acks} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("version")}, ${a("user")}${ctx.has("acknowledgements", "method") ? `, ${a("method")}` : ""}${ctx.has("acknowledgements", "signature") ? `, ${a("signature")}` : ""})
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me${ctx.has("acknowledgements", "method") ? ", case when acknowledge.signature_id is null then 'click' else 'signature' end" : ""}${ctx.has("acknowledgements", "signature") ? ", acknowledge.signature_id" : ""})
  on conflict (${a("subjectType")}, ${a("subjectId")}, ${a("version")}, ${a("user")}) do nothing
  returning * into v_row;
  if found then
    ${ctx.record({
      type: "acknowledgement.created",
      payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'subjectType', v_row.${a("subjectType")}, 'subjectId', v_row.${a("subjectId")}, 'versionId', v_row.${a("version")}, 'userId', v_row.${a("user")})`,
      subject: `'acknowledgements/' || v_row.${a("id")}::text`,
      tenant: `v_row.${a("tenant")}`,
      audit: {
        category: "data",
        targetType: "acknowledgement",
        recordId: `v_row.${a("id")}::text`,
        summary: `'acknowledged ' || v_row.${a("subjectType")} || ' ' || v_row.${a("subjectId")}`,
      },
    })}
    ${ctx.hook("after_acknowledgement_create", [["uuid", `v_row.${a("id")}`]])}
  else
    select * into v_row from ${acks} x
    where x.${a("subjectType")} = acknowledge.subject_type and x.${a("subjectId")} = acknowledge.subject_id
      and x.${a("version")} = v_version and x.${a("user")} = v_me;
  end if;
  return ${ackJson("v_row")};
end;
$$;
${userGrant(`${fn("acknowledge")}(text, text, uuid, uuid)`)}

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function ${fn("list_my_acknowledgements")}(tenant ${idType}, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from ${memberships} m where m.${mt} = list_my_acknowledgements.tenant and m.${mu} = v_me
  ) then
    ${forbidden("not a member of this organization")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', ${title("z.subject_type", "z.subject_id")},
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k.${a("id")} is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k.${a("acknowledgedAt")}
    ) order by k.${a("id")} is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ${dueOn(`(select vv.${v("createdAt")} from ${vt} vv where vv.${v("id")} = y.version_id)`, "y.due_in_days")} as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          ${current("list_my_acknowledgements.tenant", "q.subject_type", "q.subject_id")} as version_id
        from (
          select x.${g("subjectType")} as subject_type, x.${g("subjectId")} as subject_id, min(x.${g("dueInDays")}) as due_in_days
          from ${assignments} x
          join ${memberships} m on m.${mt} = x.${g("tenant")} and m.${mu} = v_me
          where x.${g("tenant")} = list_my_acknowledgements.tenant and ${covers("x", "m")}
          group by x.${g("subjectType")}, x.${g("subjectId")}
        ) q
        where ${readable("q.subject_type", "q.subject_id", "list_my_acknowledgements.tenant")}
      ) y
      where y.version_id is not null
    ) z
    left join ${acks} k on k.${a("subjectType")} = z.subject_type and k.${a("subjectId")} = z.subject_id
      and k.${a("version")} = z.version_id and k.${a("user")} = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k.${a("id")} is null
  );
end;
$$;
${userGrant(`${fn("list_my_acknowledgements")}(${idType}, boolean)`)}

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function ${fn("acknowledgement_status")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := ${subjectTenant("acknowledgement_status.subject_type", "acknowledgement_status.subject_id")};
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", read)} and ${readable("acknowledgement_status.subject_type", "acknowledgement_status.subject_id", "v_tenant")})) then
    ${forbidden("not allowed to read acknowledgements of this record")}
  end if;
  v_version := ${current("v_tenant", "acknowledgement_status.subject_type", "acknowledgement_status.subject_id")};
  select x.${v("createdAt")} into v_created from ${vt} x where x.${v("id")} = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k.${a("id")}),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', ${dueOn("v_created", "c.due_in_days")},
        'overdue', coalesce(${dueOn("v_created", "c.due_in_days")} < current_date, false)
      ) order by ${dueOn("v_created", "c.due_in_days")} nulls last, c.user_id) filter (where k.${a("id")} is null), '[]'::jsonb)
    )
    from (${covered("v_tenant", "acknowledgement_status.subject_type", "acknowledgement_status.subject_id")}) c
    left join ${acks} k on k.${a("subjectType")} = acknowledgement_status.subject_type and k.${a("subjectId")} = acknowledgement_status.subject_id
      and k.${a("version")} = v_version and k.${a("user")} = c.user_id
  );
end;
$$;
${userGrant(`${fn("acknowledgement_status")}(text, text)`)}

-- The acknowledgements of one version of a record, default the current one.
create or replace function ${fn("acknowledgements_of")}(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType} := ${subjectTenant("acknowledgements_of.subject_type", "acknowledgements_of.subject_id")};
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", read)} and ${readable("acknowledgements_of.subject_type", "acknowledgements_of.subject_id", "v_tenant")})) then
    ${forbidden("not allowed to read acknowledgements of this record")}
  end if;
  v_version := coalesce(acknowledgements_of.version_id, ${current("v_tenant", "acknowledgements_of.subject_type", "acknowledgements_of.subject_id")});
  return (
    select coalesce(jsonb_agg(${ackJson("x")} order by x.${a("acknowledgedAt")}), '[]'::jsonb)
    from ${acks} x
    where x.${a("tenant")} = v_tenant
      and x.${a("subjectType")} = acknowledgements_of.subject_type
      and x.${a("subjectId")} = acknowledgements_of.subject_id
      and x.${a("version")} = v_version
  );
end;
$$;
${userGrant(`${fn("acknowledgements_of")}(text, text, uuid)`)}

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function ${fn("notify_due_acknowledgements")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      ${dueOn(`vv.${v("createdAt")}`, "y.due_in_days")} as due_on
    from (
      select q.*, ${current("q.tenant", "q.subject_type", "q.subject_id")} as version_id
      from (
        select x.${g("tenant")} as tenant, x.${g("subjectType")} as subject_type, x.${g("subjectId")} as subject_id,
          m.${mu} as user_id, min(x.${g("dueInDays")}) as due_in_days
        from ${assignments} x
        join ${memberships} m on m.${mt} = x.${g("tenant")}
        where x.${g("dueInDays")} is not null and ${covers("x", "m")}
        group by x.${g("tenant")}, x.${g("subjectType")}, x.${g("subjectId")}, m.${mu}
      ) q
    ) y
    join ${vt} vv on vv.${v("id")} = y.version_id
    where ${dueOn(`vv.${v("createdAt")}`, "y.due_in_days")} < current_date
      and not exists (
        select 1 from ${acks} k
        where k.${a("subjectType")} = y.subject_type and k.${a("subjectId")} = y.subject_id
          and k.${a("version")} = y.version_id and k.${a("user")} = y.user_id
      )
      and not exists (
        select 1 from ${notices} nt
        where nt.${n("subjectType")} = y.subject_type and nt.${n("subjectId")} = y.subject_id
          and nt.${n("version")} = y.version_id and nt.${n("user")} = y.user_id
      )
  loop
    insert into ${notices} (${n("tenant")}, ${n("subjectType")}, ${n("subjectId")}, ${n("version")}, ${n("user")})
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict (${n("subjectType")}, ${n("subjectId")}, ${n("version")}, ${n("user")}) do nothing;
    if found then
      ${ctx.record({
        type: "acknowledgement.reminded",
        payload: `jsonb_build_object('organizationId', v_item.tenant, 'subjectType', v_item.subject_type, 'subjectId', v_item.subject_id, 'versionId', v_item.version_id, 'userId', v_item.user_id, 'dueOn', v_item.due_on)`,
        subject: `'acknowledgements/' || v_item.subject_type || '/' || v_item.subject_id`,
        tenant: "v_item.tenant",
        audit: false,
      })}${overdueNotify}
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_due_acknowledgements")}()`)}
`;
}
