import type { ActivitiesEvents } from "../../blocks/activities/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { bookingEngagementsSql, logsBookings } from "./activities-bookings.ts";
import {
  RECORDING_TABLES,
  recordingsContract,
  recordingsOn,
  recordingsSql,
} from "./activities-recordings.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The engagement types `options.types` falls back to. */
const ENGAGEMENT_TYPES = ["call", "email", "meeting", "note", "task"] as const;

const PAYLOAD = [
  "organizationId",
  "engagementId",
  "type",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<ActivitiesEvents> = {
  "engagement.logged": { subject: "engagements", payload: [...PAYLOAD] },
  "engagement.updated": { subject: "engagements", payload: [...PAYLOAD] },
  "engagement.completed": { subject: "engagements", payload: [...PAYLOAD] },
  "engagement.deleted": { subject: "engagements", payload: [...PAYLOAD] },
  "engagement.recorded": {
    subject: "engagements",
    payload: [...PAYLOAD, "recordingId"],
  },
  "engagement.transcribed": {
    subject: "engagements",
    payload: [...PAYLOAD, "recordingId"],
    retries: true,
  },
  "engagement.summarized": {
    subject: "engagements",
    payload: [...PAYLOAD],
    retries: true,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    engagement: {
      table: "engagements",
      singular: "engagement",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["body", "outcome"] },
      },
    },
  },
  events: EVENTS,
  hooks: ["before_engagement_log", "after_engagement_log"],
  options: ["types", "extraColumns", "recordings", "bookings"],
  tables: {
    engagements: {
      name: "engagements",
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type",
        title: "title",
        body: "body",
        outcome: "outcome",
        owner: "owner_user_id",
        dueAt: "due_at",
        doneAt: "done_at",
        durationSeconds: "duration_seconds",
        externalRef: "external_ref",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    links: {
      name: "engagement_subjects",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        engagement: "engagement_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        position: "position",
      },
    },
    ...RECORDING_TABLES,
  },
};

const TYPE = /^[a-z][a-z0-9_]{0,62}$/;

function types(ctx: BlockSqlContext): readonly string[] {
  const list = ctx.list("types", ENGAGEMENT_TYPES);

  if (list.length === 0 || list.some((item) => !TYPE.test(item))) {
    throw new TypeError(
      "blocks.activities.options.types must be a non-empty list of lowercase names",
    );
  }

  return list;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("activities");
  const read = ctx.permission("read", keys.read);
  const write = ctx.permission("write", keys.write);
  const manage = ctx.permission("manage", keys.manage);
  const fn = (name: string): string => ctx.fn(name);
  const t = (table: string): string => ctx.table(table);
  const e = (column: string): string => ctx.col("engagements", column);
  const l = (column: string): string => ctx.col("links", column);
  const extras = ctx.extraColumns("engagements", ["subjects", "overdue"]);
  const typeList = `${sqlString(`{${types(ctx).join(",")}}`)}::text[]`;
  const canSubject = ctx.of("subjects").fn("can_subject");

  const payload = (
    id: string,
    type: string,
    tenant: string,
    extra: string,
  ): string =>
    `jsonb_build_object('organizationId', ${tenant}, 'engagementId', ${id}, 'type', ${type}, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects${extra === "" ? "" : `, ${extra}`})`;

  const record = (
    event: string,
    id: string,
    type: string,
    tenant: string,
    extra = "",
    key?: string,
  ): string =>
    ctx.record({
      type: event,
      payload: payload(id, type, tenant, extra),
      subject: `'engagements/' || ${id}::text`,
      tenant: `${tenant}::text`,
      audit: false,
      ...(key === undefined ? {} : { key }),
    });

  const editable = (alias: string): string =>
    `(auth.role() = 'service_role' or ${alias}.${e("createdBy")} = auth.uid() or ${alias}.${e("owner")} = auth.uid() or ${ctx.scope.can(`${alias}.${e("tenant")}`, manage)})`;

  const subjectsOf = (id: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('type', sx.${l("subjectType")}, 'id', sx.${l("subjectId")}) order by sx.${l("position")}) from ${t("links")} sx where sx.${l("engagement")} = ${id}), '[]'::jsonb)`;

  const row = (alias: string): string =>
    `to_jsonb(${alias}) || jsonb_build_object('subjects', ${subjectsOf(`${alias}.${e("id")}`)}, 'overdue', ${alias}.${e("doneAt")} is null and ${alias}.${e("dueAt")} < now()${extraFieldsJson(alias, extras)})`;

  const setSubjects = (
    engagement: string,
    list: string,
    tenant: string,
  ): string => `
  if jsonb_typeof(coalesce(${list}, '[]')) <> 'array' then
    ${fail("ENGAGEMENT_SUBJECTS_INVALID", "subjects must be a list of { type, id }", "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(${list}, '[]')) loop
    if not ${subjectInTenant(ctx, "(v_item ->> 'type')", "(v_item ->> 'id')", tenant)} then
      ${fail("ENGAGEMENT_SUBJECT_FORBIDDEN", "a subject is unknown or not readable in this organization", "42501")}
    end if;
  end loop;
  delete from ${t("links")} x where x.${l("engagement")} = ${engagement};
  insert into ${t("links")} (${l("tenant")}, ${l("engagement")}, ${l("subjectType")}, ${l("subjectId")}, ${l("position")})
  select ${tenant}, ${engagement}, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(${list}, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := ${subjectsOf(engagement)};
  v_first := v_subjects -> 0;`;

  const attrs = (name: string, key: string): string =>
    `${name}.attrs ->> ${sqlString(key)}`;

  const has = (name: string, key: string): string =>
    `${name}.attrs ? ${sqlString(key)}`;

  const notifyOwner = ctx.installed("notifications")
    ? `
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    )`,
      { indent: "    " },
    )}
  end if;`
    : "";

  return `${schemaPreamble(ctx)}
-- Calls, emails, meetings, notes and tasks logged on one or more records.
${
  ctx.manages
    ? `create table if not exists ${t("engagements")} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("type")} text not null,
  ${e("title")} text not null check (length(${e("title")}) between 1 and 500),
  ${e("body")} text,
  ${e("outcome")} text,
  ${e("owner")} uuid,
  ${e("dueAt")} timestamptz,
  ${e("doneAt")} timestamptz,
  ${e("durationSeconds")} integer check (${e("durationSeconds")} >= 0),
  ${e("externalRef")} text,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("engagements_owner_open_idx")} on ${t("engagements")} (${e("tenant")}, ${e("owner")}, ${e("dueAt")}) where ${e("doneAt")} is null;
