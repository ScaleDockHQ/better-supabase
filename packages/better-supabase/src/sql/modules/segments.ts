import type { SegmentsEvents } from "../../blocks/segments/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./permissions-model.ts";

const SEGMENT_PAYLOAD = [
  "organizationId",
  "segmentId",
  "subjectType",
  "name",
] as const;

const MEMBER_PAYLOAD = [
  "organizationId",
  "segmentId",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<SegmentsEvents> = {
  "segment.saved": { subject: "segments", payload: [...SEGMENT_PAYLOAD] },
  "segment.removed": { subject: "segments", payload: [...SEGMENT_PAYLOAD] },
  "segment.entered": {
    subject: "segments",
    payload: [...MEMBER_PAYLOAD],
    retries: true,
  },
  "segment.left": {
    subject: "segments",
    payload: [...MEMBER_PAYLOAD],
    retries: true,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    segment: { table: "segments", singular: "segment", primary: true },
  },
  events: EVENTS,
  options: ["maxMembers"],
  tables: {
    segments: {
      name: "segments",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        description: "description",
        subjectType: "subject_type",
        conditions: "conditions",
        memberCount: "member_count",
        refreshedAt: "refreshed_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "createdBy"],
    },
    members: {
      name: "segment_members",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        segment: "segment_id",
        tenant: "tenant_id",
        subjectId: "subject_id",
        enteredAt: "entered_at",
      },
    },
  },
};

/**
 * At most this many records join one segment unless `maxMembers` says
 * otherwise.
 */
const MAX_MEMBERS = 10_000;

interface SegmentNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly s: (column: string) => string;
  readonly m: (column: string) => string;
  /** Whether the segments table has an optional column. */
  readonly has: (column: string) => boolean;
  readonly read: string;
  readonly edit: string;
  readonly maxMembers: number;
  readonly subjects: readonly RegisteredSubject[];
}

function names(ctx: BlockSqlContext): SegmentNames {
  const keys = moduleOperations("segments");
  const maxMembers = ctx.number("maxMembers", MAX_MEMBERS);

  if (!Number.isInteger(maxMembers) || maxMembers < 1) {
    throw new TypeError(
      "blocks.segments.options.maxMembers must be a positive integer",
    );
  }

  return {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    s: (column) => ctx.col("segments", column),
    m: (column) => ctx.col("members", column),
    has: (column) => ctx.has("segments", column),
    read: ctx.permission("read", keys.read),
    edit: ctx.permission("edit", keys.edit),
    maxMembers,
    subjects: registeredSubjects(ctx.subjects, ctx.naming).filter(
      (subject) => subject.tenant !== undefined,
    ),
  };
}

function tables(ctx: BlockSqlContext, n: SegmentNames): string {
  const { t, s, m } = n;
  const policy = (table: string): string => `${ctx.tableName(table).name}_read`;

  return `create table if not exists ${t("segments")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
${n.has("description") ? `  ${s("description")} text check (length(${s("description")}) <= 2000),\n` : ""}  ${s("subjectType")} text not null check (${s("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${s("conditions")} jsonb not null check (jsonb_typeof(${s("conditions")}) = 'object'),
  ${s("memberCount")} integer not null default 0,
  ${s("refreshedAt")} timestamptz,
${n.has("createdBy") ? `  ${s("createdBy")} uuid references auth.users (id) on delete set null,\n` : ""}  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("name")})
);
create index if not exists ${ctx.naming.rename("segments_due_idx")} on ${t("segments")} (${s("refreshedAt")} nulls first);
${n.has("createdBy") ? `create index if not exists ${ctx.naming.rename("segments_created_by_idx")} on ${t("segments")} (${s("createdBy")}) where ${s("createdBy")} is not null;\n` : ""}${lockTable(t("segments"), { read: true })}
create table if not exists ${t("members")} (
  ${m("segment")} uuid not null references ${t("segments")} (${s("id")}) on delete cascade,
  ${m("tenant")} ${ctx.idType} not null,
  ${m("subjectId")} text not null,
  ${m("enteredAt")} timestamptz not null default now(),
  primary key (${m("segment")}, ${m("subjectId")})
);${
    ctx.owns("members")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("members").name}_subject_key`)} on ${t("members")} (${m("segment")}, ${m("subjectId")});`
  }
create index if not exists ${ctx.naming.rename("segment_members_subject_idx")} on ${t("members")} (${m("tenant")}, ${m("subjectId")});
${lockTable(t("members"), { read: true })}
drop policy if exists ${policy("segments")} on ${t("segments")};
create policy ${policy("segments")} on ${t("segments")} for select to authenticated
using (${ctx.scope.check(s("tenant"), n.read)});
drop policy if exists ${policy("members")} on ${t("members")};
create policy ${policy("members")} on ${t("members")} for select to authenticated
using (${ctx.scope.check(m("tenant"), n.read)});
`;
}

/**
 * True when the caller may read records of `type` in `tenant`: the subject's
 * read permission, when it has one, on top of `segments.read`.
 */
function subjectPermission(
  ctx: BlockSqlContext,
  n: SegmentNames,
  type: string,
  tenant: string,
): string {
  const guarded = n.subjects.filter(
    (subject) => subject.config.permissions?.["read"] !== undefined,
  );

  if (guarded.length === 0) {
    return "true";
  }

  return `(case ${type}
${guarded
  .map(
    (subject) =>
      `    when ${sqlString(subject.type)} then ${ctx.scope.can(tenant, sqlString(subject.config.permissions?.["read"] ?? ""))}`,
  )
  .join("\n")}
    else true
  end)`;
}

/** The ids of the live records of each subject type that match the segment. */
function matchingIds(ctx: BlockSqlContext, n: SegmentNames): string {
  const matches = ctx.of("automations").fn("rule_matches");

  const branch = (subject: RegisteredSubject): string => {
    const deletedAt = subject.config.deletedAt;

    const live =
      deletedAt === undefined ? "" : ` and s.${sqlIdent(deletedAt)} is null`;

    return `if v_row.${n.s("subjectType")} = ${sqlString(subject.type)} then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s.${subject.id}::text as id from ${subject.qualified} s
      where ${ctx.scope.eq(`s.${subject.tenant ?? ""}`, `v_row.${n.s("tenant")}`)}${live}
        and ${matches}(v_row.${n.s("conditions")}, to_jsonb(s), v_fields, 'UTC', v_now)
      limit ${String(n.maxMembers + 1)}
    ) x;`;
  };

  const unknown = fail(
    "SEGMENT_SUBJECT_UNKNOWN",
    "The segment's subject type is not registered in config.records",
    "22023",
  );

  if (n.subjects.length === 0) {
    return unknown;
  }

  return `${n.subjects.map(branch).join("\n  els")}
  else
    ${unknown}
  end if;`;
}