create index if not exists ${ctx.naming.rename("engagements_tenant_created_idx")} on ${t("engagements")} (${e("tenant")}, ${e("createdAt")} desc);
create unique index if not exists ${ctx.naming.rename("engagements_external_ref_idx")} on ${t("engagements")} (${e("tenant")}, ${e("externalRef")}) where ${e("externalRef")} is not null;${addExtraColumns(t("engagements"), extras)}
${lockTable(t("engagements"), { read: true })}
create table if not exists ${t("links")} (
  ${l("tenant")} ${ctx.idType} not null,
  ${l("engagement")} uuid not null references ${t("engagements")} (${e("id")}) on delete cascade,
  ${l("subjectType")} text not null,
  ${l("subjectId")} text not null,
  ${l("position")} integer not null default 1,
  primary key (${l("engagement")}, ${l("subjectType")}, ${l("subjectId")})
);
create index if not exists ${ctx.naming.rename("engagement_subjects_subject_idx")} on ${t("links")} (${l("subjectType")}, ${l("subjectId")});
${lockTable(t("links"), { read: true })}
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none.
drop policy if exists ${ctx.tableName("links").name}_read on ${t("links")};
create policy ${ctx.tableName("links").name}_read on ${t("links")} for select to authenticated
using (${ctx.scope.check(l("tenant"), read)} and ${canSubject}(${l("subjectType")}, ${l("subjectId")}, 'read'));
drop policy if exists ${ctx.tableName("engagements").name}_read on ${t("engagements")};
create policy ${ctx.tableName("engagements").name}_read on ${t("engagements")} for select to authenticated
using (${ctx.scope.check(e("tenant"), read)} and (
  not exists (select 1 from ${t("links")} x where x.${l("engagement")} = ${e("id")})
  or exists (select 1 from ${t("links")} x where x.${l("engagement")} = ${e("id")} and ${canSubject}(x.${l("subjectType")}, x.${l("subjectId")}, 'read'))
));
`
    : ""
}
-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function ${fn("log_engagement")}(tenant ${ctx.idType}, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant ${ctx.idType} := log_engagement.tenant;
  v_type text := ${attrs("log_engagement", "type")};
  v_title text := nullif(trim(${attrs("log_engagement", "title")}), '');
  v_owner uuid := coalesce(nullif(${attrs("log_engagement", "ownerId")}, '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", write)}) then
    ${fail("ENGAGEMENT_FORBIDDEN", "not allowed to log engagements")}
  end if;
  if v_type is null or not (v_type = any (${typeList})) then
    ${fail("ENGAGEMENT_TYPE_INVALID", "unknown engagement type", "22023")}
  end if;
  if v_title is null then
    ${fail("ENGAGEMENT_TITLE_REQUIRED", "a title is required", "23502")}
  end if;
  ${ctx.hook("before_engagement_log", [
    [ctx.idType, "log_engagement.tenant"],
    ["jsonb", "log_engagement.attrs"],
    ["jsonb", "log_engagement.subjects"],
  ])}
  insert into ${t("engagements")} (${e("tenant")}, ${e("type")}, ${e("title")}, ${e("body")}, ${e("outcome")}, ${e("owner")}, ${e("dueAt")}, ${e("doneAt")}, ${e("durationSeconds")}, ${e("externalRef")}, ${e("createdBy")})
  values (v_tenant, v_type, v_title, ${attrs("log_engagement", "body")}, ${attrs("log_engagement", "outcome")}, v_owner,
    (${attrs("log_engagement", "dueAt")})::timestamptz, (${attrs("log_engagement", "doneAt")})::timestamptz,
    (${attrs("log_engagement", "durationSeconds")})::integer, ${attrs("log_engagement", "externalRef")}, auth.uid())
  on conflict (${e("tenant")}, ${e("externalRef")}) where ${e("externalRef")} is not null do update set
    ${e("title")} = excluded.${e("title")}, ${e("body")} = excluded.${e("body")}, ${e("outcome")} = excluded.${e("outcome")},
    ${e("dueAt")} = excluded.${e("dueAt")}, ${e("doneAt")} = excluded.${e("doneAt")},
    ${e("durationSeconds")} = excluded.${e("durationSeconds")}, ${e("updatedAt")} = now()
  returning ${e("id")} into v_id;${writeExtraColumns(t("engagements"), extras, "log_engagement.attrs -> 'fields'", `x.${e("id")} = v_id`)}
  ${setSubjects("v_id", "log_engagement.subjects", "v_tenant")}
  ${record("engagement.logged", "v_id", "v_type", "v_tenant")}${notifyOwner}
  ${ctx.hook("after_engagement_log", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("log_engagement")}(${ctx.idType}, jsonb, jsonb)`)}

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function ${fn("update_engagement")}(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
  v_tenant ${ctx.idType};
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  select x.${e("tenant")}, x.${e("type")}, x.${e("owner")} into v_tenant, v_type, v_previous_owner
  from ${t("engagements")} x where x.${e("id")} = v_id and ${editable("x")};
  if v_tenant is null then
    ${fail("ENGAGEMENT_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if ${has("update_engagement", "type")} and not (${attrs("update_engagement", "type")} = any (${typeList})) then
    ${fail("ENGAGEMENT_TYPE_INVALID", "unknown engagement type", "22023")}
  end if;
  update ${t("engagements")} x set
    ${e("type")} = coalesce(${attrs("update_engagement", "type")}, x.${e("type")}),
    ${e("title")} = coalesce(nullif(trim(${attrs("update_engagement", "title")}), ''), x.${e("title")}),
    ${["body", "outcome", "externalRef"].map((key) => `${e(key)} = case when ${has("update_engagement", key)} then ${attrs("update_engagement", key)} else x.${e(key)} end`).join(",\n    ")},
    ${e("owner")} = case when ${has("update_engagement", "ownerId")} then nullif(${attrs("update_engagement", "ownerId")}, '')::uuid else x.${e("owner")} end,
    ${e("dueAt")} = case when ${has("update_engagement", "dueAt")} then (${attrs("update_engagement", "dueAt")})::timestamptz else x.${e("dueAt")} end,
    ${e("doneAt")} = case when ${has("update_engagement", "doneAt")} then (${attrs("update_engagement", "doneAt")})::timestamptz else x.${e("doneAt")} end,
    ${e("durationSeconds")} = case when ${has("update_engagement", "durationSeconds")} then (${attrs("update_engagement", "durationSeconds")})::integer else x.${e("durationSeconds")} end,
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_id
  returning x.${e("type")}, x.${e("title")}, x.${e("owner")} into v_type, v_title, v_owner;${writeExtraColumns(t("engagements"), extras, "update_engagement.attrs -> 'fields'", `x.${e("id")} = v_id`)}
  if update_engagement.subjects is not null then
    ${setSubjects("v_id", "update_engagement.subjects", "v_tenant")}
  else
    v_subjects := ${subjectsOf("v_id")};
    v_first := v_subjects -> 0;
  end if;
  ${record("engagement.updated", "v_id", "v_type", "v_tenant")}${notifyOwner}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("update_engagement")}(uuid, jsonb, jsonb)`)}

-- Marks an engagement done now (done true) or open again.
create or replace function ${fn("complete_engagement")}(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant ${ctx.idType};
  v_type text;
  v_subjects jsonb := ${subjectsOf("complete_engagement.engagement")};
  v_first jsonb := v_subjects -> 0;
begin
  update ${t("engagements")} x set
    ${e("doneAt")} = case when complete_engagement.done then coalesce(x.${e("doneAt")}, now()) end,
    ${e("outcome")} = coalesce(complete_engagement.outcome, x.${e("outcome")}),
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_id and ${editable("x")}
  returning x.${e("tenant")}, x.${e("type")} into v_tenant, v_type;
  if v_tenant is null then
    ${fail("ENGAGEMENT_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if complete_engagement.done then
    ${record("engagement.completed", "v_id", "v_type", "v_tenant")}
  end if;
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("complete_engagement")}(uuid, boolean, text)`)}