function functions(ctx: BlockSqlContext, n: SegmentNames): string {
  const { fn, t, s, m } = n;
  const fieldMap = ctx.of("automations").fn("rule_field_map");
  const check = ctx.of("automations").fn("rule_check");
  const known = n.subjects.map((subject) => sqlString(subject.type));
  const knownList = known.length === 0 ? "(null)" : `(${known.join(", ")})`;

  const optional = (row: string, column: string): string =>
    n.has(column) ? `${row}.${s(column)}` : "null";

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'name', ${row}.${s("name")}, 'description', ${optional(row, "description")}, 'subjectType', ${row}.${s("subjectType")}, 'conditions', ${row}.${s("conditions")}, 'memberCount', ${row}.${s("memberCount")}, 'refreshedAt', ${row}.${s("refreshedAt")}, 'createdBy', ${optional(row, "createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`;

  const optionalColumn = (column: string): string =>
    n.has(column) ? `${s(column)}, ` : "";

  const segmentRecord = (event: string, row: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'segmentId', ${row}.${s("id")}, 'subjectType', ${row}.${s("subjectType")}, 'name', ${row}.${s("name")})`,
      subject: `'segments/' || ${row}.${s("id")}::text`,
      tenant: `${row}.${s("tenant")}::text`,
      audit: {
        category: "data",
        targetType: "segment",
        recordId: `${row}.${s("id")}::text`,
        targetLabel: `${row}.${s("name")}`,
      },
    });

  const memberRecord = (event: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'segmentId', v_row.${s("id")}, 'subjectType', v_row.${s("subjectType")}, 'subjectId', v_id)`,
      subject: `'segments/' || v_row.${s("id")}::text`,
      tenant: `v_row.${s("tenant")}::text`,
      key: `${sqlString(`${event}:`)} || v_row.${s("id")}::text || ':' || v_id || ':' || extract(epoch from v_now)::text`,
      audit: false,
    });

  return `
-- Creates or changes a segment: segment is { id?, subjectType, name,
-- description?, conditions }. conditions is a FilterQuery over the rule
-- fields of the subject type, whose columns name the subject table's columns.
-- Changing the conditions clears refreshed_at, so refresh_due_segments picks
-- the segment up.
create or replace function ${fn("save_segment")}(tenant ${ctx.idType}, segment jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_old ${t("segments")};
  v_row ${t("segments")};
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not ${ctx.scope.can("save_segment.tenant", n.edit)} then
    ${fail("SEGMENT_FORBIDDEN", "You need segments.edit to save a segment")}
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    ${fail("SEGMENT_INVALID", "segment must be an object", "22023")}
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${t("segments")} x
    where x.${s("id")} = v_id and x.${s("tenant")} = save_segment.tenant for update;
    if v_old.${s("id")} is null then
      ${fail("SEGMENT_NOT_FOUND", "No segment in this organization has this id", "P0002")}
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old.${s("subjectType")} then
      ${fail("SEGMENT_INVALID", "A segment's subject type can't change", "22023")}
    end if;
  end if;
  v_type := coalesce(v_old.${s("subjectType")}, segment ->> 'subjectType');
  if v_type is null or v_type not in ${knownList} then
    ${fail("SEGMENT_SUBJECT_UNKNOWN", "subjectType must be a type in config.records", "22023")}
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old.${s("name")});
  if v_name is null or length(v_name) > 200 then
    ${fail("SEGMENT_INVALID", "A segment needs a name of at most 200 characters", "22023")}
  end if;
${
  n.has("description")
    ? `  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old.${s("description")} end;`
    : `  if nullif(trim(segment ->> 'description'), '') is not null then
    ${fail("SEGMENT_DESCRIPTION_UNSUPPORTED", "this segments table has no description column", "22023")}
  end if;`
}
  v_conditions := coalesce(segment -> 'conditions', v_old.${s("conditions")});
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    ${fail("SEGMENT_INVALID", "A segment needs conditions, a filter tree", "22023")}
  end if;
  v_fields := ${fieldMap}(v_type);
  if v_fields = '{}'::jsonb then
    ${fail("SEGMENT_FIELDS_MISSING", "No rule fields for this subject type; sync them first", "22023")}
  end if;
  perform ${check}(v_conditions, v_fields, 1);
  if v_old.${s("id")} is null then
    insert into ${t("segments")} (${s("tenant")}, ${s("name")}, ${optionalColumn("description")}${s("subjectType")}, ${s("conditions")}${n.has("createdBy") ? `, ${s("createdBy")}` : ""})
    values (save_segment.tenant, v_name, ${n.has("description") ? "v_description, " : ""}v_type, v_conditions${n.has("createdBy") ? ", auth.uid()" : ""})
    returning * into v_row;
  elsif v_old.${s("name")} = v_name${n.has("description") ? ` and v_old.${s("description")} is not distinct from v_description` : ""}
    and v_old.${s("conditions")} = v_conditions then
    return ${json("v_old")};
  else
    update ${t("segments")} x set
      ${s("name")} = v_name,
${n.has("description") ? `      ${s("description")} = v_description,\n` : ""}      ${s("conditions")} = v_conditions,
      ${s("refreshedAt")} = case when x.${s("conditions")} = v_conditions then x.${s("refreshedAt")} end,
      ${s("updatedAt")} = now()
    where x.${s("id")} = v_old.${s("id")}
    returning * into v_row;
  end if;
  ${segmentRecord("segment.saved", "v_row")}
  return ${json("v_row")};
exception when unique_violation then
  ${fail("SEGMENT_NAME_TAKEN", "Another segment in this organization has this name", "23505")}
end;
$$;
${userGrant(`${fn("save_segment")}(${ctx.idType}, jsonb)`)}

-- Deletes a segment and its members. Members leave without segment.left.
create or replace function ${fn("remove_segment")}(segment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("segments")};
begin
  select * into v_row from ${t("segments")} x where x.${s("id")} = remove_segment.segment;
  if v_row.${s("id")} is null then
    return false;
  end if;
  if not (${SERVICE_CALLER} or ${ctx.scope.can(`v_row.${s("tenant")}`, n.edit)}) then
    ${fail("SEGMENT_FORBIDDEN", "You need segments.edit to remove a segment")}
  end if;
  delete from ${t("segments")} x where x.${s("id")} = v_row.${s("id")};
  ${segmentRecord("segment.removed", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("remove_segment")}(uuid)`)}

-- The organization's segments, optionally of one subject type, by name.
create or replace function ${fn("segments_list")}(tenant ${ctx.idType}, subject_type text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${ctx.scope.can("segments_list.tenant", n.read)} then
    ${fail("SEGMENT_FORBIDDEN", "You need segments.read to list segments")}
  end if;
  return coalesce((
    select jsonb_agg(${json("x")} order by x.${s("name")})
    from ${t("segments")} x
    where x.${s("tenant")} = segments_list.tenant
      and (segments_list.subject_type is null or x.${s("subjectType")} = segments_list.subject_type)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("segments_list")}(${ctx.idType}, text)`)}

create or replace function ${fn("segment_get")}(segment uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${json("x")} from ${t("segments")} x
  where x.${s("id")} = segment_get.segment and ${ctx.scope.can(`x.${s("tenant")}`, n.read)}
$$;
${userGrant(`${fn("segment_get")}(uuid)`)}

-- A page of a segment's members, newest first: { subjectId, enteredAt }.
-- after is the last page's oldest enteredAt. The caller also needs the
-- subject type's read permission.
create or replace function ${fn("list_segment_members")}(segment uuid, after timestamptz default null, max_count integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("segments")};
begin
  select * into v_row from ${t("segments")} x where x.${s("id")} = list_segment_members.segment;
  if v_row.${s("id")} is null or not ${ctx.scope.can(`v_row.${s("tenant")}`, n.read)}
    or not ${subjectPermission(ctx, n, `v_row.${s("subjectType")}`, `v_row.${s("tenant")}`)} then
    ${fail("SEGMENT_NOT_FOUND", "No segment you can read has this id", "P0002")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('subjectId', y.${m("subjectId")}, 'enteredAt', y.${m("enteredAt")}) order by y.${m("enteredAt")} desc, y.${m("subjectId")})
    from (
      select z.* from ${t("members")} z
      where z.${m("segment")} = v_row.${s("id")}
        and (list_segment_members.after is null or z.${m("enteredAt")} < list_segment_members.after)
      order by z.${m("enteredAt")} desc, z.${m("subjectId")}
      limit ${pageSize("list_segment_members.max_count", 50, 500)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_segment_members")}(uuid, timestamptz, integer)`)}

-- The segments a record is in, among those the caller can read.
create or replace function ${fn("segments_of")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${s("id")}, 'name', x.${s("name")}, 'enteredAt', y.${m("enteredAt")}) order by x.${s("name")}), '[]'::jsonb)
  from ${t("members")} y
  join ${t("segments")} x on x.${s("id")} = y.${m("segment")}
  where x.${s("subjectType")} = segments_of.subject_type and y.${m("subjectId")} = segments_of.subject_id
    and ${ctx.scope.can(`x.${s("tenant")}`, n.read)}
    and ${subjectPermission(ctx, n, `x.${s("subjectType")}`, `x.${s("tenant")}`)}
$$;
${userGrant(`${fn("segments_of")}(text, text)`)}