create or replace function ${fn("delete_engagement")}(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant ${ctx.idType};
  v_type text;
  v_subjects jsonb := ${subjectsOf("delete_engagement.engagement")};
  v_first jsonb := v_subjects -> 0;
begin
  delete from ${t("engagements")} x where x.${e("id")} = v_id and ${editable("x")}
  returning x.${e("tenant")}, x.${e("type")} into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  ${record("engagement.deleted", "v_id", "v_type", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("delete_engagement")}(uuid)`)}

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function ${fn("engagements_of")}(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select ${row("x")} as value, coalesce(x.${e("doneAt")}, x.${e("dueAt")}, x.${e("createdAt")}) as at, x.${e("id")} as id
    from ${t("engagements")} x
    join ${t("links")} k on k.${l("engagement")} = x.${e("id")}
    where k.${l("subjectType")} = engagements_of.subject_type and k.${l("subjectId")} = engagements_of.subject_id
      and (engagements_of.types is null or x.${e("type")} = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x.${e("doneAt")}, x.${e("dueAt")}, x.${e("createdAt")}) < engagements_of.before)
    order by at desc, id desc
    limit ${pageSize("engagements_of.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("engagements_of")}(text, text, text[], timestamptz, integer)`)}

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function ${fn("next_engagement")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${row("x")}
  from ${t("engagements")} x
  join ${t("links")} k on k.${l("engagement")} = x.${e("id")}
  where k.${l("subjectType")} = next_engagement.subject_type and k.${l("subjectId")} = next_engagement.subject_id
    and x.${e("doneAt")} is null and x.${e("dueAt")} is not null
  order by x.${e("dueAt")}, x.${e("id")}
  limit 1
$$;
${userGrant(`${fn("next_engagement")}(text, text)`)}

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function ${fn("open_engagements")}(tenant ${ctx.idType}, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select ${row("x")} as value, x.${e("dueAt")} as due, x.${e("id")} as id
    from ${t("engagements")} x
    where x.${e("tenant")} = open_engagements.tenant
      and x.${e("owner")} = coalesce(open_engagements.owner, auth.uid())
      and x.${e("doneAt")} is null
      and (open_engagements.due_before is null or x.${e("dueAt")} < open_engagements.due_before)
    order by x.${e("dueAt")} nulls last, x.${e("id")}
    limit ${pageSize("open_engagements.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("open_engagements")}(${ctx.idType}, uuid, timestamptz, integer)`)}
${
  recordingsOn(ctx)
    ? recordingsSql(ctx, {
        editable,
        record,
        manage,
        row,
        loadSubjects: (id) =>
          `v_subjects := ${subjectsOf(id)};
  v_first := v_subjects -> 0;`,
      })
    : ""
}${logsBookings(ctx, types(ctx)) ? bookingEngagementsSql(ctx) : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "log_engagement",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "update_engagement",
      args: ["uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "complete_engagement",
      args: ["uuid", "boolean", "text"],
      returns: "jsonb",
    },
    { name: "delete_engagement", args: ["uuid"], returns: "boolean" },
    {
      name: "engagements_of",
      args: ["text", "text", "text[]", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "next_engagement", args: ["text", "text"], returns: "jsonb" },
    {
      name: "open_engagements",
      args: ["{id}", "uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    ...(recordingsOn(ctx) ? recordingsContract() : []),
  ];
}

const REQUIRES = ["memberships", "permissions", "subjects"] as const;

export const ENGAGEMENTS: BlockSqlDefinition = {
  name: "activities",
  scopes: ["tenant"],
  title: "Engagements",
  description:
    "Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.",
  requires: [...REQUIRES],
  dependencies: (layout) =>
    layout.modules?.["activities"]?.options?.["recordings"] === true
      ? [...REQUIRES, "ai-files"]
      : [...REQUIRES],
  integrates: [
    "outbox",
    "notifications",
    "ai-files",
    "queue",
    "bookings",
    "contacts",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