-- Evaluates a segment over its subject table and stores the records that
-- match: records that start matching enter (segment.entered), records that
-- stop matching or are deleted leave (segment.left). Returns { entered,
-- left, memberCount }.
create or replace function ${fn("evaluate_segment")}(segment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("segments")};
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from ${t("segments")} x where x.${s("id")} = evaluate_segment.segment for update;
  if v_row.${s("id")} is null then
    return null;
  end if;
  v_fields := ${fieldMap}(v_row.${s("subjectType")});
  ${matchingIds(ctx, n)}
  if cardinality(v_ids) > ${String(n.maxMembers)} then
    ${fail("SEGMENT_TOO_LARGE", `A segment holds at most ${String(n.maxMembers)} records; narrow its conditions`, "54000")}
  end if;
  with gone as (
    delete from ${t("members")} y
    where y.${m("segment")} = v_row.${s("id")} and not (y.${m("subjectId")} = any (v_ids))
    returning y.${m("subjectId")} as id
  ), added as (
    insert into ${t("members")} (${m("segment")}, ${m("tenant")}, ${m("subjectId")}, ${m("enteredAt")})
    select v_row.${s("id")}, v_row.${s("tenant")}, z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning ${m("subjectId")} as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    ${memberRecord("segment.entered")}
  end loop;
  foreach v_id in array v_left loop
    ${memberRecord("segment.left")}
  end loop;
  update ${t("segments")} x set ${s("memberCount")} = cardinality(v_ids), ${s("refreshedAt")} = v_now
  where x.${s("id")} = v_row.${s("id")};
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$$;
revoke execute on function ${fn("evaluate_segment")}(uuid) from public, anon, authenticated;

-- Refreshes one segment now: segments.edit, or the service role.
create or replace function ${fn("refresh_segment")}(segment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${s("tenant")} into v_tenant from ${t("segments")} x where x.${s("id")} = refresh_segment.segment;
  if v_tenant is null then
    ${fail("SEGMENT_NOT_FOUND", "No segment has this id", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.scope.can("v_tenant", n.edit)}) then
    ${fail("SEGMENT_FORBIDDEN", "You need segments.edit to refresh a segment")}
  end if;
  return ${fn("evaluate_segment")}(refresh_segment.segment);
end;
$$;
${userGrant(`${fn("refresh_segment")}(uuid)`)}

-- Refreshes the segments not refreshed within stale_after, oldest first, for
-- a cron. Returns { segments, entered, left }.
create or replace function ${fn("refresh_due_segments")}(max_count integer default null, stale_after interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_segment uuid;
  v_result jsonb;
  v_count integer := 0;
  v_entered integer := 0;
  v_left integer := 0;
begin
  for v_segment in
    select x.${s("id")} from ${t("segments")} x
    where x.${s("refreshedAt")} is null
      or x.${s("refreshedAt")} < now() - coalesce(refresh_due_segments.stale_after, interval '1 hour')
    order by x.${s("refreshedAt")} nulls first, x.${s("id")}
    limit ${pageSize("refresh_due_segments.max_count", 25, 500)}
  loop
    v_result := ${fn("evaluate_segment")}(v_segment);
    v_count := v_count + 1;
    v_entered := v_entered + (v_result ->> 'entered')::integer;
    v_left := v_left + (v_result ->> 'left')::integer;
  end loop;
  return jsonb_build_object('segments', v_count, 'entered', v_entered, 'left', v_left);
end;
$$;
${serviceGrant(`${fn("refresh_due_segments")}(integer, interval)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  const n = names(ctx);

  return `${schemaPreamble(ctx)}
-- Segments: a tenant's saved filter over one subject type, with materialized
-- members and events when a record enters or leaves.
${tables(ctx, n)}${functions(ctx, n)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_segment", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "remove_segment", args: ["uuid"], returns: "boolean" },
    { name: "segments_list", args: ["{id}", "text"], returns: "jsonb" },
    { name: "segment_get", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_segment_members",
      args: ["uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "segments_of", args: ["text", "text"], returns: "jsonb" },
    { name: "refresh_segment", args: ["uuid"], returns: "jsonb" },
    {
      name: "refresh_due_segments",
      args: ["integer", "interval"],
      returns: "jsonb",
    },
  ];
}

export const SEGMENTS: BlockSqlDefinition = {
  name: "segments",
  scopes: ["tenant"],
  title: "Segments",
  description:
    "Saved filters over a subject type, such as companies in a region or deals over a size: the matching records materialized as members, refreshed on demand or from a cron, with an event when a record enters or leaves.",
  requires: ["memberships", "permissions", "subjects", "automations"],
  integrates: ["outbox", "audit", "data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
